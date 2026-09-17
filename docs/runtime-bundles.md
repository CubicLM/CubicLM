# CubicLM Runtime Bundles — provenance, layout, rebuild recipe

First published: `runtime-2026.09` (GitHub Release, ARM64 only).
Device-verified on Redmi K20 Pro (Android 11): proot exec, guest bash,
Node v24.21.0 — all green before publish.

## What lives where (contract with `RuntimeInstaller` + `MainActivity`)

`cubiclm-core-arm64.tar.gz` extracts to `<runtime>/`:
- `ubuntu/**` — Ubuntu 20.04.5 ARM64 base rootfs (bash, coreutils, apt/dpkg)
- `bin/proot` (0755) — PRoot user-mode-linux runner (Android/bionic ARM64)
- `libexec/proot/loader` (0755) — proot loader, found via `PROOT_LOADER`
- `lib/libtalloc.so.2`, `lib/libandroid-shmem.so` — found via `LD_LIBRARY_PATH`

`cubiclm-node-arm64.tar.gz` extracts to `<runtime>/ubuntu/`:
- `usr/local/{bin,lib,include,share}/**` — Node.js (on PATH already)

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

GPL compliance: binaries are unmodified redistributions; sources linked
above; this recipe + script rebuild them bit-for-bit from public sources.

## Rebuild recipe

Prereqs: Python 3 (`tarfile`, `lzma`, `gzip` stdlib), curl, NDK
`llvm-readelf` (optional, for auditing `.so` sections).

1. Download the three inputs (see table) + the two lib debs.
2. Repack with `build_bundles.py` (kept out of repo — TEMP workdir;
   logic: prefix ubuntu-base members with `ubuntu/`, strip node top
   dir → `usr/local/`, append `bin/`+`libexec/`+`lib/` entries with
   fixed modes; symlinks preserved, device nodes excluded by source).
3. Verify layout: `tar -tzf` must show `ubuntu/usr/bin/bash`,
   `bin/proot`, `libexec/proot/loader`, `usr/local/bin/node`.
4. `sha256sum` → sidecar `<file>.sha256` (`<hash>  <filename>` format —
   the installer verifies it when no embedded hash exists).
5. Device-test new layouts via `adb push` + proot exec BEFORE publish
   (loader resolution and guest exec break silently otherwise).
6. `gh release create runtime-<yyyy.mm> --title ... --notes ... <files>`.

## Why not build proot ourselves (yet)

Upstream proot needs Android/bionic patches (seccomp, shmem) to run on
phones — the Termux build carries exactly those, device-verified here
(`HELLO_FROM_PROOT` + Node inside Ubuntu 20.04 on Redmi K20 Pro,
Android 11). A from-source NDK build is future work, not a blocker.

## v2 repack rules (device-enforced by Android toybox tar)

The first published tarballs failed on-device for two toybox reasons —
fixed in `build_bundles2.py`, verified by re-extract + `guardcheck.py`
(9135 members, 0 blocked) before re-upload:

1. **Absolute symlinks are refused as escapes.** Ubuntu ships ~20
   (`/usr/bin/mawk`, `/lib/systemd/…`, `/run`, …). Rewritten to
   equivalent relative links at build time (guest semantics identical).
2. **Hardlinks cannot be created at all** (both orders fail). The 4
   affected files (bzip2/bunzip2, perl, gunzip) are materialized as
   regular files (~1 MB cost). Symlinks are untouched.
3. Device nodes/sockets/fifos would be skipped (none present).
