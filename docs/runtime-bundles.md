# CubicLM Runtime Bundles — provenance, layout, rebuild recipe

First published: `runtime-2026.09` (GitHub Release, ARM64 only).
Device-verified on Redmi K20 Pro (Android 11): proot exec, guest bash,
Node v24.21.0 — all green before publish.

2026-11: opt-in stacks completed — C/C++, PHP and Android & JVM overlays
added (`scripts/build_runtime_bundles.py`, guarded by
`scripts/validate_runtime_bundle.py`; all members verified against the
app's `ToolchainCatalog.unsafeMemberReason` traversal guard, 0 blocked).

## What lives where (contract with `RuntimeInstaller` + `MainActivity`)

`cubiclm-core-arm64.tar.gz` extracts to `<runtime>/`:
- `ubuntu/**` — Ubuntu 20.04.5 ARM64 base rootfs (bash, coreutils, apt/dpkg)
- `bin/proot` (0755) — PRoot user-mode-linux runner (Android/bionic ARM64)
- `libexec/proot/loader` (0755) — proot loader, found via `PROOT_LOADER`
- `lib/libtalloc.so.2`, `lib/libandroid-shmem.so` — found via `LD_LIBRARY_PATH`

`cubiclm-node-arm64.tar.gz` extracts to `<runtime>/ubuntu/`:
- `usr/local/{bin,lib,include,share}/**` — Node.js (on PATH already)

`cubiclm-cpp-arm64.tar.gz` extracts to `<runtime>/ubuntu/` (139 debs):
- `usr/bin/{gcc,g++-9,clang-10,make,cmake,gdb,…}`, `usr/lib/llvm-10/**`,
  `usr/include/**` — GCC 9.3.0 + Clang 10.0.0 + Make 4.2.1 + CMake 3.16.3
  + GDB 9.1 + pkg-config; dev headers via libc6-dev/linux-libc-dev

`cubiclm-php-arm64.tar.gz` extracts to `<runtime>/ubuntu/` (41 debs + phar):
- `usr/bin/php7.4` + `usr/bin/php → php7.4` (alternatives symlink added
  manually — postinst never runs), `usr/local/bin/composer` (Composer 2.2
  LTS phar, 0755)

`cubiclm-android-arm64.tar.gz` extracts to `<runtime>/ubuntu/`:
- `usr/lib/jvm/temurin-17/**` — Temurin JDK 17.0.21.1+2 (aarch64, glibc)
- `usr/local/bin/{java,javac,jar,…}` — relative symlinks into the JDK
- `opt/gradle/gradle-8.7/**` + `usr/local/bin/gradle` symlink
- `opt/android/platforms/android-34/android.jar` (API 34 compile jar)
- `opt/android/build-tools/34.0.3/{aapt2,aapt,zipalign,aidl,dexdump,split-select}`
  — static aarch64 AOSP builds (run in the glibc guest AND on bionic)
- `opt/android/build-tools/34.0.3/lib/{d8.jar,apksigner.jar}` — from
  Google's linux build-tools (jars are arch-free); `usr/local/bin/{d8,
  apksigner,aapt2,aapt,zipalign,aidl}` wrappers invoke them
- `opt/android/licenses/android-sdk-license` — standard hashes so Gradle
  AGP does not stall on the license check

Post-extract the app writes `ubuntu/etc/resolv.conf` (8.8.8.8/1.1.1.1)
and chmods `bin/proot` — see `RuntimeInstaller._finalizeCore`.

## Provenance (all public, downloaded — never copied from reference repos)

| Component | Source | License |
|---|---|---|
| Ubuntu 20.04.5 base ARM64 | `cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.5-base-arm64.tar.gz` | GPL (Ubuntu) |
| Node.js v24.21.0 linux-arm64 | `nodejs.org/dist/v24.21.0/` | MIT |
| PRoot 5.1.107.92 + loader (aarch64 Android) | Termux `proot` .deb, unmodified (`packages.termux.dev`) | GPLv2 — sources: `github.com/termux/proot`, upstream `github.com/proot-me/proot` |
| libtalloc.so.2 2.4.3 | Termux `libtalloc` .deb, unmodified | LGPLv3/GPLv3 — source: `samba.org` (talloc) |
| libandroid-shmem.so 0.7 | Termux `libandroid-shmem` .deb, unmodified | MIT-style — source: `github.com/termux/libandroid-shmem` |
| Python 3.8 overlay | Ubuntu focal ARM64 debs (python3.8-minimal, libpython3.8-minimal/stdlib, python3-pip/venv/setuptools/wheel, libssl1.1, libexpat1, libsqlite3-0, libreadline8, libmpdec2, libdb5.3), `usr/bin`+`usr/lib`+`lib/` kept, absolute links relativized, hardlinks materialized | Same Ubuntu/GPL terms as the base |
| C/C++ suite overlay (2026-11) | Ubuntu focal ARM64 debs, dependency closure resolved from `dists/focal/{main,universe}/binary-arm64/Packages.gz` (139 debs: gcc-9 9.3.0, g++-9, cpp-9, clang-10 10.0.0, llvm-10, make, cmake 3.16.3, cmake-data, gdb 9.1, pkg-config, binutils, libc6-dev, linux-libc-dev, libgcc-9-dev, libstdc++-9-dev, libisl23, libmpc3, libmpfr6, libz3-4, …) | Same Ubuntu/GPL terms as the base |
| PHP overlay (2026-11) | Ubuntu focal ARM64 debs closure (41 debs: php7.4-cli 7.4.3, php7.4-common, php7.4-opcache, php7.4-readline, libedit2, libargon2-1, libsodium23, libxml2, libssl1.1, tzdata, ucf, …) + `composer.phar` latest-2.2.x from `getcomposer.org` | Same Ubuntu/GPL terms; Composer MIT |
| Android & JVM overlay (2026-11) | Temurin JDK 17.0.21.1+2 linux aarch64 (`api.adoptium.net/v3/binary/latest/17/ga/linux/aarch64/jdk/…`, redirect to `github.com/adoptium/temurin17-binaries`); Gradle 8.7 (`services.gradle.org/distributions/gradle-8.7-bin.zip`); `android.jar` API 34 (`github.com/Sable/android-platforms`, android-34); static aarch64 `aapt2/aapt/zipalign/aidl/dexdump/split-select` built from AOSP source (`github.com/lzhiyong/android-sdk-tools` tag 34.0.3, asset `android-sdk-tools-static-aarch64.zip`); `d8.jar`/`apksigner.jar` from `dl.google.com/android/repository/build-tools_r34-linux.zip` (jars only, arch-free); SDK license hashes in `opt/android/licenses/android-sdk-license` | Temurin GPLv2+CPE; Gradle Apache-2.0; android.jar Android SDK terms (unmodified redistribution, same as every SDK mirror); AOSP tools Apache-2.0 (source: AOSP, built by lzhiyong); d8/apksigner Apache-2.0 |

> Bionic (Termux) Pythons canNOT run in the guest (wrong loader) —
> distro glibc debs are the only correct source. Dependency closure is
> machine-checked (`depcheck.py`: every DT_NEEDED resolves to base or
> overlay, 49 binaries, 0 problems). The C/C++/PHP overlays follow the
> same rule — Ubuntu focal arm64 debs only. The Android overlay mixes
> glibc (JDK, Gradle) and static (aapt2/zipalign — no dynamic loader
> needed) binaries; Google's x86_64-only build-tools contribute only
> arch-free jars.

GPL compliance: binaries are unmodified redistributions; sources linked
above; this recipe + `scripts/build_runtime_bundles.py` rebuild them
from public sources.

## Rebuild recipe

Prereqs: Python 3 (`tarfile`, `lzma`, `gzip`, `zipfile` stdlib), network.
Work dir needs ~4 GB free (JDK + Gradle staging).

```sh
python scripts/build_runtime_bundles.py --plan              # closures + sizes
python scripts/build_runtime_bundles.py --only cpp,php      # subset
python scripts/build_runtime_bundles.py                     # all three
python scripts/validate_runtime_bundle.py build/runtime-bundles/out/*.tar.gz
gh release upload runtime-2026.09 build/runtime-bundles/out/* --clobber
```

The script downloads the focal ARM64 Packages index, resolves the
dependency closure (Depends + Pre-Depends, first alternative, no
Recommends), fetches + SHA-256-verifies each deb, and repacks members
under `ubuntu/` applying the v2 rules below. Non-deb inputs (JDK,
Gradle, android.jar, static tools, composer.phar) are cached in
`build/runtime-bundles/work/`.

1. Verify layout: `tar -tzf` must show `ubuntu/usr/bin/gcc-9`,
   `ubuntu/usr/bin/php7.4`, `ubuntu/usr/lib/jvm/temurin-17/bin/java`,
   `ubuntu/opt/android/build-tools/34.0.3/aapt2`.
2. `sha256sum` → sidecar `<file>.sha256` (`<hash>  <filename>` format —
   the installer verifies it when no embedded hash exists).
3. Device-test new layouts via `adb push` + proot exec BEFORE publish
   (loader resolution and guest exec break silently otherwise).
4. `gh release upload runtime-<yyyy.mm> <files>`.

## Why not build proot ourselves (yet)

Upstream proot needs Android/bionic patches (seccomp, shmem) to run on
phones — the Termux build carries exactly those, device-verified here
(`HELLO_FROM_PROOT` + Node inside Ubuntu 20.04 on Redmi K20 Pro,
Android 11). A from-source NDK build is future work, not a blocker.

## v2 repack rules (device-enforced by Android toybox tar)

The first published tarballs failed on-device for two toybox reasons —
fixed in `build_bundles2.py`, verified by re-extract + `guardcheck.py`
(9135 members, 0 blocked) before re-upload; the same rules are enforced
by `scripts/build_runtime_bundles.py` and checked by
`scripts/validate_runtime_bundle.py` (cpp 13134 / php 3992 / android 861
members, 0 blocked):

1. **Absolute symlinks are refused as escapes.** Ubuntu ships ~20
   (`/usr/bin/mawk`, `/lib/systemd/…`, `/run`, …). Rewritten to
   equivalent relative links at build time (guest semantics identical).
2. **Hardlinks cannot be created at all** (both orders fail). The 4
   affected files (bzip2/bunzip2, perl, gunzip) are materialized as
   regular files (~1 MB cost). Symlinks are untouched.
3. Device nodes/sockets/fifos would be skipped (none present).
