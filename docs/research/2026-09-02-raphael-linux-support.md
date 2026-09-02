# Redmi K20 Pro native Linux support research

Snapshot date: 2026-09-02 (Asia/Shanghai)

Device codename: `raphael`

## Executive conclusion

The Redmi K20 Pro can boot a native arm64 Linux kernel and Debian/Ubuntu
userspace.  This is not an Android chroot/proot route.  The port is nevertheless
an active community port rather than an upstream-supported product: SM8150 is
upstream, while the Raphael device tree and a material patch stack remain out
of tree.

For a voice-assistant appliance, the shortest defensible route is:

1. U-Boot plus Debian Server, without GNOME or Phosh initially.
2. Reproduce and pin the active Raphael kernel and firmware sources locally.
3. Prove an ephemeral boot and recovery path before writing partitions.
4. Use USB/Bluetooth audio for the first end-to-end voice loop if necessary.
5. Close the built-in microphone ASoC/ALSA-UCM capture path as the first device
   enablement task.

postmarketOS is not the recommended first installation route in this snapshot,
because the Raphael device, kernel and firmware packages are archived as
unmaintained.  UEFI/rEFInd remains a useful later option for multi-kernel or
multi-OS experiments, but introduces more boot and partitioning layers.

## Evidence levels

- **Source-confirmed:** observed in current upstream/community source or build
  configuration.
- **Project-reported:** claimed by a project README or release; not accepted on
  this physical phone yet.
- **Hardware-confirmed:** reproduced on the connected phone and recorded under
  `docs/verification/`.

## Upstream and community state

### Mainline Linux

The current Linux tree contains Qualcomm SM8150 support and several SM8150
boards, but no `sm8150-xiaomi-raphael.dts`.  Raphael therefore still depends on
an out-of-tree device tree and patch set.

- Mainline QCOM DTS Makefile at inspected commit:
  https://github.com/torvalds/linux/blob/89a312991dc6e638a36adc43ccb91dbc25504c04/arch/arm64/boot/dts/qcom/Makefile
- Active community branch:
  https://github.com/Aospa-raphael-unofficial/linux/tree/sm8150/7.2.0
- Raphael DTS:
  https://github.com/Aospa-raphael-unofficial/linux/blob/sm8150/7.2.0/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dts

The inspected community `sm8150/7.2.0` head was
`e23773fa94eafcabc04ec6b3dd2c06634d46ce6f`.  It carries device enablement for
display/touch, audio, charging/fuel gauge, Wi-Fi/Bluetooth, USB, IPA and Qualcomm
remote processors in addition to shared SM8150 work.

### postmarketOS

The current pmaports checkout was
`3ef06e837fa6ead3ea9c5b24a50350bcc5873eba` (2026-09-01).  The Raphael device,
kernel and firmware packages live under `device/archived/`; the package header
says `Archived: unmaintained`.  The move occurred in commit
`cfbc1de3c7de56251800d53d20afcf92c313aa12`.

- Archived device package:
  https://gitlab.postmarketos.org/postmarketOS/pmaports/-/blob/main/device/archived/device-xiaomi-raphael/APKBUILD
- Archive commit:
  https://gitlab.postmarketos.org/postmarketOS/pmaports/-/commit/cfbc1de3c7de56251800d53d20afcf92c313aa12
- Historical wiki page, which may lag pmaports:
  https://wiki.postmarketos.org/wiki/Xiaomi_Mi_9T_Pro_/_Redmi_K20_Pro_(xiaomi-raphael)

### Boot and rootfs projects

- U-Boot/rootfs integration:
  https://github.com/GengWei1997/linux-xiaomi-raphael-uboot
- UEFI/rootfs integration:
  https://github.com/GengWei1997/linux-xiaomi-raphael-uefi
- Current richer rootfs/package integration inspected at
  `51f9cd0634e09ed70885f91806bf08213211cc2e`:
  https://github.com/GavinLiuOnline/xiaomi_raphael_build_rootfs
- Project Aloha SM8150 UEFI platform:
  https://github.com/Project-Aloha/mu_aloha_platforms

These projects demonstrate a working route, but their feature tables are not a
substitute for physical acceptance.  Documentation across forks also describes
more than one historical partition layout, so image generation and flashing
must be tied to one exact source revision.

## Support matrix

| Subsystem | Current evidence | Acceptance status for this phone |
| --- | --- | --- |
| ABL/Fastboot entry | Hardware-confirmed; unlocked classic Fastboot | Passed, read-only |
| U-Boot/UEFI Linux boot | Community releases and reports | Not yet booted |
| Display/panel | Project-reported usable, occasional inversion; replacement panels may differ | Not tested |
| Touch | Project-reported usable with original panel caveat | Not tested |
| Adreno GPU | Source present and project-reported usable | Not tested |
| Wi-Fi | Project-reported 2.4/5 GHz; open latency/power-save report exists | Not tested |
| Bluetooth | Project-reported file and audio output support | Not tested |
| USB NCM/OTG | Source/project support | Not tested |
| Speaker/headphone | Project-reported usable | Not tested |
| Built-in microphone | Kernel capture links exist; packaged UCM lacks capture device | Open priority |
| Charging/battery/RTC | Source and project claims | Not tested |
| Cellular data | Project-reported with SIM2/firmware/operator caveats | Not tested |
| Calls/SMS | Explicitly unsupported by current rootfs project | Out of scope initially |
| Camera | No current support plan in rootfs project | Out of scope |
| Venus video acceleration | Open/in progress | Not ready |
| NPU | Project reports unavailable | Not ready |
| Poweroff/suspend | Open reports include poweroff rebooting | Not appliance-ready |

Relevant issue evidence:

- 128 GB UFS OCS boot failure and a community U-Boot fix report:
  https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/issues/21
- Wi-Fi latency variation:
  https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/issues/15
- `shutdown`/`poweroff` reboot behaviour:
  https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/issues/8
- SIM/firmware combination warning:
  https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/issues/13

The connected device is the nominal 256 GB variant, so the reported 128 GB UFS
case is not directly applicable, but storage still requires repeated-boot and
I/O acceptance.

## Voice-assistant-specific finding

The current Raphael DTS defines SLIM capture DAI links and analog microphone
bias routes.  The currently published `kernel-v7.0`
`alsa-xiaomi-raphael.deb`, however, only exposes Speaker and Headphone
`PlaybackPCM` devices and has no `CapturePCM` or microphone device section.

This was checked against the 1,798-byte release asset with SHA-256
`932a3420bb24b7d5c8a39b1d9cdb7a6db51166579aa2ba8606f3bff8d3591d87`.
GitHub's asset digest matched, and the packaged `HiFi.conf` was byte-identical
to the file at exact source commit
`128ac1fec88e7a141cebfab4193c6c4cc512a1d1`:

https://github.com/GavinLiuOnline/xiaomi_raphael_build_kernel/blob/128ac1fec88e7a141cebfab4193c6c4cc512a1d1/alsa-xiaomi-raphael/usr/share/alsa/ucm2/Raphael/HiFi.conf

This makes built-in capture an integration gap rather than proof that the codec
has no kernel path.  The later hardware procedure should capture `dmesg`, ASoC
cards, `arecord -l`, mixer controls and debugfs DAPM state, establish one known
good raw capture route, then encode that route in a minimal UCM profile.

Until that closes, USB audio is the preferred first acceptance device.  The
first voice stack should keep wake word, VAD and audio supervision local, while
allowing ASR/LLM to be remote or hybrid.  Full local inference can be evaluated
after thermal and power measurements; current community Linux does not provide
a usable NPU path.

## Image and flashing risks

1. A current packaging script overwrites or clears `boot`, `vendor`, `cust`,
   `userdata`, `logo`, `vbmeta` and `dtbo`; it is a destructive single-OS
   conversion, not a harmless installer:
   https://github.com/GavinLiuOnline/xiaomi_raphael_build_rootfs/blob/master/pack/META-INF/com/google/android/updater-script
2. Current rootfs scripts create `root` and `user` with password `1234` and
   enable password/root SSH.  Any usable image must replace this with unique
   credentials or key-only SSH:
   https://github.com/GavinLiuOnline/xiaomi_raphael_build_rootfs/blob/master/scripts/12-create-users.sh
3. Whole-image releases include opaque boot/firmware/rootfs artifacts.  Pin
   sources, inspect scripts, rebuild locally and record SHA-256 values before
   hardware use.
4. Do not begin with `fastboot erase dtbo`.  First establish backups, recovery,
   exact partition contracts and an ephemeral boot where supported.

Official U-Boot guidance treats `fastboot boot u-boot.img` as an early Qualcomm
phone diagnostic and notes that U-Boot fastboot currently has no UFS storage
backend:

https://docs.u-boot.org/en/latest/board/qualcomm/phones.html

## Staged plan

1. **Baseline:** sanitized Android and Fastboot inventory. Completed on
   2026-09-02; see the verification record.
2. **Recovery evidence:** acquire and verify stock firmware/recovery sources,
   then produce readable backups of the exact partitions that a chosen route
   would modify.
3. **Reproducible boot artifact:** pin U-Boot, Linux, DTS, firmware and rootfs
   revisions; build locally and generate a manifest plus hashes.
4. **Ephemeral boot:** try only a source-reviewed artifact; collect display,
   USB console and kernel logs without writing partitions.
5. **Linux acceptance:** storage soak, reboot cycles, thermal/power, Wi-Fi, USB,
   display/touch, charging and playback/capture.
6. **Voice integration:** close microphone UCM, then deploy the supervised
   wake/VAD/ASR/LLM/TTS service.
7. **Later OpenVela/NuttX work:** start only after the Linux path is measured;
   keep SM8150 chip support separate from the physical Raphael board layer.
