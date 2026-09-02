# Raphael ABL findings and recovery backup gate

Snapshot date: 2026-09-03 (Asia/Shanghai)

## Outcome

The connected phone's ABL `fastboot boot` implementation is not a usable entry
point for the planned RAM-only U-Boot chain.  This is now based on three
controlled hardware outcomes rather than a toolchain guess:

1. A source-built Linux image made with GCC was accepted by the Fastboot command
   but returned immediately to ABL Fastboot before its USB marker appeared.
2. The same pinned source and initramfs built with the community's LLVM 22
   lineage behaved identically.  GCC is therefore not the sole cause.
3. The Raphael project's published U-Boot v1.0.0 image was rejected by ABL with
   `Failed to load/authenticate boot image: Load Error`, despite using a
   different Android load-address layout from the local U-Boot image.

Shrinking the Linux PID 1 would only test the first case's image-size margin; it
cannot make the published U-Boot pass ABL authentication/loading.  That
experiment is deferred until a useful ABL diagnostic path exists.

## Community boot-chain comparison

The current Raphael integration installs a three-part chain:

`ABL -> U-Boot in boot -> Linux boot material in cache -> rootfs in userdata`

Its documented install procedure erases and rewrites several partitions.  It
is evidence that Raphael Linux exists, but it is not itself a safe first action
on this phone.  The source and release are used only as inputs to a locally
reviewed, reproducible delivery:

- https://github.com/GengWei1997/linux-xiaomi-raphael-uboot
- https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/releases/tag/v1.0.0
- https://github.com/cuicanmx/Linux-xiaomi-raphael

Official U-Boot guidance describes ABL chain-loading for modern Qualcomm phones
and requires `CONFIG_LINUX_KERNEL_IMAGE_HEADER=y`.  The local U-Boot build has
that option enabled.  The FOSDEM companion material also explains that failures
before a console is available commonly provide no feedback and fall back to
Fastboot:

- https://docs.u-boot.org/en/latest/board/qualcomm/phones.html
- https://archive.fosdem.org/2024/events/attachments/fosdem-2024-1716-u-boot-for-modern-qualcomm-phones/slides/22104/fosdem24_aDevbas.pdf

## Recovery bootstrap decision

Raw modem NV and calibration partitions cannot be read from ordinary non-root
Android or classic Fastboot.  A root recovery session is required before the
first Linux installation writes `boot`, `cache`, `dtbo` or `userdata`.

The bounded bootstrap is:

1. Match the running MIUI build exactly.
2. Download and verify its full stock fastboot package.
3. Extract and verify stock `recovery.img` before changing recovery.
4. Write only the independent `recovery` partition with the official,
   device-matched TWRP image.
5. Enter TWRP and use root ADB only to read the preservation and safety sets.
6. Refuse every later flash if any required backup is missing, short or lacks a
   SHA-256 digest.

The phone runs `V12.0.6.0.QFKCNXM`; the matching Xiaomi CDN package passed its
published MD5 and all extracted image MD5 values matched the package's own
manifest.  The selected TWRP 3.7.1_12-1 image passed SHA-256 and TeamWin OpenPGP
signature verification.  TeamWin's current Raphael page documents the same
`fastboot flash recovery` installation target:

- https://twrp.me/xiaomi/xiaomimi9tpro.html
- https://dl.twrp.me/raphael/twrp-3.7.1_12-1-raphael.img.html

## Completed recovery and preservation gate

After explicit approval, the official TWRP image was written to `recovery`.
MIUI restored stock recovery after the first normal boot, so the same verified
image was flashed a second time and the phone was booted immediately with
Volume Up.  TWRP 3.7.1_12-1 identified the device as Raphael, and the user chose
the read-only system-partition policy.

Two independent copies of the seven-partition modem NV/calibration preservation
set were read through root ADB and compared byte-for-byte.  A third backup then
captured the complete 19-partition preservation and rollback set, including
`boot`, `cache`, `dtbo`, `vbmeta`, `recovery`, `vendor`, `cust`, `modem`,
`bluetooth`, `dsp`, `logo` and `splash`.  Every file has its exact size and
SHA-256 in a private manifest.  Userdata was deliberately excluded by the
user's stated scope.

The backup gate is therefore `PASS`.  Raw backups remain under ignored
`artifacts/device-private/`; their device-specific hashes are not copied into
Git.  At this gate no Linux image had been written to `boot`, `cache`,
`userdata` or `dtbo`.  A later explicit authorization tied to the exact write
manifest allowed that transition on 2026-09-03; its execution and hardware
results are recorded separately in the persistent boot evidence.
