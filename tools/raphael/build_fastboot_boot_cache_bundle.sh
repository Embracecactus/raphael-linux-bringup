#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Package a committed Raphael fork build with retained boot inputs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
retained_inputs="${RETAINED_INPUTS:-${repo_root}/artifacts/retained/raphael-boot-inputs}"
source_dir="${UPSTREAM_TREE:-${repo_root}/linux}"
build_dir="${BUILD_DIR:-${repo_root}/artifacts/build/raphael-mainline}"
output_dir="${OUTPUT_DIR:-${repo_root}/artifacts/build/fastboot-raphael-mainline}"
stable_loader="${STABLE_LOADER:-${retained_inputs}/raphael-uboot-cache.img}"
stable_initramfs="${STABLE_INITRAMFS:-${retained_inputs}/recovery-initramfs-7.1}"
stable_initramfs_release="${STABLE_INITRAMFS_RELEASE:-}"
grub_efi="${GRUB_EFI:-${retained_inputs}/BOOTAA64.EFI}"
kernel="$build_dir/arch/arm64/boot/vmlinuz.efi"
built_dtb="$build_dir/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb"
dtb="${CONTROL_DTB:-$built_dtb}"
system_map="$build_dir/System.map"
config="$build_dir/.config"
build_manifest="$build_dir/build-manifest.txt"
boot_bytes=134217728
cache_bytes=268435456
volume_id=52415048
work=''

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{ print $1 }'; }
manifest_value() {
	local key="$1"
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; found=1 } END { exit !found }' "$build_manifest"
}
cleanup() {
	if [[ -n "$work" && -d "$work" ]]; then chmod -R u+w "$work" 2>/dev/null || true; rm -r -- "$work"; fi
}
trap cleanup EXIT HUP INT TERM

[[ -e "$source_dir/.git" ]] || die "source is not a Git checkout: $source_dir"
source_dir="$(realpath "$source_dir")"
output_dir="$(realpath -m "$output_dir")"
mkdir -p "$repo_root/artifacts/build"
build_root="$(realpath "$repo_root/artifacts/build")"
case "$output_dir/" in "$build_root"/*) ;; *) die 'OUTPUT_DIR must remain below artifacts/build/' ;; esac
[[ -z "$(git -C "$source_dir" status --porcelain)" ]] || die 'source checkout is dirty; commit or remove all changes first'
for tool in awk cmp cpio depmod du file find fsck.fat gzip install lsinitramfs make mcopy mmd mkfs.fat mktemp modinfo sha256sum sort stat truncate unmkinitramfs; do
	command -v "$tool" >/dev/null 2>&1 || die "missing host tool: $tool"
done
for input in "$stable_loader" "$grub_efi" "$stable_initramfs" "$kernel" "$built_dtb" "$dtb" "$system_map" "$config" "$build_manifest"; do
	[[ -s "$input" ]] || die "missing input: $input"
done
[[ -n "$stable_initramfs_release" ]] || die 'STABLE_INITRAMFS_RELEASE must identify the retained initramfs ABI'

source_head="$(git -C "$source_dir" rev-parse HEAD)"
[[ "$(manifest_value source_content)" = git ]] || die 'build manifest must declare source_content=git'
[[ "$(manifest_value source_patch_sha256)" = none ]] || die 'build manifest must declare source_patch_sha256=none'
[[ "$(manifest_value source_commit)" = "$source_head" ]] || die 'source HEAD differs from build manifest; rebuild first'
[[ "$(manifest_value config_sha256)" = "$(sha "$config")" ]] || die 'build config differs from manifest'
[[ "$(manifest_value kernel_sha256)" = "$(sha "$kernel")" ]] || die 'EFI kernel differs from manifest'
[[ "$(manifest_value vmlinuz_efi_sha256)" = "$(sha "$kernel")" ]] || die 'EFI kernel vmlinuz hash differs from manifest'
[[ "$(manifest_value dtb_sha256)" = "$(sha "$built_dtb")" ]] || die 'built Raphael DTB differs from manifest'

common_make=(make -s -C "$source_dir" O="$build_dir" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=)
kernel_release="$("${common_make[@]}" kernelrelease)"
[[ "$(manifest_value kernel_release)" = "$kernel_release" ]] || die 'kernel release differs from build manifest'
if [[ "$kernel_release" =~ ^([0-9]+\.[0-9]+)\.[0-9]+.*-raphael-mainline-dev$ ]]; then kernel_series="${BASH_REMATCH[1]}"; else die "unexpected committed-fork kernel release: $kernel_release"; fi
for option in EFI_STUB EXT4_FS SCSI_UFS_QCOM USB_CONFIGFS_NCM; do grep -qx "CONFIG_${option}=y" "$config" || die "kernel lacks built-in CONFIG_${option}"; done

mkdir -p "$output_dir"
boot_image="$output_dir/raphael-boot-stable-uboot-full.img"
cache_image="$output_dir/raphael-cache-linux-${kernel_series}-persistent.img"
initramfs="$output_dir/initramfs-${kernel_series}"
grub_cfg="$output_dir/grub.cfg"
manifest="$output_dir/fastboot-manifest.txt"
work="$(mktemp -d -p /tmp raphael-fork-bundle.XXXXXX)"
initramfs_root="$work/initramfs-root"
module_root="$work/modules"
verify_dir="$work/verify"
mkdir -p "$verify_dir"

unmkinitramfs "$stable_initramfs" "$initramfs_root"
[[ -x "$initramfs_root/init" && -d "$initramfs_root/usr/lib/modules" ]] || die 'retained initramfs lacks /init or modules'
mapfile -t inherited < <(find "$initramfs_root/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ "${#inherited[@]}" -eq 1 && "${inherited[0]}" = "$stable_initramfs_release" ]] || die "retained initramfs must contain exactly module release: $stable_initramfs_release"
rm -r -- "$initramfs_root/usr/lib/modules/$stable_initramfs_release"
"${common_make[@]}" modules_install INSTALL_MOD_PATH="$module_root" INSTALL_MOD_STRIP=1 DEPMOD=/bin/true
rm -f -- "$module_root/lib/modules/$kernel_release/build" "$module_root/lib/modules/$kernel_release/source"
depmod -b "$module_root" -F "$system_map" "$kernel_release"
module_count="$(find "$module_root/lib/modules/$kernel_release" -type f -name '*.ko' | wc -l)"
[[ "$module_count" -gt 0 ]] || die 'modules_install produced no modules'
module_bytes="$(du -s -B1 "$module_root/lib/modules/$kernel_release" | awk '{ print $1 }')"
[[ "$module_bytes" -lt $((134217728 - 8388608)) ]] || die 'module tree exceeds handoff tmpfs budget'
while IFS= read -r -d '' module; do
	[[ "$(modinfo -k "$kernel_release" -F vermagic "$module")" = "$kernel_release "* ]] || die "module ABI mismatch: $module"
	file -b "$module" | grep -q 'ELF 64-bit.*ARM aarch64' || die "module is not ARM64: $module"
done < <(find "$module_root/lib/modules/$kernel_release" -type f -name '*.ko' -print0)
cp -a "$module_root/lib/modules/$kernel_release" "$initramfs_root/usr/lib/modules/"
install -m 0755 "$repo_root/tools/raphael/initramfs-live-modules" "$initramfs_root/scripts/init-bottom/raphael-live-modules"
order_file="$initramfs_root/scripts/init-bottom/ORDER"
handoff_line='/scripts/init-bottom/raphael-live-modules "$@" || panic "Raphael module handoff failed"'
[[ -f "$order_file" ]] || die 'retained initramfs has no init-bottom ORDER'
handoff_count="$(grep -Fxc "$handoff_line" "$order_file" || true)"
[[ "$handoff_count" -le 1 ]] || die 'duplicate Raphael module handoff entry'
[[ "$handoff_count" -eq 1 ]] || printf '%s\n' "$handoff_line" >>"$order_file"
(
	cd "$initramfs_root"
	find . -print0 | sort -z | cpio --quiet --null -o -H newc --owner=0:0 --reproducible | gzip -n -9 >"$initramfs"
)
gzip -t "$initramfs"
listing="$work/initramfs-list.txt"
lsinitramfs "$initramfs" >"$listing"
grep -q "^usr/lib/modules/${kernel_release}/modules.dep$" "$listing" || die 'generated initramfs lacks matching modules.dep'
mapfile -t final_releases < <(sed -n 's#^usr/lib/modules/\([^/]*\)/.*#\1#p' "$listing" | sort -u)
[[ "${#final_releases[@]}" -eq 1 && "${final_releases[0]}" = "$kernel_release" ]] || die 'generated initramfs contains another module ABI'

linux_line='    linux ($bootfs)/linux.efi root=PARTLABEL=userdata rw rootwait console=ttyMSM0,115200 console=tty0 loglevel=7 ignore_loglevel clk_ignore_unused pd_ignore_unused'
printf '%s\n' 'set timeout=0' 'set default=0' '' 'search --no-floppy --label --set=bootfs RAPHAELBOOT' '' "menuentry 'Debian Raphael Linux ${kernel_series} persistent' {" "$linux_line" '    initrd ($bootfs)/initramfs' '    devicetree ($bootfs)/dtbs/qcom/sm8150-xiaomi-raphael.dtb' '}' >"$grub_cfg"
[[ "$(stat -c %s "$stable_loader")" -lt "$boot_bytes" ]] || die 'retained U-Boot does not fit the boot partition'
install -m 0644 "$stable_loader" "$boot_image"
truncate -s "$boot_bytes" "$boot_image"
truncate -s 0 "$cache_image"
truncate -s "$cache_bytes" "$cache_image"
mkfs.fat -F 16 -S 4096 -s 1 -i "$volume_id" -n RAPHAELBOOT "$cache_image" >/dev/null
export MTOOLS_SKIP_CHECK=1
for path in ::/EFI ::/EFI/BOOT ::/dtbs ::/dtbs/qcom; do mmd -i "$cache_image" "$path"; done
mcopy -o -i "$cache_image" "$grub_efi" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -o -i "$cache_image" "$grub_cfg" ::/EFI/BOOT/grub.cfg
mcopy -o -i "$cache_image" "$kernel" ::/linux.efi
mcopy -o -i "$cache_image" "$initramfs" ::/initramfs
mcopy -o -i "$cache_image" "$dtb" ::/dtbs/qcom/sm8150-xiaomi-raphael.dtb
verify_file() { local src="$1" dst="$2" out="$verify_dir/$(printf '%s' "$2" | tr / _)"; mcopy -i "$cache_image" "::$dst" "$out"; cmp -s "$src" "$out" || die "cache round-trip mismatch: $dst"; }
verify_file "$grub_efi" /EFI/BOOT/BOOTAA64.EFI
verify_file "$grub_cfg" /EFI/BOOT/grub.cfg
verify_file "$kernel" /linux.efi
verify_file "$initramfs" /initramfs
verify_file "$dtb" /dtbs/qcom/sm8150-xiaomi-raphael.dtb
fsck.fat -n "$cache_image" >/dev/null

{
	printf 'format=raphael-fastboot-boot-cache-v3\npurpose=committed-fork-Linux-%s-with-retained-Debian-userdata\nphone_write_operations=none\nhardware_boot=NOT_RUN\npartition_allowlist=boot,cache\n' "$kernel_series"
	printf 'partition_denylist=userdata,modem,modemst1,modemst2,fsg,fsc,persist,dsp,bluetooth,abl,xbl,tz,aop,recovery,dtbo,vbmeta\nboot_payload=retained-U-Boot-cache-EFI-loader\n'
	printf 'boot_payload_bytes=%s\nboot_payload_sha256=%s\nboot_image=%s\nboot_image_bytes=%s\nboot_image_sha256=%s\n' "$(stat -c %s "$stable_loader")" "$(sha "$stable_loader")" "${boot_image#$repo_root/}" "$(stat -c %s "$boot_image")" "$(sha "$boot_image")"
	printf 'cache_image=%s\ncache_image_bytes=%s\ncache_image_sha256=%s\ncache_fat=FAT16\ncache_logical_sector_bytes=4096\ncache_volume_id=%s\ncache_label=RAPHAELBOOT\ncache_roundtrip=PASS\nboot_policy=persistent-no-fallback\n' "${cache_image#$repo_root/}" "$(stat -c %s "$cache_image")" "$(sha "$cache_image")" "$volume_id"
	printf 'kernel_release=%s\nsource_commit=%s\nsource_content=git\nsource_patch_sha256=none\nconfig_sha256=%s\nkernel_sha256=%s\ndtb_sha256=%s\n' "$kernel_release" "$source_head" "$(sha "$config")" "$(sha "$kernel")" "$(sha "$dtb")"
	printf 'dtb_input=%s\n' "${dtb#$repo_root/}"
	printf 'initramfs_sha256=%s\nbase_initramfs_source=%s\nbase_initramfs_sha256=%s\nbase_initramfs_module_release=%s\ngrub_efi_input=%s\ngrub_efi_input_sha256=%s\ninitramfs_module_release=%s\ninitramfs_module_count=%s\ninitramfs_module_bytes=%s\n' "$(sha "$initramfs")" "$stable_initramfs" "$(sha "$stable_initramfs")" "$stable_initramfs_release" "$grub_efi" "$(sha "$grub_efi")" "$kernel_release" "$module_count" "$module_bytes"
	printf 'userspace_module_handoff=init-bottom-tmpfs-128MiB;userdata-module-files-unchanged\nuserdata_policy=preserve-existing-Debian-rootfs;never-flash-or-erase\nbaseband_nv_policy=never-flash-or-erase\n'
} >"$manifest"
printf 'Built committed-fork Fastboot boot+cache bundle: %s\n' "$output_dir"
cat "$manifest"
