#!/usr/bin/env bash
# Build a read-mostly, source-pinned U-Boot Android image for Raphael.
# The resulting bootloader reads EFI/BOOT/BOOTAA64.EFI from cache and has no
# U-Boot flash, mass-storage, saveenv or remote-command write path enabled.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
UBOOT_SOURCE=${UBOOT_SOURCE:-$REPO_ROOT/third_party/raphael-uboot}
ENV_SOURCE=${ENV_SOURCE:-$SCRIPT_DIR/uboot-cache.env}
MKBOOTIMG_DEB=${MKBOOTIMG_DEB:-$REPO_ROOT/artifacts/downloads/community-audit/mkbootimg_10.0.0+r36-9_all.deb}
OUTPUT_DIR=${OUTPUT_DIR:-$REPO_ROOT/artifacts/build/uboot-cache-boot}
JOBS=${JOBS:-$(nproc)}
ALLOW_CLEAN=${ALLOW_CLEAN:-0}

EXPECTED_COMMIT=b5e36b80ecf58b00f4f4245cf411d73ed36832d5
EXPECTED_MKBOOTIMG_DEB_SHA256=63a21af69fd622fb1261f9a12375007ca48613830d9a9bf8436721e56886c2c9

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

need()
{
	command -v "$1" >/dev/null 2>&1 || die "missing host tool: $1"
}

assert_disabled()
{
	local option=$1
	if grep -qx "$option=y" "$config"; then
		die "$option was not disabled"
	fi
}

for tool in aarch64-linux-gnu-gcc awk bison date dd dpkg-deb file flex git \
	grep gzip install make nproc python3 realpath sha256sum stat swig tar; do
	need "$tool"
done
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die 'JOBS must be a positive integer'
[ -f "$ENV_SOURCE" ] || die "missing U-Boot environment: $ENV_SOURCE"
[ -d "$UBOOT_SOURCE/.git" ] || die "not a Git checkout: $UBOOT_SOURCE"
[ "$(git -C "$UBOOT_SOURCE" rev-parse HEAD)" = "$EXPECTED_COMMIT" ] || \
	die 'U-Boot source commit is not pinned value'
[ -z "$(git -C "$UBOOT_SOURCE" status --porcelain)" ] || \
	die 'U-Boot source checkout is dirty'

actual_mkbootimg_sha=$(sha256sum "$MKBOOTIMG_DEB" | awk '{print $1}')
[ "$actual_mkbootimg_sha" = "$EXPECTED_MKBOOTIMG_DEB_SHA256" ] || \
	die 'mkbootimg package SHA-256 mismatch'

OUTPUT_DIR=$(realpath -m -- "$OUTPUT_DIR")
case "$OUTPUT_DIR/" in
	"$REPO_ROOT/artifacts/build/"*) ;;
	*) die 'OUTPUT_DIR must remain below artifacts/build/' ;;
esac
if [ -e "$OUTPUT_DIR" ]; then
	[ "$ALLOW_CLEAN" = 1 ] || die "output exists; set ALLOW_CLEAN=1 to replace it: $OUTPUT_DIR"
	rm -rf -- "$OUTPUT_DIR"
fi

stage=$(mktemp -d /tmp/raphael-uboot-cache.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/src" "$stage/build" "$stage/mkbootimg" "$OUTPUT_DIR"
git -C "$UBOOT_SOURCE" archive --format=tar "$EXPECTED_COMMIT" | tar -xf - -C "$stage/src"
install -m 0644 "$ENV_SOURCE" "$stage/src/board/qualcomm/raphael-cache.env"
dpkg-deb -x "$MKBOOTIMG_DEB" "$stage/mkbootimg"

commit_epoch=$(git -C "$UBOOT_SOURCE" show -s --format=%ct "$EXPECTED_COMMIT")
export SOURCE_DATE_EPOCH=$commit_epoch
export KBUILD_BUILD_TIMESTAMP
KBUILD_BUILD_TIMESTAMP=$(date -u -d "@$commit_epoch" '+%Y-%m-%d %H:%M:%S')
export KBUILD_BUILD_USER=raphael
export KBUILD_BUILD_HOST=source-build
export CROSS_COMPILE=aarch64-linux-gnu-
export KCFLAGS="-ffile-prefix-map=$stage=/usr/src/raphael-uboot -fdebug-prefix-map=$stage=/usr/src/raphael-uboot"

make -C "$stage/src" O="$stage/build" qcom_defconfig qcom-phone.config raphael-phone-log.config
config_tool=$stage/src/scripts/config
config=$stage/build/.config
"$config_tool" --file "$config" --set-str CONFIG_DEFAULT_DEVICE_TREE qcom/sm8150-xiaomi-raphael
"$config_tool" --file "$config" --set-str CONFIG_ENV_DEFAULT_ENV_TEXT_FILE board/qualcomm/raphael-cache.env
"$config_tool" --file "$config" --disable CONFIG_FASTBOOT_FLASH
"$config_tool" --file "$config" --disable CONFIG_FASTBOOT_OEM_RUN
"$config_tool" --file "$config" --disable CONFIG_CMD_USB_MASS_STORAGE
"$config_tool" --file "$config" --disable CONFIG_USB_FUNCTION_MASS_STORAGE
"$config_tool" --file "$config" --disable CONFIG_CMD_SAVEENV
"$config_tool" --file "$config" --disable CONFIG_TOOLS_MKEFICAPSULE
"$config_tool" --file "$config" --disable CONFIG_EFI_RUNTIME_UPDATE_CAPSULE
"$config_tool" --file "$config" --disable CONFIG_EFI_CAPSULE_ON_DISK
"$config_tool" --file "$config" --disable CONFIG_EFI_CAPSULE_FIRMWARE_RAW
make -C "$stage/src" O="$stage/build" olddefconfig

grep -qx 'CONFIG_SCSI=y' "$config" || die 'SCSI is not enabled'
grep -qx 'CONFIG_UFS=y' "$config" || die 'UFS is not enabled'
grep -qx 'CONFIG_UFS_QCOM=y' "$config" || die 'Qualcomm UFS is not enabled'
grep -qx 'CONFIG_EFI_LOADER=y' "$config" || die 'EFI loader is not enabled'
grep -qx 'CONFIG_CMD_FAT=y' "$config" || die 'FAT command is not enabled'
grep -qx 'CONFIG_USB_FUNCTION_FASTBOOT=y' "$config" || die 'diagnostic USB fastboot is not enabled'
for option in CONFIG_FASTBOOT_FLASH CONFIG_FASTBOOT_OEM_RUN \
	CONFIG_CMD_USB_MASS_STORAGE CONFIG_USB_FUNCTION_MASS_STORAGE \
	CONFIG_CMD_SAVEENV; do
	assert_disabled "$option"
done

make -C "$stage/src" O="$stage/build" -j"$JOBS"

u_boot_bin=$stage/build/u-boot-nodtb.bin
u_boot_dtb=$stage/build/u-boot.dtb
[ -s "$u_boot_bin" ] || die 'u-boot-nodtb.bin was not produced'
[ -s "$u_boot_dtb" ] || die 'u-boot.dtb was not produced'
gzip -n -9 -c "$u_boot_bin" >"$OUTPUT_DIR/u-boot-nodtb.bin.gz"
cat "$OUTPUT_DIR/u-boot-nodtb.bin.gz" "$u_boot_dtb" \
	>"$OUTPUT_DIR/u-boot-nodtb.bin.gz-dtb"

mkbootimg=$stage/mkbootimg/usr/bin/mkbootimg
boot_img=$OUTPUT_DIR/raphael-uboot-cache.img
python3 "$mkbootimg" \
	--kernel "$OUTPUT_DIR/u-boot-nodtb.bin.gz-dtb" \
	--pagesize 4096 \
	--base 0x80000000 \
	--header_version 0 \
	--output "$boot_img"
[ "$(dd if="$boot_img" bs=1 count=8 status=none)" = 'ANDROID!' ] || \
	die 'output lacks Android boot magic'
[ "$(stat -c %s "$boot_img")" -le 134217728 ] || \
	die 'U-Boot image exceeds live boot partition size'

install -m 0644 "$config" "$OUTPUT_DIR/uboot.config"
install -m 0644 "$stage/build/include/generated/defaultenv_autogenerated.h" \
	"$OUTPUT_DIR/uboot.defaultenv_autogenerated.h"
install -m 0644 "$u_boot_dtb" "$OUTPUT_DIR/u-boot.dtb"

manifest=$OUTPUT_DIR/manifest.txt
{
	printf 'format=raphael-uboot-cache-v1\n'
	printf 'source_commit=%s\n' "$EXPECTED_COMMIT"
	printf 'source_commit_epoch=%s\n' "$commit_epoch"
	printf 'source_tree_clean=true\n'
	printf 'boot_source_partition=cache\n'
	printf 'boot_source_path=EFI/BOOT/BOOTAA64.EFI\n'
	printf 'ufs_read_enabled=true\n'
	printf 'fastboot_diagnostics_enabled=true\n'
	printf 'fastboot_flash_erase=disabled\n'
	printf 'fastboot_oem_run=disabled\n'
	printf 'usb_mass_storage=disabled\n'
	printf 'saveenv=disabled\n'
	printf 'env_sha256=%s\n' "$(sha256sum "$ENV_SOURCE" | awk '{print $1}')"
	printf 'resolved_config_sha256=%s\n' "$(sha256sum "$OUTPUT_DIR/uboot.config" | awk '{print $1}')"
	printf 'u_boot_nodtb_sha256=%s\n' "$(sha256sum "$u_boot_bin" | awk '{print $1}')"
	printf 'u_boot_dtb_sha256=%s\n' "$(sha256sum "$u_boot_dtb" | awk '{print $1}')"
	printf 'boot_img_sha256=%s\n' "$(sha256sum "$boot_img" | awk '{print $1}')"
	printf 'boot_img_size=%s\n' "$(stat -c %s "$boot_img")"
} >"$manifest"

printf 'Built source-pinned Raphael U-Boot without accessing the phone:\n'
cat "$manifest"
