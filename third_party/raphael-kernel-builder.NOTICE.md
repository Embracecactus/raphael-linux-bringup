# Raphael kernel builder: complete upstream snapshot

The complete `raphael-kernel-builder/` directory is tracked directly in this
repository. A normal clone includes all 613 regular files (163356160 bytes),
with their original contents and executable modes. It is not a submodule or
an LFS pointer collection. No `.git` metadata or local build output is included.

- Upstream: https://github.com/GavinLiuOnline/xiaomi_raphael_build_kernel
- Commit: `128ac1fec88e7a141cebfab4193c6c4cc512a1d1`
- Tree: `ee3e9a20ba8b20b438ff649e4ced707d54611bb1`

All 613 file blob hashes and modes were checked against the pinned upstream
GitHub tree. The repository's existing tree verifier also reconstructed that
exact tree. Verify from the bring-up repository root:

```sh
bash tools/raphael/verify_git_tree.sh third_party/raphael-kernel-builder ee3e9a20ba8b20b438ff649e4ced707d54611bb1
```

## Publication scope and provenance

The repository operator explicitly requested publication of the entire upstream
directory and separately authorized inclusion of its sensor calibration data.
This scope is wider than the 43 firmware files in the boot-input initramfs:
it includes the original firmware/ALSA packages, modem/DSP/sensor material,
configuration, patches (including upstream backup-named patches), documents,
build script and nested workflow.

The upstream snapshot has no LICENSE/COPYING/copyright/WHENCE file. Publication
records the operator's instruction; it does not supply an independently verified
vendor grant or relicense these materials under the bring-up project's license.
Original authorship and notices remain unchanged. Consult the upstream and
respective component rights holders for additional distribution/use terms.

There are 27 calibration-named files in the upstream sensor registry, including
nonzero persistent/factory calibration values. They were already part of the
pinned public upstream tree and are not data newly extracted from this user's
phone. Their originating device and suitability for another handset have not
been independently established; do not treat them as universal calibration.

Static inspection found no private keys, personal SSH public keys, common access
tokens, password hashes or this workspace user's absolute paths. Identity words
in the upstream notes describe diagnostic commands/results; the examined strings
in firmware are not evidence of an actual device identity. Static scanning is
not proof that arbitrary binary content contains no hidden identifiers.
No phone was accessed and no downloaded/vendor program was executed.

## Use in this repository

`tools/raphael/build_debian_trixie_server.sh` consumes this exact tree for the
historical server rootfs recipe. Its tree lock is unchanged. The current fork's
kernel build still uses `tools/raphael/build_fork_kernel.sh` and the separate
locked `linux/` source; bundling this directory does not rebuild a rootfs or
deliver the later Phosh/XFCE desktop image.

The original `raphael-kernel_build.sh` is preserved for source correspondence.
It contains destructive cleanup/reset commands and global Git identity changes;
it was not run during publication. The nested `.github/workflows/` is preserved
as upstream material, not installed as a top-level workflow for this repository.
