# Redmi K20 Pro sanitized device baseline

Date: 2026-09-02, Asia/Shanghai

Result: PASS for Android ADB connectivity and read-only classic Fastboot
inventory.  This is not a Linux boot, partition backup or flashing acceptance.

## Scope and privacy

The session was limited to device enumeration, Android properties, battery,
storage/partition layout and Fastboot `getvar`/`oem device-info`.  The only phone
state changes were rebooting Android into Fastboot and rebooting back to
Android, both explicitly authorized.

No `flash`, `erase`, `format`, `boot`, lock/unlock, `set_active`, partition read
or partition write command was issued.

The raw Android property stream contained unique identifiers.  It was used only
interactively and was not persisted.  This record intentionally omits serial
number, IMEI, MEID, account identifiers, carrier identity and camera fuse IDs.

## Host/tool baseline

| Item | Evidence |
| --- | --- |
| Workspace | `/home/lijian/project/work/xiaomi` |
| WSL | Ubuntu 22.04 under WSL 2 |
| Native WSL adb/fastboot | Not initially installed |
| Windows Platform Tools | ADB/Fastboot 36.0.0 (`13206524`) |
| Linux temporary Platform Tools | Fastboot 37.0.1 (`15733141`) |
| Linux ZIP source | `https://dl.google.com/android/repository/platform-tools-latest-linux.zip` |
| Clean ZIP SHA-256 | `d230f13842f60f782a8645f9c813f8f845bf36089ea7289f28c48f17979313f1` |
| ZIP integrity | `unzip -t`: no errors |

The first download was interrupted and then resumed.  Its SHA-256 was
`3e01ac5811987bf57cebe7e7129e9d1e31060c08320ab8737aae017114142cdd`, and
`unzip -t` reported extra bytes plus invalid compressed data.  It was rejected
and never executed.  A fresh complete download produced the clean evidence
above.

## USB and driver path

1. Windows enumerated Android mode as Redmi K20 Pro and ADB initially reported
   `unauthorized`.
2. After the user approved the phone's USB debugging prompt, ADB reported
   `device`.
3. In Fastboot mode Windows enumerated `18d1:d00d`, but Device Manager reported
   `CM_PROB_FAILED_INSTALL`; Windows fastboot therefore saw no device.
4. `usbipd-win 4.3.0` temporarily bound only that Fastboot USB device and
   attached it to WSL.  WSL then enumerated `18d1:d00d`.
5. The Linux fastboot process was run in a temporary WSL root process because
   the normal WSL user had no udev permission.
6. After `fastboot reboot`, the temporary usbipd binding was explicitly removed.
   Android mode returned as `18d1:4ee7`, `Not shared`.
7. Final ADB state was `device`; `sys.boot_completed` was `1`.
8. The temporary `/tmp/raphael-fastboot.*` tool directory was removed after its
   source URL, version, integrity result and SHA-256 were recorded here.

## Sanitized Android baseline

| Field | Observed value |
| --- | --- |
| Product/model | `raphael` / Redmi K20 Pro, China variant |
| CPU architecture/platform | arm64, Qualcomm `msmnile`/SM8150 family |
| RAM | `7683048 kB` usable; nominal 8 GB model |
| Storage variant | nominal 256 GB; `/data` filesystem 227 GiB |
| `/data` usage | 27 GiB used, 200 GiB available at observation time |
| Android/MIUI | Android 10, MIUI 12, `V12.0.6.0.QFKCNXM` |
| Security patch | 2020-11-01 |
| Android kernel | `4.14.117-perf-g66aed98`, arm64 |
| Bootloader state | unlocked |
| Android Verified Boot | orange/unlocked; verity enforcing |
| Partition scheme | classic non-A/B; no slot suffix or slotted names |
| Data encryption | file-based encryption enabled |
| Root | no `su` found; no Magisk package found |
| SELinux | Enforcing |
| Battery | 46%, charging, 3.933 V, 29.5 C, health good |

Direct UFS model/revision sysfs nodes and `/proc/scsi/scsi` were permission
denied to the unprivileged Android shell.  The storage-capacity classification
comes from the 231 GiB Fastboot `userdata` partition and the mounted `/data`
filesystem, not from a claimed UFS model string.

## Sanitized Fastboot baseline

The reusable command is
`tools/raphael/read_fastboot_vars.sh /absolute/path/to/fastboot`.  It explicitly
excludes unique identifiers and all write operations.

| Variable | Result |
| --- | --- |
| `product` | `raphael` |
| `unlocked` | `yes` |
| `secure` | `yes` |
| anti-rollback (`anti`) | `1` |
| `current-slot`, `slot-count` | unsupported/not found |
| `has-slot:boot`, `has-slot:system` | unsupported/not found |
| `is-userspace` | unsupported/not found; session was classic bootloader Fastboot |
| maximum download | 805306368 bytes / 768 MiB |
| boot type/size | raw / 128 MiB |
| dtbo size | 32 MiB |
| vbmeta size | 128 KiB |
| recovery size | 64 MiB |
| cache size | 256 MiB |
| vendor size | 1.5 GiB |
| userdata size | 231 GiB |
| cust size | 1 GiB |
| Verity mode | true |
| Device unlocked | true |
| Device critical unlocked | true |
| Charger screen enabled | false |

The exact sanitized command output is stored at
`logs/raphael/2026-09-02-fastboot-inventory.txt`.

## Failed/non-result checks retained for traceability

- Initial WSL `adb` and `fastboot` lookup: command not found.
- Initial WSL `lsusb` inside the sandbox: libusb initialization error; outside
  the sandbox it enumerated the attached device correctly.
- Windows Fastboot driver: failed install; no Google USB driver package existed
  under the local Android SDK.
- First `usbipd bind`: access denied because administrator privileges were
  required; the user then approved the scoped UAC operation.
- First inline cross-WSL variable loop: Windows/WSL quoting consumed the shell
  variables, producing empty labels and `Permission denied`.  No Fastboot
  request reached the phone.  It was replaced by the checked-in script.
- Direct Android reads of UFS model/revision/size and panel info were unavailable
  to the non-root shell.  They are recorded as gaps, not treated as passes.

## Gate decision

The physical device is a strong candidate for the U-Boot/Debian route: it is an
8/256 GB `raphael`, both normal and critical unlocking are already enabled, and
the classic partition contract matches the community work at a high level.

The next gate is not flashing.  It is obtaining trusted stock recovery material
and verified backups for every partition a selected image would modify, then
building or auditing an ephemeral boot artifact tied to exact source revisions.
