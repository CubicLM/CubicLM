#!/usr/bin/env python3
"""Build CubicLM runtime toolchain overlay bundles (cpp / php / android).

Produces the three opt-in stacks published at
https://github.com/CubicLM/CubicLM/releases#release-runtime-2026.09
that the app's RuntimeInstaller downloads:

  cubiclm-cpp-arm64.tar.gz      GCC 9 / Clang 10 / Make / CMake / pkg-config / gdb
  cubiclm-php-arm64.tar.gz      PHP 7.4 CLI + Composer 2.2
  cubiclm-android-arm64.tar.gz  Temurin JDK 17 + Gradle 8.7 + android.jar +
                                static ARM64 aapt2/aapt/zipalign/aidl +
                                d8/apksigner jars + license stubs

Every overlay extracts into the core rootfs at <runtime>/ubuntu/ (see
RuntimeInstaller.extractSubdirFor) and follows the device-enforced repack
rules from docs/runtime-bundles.md:

  * members are prefixed with `ubuntu/`
  * absolute symlinks are rewritten to equivalent relative links
  * hardlinks are materialized as regular files (toybox tar cannot create them)
  * device nodes / sockets / fifos are skipped
  * no member may escape the root (the app's traversal guard rejects it)

Ubuntu (glibc) binaries only — the same rule as the Python overlay:
bionic/Termux builds cannot run inside the proot'd Ubuntu guest.

Usage:
  python scripts/build_runtime_bundles.py --plan            # show closures+sizes
  python scripts/build_runtime_bundles.py --only cpp,php    # build a subset
  python scripts/build_runtime_bundles.py                   # build all three

Inputs are cached under --work (default build/runtime-bundles/work).
Outputs + sha256 sidecars land in --out (default build/runtime-bundles/out).
"""

import argparse
import gzip
import io
import lzma
import os
import posixpath
import struct
import sys
import tarfile
import urllib.request
import hashlib

# ── Paths ────────────────────────────────────────────────────────────────────

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_WORK = os.path.join(REPO, "build", "runtime-bundles", "work")
DEFAULT_OUT = os.path.join(REPO, "build", "runtime-bundles", "out")

PORTS = "https://ports.ubuntu.com/ubuntu-ports"

# ── Stack definitions ────────────────────────────────────────────────────────

CPP_ROOTS = ["gcc", "g++", "cpp", "make", "cmake", "pkg-config", "gdb", "clang"]

PHP_ROOTS = ["php7.4-cli"]

# Non-deb inputs (arch-independent unless noted).
JDK17_URL = ("https://github.com/adoptium/temurin17-binaries/releases/download/"
             "jdk-17.0.21.1%2B2/OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.21.1_2.tar.gz")
GRADLE_URL = "https://services.gradle.org/distributions/gradle-8.7-bin.zip"
GRADLE_VERSION = "8.7"
ANDROID_JAR_URL = "https://github.com/Sable/android-platforms/raw/master/android-34/android.jar"
SDK_TOOLS_URL = ("https://github.com/lzhiyong/android-sdk-tools/releases/download/"
                 "34.0.3/android-sdk-tools-static-aarch64.zip")  # static aarch64: aapt2 aapt zipalign aidl ...
BUILD_TOOLS_URL = "https://dl.google.com/android/repository/build-tools_r34-linux.zip"  # jars only (d8, apksigner)
BUILD_TOOLS_VERSION = "34.0.3"
COMPOSER_URL = "https://getcomposer.org/download/latest-2.2.x/composer.phar"

JDK_PREFIX = "usr/lib/jvm/temurin-17"
BT_PREFIX = "opt/android/build-tools/" + BUILD_TOOLS_VERSION

# Tools from the JDK surfaced on PATH (usr/local/bin is already on PATH).
JAVA_TOOLS = ["java", "javac", "jar", "javadoc", "javap", "jdb", "jdeps",
              "jlink", "jmod", "jps", "jstack", "jshell", "keytool", "jarsigner"]

# The standard Android SDK license hashes (public knowledge; AGP refuses to
# build without a licenses/android-sdk-license file matching these).
ANDROID_SDK_LICENSE = (
    "\n8933bad161af4178b1185d1a37fbf41ea5269c55\n"
    "d56f5187479451eabf01fb78af6dfcb131a6481e\n"
    "24333f8a63b6825ea9c5514f83c2829b004d1fee\n"
)

# Wrapper scripts (guest-absolute paths; run inside the proot'd rootfs).
BT_WRAPPER = {
    "d8": "#!/bin/sh\nexec java -cp /%s/lib/d8.jar com.android.tools.r8.D8 \"$@\"\n" % BT_PREFIX,
    "apksigner": "#!/bin/sh\nexec java -jar /%s/lib/apksigner.jar \"$@\"\n" % BT_PREFIX,
    "aapt2": "#!/bin/sh\nexec /%s/aapt2 \"$@\"\n" % BT_PREFIX,
    "aapt": "#!/bin/sh\nexec /%s/aapt \"$@\"\n" % BT_PREFIX,
    "zipalign": "#!/bin/sh\nexec /%s/zipalign \"$@\"\n" % BT_PREFIX,
    "aidl": "#!/bin/sh\nexec /%s/aidl \"$@\"\n" % BT_PREFIX,
}

# ── Debian Packages index ────────────────────────────────────────────────────


def fetch(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    print("  downloading %s" % url)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    last = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "cubiclm-bundle-builder/1.0"})
            with urllib.request.urlopen(req, timeout=300) as r, \
                    open(dest + ".part", "wb") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
            os.replace(dest + ".part", dest)
            return dest
        except Exception as e:  # noqa: BLE001 — retry any transport error
            last = e
            print("    retry %d after error: %s" % (attempt + 1, e))
    raise SystemExit("download failed after retries: %s (%s)" % (url, last))


def load_index(work):
    """Parse focal main+universe arm64 Packages indexes → name → stanza."""
    pkgs = {}
    for pocket in ("main", "universe"):
        gz = fetch("%s/dists/focal/%s/binary-arm64/Packages.gz" % (PORTS, pocket),
                   os.path.join(work, "Packages-%s.gz" % pocket))
        text = gzip.open(gz, "rt", encoding="utf-8", errors="replace").read()
        for stanza in text.split("\n\n"):
            fields = {}
            key = None
            for line in stanza.split("\n"):
                if line.startswith(" ") and key:  # continuation
                    fields[key] += line
                elif ":" in line:
                    key, _, val = line.partition(":")
                    fields[key.strip()] = val.strip()
            name = fields.get("Package")
            if name and name not in pkgs:  # main wins over universe
                pkgs[name] = fields
    return pkgs


def dep_names(value):
    """Yield every package name mentioned in a Depends/Pre-Depends field."""
    for group in value.split(","):
        group = group.strip()
        if not group:
            continue
        for alt in group.split("|"):
            name = alt.strip().split("(")[0].split(":")[0].strip()
            name = name.split("<")[0].strip()
            if name:
                yield name


def resolve_closure(pkgs, roots):
    """BFS over Depends + Pre-Depends. First alternative wins when present."""
    seen = {}
    queue = list(roots)
    missing = set()
    while queue:
        name = queue.pop(0)
        if name in seen or name in missing:
            continue
        fields = pkgs.get(name)
        if fields is None:
            missing.add(name)
            continue
        seen[name] = fields
        for field in ("Depends", "Pre-Depends"):
            for dep in dep_names(fields.get(field, "")):
                if dep not in seen:
                    queue.append(dep)
    return seen, missing


# ── .deb handling ────────────────────────────────────────────────────────────


def deb_data_tar(deb_path):
    """Open a .deb (ar archive) and return (tarfile, mode) for data.tar.*."""
    with open(deb_path, "rb") as f:
        magic = f.read(8)
        if magic != b"!<arch>\n":
            raise ValueError("%s is not an ar archive" % deb_path)
        while True:
            hdr = f.read(60)
            if len(hdr) < 60:
                raise ValueError("no data.tar member in %s" % deb_path)
            name = hdr[0:16].decode("ascii").rstrip()
            size = int(hdr[48:58].decode("ascii").strip())
            blob = f.read(size)
            if size % 2:
                f.read(1)
            if name.startswith("data.tar"):
                if name.endswith(".xz"):
                    return tarfile.open(fileobj=io.BytesIO(lzma.decompress(blob)), mode="r:")
                if name.endswith(".gz"):
                    return tarfile.open(fileobj=io.BytesIO(gzip.decompress(blob)), mode="r:")
                if name.endswith(".zst"):
                    raise ValueError("zstd-compressed deb (unexpected for focal): %s" % deb_path)
                return tarfile.open(fileobj=io.BytesIO(blob), mode="r:")


def deb_sha256_ok(path, expected):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest() == expected.lower()


# ── Tar repacking (shared with the original build_bundles.py rules) ─────────


def normalize_linkname(linkname):
    """Strip ./ and leading / from a tar link target (tar-internal space)."""
    ln = linkname.lstrip("/")
    while ln.startswith("./"):
        ln = ln[2:]
    return ln


def relativize(member_path, target):
    """Rewrite an absolute symlink target to a relative one, or None when
    the target resolves outside the bundle root (guest semantics broken)."""
    if not target.startswith("/"):
        t = normalize_linkname(target)
        return target if not posixpath.isabs(target) else None
    # Inside the archive: /lib/x -> usr/lib/x  (members carry no leading /)
    in_root = normalize_linkname(target)
    if in_root.startswith("../"):
        return None
    base = posixpath.dirname(member_path.rstrip("/"))
    rel = posixpath.relpath(in_root, base or ".")
    if rel.startswith("../"):
        # Escapes the archive — check against real root (/usr/lib/x style
        # links usually target another rootfs tree that already exists).
        return None
    return rel


class TarBuilder:
    """Accumulates (TarInfo, fileobj|None) pairs and writes one tar.gz."""

    def __init__(self):
        self.members = []
        self.paths = set()

    def add_dir(self, path, mode=0o755, mtime=0):
        if path in self.paths:
            return
        info = tarfile.TarInfo(name=path)
        info.type = tarfile.DIRTYPE
        info.mode = mode
        info.uid = info.gid = 0
        info.uname = info.gname = "root"
        info.mtime = mtime
        self.members.append((info, None))
        self.paths.add(path)

    def ensure_parents(self, path, mtime=0):
        parts = path.split("/")
        for i in range(2, len(parts)):  # skip 'ubuntu' itself
            self.add_dir("/".join(parts[:i]), mtime=mtime)

    def add_file(self, path, data, mode=0o644, mtime=0):
        self.ensure_parents(path, mtime)
        info = tarfile.TarInfo(name=path)
        info.size = len(data)
        info.mode = mode
        info.uid = info.gid = 0
        info.uname = info.gname = "root"
        info.mtime = mtime
        self.members.append((info, io.BytesIO(data)))
        self.paths.add(path)

    def add_symlink(self, path, target, mtime=0):
        self.ensure_parents(path, mtime)
        info = tarfile.TarInfo(name=path)
        info.type = tarfile.SYMTYPE
        info.linkname = target
        info.mode = 0o777
        info.uid = info.gid = 0
        info.uname = info.gname = "root"
        info.mtime = mtime
        self.members.append((info, None))
        self.paths.add(path)

    def absorb_deb(self, tf, log_name):
        """Copy one deb's data.tar members under ubuntu/ with repack rules."""
        files = {normalize_linkname(m.name): m for m in tf.getmembers()}
        count = 0
        for m in tf.getmembers():
            src = normalize_linkname(m.name)
            if not src or src == ".":
                continue
            dst = "ubuntu/" + src
            if m.isdir():
                self.add_dir(dst, mode=m.mode, mtime=m.mtime)
                count += 1
            elif m.issym():
                target = relativize(src, m.linkname)
                if target is None:
                    print("    [skip] unsafe absolute symlink %s -> %s" % (src, m.linkname))
                    continue
                self.add_symlink(dst, target, mtime=m.mtime)
                count += 1
            elif m.islnk():
                real = files.get(normalize_linkname(m.linkname))
                if real is None or not real.isfile():
                    print("    [skip] dangling hardlink %s -> %s" % (src, m.linkname))
                    continue
                data = tf.extractfile(real).read()
                self.add_file(dst, data, mode=m.mode, mtime=m.mtime)
                count += 1
            elif m.isfile():
                data = tf.extractfile(m).read()
                self.add_file(dst, data, mode=m.mode, mtime=m.mtime)
                count += 1
            else:  # device / fifo / socket — device-enforced skip
                print("    [skip] special member %s" % src)
        print("    %s: %d members" % (log_name, count))

    def write(self, out_path):
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with tarfile.open(out_path, "w:gz", compresslevel=6) as tf:
            for info, fileobj in self.members:
                tf.addfile(info, fileobj)
        return out_path


# ── Stack builders ───────────────────────────────────────────────────────────


def build_deb_stack(pkgs, work, out, name, roots, extra=None):
    closure, missing = resolve_closure(pkgs, roots)
    if missing:
        print("  [%s] NOT IN INDEX: %s" % (name, ", ".join(sorted(missing))))
    total = sum(int(f.get("Size", 0)) for f in closure.values())
    print("  [%s] %d debs, %.1f MB download" % (name, len(closure), total / 1e6))
    if extra is None:
        extra = TarBuilder()
    deb_dir = os.path.join(work, name + "-debs")
    for i, (pname, fields) in enumerate(sorted(closure.items()), 1):
        deb = fetch(PORTS + "/" + fields["Filename"],
                    os.path.join(deb_dir, pname + ".deb"))
        if fields.get("SHA256") and not deb_sha256_ok(deb, fields["SHA256"]):
            raise SystemExit("SHA256 mismatch for %s" % deb)
        with deb_data_tar(deb) as tf:
            extra.absorb_deb(tf, "%s (%d/%d: %s)" % (name, i, len(closure), pname))
    return extra, closure


def build_cpp(pkgs, work, out):
    print("== cpp stack ==")
    b, closure = build_deb_stack(pkgs, work, out, "cpp", CPP_ROOTS)
    path = b.write(os.path.join(out, "cubiclm-cpp-arm64.tar.gz"))
    return path, closure


def build_php(pkgs, work, out):
    print("== php stack ==")
    b, closure = build_deb_stack(pkgs, work, out, "php", PHP_ROOTS)
    phar = fetch(COMPOSER_URL, os.path.join(work, "composer.phar"))
    b.add_file("ubuntu/usr/local/bin/composer", open(phar, "rb").read(), mode=0o755, mtime=0)
    # `php` itself is alternatives-managed (postinst creates it, which never
    # runs here) — add the symlink the way update-alternatives would.
    b.add_symlink("ubuntu/usr/bin/php", "php7.4")
    path = b.write(os.path.join(out, "cubiclm-php-arm64.tar.gz"))
    return path, closure


def strip_top_dir_members(tf):
    """Yield members of a single-top-level-dir tarball with that dir stripped."""
    for m in tf.getmembers():
        parts = m.name.split("/", 1)
        if len(parts) == 2 and parts[1]:
            yield parts[1], m


def build_android(pkgs, work, out):
    print("== android stack ==")
    b = TarBuilder()

    # 1. Temurin JDK 17 (aarch64 glibc) → usr/lib/jvm/temurin-17/
    jdk = fetch(JDK17_URL, os.path.join(work, "jdk17.tar.gz"))
    with tarfile.open(jdk, "r:gz") as tf:
        for rel, m in strip_top_dir_members(tf):
            dst = "ubuntu/%s/%s" % (JDK_PREFIX, rel)
            if m.isdir():
                b.add_dir(dst, mode=m.mode, mtime=m.mtime)
            elif m.issym():
                target = relativize(rel, m.linkname)
                if target is None:
                    print("    [skip] jdk symlink %s -> %s" % (rel, m.linkname))
                    continue
                b.add_symlink(dst, target, mtime=m.mtime)
            elif m.isfile():
                b.add_file(dst, tf.extractfile(m).read(), mode=m.mode, mtime=m.mtime)

    # 2. PATH links for the common java tools (usr/local/bin is on PATH).
    for tool in JAVA_TOOLS:
        b.add_symlink("ubuntu/usr/local/bin/%s" % tool,
                      "../../lib/jvm/temurin-17/bin/%s" % tool)

    # 3. Gradle 8.7 → opt/gradle/gradle-8.7/
    gradle = fetch(GRADLE_URL, os.path.join(work, "gradle-bin.zip"))
    import zipfile
    with zipfile.ZipFile(gradle) as zf:
        for name in zf.namelist():
            rel = name.split("/", 1)[1] if "/" in name else None
            if not rel or name.endswith("/"):
                if rel:
                    b.add_dir("ubuntu/opt/gradle/gradle-%s/%s" % (GRADLE_VERSION, rel.rstrip("/")))
                continue
            info = zf.getinfo(name)
            mode = 0o755 if (info.external_attr >> 16) & 0o111 else 0o644
            b.add_file("ubuntu/opt/gradle/gradle-%s/%s" % (GRADLE_VERSION, rel),
                       zf.read(name), mode=mode, mtime=0)
    b.add_symlink("ubuntu/usr/local/bin/gradle",
                  "../../../opt/gradle/gradle-%s/bin/gradle" % GRADLE_VERSION)

    # 4. android.jar (API 34)
    ajar = fetch(ANDROID_JAR_URL, os.path.join(work, "android.jar"))
    b.add_file("ubuntu/opt/android/platforms/android-34/android.jar",
               open(ajar, "rb").read(), mode=0o644)

    # 5. Static ARM64 build-tools from lzhiyong/android-sdk-tools (aapt2 etc.)
    tools = fetch(SDK_TOOLS_URL, os.path.join(work, "sdk-tools-aarch64.zip"))
    wanted = {"aapt2", "aapt", "zipalign", "aidl", "dexdump", "split-select"}
    seen_bin = []
    import zipfile as zf2
    with zf2.ZipFile(tools) as zf:
        for name in zf.namelist():
            base = posixpath.basename(name)
            if base in wanted:
                b.add_file("ubuntu/%s/%s" % (BT_PREFIX, base),
                           zf.read(name), mode=0o755)
                seen_bin.append(base)

    # 6. Java jars from Google's (x86_64) build-tools — jars are arch-free.
    bt = fetch(BUILD_TOOLS_URL, os.path.join(work, "buildtools34.zip"))
    with zf2.ZipFile(bt) as zf:
        for name in zf.namelist():
            base = posixpath.basename(name)
            if name.startswith("android-14/lib/") and base in ("d8.jar", "apksigner.jar"):
                b.add_file("ubuntu/%s/lib/%s" % (BT_PREFIX, base),
                           zf.read(name), mode=0o644)

    # 7. PATH wrappers + license stubs.
    for tool, script in BT_WRAPPER.items():
        b.add_file("ubuntu/usr/local/bin/%s" % tool, script.encode(), mode=0o755)
    b.add_file("ubuntu/opt/android/licenses/android-sdk-license",
               ANDROID_SDK_LICENSE.encode(), mode=0o644)

    path = b.write(os.path.join(out, "cubiclm-android-arm64.tar.gz"))
    return path, {"(jdk17)": None, "(gradle)": None,
                  "(build-tools)": seen_bin}


# ── Driver ───────────────────────────────────────────────────────────────────


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default=DEFAULT_WORK)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--only", default="cpp,php,android")
    ap.add_argument("--plan", action="store_true", help="print closures, write nothing")
    args = ap.parse_args()

    os.makedirs(args.work, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)

    which = [s.strip() for s in args.only.split(",") if s.strip()]
    need_index = any(s in ("cpp", "php") for s in which)
    pkgs = load_index(args.work) if need_index else {}

    if args.plan:
        for stack, roots in (("cpp", CPP_ROOTS), ("php", PHP_ROOTS)):
            closure, missing = resolve_closure(pkgs, roots)
            total = sum(int(f.get("Size", 0)) for f in closure.values())
            print("[%s] %d debs, %.1f MB, missing: %s" %
                  (stack, len(closure), total / 1e6, sorted(missing) or "none"))
        return

    results = {}
    if "cpp" in which:
        results["cpp"] = build_cpp(pkgs, args.work, args.out)
    if "php" in which:
        results["php"] = build_php(pkgs, args.work, args.out)
    if "android" in which:
        results["android"] = build_android(pkgs, args.work, args.out)

    print("\n== outputs ==")
    for name, (path, _) in results.items():
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        sidecar = path + ".sha256"
        with open(sidecar, "w", newline="\n") as f:
            f.write("%s  %s\n" % (h.hexdigest(), os.path.basename(path)))
        print("  %-42s %8.1f MB  sha256 %s…" % (
            os.path.basename(path), os.path.getsize(path) / 1e6, h.hexdigest()[:12]))
        print("     sidecar: %s" % sidecar)


if __name__ == "__main__":
    main()
