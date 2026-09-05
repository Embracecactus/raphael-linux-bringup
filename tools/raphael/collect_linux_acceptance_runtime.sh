#!/usr/bin/env bash
# Collect a non-touch, non-destructive Linux subsystem inventory over USB-NCM.
# Raw output remains below the ignored device-private artifact directory.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
SSH_TARGET=${SSH_TARGET:-raphael@172.16.42.1}
SSH_KEY=${SSH_KEY:-$REPO_ROOT/artifacts/device-private/raphael-linux-id_ed25519}
OUTPUT_DIR=${OUTPUT_DIR:-$REPO_ROOT/artifacts/device-private/runtime-captures}

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

command -v ssh >/dev/null 2>&1 || die 'missing host tool: ssh'
[ -f "$SSH_KEY" ] || die "missing private SSH key: $SSH_KEY"
mkdir -p "$OUTPUT_DIR"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
output=$OUTPUT_DIR/raphael-linux-acceptance-$stamp.txt

ssh -i "$SSH_KEY" \
	-o BatchMode=yes \
	-o ConnectTimeout=5 \
	-o StrictHostKeyChecking=yes \
	"$SSH_TARGET" "sudo -n sh -s" >"$output" <<'REMOTE_SCRIPT'
set -u

section()
{
	printf '\n--- %s ---\n' "$1"
}

read_files()
{
	for file do
		[ -r "$file" ] || continue
		printf '%s=' "$file"
		cat "$file" 2>/dev/null || true
	done
}

printf 'RAPHAEL_LINUX_ACCEPTANCE_RUNTIME\n'
date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
uname -a
printf 'uptime_seconds='; cut -d ' ' -f 1 /proc/uptime 2>/dev/null || true
printf 'cmdline='; cat /proc/cmdline 2>/dev/null || true

section 'boot and root storage'
lsblk -o NAME,SIZE,RO,TYPE,FSTYPE,MOUNTPOINTS 2>&1 || true
awk '$2 == "/" || $2 == "/boot" { print }' /proc/mounts 2>&1 || true
df -h / /boot 2>&1 || true
read_files /sys/class/block/sda/device/model /sys/class/block/sda/device/rev \
	/sys/class/block/sda/device/life_time_estimation_a \
	/sys/class/block/sda/device/life_time_estimation_b

section 'CPU and memory'
grep -E '^(processor|model name|BogoMIPS|Features)' /proc/cpuinfo 2>&1 || true
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo 2>&1 || true
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
	[ -d "$policy" ] || continue
	read_files "$policy/scaling_driver" "$policy/scaling_governor" \
		"$policy/scaling_cur_freq" "$policy/cpuinfo_max_freq"
done

section 'display and GPU'
for status in /sys/class/drm/card*-*/status; do
	read_files "$status"
done
read_files /sys/class/graphics/fb0/name /sys/class/graphics/fb0/virtual_size \
	/sys/class/graphics/fb0/bits_per_pixel
for gpu in /sys/class/devfreq/*gpu* /sys/class/devfreq/*2c00000*; do
	[ -d "$gpu" ] || continue
	read_files "$gpu/name" "$gpu/governor" "$gpu/cur_freq" \
		"$gpu/min_freq" "$gpu/max_freq" "$gpu/available_frequencies"
done
for device in /sys/bus/platform/devices/*2c00000*; do
	[ -d "$device" ] || continue
	printf '%s driver=' "${device##*/}"
	readlink "$device/driver" 2>/dev/null || printf 'UNBOUND\n'
done

section 'network without identifiers'
for interface in /sys/class/net/*; do
	[ -d "$interface" ] || continue
	name=${interface##*/}
	printf '%s driver=' "$name"
	readlink "$interface/device/driver" 2>/dev/null || printf 'virtual-or-unbound\n'
	read_files "$interface/operstate" "$interface/carrier" "$interface/mtu"
done
if command -v iw >/dev/null 2>&1; then
	iw dev 2>/dev/null | sed -n '/^[[:space:]]*Interface /p;/^[[:space:]]*type /p;/^[[:space:]]*channel /p' || true
fi
if command -v nmcli >/dev/null 2>&1; then
	nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE device show 2>&1 || true
fi
rfkill list 2>&1 | sed -E 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/REDACTED-MAC/g' || true

section 'Bluetooth without identifiers'
ls -la /sys/class/bluetooth 2>&1 || true
for hci in /sys/class/bluetooth/hci*; do
	[ -d "$hci" ] || continue
	read_files "$hci/name" "$hci/operstate"
done
systemctl is-active bluetooth.service 2>&1 || true

section 'ALSA inventory only; no audio is recorded or played'
cat /proc/asound/cards 2>&1 || true
cat /proc/asound/pcm 2>&1 || true
aplay -l 2>&1 || true
arecord -l 2>&1 || true
for card in /sys/class/sound/card*; do
	[ -d "$card" ] || continue
	read_files "$card/id"
done
if command -v amixer >/dev/null 2>&1; then
	for card in /sys/class/sound/card*; do
		[ -d "$card" ] || continue
		index=${card##*card}
		amixer -c "$index" scontrols 2>&1 || true
	done
fi

section 'battery and charging'
for supply in /sys/class/power_supply/*; do
	[ -d "$supply" ] || continue
	printf '[%s]\n' "${supply##*/}"
	read_files "$supply/type" "$supply/status" "$supply/present" \
		"$supply/online" "$supply/capacity" "$supply/health" \
		"$supply/voltage_now" "$supply/current_now" "$supply/temp"
done

section 'thermal zones'
for zone in /sys/class/thermal/thermal_zone*; do
	[ -d "$zone" ] || continue
	type=$(cat "$zone/type" 2>/dev/null || true)
	temp=$(cat "$zone/temp" 2>/dev/null || true)
	printf '%s type=%s temp=%s\n' "${zone##*/}" "$type" "$temp"
done

section 'remote processors'
for remoteproc in /sys/class/remoteproc/remoteproc*; do
	[ -d "$remoteproc" ] || continue
	printf '%s ' "${remoteproc##*/}"
	for property in name state recovery firmware; do
		[ -r "$remoteproc/$property" ] || continue
		printf '%s=%s ' "$property" "$(cat "$remoteproc/$property" 2>/dev/null || true)"
	done
	printf '\n'
done

section 'deferred probes'
if [ -r /sys/kernel/debug/devices_deferred ]; then
	cat /sys/kernel/debug/devices_deferred 2>&1 || true
else
	printf 'debugfs devices_deferred unavailable\n'
fi

section 'filtered subsystem kernel messages'
dmesg 2>&1 |
	grep -Ei 'ufs|drm|dsi|mdp|gpu|adreno|ath10k|wlan|bluetooth|btqca|snd|soc-audio|wcd934|tfa987|battery|charger|thermal|remoteproc|q6v5|slpi|adsp|cdsp|modem' |
	sed -E 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/REDACTED-MAC/g; s/(serial(number)?[=:])[[:graph:]]+/\1REDACTED/Ig' || true
REMOTE_SCRIPT

printf 'Captured read-only non-touch acceptance evidence: %s\n' "$output"
