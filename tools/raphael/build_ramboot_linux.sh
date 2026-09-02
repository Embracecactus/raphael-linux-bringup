#!/usr/bin/env bash
# Build a boot.img that runs only a BusyBox initramfs on Xiaomi Raphael.
# This script never communicates with a phone; booting is a separate step.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
KERNEL_DEB=${KERNEL_DEB:-$REPO_ROOT/artifacts/downloads/community-audit/kernel-v7.0/linux-image-xiaomi-raphael.deb}
BUSYBOX_DEB=${BUSYBOX_DEB:-$REPO_ROOT/artifacts/downloads/community-audit/busybox-static_1.30.1-7ubuntu3.1_arm64.deb}
MKBOOTIMG_DEB=${MKBOOTIMG_DEB:-$REPO_ROOT/artifacts/downloads/community-audit/mkbootimg_10.0.0+r36-9_all.deb}
INIT_SOURCE=$SCRIPT_DIR/ramboot-init
OUTPUT_DIR=${OUTPUT_DIR:-$REPO_ROOT/artifacts/build/ramboot}

EXPECTED_KERNEL_DEB_SHA256=9f1a0ca50c7e0035c0ec8fea84e46dd9e5b04869e3f3506d7aae83ea9d7f230e
EXPECTED_BUSYBOX_DEB_SHA256=c467c2014f91795a69237339693a64089347f73a96d10613e7285b7433b3965a
EXPECTED_MKBOOTIMG_DEB_SHA256=63a21af69fd622fb1261f9a12375007ca48613830d9a9bf8436721e56886c2c9
EXPECTED_KERNEL_PAYLOAD_SHA256=36c09c7ccbe5ec31a2549267a0921db9ec9e9c5d7086071719a5dc1de1cd8490
BOOT_PARTITION_LIMIT=134217728
KERNEL_LOAD_ADDRESS=$((0x80008000))
KERNEL_UNCOMPRESSED_SIZE=$((0x02040000))
RAMDISK_LOAD_ADDRESS=$((0x84000000))
DTB_LOAD_ADDRESS=$((0x85000000))
FIRST_RESERVED_ADDRESS=$((0x85700000))

CMDLINE='console=ttyMSM0,115200n8 console=tty0 earlycon rdinit=/init loglevel=8 ignore_loglevel clk_ignore_unused pd_ignore_unused panic=30'

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

need()
{
	command -v "$1" >/dev/null 2>&1 || die "missing host tool: $1"
}

verify_sha256()
{
	local file=$1 expected=$2 actual
	[ -f "$file" ] || die "missing input: $file"
	actual=$(sha256sum "$file" | awk '{print $1}')
	[ "$actual" = "$expected" ] || die "SHA-256 mismatch for $file: $actual"
}

for tool in awk cpio dd dpkg-deb find gzip install od python3 sha256sum sort stat touch tr; do
	need "$tool"
done
verify_sha256 "$KERNEL_DEB" "$EXPECTED_KERNEL_DEB_SHA256"
verify_sha256 "$BUSYBOX_DEB" "$EXPECTED_BUSYBOX_DEB_SHA256"
verify_sha256 "$MKBOOTIMG_DEB" "$EXPECTED_MKBOOTIMG_DEB_SHA256"
[ -x "$INIT_SOURCE" ] || die "init is missing or not executable: $INIT_SOURCE"

stage=$(mktemp -d /tmp/raphael-ramboot-build.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/kernel" "$stage/busybox" "$stage/mkbootimg" "$stage/rootfs" "$OUTPUT_DIR"
dpkg-deb -x "$KERNEL_DEB" "$stage/kernel"
dpkg-deb -x "$BUSYBOX_DEB" "$stage/busybox"
dpkg-deb -x "$MKBOOTIMG_DEB" "$stage/mkbootimg"

mapfile -t kernels < <(printf '%s\n' "$stage"/kernel/boot/vmlinuz-*)
[ "${#kernels[@]}" -eq 1 ] || die 'expected exactly one vmlinuz in kernel package'
kernel=${kernels[0]}
mapfile -t configs < <(printf '%s\n' "$stage"/kernel/boot/config-*)
[ "${#configs[@]}" -eq 1 ] || die 'expected exactly one kernel config'
config=${configs[0]}
dtb=$stage/kernel/boot/dtbs/qcom/sm8150-xiaomi-raphael.dtb
busybox=$stage/busybox/bin/busybox
mkbootimg=$stage/mkbootimg/usr/bin/mkbootimg
[ -f "$dtb" ] || die 'Raphael DTB is absent from kernel package'
[ -x "$busybox" ] || die 'static arm64 BusyBox is absent from package'
[ -f "$mkbootimg" ] || die 'mkbootimg is absent from package'

required_builtin=(
	CONFIG_BLK_DEV_INITRD CONFIG_RD_GZIP CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT
	CONFIG_PROC_FS CONFIG_SYSFS CONFIG_TMPFS CONFIG_CONFIGFS_FS
	CONFIG_SERIAL_MSM CONFIG_SERIAL_MSM_CONSOLE CONFIG_SERIAL_QCOM_GENI
	CONFIG_SERIAL_QCOM_GENI_CONSOLE CONFIG_USB CONFIG_USB_DWC3
	CONFIG_USB_DWC3_QCOM CONFIG_USB_GADGET CONFIG_USB_CONFIGFS
	CONFIG_USB_CONFIGFS_ACM CONFIG_USB_CONFIGFS_NCM
)
for option in "${required_builtin[@]}"; do
	grep -qx "$option=y" "$config" || die "kernel lacks built-in $option"
done

# Linux EFI zboot header: u32 payload_offset and payload_size at bytes 8..15;
# the NUL-padded compression name starts at byte 24 after two reserved u32s.
zboot_magic=$(od -An -tu4 -j0 -N4 "$kernel" | tr -d ' ')
[ "$zboot_magic" = 23117 ] || die 'not an arm64 EFI zboot image'
read -r payload_offset payload_size < <(od -An -tu4 -j8 -N8 "$kernel")
compression=$(dd if="$kernel" bs=1 skip=24 count=4 status=none)
[ "$compression" = gzip ] || die "unsupported EFI zboot compression: $compression"
kernel_size=$(stat -c %s "$kernel")
(( payload_offset > 0 && payload_size > 0 && payload_offset + payload_size <= kernel_size )) || die 'invalid EFI zboot payload bounds'

image_gz=$stage/Image.gz
dd if="$kernel" of="$image_gz" iflag=skip_bytes,count_bytes skip="$payload_offset" count="$payload_size" status=none
gzip -t "$image_gz"
verify_sha256 "$image_gz" "$EXPECTED_KERNEL_PAYLOAD_SHA256"

rootfs=$stage/rootfs
mkdir -p "$rootfs"/{bin,dev,etc,proc,root,run,sys,tmp}
install -m 0755 "$busybox" "$rootfs/bin/busybox"
install -m 0755 "$INIT_SOURCE" "$rootfs/init"
printf 'Raphael RAM-only Linux\n' >"$rootfs/etc/issue"
# Normalize archive mtimes so identical verified inputs produce identical bytes.
find "$rootfs" -exec touch -h -d '@0' {} +

initramfs=$OUTPUT_DIR/raphael-ramboot-initramfs.cpio.gz
(
	cd "$rootfs"
	find . -print0 | LC_ALL=C sort -z | cpio --null -o --format=newc --owner=0:0 --reproducible 2>/dev/null
) | gzip -n -9 >"$initramfs"
gzip -t "$initramfs"

kernel_dtb=$OUTPUT_DIR/raphael-Image.gz-dtb
install -m 0644 "$image_gz" "$kernel_dtb"
cat "$dtb" >>"$kernel_dtb"

boot_img=$OUTPUT_DIR/raphael-ramboot-linux.img
python3 "$mkbootimg" \
	--kernel "$kernel_dtb" \
	--ramdisk "$initramfs" \
	--cmdline "$CMDLINE" \
	--pagesize 4096 \
	--base 0x80000000 \
	--ramdisk_offset 0x04000000 \
	--header_version 0 \
	--output "$boot_img"

# U-Boot's Android image parser obtains DTBs from the dedicated v2 area.  This
# second image is for a RAM-only ABL -> U-Boot -> Linux chain, not direct ABL.
uboot_boot_img=$OUTPUT_DIR/raphael-ramboot-linux-v2.img
python3 "$mkbootimg" \
	--kernel "$image_gz" \
	--ramdisk "$initramfs" \
	--dtb "$dtb" \
	--cmdline "$CMDLINE" \
	--pagesize 4096 \
	--base 0x80000000 \
	--ramdisk_offset 0x04000000 \
	--dtb_offset 0x05000000 \
	--header_version 2 \
	--output "$uboot_boot_img"

boot_size=$(stat -c %s "$boot_img")
uboot_boot_size=$(stat -c %s "$uboot_boot_img")
kernel_end=$((KERNEL_LOAD_ADDRESS + KERNEL_UNCOMPRESSED_SIZE))
initramfs_size=$(stat -c %s "$initramfs")
ramdisk_end=$((RAMDISK_LOAD_ADDRESS + initramfs_size))
dtb_size=$(stat -c %s "$dtb")
dtb_end=$((DTB_LOAD_ADDRESS + dtb_size))
(( kernel_end <= RAMDISK_LOAD_ADDRESS )) || die 'uncompressed kernel overlaps initramfs load address'
(( ramdisk_end <= DTB_LOAD_ADDRESS )) || die 'initramfs overlaps v2 DTB load address'
(( dtb_end <= FIRST_RESERVED_ADDRESS )) || die 'v2 DTB overlaps first DT reserved-memory region'
(( boot_size < BOOT_PARTITION_LIMIT )) || die "boot image exceeds 128 MiB partition: $boot_size"
(( uboot_boot_size < BOOT_PARTITION_LIMIT )) || die "U-Boot-target image exceeds 128 MiB partition: $uboot_boot_size"
[ "$(dd if="$boot_img" bs=1 count=8 status=none)" = 'ANDROID!' ] || die 'output lacks Android boot magic'
[ "$(dd if="$uboot_boot_img" bs=1 count=8 status=none)" = 'ANDROID!' ] || die 'U-Boot-target output lacks Android boot magic'

manifest=$OUTPUT_DIR/manifest.txt
{
	printf 'format=android-bootimg-v0\n'
	printf 'safety=ram-only-no-block-device-mount-or-write\n'
	printf 'pagesize=4096\n'
	printf 'base=0x80000000\n'
	printf 'kernel_load_address=0x80008000\n'
	printf 'kernel_uncompressed_end=0x%x\n' "$kernel_end"
	printf 'ramdisk_load_address=0x84000000\n'
	printf 'ramdisk_end=0x%x\n' "$ramdisk_end"
	printf 'v2_dtb_load_address=0x85000000\n'
	printf 'v2_dtb_end=0x%x\n' "$dtb_end"
	printf 'first_reserved_memory_address=0x85700000\n'
	printf 'cmdline=%s\n' "$CMDLINE"
	printf 'efi_zboot_payload_offset=%s\n' "$payload_offset"
	printf 'efi_zboot_payload_size=%s\n' "$payload_size"
	printf 'kernel_deb_sha256=%s\n' "$EXPECTED_KERNEL_DEB_SHA256"
	printf 'busybox_deb_sha256=%s\n' "$EXPECTED_BUSYBOX_DEB_SHA256"
	printf 'mkbootimg_deb_sha256=%s\n' "$EXPECTED_MKBOOTIMG_DEB_SHA256"
	printf 'image_gz_sha256=%s\n' "$(sha256sum "$image_gz" | awk '{print $1}')"
	printf 'dtb_sha256=%s\n' "$(sha256sum "$dtb" | awk '{print $1}')"
	printf 'init_sha256=%s\n' "$(sha256sum "$INIT_SOURCE" | awk '{print $1}')"
	printf 'initramfs_sha256=%s\n' "$(sha256sum "$initramfs" | awk '{print $1}')"
	printf 'kernel_dtb_sha256=%s\n' "$(sha256sum "$kernel_dtb" | awk '{print $1}')"
	printf 'boot_img_sha256=%s\n' "$(sha256sum "$boot_img" | awk '{print $1}')"
	printf 'boot_img_size=%s\n' "$boot_size"
	printf 'uboot_boot_img_format=android-bootimg-v2-with-dtb\n'
	printf 'uboot_boot_img_sha256=%s\n' "$(sha256sum "$uboot_boot_img" | awk '{print $1}')"
	printf 'uboot_boot_img_size=%s\n' "$uboot_boot_size"
} >"$manifest"

printf 'Built direct-ABL RAM-only Linux image: %s\n' "$boot_img"
printf 'Built U-Boot-target RAM-only Linux image: %s\n' "$uboot_boot_img"
cat "$manifest"
