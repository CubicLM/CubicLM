#!/usr/bin/env python3
"""Validate a runtime bundle against the app's traversal guard.

Mirrors ToolchainCatalog.unsafeMemberReason (Dart): every member path must
resolve inside the bundle root (`..` allowed while it stays inside) and
symlink targets — relative (against the link's directory) or absolute
(against the guest root) — must also stay inside.

Usage: python scripts/validate_runtime_bundle.py <bundle.tar.gz> [...]
Exit code 1 on the first blocked member.
"""
import posixpath
import sys
import tarfile


def resolve_inside(root, path):
    """Lexically resolve path under root, popping `..`. None on escape."""
    p = path.replace("\\", "/").lstrip("/")
    if not p or (len(p) > 1 and p[1] == ":"):
        return None
    parts = []
    for seg in p.split("/"):
        seg = seg.strip()
        if seg in ("", "."):
            continue
        if seg == "..":
            if not parts:
                return None
            parts.pop()
            continue
        parts.append(seg)
    if not parts:
        return None
    sep = "" if root.endswith("/") else "/"
    return root + sep + "/".join(parts)


def split_member(raw):
    i = raw.find(" -> ")
    if i < 0:
        return raw.strip(), None
    return raw[:i].strip(), raw[i + 4:].strip()


def unsafe_reason(root, raw):
    path, target = split_member(raw)
    if resolve_inside(root, path) is None:
        return "escapes the runtime: %s" % path
    if target:
        if target.startswith("/"):
            rel = target
        else:
            d = path.rsplit("/", 1)[0] if "/" in path else ""
            rel = target if not d else d + "/" + target
        if resolve_inside(root, rel) is None:
            return "link escapes the runtime: %s -> %s" % (path, target)
    return None


def main():
    failed = 0
    for bundle in sys.argv[1:]:
        root = "/"  # guest-root semantics: all paths resolve from /
        n = 0
        blocked = None
        with tarfile.open(bundle, "r:gz") as tf:
            for m in tf.getmembers():
                n += 1
                raw = m.name
                if m.issym():
                    raw += " -> " + m.linkname
                elif m.islnk():
                    raw += " -> " + m.linkname
                reason = unsafe_reason(root, raw)
                if reason:
                    blocked = (raw, reason)
                    break
        if blocked:
            print("%s: BLOCKED after %d members — %s (%s)" %
                  (bundle, n, blocked[0], blocked[1]))
            failed = 1
        else:
            print("%s: OK — %d members, 0 blocked" % (bundle, n))
    sys.exit(failed)


if __name__ == "__main__":
    main()
