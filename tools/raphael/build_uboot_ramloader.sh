#!/usr/bin/env bash
# Build a fail-closed U-Boot stage that accepts only a RAM boot payload.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
UBOOT_SOURCE=${UBOOT_SOURCE:-$REPO_ROOT/third_party/raphael-uboot}
ENV_SOURCE=$SCRIPT_DIR/uboot-ramloader.env
MKBOOTIMG_DEB=${MKBOOTIMG_DEB:-$REPO_ROOT/artifacts/downloads/community-audit/mkbootimg_10.0.0+r36-9_all.deb}
OUTPUT_DIR=${OUTPUT_DIR:-$REPO_ROOT/artifacts/build/uboot-ramloader}
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

for tool in aarch64-linux-gnu-gcc awk bison date dd dpkg-deb flex git grep gzip install make nproc python3 sha256sum stat swig tar; do
	need "$tool"
done
[ -f "$ENV_SOURCE" ] || die "missing RAM-loader environment: $ENV_SOURCE"
[ -d "$UBOOT_SOURCE/.git" ] || die "not a Git checkout: $UBOOT_SOURCE"
[ "$(git -C "$UBOOT_SOURCE" rev-parse HEAD)" = "$EXPECTED_COMMIT" ] || die 'U-Boot source commit is not pinned value'
[ -z "$(git -C "$UBOOT_SOURCE" status --porcelain)" ] || die 'U-Boot source checkout is dirty'
actual_mkbootimg_sha=$(sha256sum "$MKBOOTIMG_DEB" | awk '{print $1}')
[ "$actual_mkbootimg_sha" = "$EXPECTED_MKBOOTIMG_DEB_SHA256" ] || die 'mkbootimg package SHA-256 mismatch'

stage=$(mktemp -d /tmp/raphael-uboot-ramloader.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/src" "$stage/build" "$stage/mkbootimg" "$OUTPUT_DIR"
git -C "$UBOOT_SOURCE" archive --format=tar "$EXPECTED_COMMIT" | tar -xf - -C "$stage/src"
install -m 0644 "$ENV_SOURCE" "$stage/src/board/qualcomm/raphael-ramloader.env"
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
"$config_tool" --file "$config" --set-str CONFIG_ENV_DEFAULT_ENV_TEXT_FILE board/qualcomm/raphael-ramloader.env
"$config_tool" --file "$config" --disable CONFIG_FASTBOOT_FLASH
"$config_tool" --file "$config" --disable CONFIG_FASTBOOT_OEM_RUN
"$config_tool" --file "$config" --disable CONFIG_CMD_USB_MASS_STORAGE
"$config_tool" --file "$config" --disable CONFIG_USB_FUNCTION_MASS_STORAGE
"$config_tool" --file "$config" --disable CONFIG_CMD_SAVEENV
"$config_tool" --file "$config" --disable CONFIG_CMD_SCSI
"$config_tool" --file "$config" --disable CONFIG_SCSI
"$config_tool" --file "$config" --disable CONFIG_UFS
"$config_tool" --file "$config" --disable CONFIG_UFS_QCOM
"$config_tool" --file "$config" --disable CONFIG_TOOLS_MKEFICAPSULE
"$config_tool" --file "$config" --disable CONFIG_EFI_RUNTIME_UPDATE_CAPSULE
"$config_tool" --file "$config" --disable CONFIG_EFI_CAPSULE_ON_DISK
"$config_tool" --file "$config" --disable CONFIG_EFI_CAPSULE_FIRMWARE_RAW
make -C "$stage/src" O="$stage/build" olddefconfig

grep -qx 'CONFIG_USB_FUNCTION_FASTBOOT=y' "$config" || die 'USB fastboot gadget is not built'
grep -qx 'CONFIG_ANDROID_BOOT_IMAGE=y' "$config" || die 'Android boot-image parser is not built'
grep -qx 'CONFIG_CMD_BOOTM=y' "$config" || die 'bootm is not built'
for option in \
	CONFIG_FASTBOOT_FLASH CONFIG_FASTBOOT_OEM_RUN CONFIG_CMD_USB_MASS_STORAGE \
	CONFIG_USB_FUNCTION_MASS_STORAGE CONFIG_CMD_SAVEENV CONFIG_CMD_SCSI \
	CONFIG_SCSI CONFIG_UFS CONFIG_UFS_QCOM; do
	assert_disabled "$option"
done

jobs=$(nproc)
(( jobs > 8 )) && jobs=8
make -C "$stage/src" O="$stage/build" -j"$jobs"

u_boot_bin=$stage/build/u-boot-nodtb.bin
u_boot_dtb=$stage/build/u-boot.dtb
[ -f "$u_boot_bin" ] || die 'u-boot-nodtb.bin was not produced'
[ -f "$u_boot_dtb" ] || die 'u-boot.dtb was not produced'

u_boot_gz=$OUTPUT_DIR/u-boot-nodtb.bin.gz
u_boot_gz_dtb=$OUTPUT_DIR/u-boot-nodtb.bin.gz-dtb
gzip -n -9 -c "$u_boot_bin" >"$u_boot_gz"
install -m 0644 "$u_boot_gz" "$u_boot_gz_dtb"
cat "$u_boot_dtb" >>"$u_boot_gz_dtb"

mkbootimg=$stage/mkbootimg/usr/bin/mkbootimg
boot_img=$OUTPUT_DIR/raphael-uboot-ramloader.img
python3 "$mkbootimg" \
	--kernel "$u_boot_gz_dtb" \
	--pagesize 4096 \
	--base 0x80000000 \
	--header_version 0 \
	--output "$boot_img"
[ "$(dd if="$boot_img" bs=1 count=8 status=none)" = 'ANDROID!' ] || die 'output lacks Android boot magic'

resolved_config=$OUTPUT_DIR/uboot.config
resolved_env=$OUTPUT_DIR/uboot.defaultenv_autogenerated.h
install -m 0644 "$config" "$resolved_config"
install -m 0644 "$stage/build/include/generated/defaultenv_autogenerated.h" "$resolved_env"
manifest=$OUTPUT_DIR/manifest.txt
{
	printf 'source_commit=%s\n' "$EXPECTED_COMMIT"
	printf 'source_commit_epoch=%s\n' "$commit_epoch"
	printf 'source_tree_clean=true\n'
	printf 'purpose=ram-only-fastboot-stage\n'
	printf 'storage_preboot=disabled\n'
	printf 'fastboot_flash_erase=disabled\n'
	printf 'fastboot_oem_run=disabled\n'
	printf 'usb_mass_storage=disabled\n'
	printf 'scsi_ufs_access=disabled\n'
	printf 'env_sha256=%s\n' "$(sha256sum "$ENV_SOURCE" | awk '{print $1}')"
	printf 'compiled_defaultenv_sha256=%s\n' "$(sha256sum "$resolved_env" | awk '{print $1}')"
	printf 'resolved_config_sha256=%s\n' "$(sha256sum "$resolved_config" | awk '{print $1}')"
	printf 'u_boot_nodtb_sha256=%s\n' "$(sha256sum "$u_boot_bin" | awk '{print $1}')"
	printf 'u_boot_dtb_sha256=%s\n' "$(sha256sum "$u_boot_dtb" | awk '{print $1}')"
	printf 'u_boot_gz_dtb_sha256=%s\n' "$(sha256sum "$u_boot_gz_dtb" | awk '{print $1}')"
	printf 'boot_img_sha256=%s\n' "$(sha256sum "$boot_img" | awk '{print $1}')"
	printf 'boot_img_size=%s\n' "$(stat -c %s "$boot_img")"
} >"$manifest"

printf 'Built source-based RAM-loader U-Boot: %s\n' "$boot_img"
cat "$manifest"
