#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Flash only the complete boot and cache images produced by the matching
# builder.  No erase command and no other partition name exists in this file.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bundle="${BUNDLE:-${repo_root}/artifacts/build/fastboot-raphael-mainline}"
manifest="${bundle}/fastboot-manifest.txt"
fastboot="${FASTBOOT:-${repo_root}/artifacts/downloads/tools/platform-tools/fastboot}"
expected_serial="${EXPECTED_FASTBOOT_SERIAL:-}"

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

usage()
{
	cat <<'EOF'
usage:
  flash_fastboot_boot_cache.sh preflight
  flash_fastboot_boot_cache.sh probe
  flash_fastboot_boot_cache.sh flash --write-boot --write-cache [--reboot]

preflight is host-only. probe reads classic Fastboot identity and partition
sizes. flash requires both literal write gates and writes only cache then boot;
userdata, radio/NV, firmware, recovery, dtbo and vbmeta are never addressed.
EOF
}

manifest_value()
{
	local key="$1"
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; found=1 }
		END { exit !found }' "$manifest"
}

fastboot_value()
{
	local key="$1" output value
	output="$("${fastboot_cmd[@]}" getvar "$key" 2>&1)" || true
	value="$(printf '%s\n' "$output" | sed -n "s/^[[:space:]]*${key}:[[:space:]]*//p" | tail -n 1)"
	[[ -n "$value" ]] || die "Fastboot did not return $key"
	printf '%s\n' "$value"
}

action="${1:-preflight}"
shift || true
write_boot=0
write_cache=0
reboot_after=0
while (($#)); do
	case "$1" in
		--write-boot) write_boot=1 ;;
		--write-cache) write_cache=1 ;;
		--reboot) reboot_after=1 ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
	shift
done
case "$action" in
	preflight|probe|flash) ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; die "unknown action: $action" ;;
esac

for tool in awk sed sha256sum stat; do
	command -v "$tool" >/dev/null 2>&1 || die "missing host tool: $tool"
done
[[ -x "$fastboot" ]] || die "Fastboot tool is missing: $fastboot"
[[ -s "$manifest" ]] || die "bundle manifest is missing: $manifest"
[[ "$(manifest_value partition_allowlist)" = boot,cache ]] ||
	die 'manifest partition allowlist is not exactly boot,cache'

boot_image="${repo_root}/$(manifest_value boot_image)"
cache_image="${repo_root}/$(manifest_value cache_image)"
for spec in \
	"boot:$boot_image:boot_image_bytes:boot_image_sha256:134217728" \
	"cache:$cache_image:cache_image_bytes:cache_image_sha256:268435456"; do
	IFS=: read -r name image bytes_key sha_key locked_bytes <<<"$spec"
	[[ -s "$image" ]] || die "missing $name image: $image"
	[[ "$(stat -c %s "$image")" = "$(manifest_value "$bytes_key")" ]] ||
		die "$name image size differs from manifest"
	[[ "$(stat -c %s "$image")" = "$locked_bytes" ]] ||
		die "$name image is not a complete partition image"
	[[ "$(sha256sum "$image" | awk '{ print $1 }')" = "$(manifest_value "$sha_key")" ]] ||
		die "$name image hash differs from manifest"
done

printf 'preflight=PASS\n'
printf 'allowlist=boot,cache\n'
printf 'boot=%s bytes sha256=%s\n' "$(stat -c %s "$boot_image")" "$(manifest_value boot_image_sha256)"
printf 'cache=%s bytes sha256=%s\n' "$(stat -c %s "$cache_image")" "$(manifest_value cache_image_sha256)"
[[ "$action" != preflight ]] || exit 0

[[ -n "$expected_serial" ]] || die 'set EXPECTED_FASTBOOT_SERIAL to the confirmed phone serial'
device_list="$("$fastboot" devices)"
device_count="$(printf '%s\n' "$device_list" | awk 'NF >= 2 { count++ } END { print count+0 }')"
[[ "$device_count" = 1 ]] || die "expected exactly one Fastboot device, found $device_count"
device_serial="$(printf '%s\n' "$device_list" | awk 'NF >= 2 { print $1 }')"
[[ -z "$expected_serial" || "$device_serial" = "$expected_serial" ]] ||
	die 'connected Fastboot serial differs from the expected target'
fastboot_cmd=("$fastboot" -s "$device_serial")
[[ "$(fastboot_value product)" = raphael ]] || die 'connected Fastboot product is not raphael'
[[ "$(fastboot_value unlocked)" = yes ]] || die 'connected Raphael bootloader is not unlocked'
[[ "$(fastboot_value partition-size:boot)" = 0x8000000 ]] ||
	die 'boot partition is not the locked 128 MiB size'
[[ "$(fastboot_value partition-size:cache)" = 0x10000000 ]] ||
	die 'cache partition is not the locked 256 MiB size'
printf 'device_probe=PASS product=raphael unlocked=yes boot=0x8000000 cache=0x10000000\n'
[[ "$action" != probe ]] || exit 0

[[ "$write_boot" -eq 1 && "$write_cache" -eq 1 ]] ||
	die 'flash requires both --write-boot and --write-cache'

"${fastboot_cmd[@]}" flash cache "$cache_image"
"${fastboot_cmd[@]}" flash boot "$boot_image"
printf 'flash=PASS partitions=cache,boot\n'
if [[ "$reboot_after" -eq 1 ]]; then
	"${fastboot_cmd[@]}" reboot
	printf 'reboot=requested\n'
else
	printf 'reboot=not-requested\n'
fi
