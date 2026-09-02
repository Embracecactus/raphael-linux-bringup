# Redmi K20 Pro native Linux bring-up

Suggested GitHub repository name: `raphael-linux-bringup`.

This workspace records research and hardware evidence for booting a native
Linux system on a Xiaomi Redmi K20 Pro (`raphael`) and using it as the host for
the “傻妞” voice assistant.

Current milestone: boot a minimal, RAM-only Linux through an ephemeral
`fastboot boot` first.  Its initramfs never mounts or writes a phone partition.
Only after that runtime gate passes will work continue toward a persistent
Debian server userspace and U-Boot.  Do not flash a community full-image package
until the boot chain, backups, image provenance and recovery path have
independent acceptance evidence.

## Evidence index

- [Current Linux support research](docs/research/2026-09-02-raphael-linux-support.md)
- [Sanitized device and Fastboot baseline](docs/verification/2026-09-02-raphael-device-baseline.md)
- [Recovery-material acquisition](docs/verification/2026-09-02-recovery-materials.md)
- [Community build-chain audit](docs/research/2026-09-02-build-chain-audit.md)
- [Verified source acquisition and provenance](docs/research/2026-09-02-source-acquisition.md)
- [Community prebuilt binary inventory](docs/research/2026-09-02-rootfs-prebuilt-inventory.tsv)
- [Exact sanitized Fastboot output](logs/raphael/2026-09-02-fastboot-inventory.txt)
- [Sanitized partition-name inventory](logs/raphael/2026-09-02-partition-name-inventory.txt)
- [Sanitized recovery boot attempts](logs/raphael/2026-09-02-recovery-boot-attempts.txt)
- [Source RAM-boot build evidence](logs/raphael/2026-09-02-source-ramboot-builds.txt)
- [Reusable read-only Fastboot inventory script](tools/raphael/read_fastboot_vars.sh)
- [Read-only recovery partition backup script](tools/raphael/backup_recovery_partitions.sh)
- [RAM-only Linux init](tools/raphael/ramboot-init)
- [Reproducible RAM-only boot-image builder](tools/raphael/build_ramboot_linux.sh)
- [Source-kernel RAM-only boot-image builder](tools/raphael/build_source_ramboot_linux.sh)
- [Verified GitHub archive importer](tools/raphael/import_verified_github_archive.sh)
- [Imported Git-tree verifier](tools/raphael/verify_git_tree.sh)
- [Pinned upstream sources](third_party/SOURCES.lock)

## Safety boundary

- Research and inventory are read-only unless a later record explicitly says
  otherwise.
- The inventory stage is complete.  A later gate may use an explicitly recorded
  ephemeral `fastboot boot`; `flash`, `erase`, `format`, bootloader lock/unlock
  and partition writes remain prohibited until the backup gate passes.
- IMEI, MEID, serial numbers, account identifiers and raw unfiltered Android
  properties must not be committed or copied into reports.

## Repository note

The directory was initialized as a Git repository on 2026-09-02 with default
branch `main`.  Large downloads, reproducible build outputs, imported upstream
trees and device-private backups remain ignored; their tracked hashes, source
locks, scripts and sanitized evidence provide the review trail.  No remote is
configured yet.
