# Redmi K20 Pro native Linux bring-up

Suggested GitHub repository name: `raphael-linux-bringup`.

This workspace records research and hardware evidence for booting a native
Linux system on a Xiaomi Redmi K20 Pro (`raphael`) and using it as the host for
the “傻妞” voice assistant.

Current milestone: native Debian 13 arm64 reaches multi-user userspace through
the persistent ABL -> source-built U-Boot -> GRUB -> Linux chain.  UFS rootfs,
the 1080x2340 DSI console, USB ACM/NCM and key-only SSH have all been verified
on the phone.  The device-bound NV/calibration and rollback backup gate was
completed before the authorized `boot`/`cache`/`userdata`/`dtbo` transition.

Known open hardware work is recorded rather than hidden: the Goodix GTX8 input
device binds but produced no touch events, SLPI repeatedly crashes with the
current firmware/device-tree combination, and the display startup still emits
SMMU/clock warnings even though the former black screen and `disp_snapshot`
NULL dereference are gone.

## Connect over USB

Connect the phone to the host and wait for the USB-NCM adapter to appear.  From
this repository in WSL, use the private bring-up key:

```sh
ssh -i artifacts/device-private/raphael-linux-id_ed25519 raphael@172.16.42.1
```

The account is key-only and has passwordless `sudo`; root and password login
remain disabled.  The private key and raw device evidence are ignored by Git.

## Verified hardware state (2026-09-03)

| Gate | Result |
| --- | --- |
| ABL -> pinned source-built U-Boot | PASS |
| U-Boot UFS/FAT16 -> ARM64 GRUB EFI | PASS |
| Linux 7.0, 8 CPUs, UFS/ext4 root, Debian multi-user | PASS |
| DSI/DRM console, 1080x2340, framebuffer and backlight | PASS |
| USB ACM + CDC-NCM, ping and key-only SSH | PASS |
| Goodix GTX8 touch events | FAIL / next-stage diagnosis |
| SLPI stability | FAIL / runtime recovery disabled for this boot only |

The final hardware-tested cache image is FAT16 with 4096-byte logical sectors,
268,435,456 bytes, SHA-256
`a8e87b6387f407ef03431baa2ff6edb8f99981a733e2655d8415a3181753d927`.
Its runtime DTB policy is represented both by a deterministic DTB transformer
and by a source patch applied after the pinned community kernel patch.

## Evidence index

- [Current Linux support research](docs/research/2026-09-02-raphael-linux-support.md)
- [Sanitized device and Fastboot baseline](docs/verification/2026-09-02-raphael-device-baseline.md)
- [Recovery-material acquisition](docs/verification/2026-09-02-recovery-materials.md)
- [Community build-chain audit](docs/research/2026-09-02-build-chain-audit.md)
- [Verified source acquisition and provenance](docs/research/2026-09-02-source-acquisition.md)
- [ABL findings and recovery backup gate](docs/research/2026-09-03-abl-and-recovery-gate.md)
- [Community prebuilt binary inventory](docs/research/2026-09-02-rootfs-prebuilt-inventory.tsv)
- [Domestic-mirror rootfs decision](docs/research/2026-09-03-domestic-rootfs-plan.md)
- [Exact sanitized Fastboot output](logs/raphael/2026-09-02-fastboot-inventory.txt)
- [Sanitized partition-name inventory](logs/raphael/2026-09-02-partition-name-inventory.txt)
- [Sanitized recovery boot attempts](logs/raphael/2026-09-02-recovery-boot-attempts.txt)
- [Ephemeral Linux boot attempts](logs/raphael/2026-09-02-linux-boot-attempts.txt)
- [Source RAM-boot build evidence](logs/raphael/2026-09-02-source-ramboot-builds.txt)
- [LLVM 22 toolchain acquisition evidence](logs/raphael/2026-09-02-llvm22-toolchain.txt)
- [Stock recovery and preservation gate](logs/raphael/2026-09-03-recovery-gate.txt)
- [Domestic Debian image build evidence](logs/raphael/2026-09-03-domestic-rootfs-build.txt)
- [Executed Linux partition-write manifest](logs/raphael/2026-09-03-linux-write-manifest.tsv)
- [Persistent Linux hardware boot evidence](logs/raphael/2026-09-03-persistent-linux-boot.txt)
- [Reusable read-only Fastboot inventory script](tools/raphael/read_fastboot_vars.sh)
- [Read-only recovery partition backup script](tools/raphael/backup_recovery_partitions.sh)
- [RAM-only Linux init](tools/raphael/ramboot-init)
- [Reproducible RAM-only boot-image builder](tools/raphael/build_ramboot_linux.sh)
- [Source-kernel RAM-only boot-image builder](tools/raphael/build_source_ramboot_linux.sh)
- [Authenticated TUNA LLVM 22 installer](tools/raphael/install_llvm22_tuna.sh)
- [TUNA-backed Debian 13 arm64 image builder](tools/raphael/build_debian_trixie_server.sh)
- [Hardware-tested runtime DTB transformer](tools/raphael/prepare_runtime_dtb.sh)
- [Source-level display/USB DT patch](patches/raphael-kernel/0001-raphael-runtime-v3-display-usb-policy.patch)
- [Offline hardware snapshot helper](tools/raphael/raphael-hw-snapshot)
- [Pinned cache-boot U-Boot builder](tools/raphael/build_uboot_cache_boot.sh)
- [Verified GitHub archive importer](tools/raphael/import_verified_github_archive.sh)
- [Imported Git-tree verifier](tools/raphael/verify_git_tree.sh)
- [Pinned upstream sources](third_party/SOURCES.lock)

## Safety boundary

- Research and inventory are read-only unless a later record explicitly says
  otherwise.  The 2026-09-03 manifest records the exact authorized and executed
  writes to `userdata`, `cache`, `dtbo` and `boot`.
- Recovery, vendor, cust, vbmeta, modem and NV/calibration partitions were not
  part of the Linux transition.  TWRP and stock rollback material remain
  available, and raw device-bound backups stay outside Git.
- IMEI, MEID, serial numbers, account identifiers and raw unfiltered Android
  properties must not be committed or copied into reports.

## Repository note

The directory was initialized as a Git repository on 2026-09-02 with default
branch `main`.  Its configured `origin` is
`https://github.com/Embracecactus/raphael-linux-bringup.git`.  Large downloads,
reproducible build outputs, imported upstream trees and device-private backups
remain ignored; tracked hashes, source locks, scripts and sanitized evidence
provide the review trail.
