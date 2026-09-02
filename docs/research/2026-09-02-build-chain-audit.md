# Raphael community build-chain audit

Snapshot date: 2026-09-02 (Asia/Shanghai)

## Decision

Do not execute or flash the community recovery ZIPs or whole-image releases.
The repositories are useful engineering inputs, but their current delivery
chain does not meet the provenance, rollback, credential or partition-contract
gates for this physical phone.

Proceed by pinning and locally rebuilding the smallest independently reviewable
pieces: U-Boot, kernel/DTB, firmware manifest and a minimal Debian rootfs.  Later
hardware writes must use a reviewed per-partition plan, not the bundled updater.

No build output from these repositories has been booted on or written to the
phone during this audit.

## Exact inspected sources

| Component | Commit | Local state |
| --- | --- | --- |
| Legacy image builder | `6cf98b674514bd61e0ec3723ac3c227d0e33da3d` | clean shallow clone |
| Current rootfs builder | `51f9cd0634e09ed70885f91806bf08213211cc2e` | clean shallow clone |
| Current Raphael U-Boot | `b5e36b80ecf58b00f4f4245cf411d73ed36832d5` (`mailing`) | clean shallow clone |

Remote URLs and the separate kernel ref are recorded in
`third_party/SOURCES.lock`.  A shallow clone pins the observed tree but is not a
complete history/provenance review.

## Partition contracts are inconsistent

The legacy image builder documents this layout:

- erase `dtbo`, `boot`, `cache` and `userdata`;
- put U-Boot in `boot`;
- put the Linux `/boot` filesystem in `cache`;
- put the root filesystem in `userdata`.

The current rootfs builder explicitly deprecates that cache layout.  Its manual
and recovery flows instead use:

| Android partition | Linux payload |
| --- | --- |
| `boot` | U-Boot Android boot image |
| `vendor` | ext4 `/boot`, kernel, DTBs and firmware |
| `cust` | FAT EFI/rEFInd filesystem |
| `userdata` | root filesystem |
| `logo`, `vbmeta`, `dtbo` | bundled static images |

Its updater first zero-fills `dtbo`, `boot`, `cache`, `vendor`, `userdata`,
`vbmeta` and `cust`, then writes the payloads above.  Meanwhile, the current
U-Boot repository's release instructions still say to flash Linux `/boot` to
`cache` and erase `dtbo`, although its current environment loads EFI directly
from `cust`.  Mixing releases across these repositories is therefore unsafe.

The user's permission to discard photos/apps only applies to `userdata`; it
does not remove the requirement to preserve device-bound NV/calibration and
every non-userdata partition selected for reuse or overwrite.

## Delivery and security findings

1. Both rootfs builders default the ordinary user and `root` passwords to
   `1234`, append `PermitRootLogin yes`, and enable SSH password authentication.
   The current image advertises SSH on USB NCM address `172.16.42.1`.  A locally
   built image must use unique credentials or key-only SSH before first boot.
2. Kernel, header, firmware, audio and boot artifacts are downloaded with
   `curl -sL`; the examined paths do not bind those files to hashes or
   signatures before installation.  The legacy documentation also pipes a
   mutable remote kernel-update script into a root shell.
3. The repositories contain prebuilt Debian packages, EFI executables, an
   AArch64 recovery updater and raw Android partition images.  Their current
   tree does not provide a complete source-to-binary manifest, signatures or an
   SBOM.  Exact observed bytes are recorded separately in
   `2026-09-02-rootfs-prebuilt-inventory.tsv`; a hash identifies bytes but does
   not establish trust.
4. The current recovery template claims `pre-device=cepheus` and a Xiaomi
   `cepheus` post-build, not `raphael`.  Its builder invokes ordinary `zip` and
   has no signing step.  Bundling an `otacert` file does not sign the resulting
   archive.
5. The legacy workflow writes a checksum file for `rootfs.img` and the boot
   image, then labels the first entry as the SHA-256 of the compressed `.7z`
   release.  That published label can therefore describe different bytes from
   the downloadable archive.
6. GitHub Actions and the external `mkbootimg` checkout are selected by mutable
   tags/default branch rather than immutable action and source commits.  The
   rootfs workflow also marks its build job `continue-on-error`, weakening a
   green-workflow interpretation.
7. The default build installs a DIAG package whose post-install script enables
   both router and TCP-forward services.  The forwarder listens on
   `0.0.0.0:2500` with no authentication or transport security and bridges to
   Qualcomm's DIAG socket.  This is an unacceptable appliance default: omit it
   from production images, and enable a tightly bound/firewalled diagnostic
   path only for an explicit hardware-debug session.

## U-Boot source assessment

The current U-Boot fork identifies as U-Boot 2026.01 and contains a Raphael DTS,
UFS, USB, framebuffer, buttons, poweroff and two console variants.  Its build
script selects `qcom/sm8150-xiaomi-raphael`, builds `u-boot-nodtb.bin`, appends
the DTB, and packages an Android boot image for ABL.  The default environment
scans UFS through the SCSI layer and loads `EFI/BOOT/BOOTAA64.EFI` from `cust`.

That is a credible source starting point, not a hardware acceptance result.  In
particular, its generic phone configuration comments that U-Boot Fastboot flash
supports MMC only, while Raphael boots from UFS.  We must not treat the U-Boot
Fastboot menu as a proven recovery writer.  The release workflow also acquires
`mkbootimg` from an unpinned default branch and publishes no detached signature
or build manifest.

## Baseband and voice-assistant implications

The current rootfs project reports cellular data using device firmware, QRTR,
a patched ModemManager package and startup ordering.  Those claims remain
project-reported until the custom packages are source-mapped/rebuilt and the
phone is tested.  `modemst1`, `modemst2`, `fsg`, `fsc` and `persist` are never
Linux installation targets.

The audited audio setup automates Speaker/Headphone playback and recovery from
PipeWire/RDP state.  The tree downloads `alsa-xiaomi-raphael.deb` externally and
does not contain an accepted built-in microphone capture profile or hardware
test.  Built-in capture therefore remains the first voice-appliance enablement
gap; USB audio is still the initial end-to-end fallback.

## Required replacement gates

1. Complete private device-bound and overwrite-target backups from a compatible
   ephemeral recovery; verify exact sizes and SHA-256 values.
2. Fully acquire and inspect the matching official Xiaomi Fastboot ROM before
   any persistent recovery or Linux write.
3. Convert every source input to an immutable commit and every downloaded
   binary/firmware input to a source URL, exact size and cryptographic hash.
4. Pin the cross toolchain, `mkbootimg` source commit and build container; set a
   controlled build timestamp and perform a second clean reproducibility build.
5. Replace default passwords/root SSH with key-only access and a first-boot
   recovery console policy.
6. Generate a machine-readable partition write manifest and review it against
   the live device inventory.  Exclude all NV/calibration partitions.
7. Test U-Boot and Linux with the least persistent path available; collect boot,
   storage, thermal, USB, network and audio evidence before appliance work.
