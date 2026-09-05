#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Build the committed Raphael fork without staging local source overlays.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="${SOURCE_DIR:-${repo_root}/linux}"
output_dir="${OUTPUT_DIR:-${repo_root}/artifacts/build/raphael-mainline}"
jobs="${JOBS:-16}"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"

die()
{
	echo "build_fork_kernel: $*" >&2
	exit 1
}

sha()
{
	sha256sum "$1" | awk '{print $1}'
}

require_builtin()
{
	grep -qx "CONFIG_$1=y" "$output_dir/.config" ||
		die "resolved config lacks built-in CONFIG_$1"
}

[[ -e "$source_dir/.git" ]] || die "source is not a Git checkout: $source_dir"
source_dir="$(realpath "$source_dir")"
output_dir="$(realpath -m "$output_dir")"
mkdir -p "$repo_root/artifacts/build"
build_root="$(realpath "$repo_root/artifacts/build")"
case "$output_dir/" in
"$build_root"/*) ;;
*) die "output must be below $build_root" ;;
esac

[[ -z "$(git -C "$source_dir" status --porcelain)" ]] ||
	die "source checkout is dirty; commit or remove all changes first"
[[ -f "$source_dir/arch/arm64/configs/raphael_defconfig" ]] ||
	die "missing committed Raphael defconfig"
command -v "${cross_compile}gcc" >/dev/null ||
	die "missing cross compiler: ${cross_compile}gcc"

source_commit="$(git -C "$source_dir" rev-parse HEAD)"
upstream_base="$(git -C "$source_dir" merge-base master HEAD)" ||
	die "cannot determine merge-base of master and HEAD"
source_date_epoch="${SOURCE_DATE_EPOCH:-$(git -C "$source_dir" show -s --format=%ct HEAD)}"
[[ "$source_date_epoch" =~ ^[0-9]+$ ]] || die 'SOURCE_DATE_EPOCH must be an integer'

export ARCH=arm64
export CROSS_COMPILE="$cross_compile"
export SOURCE_DATE_EPOCH="$source_date_epoch"
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@${source_date_epoch}" '+%a %b %e %T UTC %Y')"
export KBUILD_BUILD_USER="raphael"
export KBUILD_BUILD_HOST="reproducible"
export KBUILD_BUILD_VERSION=1

# An explicit empty LOCALVERSION suppresses setlocalversion's trailing '+'
# for development commits, even when CONFIG_LOCALVERSION_AUTO is disabled.
common_make=(make -C "$source_dir" "O=$output_dir" "ARCH=$ARCH" "CROSS_COMPILE=$CROSS_COMPILE" LOCALVERSION=)
mkdir -p "$output_dir"
"${common_make[@]}" raphael_defconfig

for option in EFI EFI_STUB EFI_ZBOOT SCSI_UFSHCD SCSI_UFSHCD_PLATFORM \
	SCSI_UFS_QCOM USB USB_DWC3 USB_DWC3_QCOM USB_GADGET USB_CONFIGFS \
	USB_CONFIGFS_NCM QCOM_RPMH BATTERY_QCOM_FG CHARGER_QCOM_SMB2; do
	require_builtin "$option"
done
grep -qx 'CONFIG_LOCALVERSION="-raphael-mainline-dev"' "$output_dir/.config" ||
	die 'raphael_defconfig has an unexpected LOCALVERSION'
grep -qx '# CONFIG_LOCALVERSION_AUTO is not set' "$output_dir/.config" ||
	die 'raphael_defconfig enables LOCALVERSION_AUTO'

"${common_make[@]}" -j"$jobs" Image.gz vmlinuz.efi modules \
	qcom/sm8150-xiaomi-raphael.dtb

image="$output_dir/arch/arm64/boot/Image"
image_gz="$output_dir/arch/arm64/boot/Image.gz"
efi="$output_dir/arch/arm64/boot/vmlinuz.efi"
dtb="$output_dir/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb"
for artifact in "$image" "$image_gz" "$efi" "$dtb"; do
	[[ -s "$artifact" ]] || die "missing build output: $artifact"
done
[[ "$(od -An -tu2 -N2 "$efi" | tr -d ' ')" = 23117 ]] ||
	die 'vmlinuz.efi lacks the EFI MZ magic'
file "$efi" | grep -Eq 'PE32\+.*Aarch64' ||
	die 'vmlinuz.efi is not a PE32+ AArch64 EFI image'
command -v fdtget >/dev/null || die 'missing fdtget for board identity check'
[[ "$(fdtget -t s "$dtb" / model)" = 'Xiaomi Redmi K20 Pro' ]] ||
	die 'DTB board model is not Xiaomi Redmi K20 Pro'

kernel_release="$("${common_make[@]}" -s kernelrelease)"
base_release="$("${common_make[@]}" -s kernelversion)"
[[ "$kernel_release" = "$base_release-raphael-mainline-dev" ]] ||
	die "unexpected kernel release: $kernel_release"
compiler="$(${cross_compile}gcc -dumpfullversion -dumpversion)"
cat >"$output_dir/build-manifest.txt" <<EOF
Raphael committed-fork kernel build
upstream_commit=${source_commit}
source_commit=${source_commit}
upstream_base=${upstream_base}
source_content=git
source_patch_sha256=none
source_path=${source_dir}
output_path=${output_dir}
source_date_epoch=${source_date_epoch}
kernel_release=${kernel_release}
config_sha256=$(sha "$output_dir/.config")
kernel_sha256=$(sha "$efi")
vmlinuz_efi_sha256=$(sha "$efi")
dtb_sha256=$(sha "$dtb")
image_gz_sha256=$(sha "$image_gz")
compiler=${compiler}
hardware_boot=NOT_RUN
EOF

echo "build complete: $output_dir"
