# Raphael recovery-material acquisition

Date: 2026-09-02, Asia/Shanghai

Status: in progress

## User-data boundary

The user explicitly does not require files stored in the Android filesystem,
including photos, downloads and application data.  The 231 GiB `userdata`
partition is therefore excluded from backup.

This does not waive protection for device-bound NV and calibration data.
`modemst1`, `modemst2`, `fsg`, `fsc`, `persist`, `persistbak` and
`devinfo` remain in the preservation set.  The safety set additionally keeps
the matching `modem`, `bluetooth` and `dsp` firmware partitions.  None is a
planned Linux installation target, and every raw copy remains private.

## Matching stock Fastboot ROM

The connected Android build identifies itself as China stable
`V12.0.6.0.QFKCNXM`.  The matching package is:

- file: `raphael_images_V12.0.6.0.QFKCNXM_20201209.0000.00_10.0_cn_4589b26f0f.tgz`
- official URL:
  `https://bigota.d.miui.com/V12.0.6.0.QFKCNXM/raphael_images_V12.0.6.0.QFKCNXM_20201209.0000.00_10.0_cn_4589b26f0f.tgz`
- expected size from the official CDN range response: `3727922045` bytes
- historical published MD5: `4589b26f0fb147c93fa0c127abd31f0a`
- official object last-modified value: `2020-12-30 09:03:52 GMT`
- official object ETag: `d0f212c1ba8e07b6d19d8e6f29c71045`

A bare HEAD request returned `403 referer-acl-deny`.  A one-byte GET with a
MIUI Referer returned HTTP 206 and `Content-Range: bytes 0-0/3727922045`,
confirming that the object currently exists without downloading it yet.

## Official TWRP candidates

Team Win currently marks `raphael/raphaelin` support as current.  The newest
published Raphael image is:

- file: `twrp-3.7.1_12-1-raphael.img`
- official landing page:
  `https://dl.twrp.me/raphael/twrp-3.7.1_12-1-raphael.img.html`
- size: `67108864` bytes (64 MiB), matching the device recovery partition
- expected SHA-256:
  `3f555e26847df70e4c61ae8c5fd7d27ca7013a21d72d548dc738354ea071c9b2`
- expected MD5: `8b99578e89672ae28b1432a501098a33`
- official detached PGP signature: available from the landing page
- official Team Win public key: `https://dl.twrp.me/public.asc`

The image was transported through a SourceForge mirror because the Team Win
payload endpoint was impractically slow.  Its identity was independently tied
back to Team Win's official publication:

- observed size: `67108864` bytes
- observed SHA-256:
  `3f555e26847df70e4c61ae8c5fd7d27ca7013a21d72d548dc738354ea071c9b2`
- observed MD5: `8b99578e89672ae28b1432a501098a33`
- detached signature: good RSA signature by Team Win key
  `9570 7D42 307C 9D41 D09B F709 1D85 97D7 891A 43DF`
- signature time: 2024-07-25 08:13:39 CST
- static boot-image inspection: Android boot image, 4 KiB page size;
  `twrp_raphael-eng`, build date 2024-07-24; its `twrp.flags` explicitly maps
  the modem/EFS, persist, boot, recovery, cache, DTBO, vendor, cust, logo,
  VBMeta, Bluetooth and DSP partitions

The isolated verification keyring reports an unknown trust level, as expected
for a freshly imported key; the fingerprint above was checked against Team
Win's official key publication.  Matching both official digests plus the
detached signature accepts the bytes, not their runtime compatibility.

### Ephemeral boot attempt 1

`fastboot boot twrp-3.7.1_12-1-raphael.img` completed both its loader `Sending`
and `Booting` stages with `OKAY`.  The phone then re-enumerated as ordinary
Android: ADB was non-root, build flavor was `raphael-user`, and Android boot
completed normally.  Therefore this is a **runtime compatibility failure**,
not a successful recovery boot.  No partition was flashed, erased or formatted.

Team Win's official Raphael listing advises trying an older version when the
newest image does not work with the installed firmware.  One final non-writing
compatibility attempt is therefore limited to the official Android-9-based
image:

- file: `twrp-3.7.0_9-0-raphael.img`
- official landing page:
  `https://dl.twrp.me/raphael/twrp-3.7.0_9-0-raphael.img.html`
- expected size: `67108864` bytes
- expected SHA-256:
  `bc39b3e152bfe3c6ccf64e037d84fb843e072740d9aa4cec9780b61cef88c5ad`
- expected MD5: `1ecf91bf43919e7a72a2f9fbe23c0ebe`

If that image also falls back to Android, recovery will not be flashed merely
to obtain backups.  The gate will stop until matching stock recovery/ROM bytes
are fully secured and a reviewed rollback procedure exists.

## Backup implementation

`tools/raphael/backup_recovery_partitions.sh` is the only prepared raw-read
path.  It requires root ADB plus Raphael TWRP runtime markers, resolves named
block devices, checks every expected size, streams with `adb exec-out dd`, and
hashes each completed image.  It contains no restore or phone-write command and
has an explicit `userdata` guard.  Private output is mode `0600` below a mode
`0700` ignored directory.

A normal-Android, name-only block inventory confirmed that every required
preservation name exists on this device, including `fsc` and `persistbak`.
It also confirmed both `logo` and legacy `splash`.  No block contents were read
during that check.  Running the helper against ordinary non-root Android was
also verified to stop with `recovery adbd is not root`; it created no output.

## Acceptance gates

- [ ] Download the stock Fastboot ROM from the official Xiaomi CDN.
- [ ] Verify exact byte size, MD5 and locally record SHA-256.
- [ ] Extract into a staging directory and inventory every image and flash
      script without executing any script.
- [x] Acquire the latest TWRP bytes and bind them to the official publication.
- [x] Verify SHA-256, MD5 and detached PGP signature.
- [x] Inspect the Android boot-image header and confirm `raphael` provenance.
- [ ] Obtain a compatible ephemeral TWRP runtime; latest-image attempt failed.
- [ ] Back up only the preservation set and the currently installed partitions
      that the selected Linux layout will overwrite.
- [ ] Store private backups with mode `0600` and publish only hashes/sizes.
- [x] Prove Android reboot after the failed temporary-boot attempt: ADB online,
      `raphael-user`, `sys.boot_completed=1`.
