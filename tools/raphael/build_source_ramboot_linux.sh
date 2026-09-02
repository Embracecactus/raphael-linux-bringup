#!/usr/bin/env bash
# Build a source-derived, RAM-only Linux boot image for Xiaomi Raphael.
# The Android boot header contains a zero-length ramdisk; the initramfs is
# compiled into the kernel to avoid ABL's fixed external-ramdisk layout.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
KERNEL_SOURCE=${KERNEL_SOURCE:-$REPO_ROOT/third_party/raphael-kernel}
BUILDER_SOURCE=${BUILDER_SOURCE:-$REPO_ROOT/third_party/raphael-kernel-builder}
BUSYBOX_DEB=${BUSYBOX_DEB:-$REPO_ROOT/artifacts/downloads/community-audit/busybox-static_1.30.1-7ubuntu3.1_arm64.deb}
MKBOOTIMG_DEB=${MKBOOTIMG_DEB:-$REPO_ROOT/artifacts/downloads/community-audit/mkbootimg_10.0.0+r36-9_all.deb}
KERNEL_ARCHIVE=${KERNEL_ARCHIVE:-$REPO_ROOT/artifacts/downloads/source/xiaomi_raphael_kernel-c526b7bf7ebc3fbfee244be252a2c1bd061ca749.proxy.tar.gz}
BUILDER_ARCHIVE=${BUILDER_ARCHIVE:-$REPO_ROOT/artifacts/downloads/source/xiaomi_raphael_build_kernel-128ac1fec88e7a141cebfab4193c6c4cc512a1d1.proxy.tar.gz}
OUTPUT_DIR=${OUTPUT_DIR:-$REPO_ROOT/artifacts/build/source-ramboot-c526-gcc11}
TOOLCHAIN=${TOOLCHAIN:-gcc}
JOBS=${JOBS:-$(nproc)}
ALLOW_CLEAN=${ALLOW_CLEAN:-0}

KERNEL_COMMIT=c526b7bf7ebc3fbfee244be252a2c1bd061ca749
KERNEL_TREE=505b5c0cbd9307ce58f62a8d48150a49217735f6
KERNEL_ARCHIVE_SHA256=d18e0ae1a9a76d467a5daf8c5e7d2265b3edfbddafe3e2752f51dffc852c66ba
BUILDER_COMMIT=128ac1fec88e7a141cebfab4193c6c4cc512a1d1
BUILDER_TREE=ee3e9a20ba8b20b438ff649e4ced707d54611bb1
BUILDER_ARCHIVE_SHA256=606e5b33afa19d234067557758de6f713879a0df9442af9b36ef0bdcb1349c99
PATCH_SHA256=7af97408440be4b57b321eb03f5fbed2d1b96f6108f307a7c9bfc9a8d157bbf7
RUNTIME_PATCH_SHA256=eaddf7fd86bfde88d63e0e52b7f8182af10ce8f71d83f958782f258207ea34e3
BASE_CONFIG_SHA256=81a9ef815a22ba6d9b8ffeda99d650662243ea605f802bb5cd910908c2d0d053
BUSYBOX_DEB_SHA256=c467c2014f91795a69237339693a64089347f73a96d10613e7285b7433b3965a
MKBOOTIMG_DEB_SHA256=63a21af69fd622fb1261f9a12375007ca48613830d9a9bf8436721e56886c2c9
INIT_SHA256=119a1a62e72704b88a8e88ba6eb4ddf4f03e082f040069bcd547dc788b14fe9b
SOURCE_DATE_EPOCH=1781099591
BOOT_PARTITION_LIMIT=134217728
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

for tool in awk cat cpio dd dpkg-deb file find git grep gzip install make mkdir \
	nproc od python3 readelf realpath rm rsync sed sha256sum stat touch tr; do
	need "$tool"
done
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die 'JOBS must be a positive integer'

KERNEL_SOURCE=$(realpath -- "$KERNEL_SOURCE")
BUILDER_SOURCE=$(realpath -- "$BUILDER_SOURCE")
OUTPUT_DIR=$(realpath -m -- "$OUTPUT_DIR")
case "$OUTPUT_DIR/" in
	"$REPO_ROOT/artifacts/build/"*) ;;
	*) die 'OUTPUT_DIR must remain below artifacts/build/' ;;
esac
if [ -e "$OUTPUT_DIR" ]; then
	[ "$ALLOW_CLEAN" = 1 ] || die "output exists; set ALLOW_CLEAN=1 to replace it: $OUTPUT_DIR"
	rm -rf -- "$OUTPUT_DIR"
fi

patch_file=$BUILDER_SOURCE/patchs/raphael.patch
runtime_patch=$REPO_ROOT/patches/raphael-kernel/0001-raphael-runtime-v3-display-usb-policy.patch
base_config=$BUILDER_SOURCE/raphael.config
verify_sha256 "$patch_file" "$PATCH_SHA256"
verify_sha256 "$runtime_patch" "$RUNTIME_PATCH_SHA256"
verify_sha256 "$base_config" "$BASE_CONFIG_SHA256"
verify_sha256 "$BUSYBOX_DEB" "$BUSYBOX_DEB_SHA256"
verify_sha256 "$MKBOOTIMG_DEB" "$MKBOOTIMG_DEB_SHA256"
verify_sha256 "$KERNEL_ARCHIVE" "$KERNEL_ARCHIVE_SHA256"
verify_sha256 "$BUILDER_ARCHIVE" "$BUILDER_ARCHIVE_SHA256"
verify_sha256 "$SCRIPT_DIR/ramboot-init" "$INIT_SHA256"

actual_kernel_tree=$($SCRIPT_DIR/verify_git_tree.sh "$KERNEL_SOURCE" "$KERNEL_TREE")
actual_builder_tree=$($SCRIPT_DIR/verify_git_tree.sh "$BUILDER_SOURCE" "$BUILDER_TREE")

case "$TOOLCHAIN" in
	gcc)
		need aarch64-linux-gnu-gcc
		make_toolchain=(CROSS_COMPILE=aarch64-linux-gnu-)
		compiler=aarch64-linux-gnu-gcc
		;;
	llvm-22)
		for tool in clang-22 ld.lld-22 llvm-ar-22 llvm-nm-22 llvm-objcopy-22 \
			llvm-objdump-22 llvm-readelf-22 llvm-strip-22; do
			need "$tool"
		done
		make_toolchain=(LLVM=-22)
		compiler=clang-22
		;;
	*) die "unsupported TOOLCHAIN: $TOOLCHAIN" ;;
esac

work_source=$OUTPUT_DIR/source
object_dir=$OUTPUT_DIR/obj
input_dir=$OUTPUT_DIR/inputs
package_dir=$OUTPUT_DIR/package
mkdir -p "$work_source" "$object_dir" "$input_dir" "$package_dir"
rsync -a --delete "$KERNEL_SOURCE/" "$work_source/"

(
	cd "$work_source"
	git apply --check "$patch_file"
	git apply "$patch_file"
	git apply --unidiff-zero --check "$runtime_patch"
	git apply --unidiff-zero "$runtime_patch"
)
install -m 0644 "$base_config" "$work_source/arch/arm64/configs/raphael.config"

busybox_root=$input_dir/busybox
mkbootimg_root=$input_dir/mkbootimg
mkdir -p "$busybox_root" "$mkbootimg_root" "$object_dir/ramboot-files"
dpkg-deb -x "$BUSYBOX_DEB" "$busybox_root"
dpkg-deb -x "$MKBOOTIMG_DEB" "$mkbootimg_root"
busybox=$busybox_root/bin/busybox
mkbootimg=$mkbootimg_root/usr/bin/mkbootimg
[ -x "$busybox" ] || die 'arm64 static BusyBox was not extracted'
[ -f "$mkbootimg" ] || die 'mkbootimg script was not extracted'
file "$busybox" | grep -q 'ARM aarch64' || die 'BusyBox is not an AArch64 executable'
if readelf -l "$busybox" | grep -q 'INTERP'; then
	die 'BusyBox is dynamically linked; RAM boot requires a static binary'
fi

install -m 0755 "$busybox" "$object_dir/ramboot-files/busybox"
install -m 0755 "$SCRIPT_DIR/ramboot-init" "$object_dir/ramboot-files/init"
printf 'Raphael RAM-only Linux (source-built kernel)\n' >"$object_dir/ramboot-files/issue"
find "$object_dir/ramboot-files" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

ramboot_list=$object_dir/ramboot.list
{
	printf 'dir /bin 0755 0 0\n'
	printf 'dir /dev 0755 0 0\n'
	printf 'nod /dev/console 0600 0 0 c 5 1\n'
	printf 'nod /dev/null 0666 0 0 c 1 3\n'
	printf 'dir /etc 0755 0 0\n'
	printf 'dir /proc 0555 0 0\n'
	printf 'dir /root 0700 0 0\n'
	printf 'dir /run 0755 0 0\n'
	printf 'dir /sys 0555 0 0\n'
	printf 'dir /tmp 01777 0 0\n'
	printf 'file /bin/busybox %s 0755 0 0\n' "$object_dir/ramboot-files/busybox"
	printf 'file /init %s 0755 0 0\n' "$object_dir/ramboot-files/init"
	printf 'file /etc/issue %s 0644 0 0\n' "$object_dir/ramboot-files/issue"
} >"$ramboot_list"
touch -d "@$SOURCE_DATE_EPOCH" "$ramboot_list"

common_make=(make -C "$work_source" O="$object_dir" ARCH=arm64 "${make_toolchain[@]}")
"${common_make[@]}" defconfig
"${common_make[@]}" raphael.config

config_tool=$work_source/scripts/config
"$config_tool" --file "$object_dir/.config" \
	--enable BLK_DEV_INITRD \
	--set-str INITRAMFS_SOURCE ramboot.list \
	--set-val INITRAMFS_ROOT_UID 0 \
	--set-val INITRAMFS_ROOT_GID 0 \
	--enable RD_GZIP \
	--enable INITRAMFS_COMPRESSION_GZIP \
	--disable INITRAMFS_COMPRESSION_BZIP2 \
	--disable INITRAMFS_COMPRESSION_LZMA \
	--disable INITRAMFS_COMPRESSION_XZ \
	--disable INITRAMFS_COMPRESSION_LZO \
	--disable INITRAMFS_COMPRESSION_LZ4 \
	--disable INITRAMFS_COMPRESSION_ZSTD \
	--disable INITRAMFS_COMPRESSION_NONE \
	--disable INITRAMFS_PRESERVE_MTIME \
	--set-str LOCALVERSION '-sm8150-ramboot-c526b7bf' \
	--disable LOCALVERSION_AUTO

export KBUILD_BUILD_TIMESTAMP="@$SOURCE_DATE_EPOCH"
export KBUILD_BUILD_USER=raphael-builder
export KBUILD_BUILD_HOST=source-verified
export KBUILD_BUILD_VERSION=1
export SOURCE_DATE_EPOCH
"${common_make[@]}" olddefconfig

required_builtin=(
	CONFIG_BLK_DEV_INITRD CONFIG_RD_GZIP CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT
	CONFIG_PROC_FS CONFIG_SYSFS CONFIG_TMPFS CONFIG_CONFIGFS_FS CONFIG_TTY
	CONFIG_SERIAL_MSM CONFIG_SERIAL_MSM_CONSOLE CONFIG_SERIAL_QCOM_GENI
	CONFIG_SERIAL_QCOM_GENI_CONSOLE CONFIG_NET CONFIG_INET CONFIG_USB
	CONFIG_USB_DWC3 CONFIG_USB_DWC3_QCOM CONFIG_USB_GADGET
	CONFIG_USB_LIBCOMPOSITE CONFIG_USB_CONFIGFS CONFIG_USB_CONFIGFS_ACM
	CONFIG_USB_CONFIGFS_NCM CONFIG_USB_F_ACM CONFIG_USB_F_NCM CONFIG_USB_U_SERIAL
	CONFIG_INITRAMFS_COMPRESSION_GZIP
)
for option in "${required_builtin[@]}"; do
	grep -qx "$option=y" "$object_dir/.config" || die "resolved config lacks built-in $option"
done
grep -qx 'CONFIG_INITRAMFS_SOURCE="ramboot.list"' "$object_dir/.config" || \
	die 'resolved config does not point to built-in RAM boot list'
grep -qx '# CONFIG_LOCALVERSION_AUTO is not set' "$object_dir/.config" || \
	die 'LOCALVERSION_AUTO is still enabled'

"${common_make[@]}" -j"$JOBS" Image.gz qcom/sm8150-xiaomi-raphael.dtb

image=$object_dir/arch/arm64/boot/Image
image_gz=$object_dir/arch/arm64/boot/Image.gz
dtb=$object_dir/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb
vmlinux=$object_dir/vmlinux
system_map=$object_dir/System.map
initramfs_cpio=$object_dir/usr/initramfs_data.cpio
for output in "$image" "$image_gz" "$dtb" "$vmlinux" "$system_map" "$initramfs_cpio"; do
	[ -s "$output" ] || die "missing build output: $output"
done
gzip -t "$image_gz"

cpio_listing=$package_dir/initramfs-list.txt
cpio --quiet -it <"$initramfs_cpio" >"$cpio_listing"
for member in bin/busybox dev/console dev/null etc/issue init; do
	grep -qx "$member" "$cpio_listing" || die "built-in initramfs lacks $member"
done
embedded_init_sha=$(cpio --quiet -i --to-stdout init <"$initramfs_cpio" | sha256sum | awk '{print $1}')
[ "$embedded_init_sha" = "$INIT_SHA256" ] || die 'embedded /init differs from reviewed source'

kernel_dtb=$package_dir/raphael-Image.gz-dtb
install -m 0644 "$image_gz" "$kernel_dtb"
cat "$dtb" >>"$kernel_dtb"
empty_ramdisk=$package_dir/empty-android-ramdisk
: >"$empty_ramdisk"
boot_img=$package_dir/raphael-source-ramboot.img
python3 "$mkbootimg" \
	--kernel "$kernel_dtb" \
	--ramdisk "$empty_ramdisk" \
	--cmdline "$CMDLINE" \
	--pagesize 4096 \
	--base 0x80000000 \
	--ramdisk_offset 0x01000000 \
	--header_version 0 \
	--output "$boot_img"

[ "$(dd if="$boot_img" bs=1 count=8 status=none)" = 'ANDROID!' ] || \
	die 'output lacks Android boot magic'
read -r kernel_size kernel_addr ramdisk_size ramdisk_addr \
	second_size second_addr tags_addr page_size < <(
	od -An -tu4 -w32 -j8 -N32 "$boot_img"
)
[ "$ramdisk_size" -eq 0 ] || die "Android ramdisk is not empty: $ramdisk_size"
[ "$kernel_addr" -eq $((0x80008000)) ] || die "unexpected kernel load address: $kernel_addr"
[ "$ramdisk_addr" -eq $((0x81000000)) ] || die "unexpected fixed ramdisk address: $ramdisk_addr"
[ "$page_size" -eq 4096 ] || die "unexpected boot page size: $page_size"
boot_size=$(stat -c %s "$boot_img")
(( boot_size < BOOT_PARTITION_LIMIT )) || die "boot image exceeds 128 MiB: $boot_size"

install -m 0644 "$object_dir/.config" "$package_dir/kernel.config"
install -m 0644 "$image" "$package_dir/Image"
install -m 0644 "$image_gz" "$package_dir/Image.gz"
install -m 0644 "$dtb" "$package_dir/sm8150-xiaomi-raphael.dtb"
install -m 0644 "$system_map" "$package_dir/System.map"
install -m 0644 "$vmlinux" "$package_dir/vmlinux"
install -m 0644 "$initramfs_cpio" "$package_dir/initramfs_data.cpio"

manifest=$package_dir/manifest.txt
{
	printf 'purpose=ephemeral RAM-only Linux hardware acceptance\n'
	printf 'phone_write_operations=none\n'
	printf 'android_boot_format=v0\n'
	printf 'android_ramdisk_size=%s\n' "$ramdisk_size"
	printf 'kernel_load_address=0x%x\n' "$kernel_addr"
	printf 'fixed_ramdisk_address=0x%x\n' "$ramdisk_addr"
	printf 'page_size=%s\n' "$page_size"
	printf 'cmdline=%s\n' "$CMDLINE"
	printf 'kernel_repository=https://github.com/GavinLiuOnline/xiaomi_raphael_kernel.git\n'
	printf 'kernel_commit=%s\n' "$KERNEL_COMMIT"
	printf 'kernel_tree=%s\n' "$actual_kernel_tree"
	printf 'kernel_archive_sha256=%s\n' "$KERNEL_ARCHIVE_SHA256"
	printf 'builder_repository=https://github.com/GavinLiuOnline/xiaomi_raphael_build_kernel.git\n'
	printf 'builder_commit=%s\n' "$BUILDER_COMMIT"
	printf 'builder_tree=%s\n' "$actual_builder_tree"
	printf 'builder_archive_sha256=%s\n' "$BUILDER_ARCHIVE_SHA256"
	printf 'community_patch_sha256=%s\n' "$PATCH_SHA256"
	printf 'runtime_v3_patch_sha256=%s\n' "$RUNTIME_PATCH_SHA256"
	printf 'base_config_sha256=%s\n' "$BASE_CONFIG_SHA256"
	printf 'busybox_deb_sha256=%s\n' "$BUSYBOX_DEB_SHA256"
	printf 'busybox_binary_sha256=%s\n' "$(sha256sum "$busybox" | awk '{print $1}')"
	printf 'mkbootimg_deb_sha256=%s\n' "$MKBOOTIMG_DEB_SHA256"
	printf 'mkbootimg_script_sha256=%s\n' "$(sha256sum "$mkbootimg" | awk '{print $1}')"
	printf 'init_sha256=%s\n' "$INIT_SHA256"
	printf 'source_date_epoch=%s\n' "$SOURCE_DATE_EPOCH"
	printf 'toolchain=%s\n' "$TOOLCHAIN"
	printf 'compiler=%s\n' "$($compiler --version | sed -n '1p')"
	printf 'jobs=%s\n' "$JOBS"
	printf 'resolved_config_sha256=%s\n' "$(sha256sum "$object_dir/.config" | awk '{print $1}')"
	printf 'initramfs_cpio_sha256=%s\n' "$(sha256sum "$initramfs_cpio" | awk '{print $1}')"
	printf 'image_sha256=%s\n' "$(sha256sum "$image" | awk '{print $1}')"
	printf 'image_size=%s\n' "$(stat -c %s "$image")"
	printf 'image_gz_sha256=%s\n' "$(sha256sum "$image_gz" | awk '{print $1}')"
	printf 'dtb_sha256=%s\n' "$(sha256sum "$dtb" | awk '{print $1}')"
	printf 'kernel_dtb_sha256=%s\n' "$(sha256sum "$kernel_dtb" | awk '{print $1}')"
	printf 'vmlinux_sha256=%s\n' "$(sha256sum "$vmlinux" | awk '{print $1}')"
	printf 'system_map_sha256=%s\n' "$(sha256sum "$system_map" | awk '{print $1}')"
	printf 'boot_img_sha256=%s\n' "$(sha256sum "$boot_img" | awk '{print $1}')"
	printf 'boot_img_size=%s\n' "$boot_size"
} >"$manifest"

printf 'Built source-derived RAM-only boot image: %s\n' "$boot_img"
cat "$manifest"
