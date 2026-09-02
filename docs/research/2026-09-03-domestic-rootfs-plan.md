# Domestic-mirror rootfs decision

Snapshot date: 2026-09-03 (Asia/Shanghai)

## Decision

Build the first server root filesystem locally as Debian 13 (`trixie`) arm64.
Use Tsinghua TUNA for the Debian and Debian Security package archives, while
retaining USTC as a documented fallback.  Ubuntu is supported by the same
method, but Ubuntu 24.04 LTS (`noble`) is the later compatibility image rather
than another variable in the first hardware boot.

This is a cross-architecture build: the workstation is x86_64, the target is
arm64, and target maintainer tools execute through QEMU user emulation.  Kernel
and U-Boot source builds use an AArch64 cross toolchain.  The first rootfs gate
uses the independently verified published kernel package that matches pinned
commit `c526b7bf7ebc3fbfee244be252a2c1bd061ca749`; a later clean closure rebuild
will replace that package with its source-built equivalent.  The host exposes
32 logical CPUs; the U-Boot builder uses all requested jobs, while foreign-arch
package configuration is mostly serial under QEMU.

Official mirror help:

- TUNA Debian: <https://mirrors.tuna.tsinghua.edu.cn/help/debian/>
- TUNA Debian Security: <https://mirrors.tuna.tsinghua.edu.cn/help/debian-security/>
- TUNA Ubuntu Ports: <https://mirrors.tuna.tsinghua.edu.cn/help/ubuntu-ports/>
- USTC Debian: <https://mirrors.ustc.edu.cn/help/debian.html>
- USTC Ubuntu Ports: <https://mirrors.ustc.edu.cn/help/ubuntu-ports.html>

## Why the upstream image script is not run directly

The reviewed legacy builder advertises TUNA in the installed APT configuration,
but its bootstrap stage still hard-codes `deb.debian.org` or
`ports.ubuntu.com`.  It also creates `root` and `user` with password `1234` and
enables root/password SSH on the USB network.  Those defaults are unacceptable
for a device that will later host a voice assistant.

`tools/raphael/build_debian_trixie_server.sh` replaces that path with:

- archive-signature-checked packages fetched from TUNA;
- a minimal Debian server system, not a desktop image;
- a locked root account and a locked ordinary account with key-only SSH;
- per-device SSH host keys generated on first boot;
- USB ACM console plus CDC-NCM at `172.16.42.1`;
- a first-userspace-boot marker;
- Debian's archive-supplied ARM64 GRUB EFI, assembled locally with a fixed
  Raphael boot configuration;
- exact input and output hashes plus a complete installed-package manifest.

The private SSH key stays below ignored `artifacts/device-private/`.  The script
does not contact the phone and cannot flash it.

## Host build result

The source-pinned U-Boot build completed twice from independent temporary build
directories.  The Android boot images, resolved configurations, DTBs and
compiled default environments were byte-identical.  The resulting boot image
is 630,784 bytes with SHA-256
`41b90496cf53c47e2bfebf20c28f6c62bbcafae07a023488f75b88a32669db42`.

The Debian bootstrap completed from TUNA.  During iterative packaging, strict
checks found and fixed the older kernel package's `/lib/modules` payload for
Debian 13 merged-/usr.  The original FAT32/512-byte cache image passed host
checks but failed on hardware because U-Boot exposes the UFS LUN with 4096-byte
logical sectors.  The hardware-compatible cache is therefore FAT16 with
4096-byte logical sectors.  At the user's request, the first image gate reused
the already verified bootstrap, initramfs and GRUB staging through
`RESUME_FROM_IMAGES=1` rather than downloading and configuring all packages a
fourth time.  Its manifest therefore records
`build_mode=resume-images-from-validated-staging` and
`bootstrap_reused=true`; a full clean rebuild remains a later closure gate.

Host-side filesystem and payload verification passed:

- final hardware-tested `raphael-cache-boot.img`: 268,435,456 bytes, SHA-256
  `a8e87b6387f407ef03431baa2ff6edb8f99981a733e2655d8415a3181753d927`;
- `raphael-userdata-rootfs.img`: 1,138,638,848 bytes, SHA-256
  `b6f55322aac6edd088a2dcce395c66a6f102da299d2d1a5f52ae537b026e94ac`;
- ext4 and FAT16/4096 checks report clean filesystems;
- all five files extracted back from the cache image are byte-identical to the
  staged GRUB EFI, GRUB configuration, kernel EFI stub, initramfs and Raphael
  DTB;
- the rootfs contains 222 archive-managed packages, locked root and user
  passwords, key-only SSH, first-boot host-key generation, USB ACM/NCM services
  and enabled Qualcomm `rmtfs`, `pd-mapper` and `tqftpserv` services.

The builders themselves never access a phone.  After the preservation gate and
explicit authorization, the image set was written and the complete persistent
hardware path passed: U-Boot loaded GRUB, Debian reached multi-user, the DSI
console rendered at 1080x2340, and USB-NCM plus key-only SSH worked at
`172.16.42.1`.  See the persistent boot evidence for exact boundaries and the
remaining touch/SLPI failures.

## Coherent first-boot partition contract

Do not mix the newer `vendor`/`cust` layout with the older `cache` layout.  The
first gate deliberately minimizes overwritten partitions:

| Android partition | First-gate content |
| --- | --- |
| `boot` | locally built, pinned U-Boot Android image |
| `cache` | FAT16/4096: GRUB ARM64 EFI, Linux EFI stub, initramfs and hardware-tested Raphael DTB |
| `userdata` | locally built Debian ext4 root filesystem |
| `dtbo` | erased only if separately authorized, because the Linux DTB is loaded by GRUB |

`tools/raphael/build_uboot_cache_boot.sh` uses the pinned Raphael U-Boot source
and explicitly loads `EFI/BOOT/BOOTAA64.EFI` from `cache`.  Its diagnostic USB
Fastboot remains available, but U-Boot-side flash, mass-storage, remote-command
and persistent-environment writes are disabled.

The first transition was authorized and executed on 2026-09-03 after live-size,
rollback and raw-backup checks.  Future writes still require an updated manifest
and explicit scope; a successful old gate is not blanket authorization.

## Hardware-derived DT policy

The working v3 DTB sets both the Qualcomm DWC3 wrapper and core to peripheral
mode, removes the core role-switch property, and removes the two community
`qcom,boot-display-on` opt-ins.  The exact compiled-DTB transform is implemented
by `tools/raphael/prepare_runtime_dtb.sh`; the same change is carried as
`patches/raphael-kernel/0001-raphael-runtime-v3-display-usb-policy.patch` for
the next clean source rebuild.  The runtime DTB was read back from Linux and
verified to contain the intended properties.

## Ubuntu follow-up

For Ubuntu, use `noble` with either:

- `https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/`, or
- `https://mirrors.ustc.edu.cn/ubuntu-ports/`.

The kernel, DTB and U-Boot are distribution-independent.  Once Debian proves
the boot/storage/display/USB path, an Ubuntu root filesystem is a userspace
substitution rather than a second bootloader experiment.
