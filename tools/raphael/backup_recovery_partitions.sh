#!/usr/bin/env bash
# Read-only partition inventory and backup helper for Xiaomi Raphael recovery.
#
# This script never writes to the phone. It intentionally excludes userdata.
# Raw images and the private manifest stay under artifacts/device-private/,
# which is excluded from Git because the images may contain unique identifiers.

set -Eeuo pipefail

umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly DEFAULT_PRIVATE_ROOT="${REPO_ROOT}/artifacts/device-private"

ADB_BIN="${ADB:-adb}"
ADB_SERIAL_VALUE="${ADB_SERIAL:-}"
MODE="${1:---inventory}"

usage() {
  cat <<'EOF'
Usage:
  backup_recovery_partitions.sh --inventory
  backup_recovery_partitions.sh --backup-preservation
  backup_recovery_partitions.sh --backup-safety-set

Modes:
  --inventory             List partition names and sizes only (default).
  --backup-preservation   Back up device-bound NV/calibration partitions.
  --backup-safety-set     Also back up boot-chain/install-target partitions.

Environment:
  ADB=/path/to/adb        Select the adb binary.
  ADB_SERIAL=VALUE        Select a device without recording its serial.
  BACKUP_ROOT=/path       Override the private output root.

The phone must be running an ephemeral TWRP session with root adbd. The script
does not back up userdata and has no restore or device-write operation.
EOF
}

case "${MODE}" in
  --inventory|--backup-preservation|--backup-safety-set)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if ! command -v "${ADB_BIN}" >/dev/null 2>&1 && [[ ! -x "${ADB_BIN}" ]]; then
  printf 'ERROR: adb binary not found: %s\n' "${ADB_BIN}" >&2
  exit 1
fi

adb_args=()
if [[ -n "${ADB_SERIAL_VALUE}" ]]; then
  adb_args=(-s "${ADB_SERIAL_VALUE}")
fi

adb_run() {
  "${ADB_BIN}" "${adb_args[@]}" "$@"
}

strip_cr() {
  tr -d '\r'
}

adb_state="$(adb_run get-state 2>/dev/null | strip_cr || true)"
if [[ "${adb_state}" != "device" ]]; then
  printf 'ERROR: exactly one authorized adb device must be online.\n' >&2
  exit 1
fi

remote_id="$(adb_run shell id 2>/dev/null | strip_cr || true)"
if [[ "${remote_id}" != uid=0\(* ]]; then
  printf 'ERROR: recovery adbd is not root; refusing raw partition access.\n' >&2
  exit 1
fi

twrp_version="$(adb_run shell getprop ro.twrp.version 2>/dev/null | strip_cr || true)"
twrp_flavor="$(adb_run shell getprop ro.build.flavor 2>/dev/null | strip_cr || true)"
twrp_flags_present="$(adb_run shell \
  'test -f /system/etc/twrp.flags && echo yes || true' 2>/dev/null | strip_cr || true)"
if [[ -z "${twrp_version}" && "${twrp_flavor}" != twrp_raphael-* && "${twrp_flags_present}" != "yes" ]]; then
  printf 'ERROR: signed Raphael TWRP runtime markers are absent; refusing to continue.\n' >&2
  exit 1
fi
if [[ -z "${twrp_version}" ]]; then
  twrp_version="${twrp_flavor}"
fi

device_name=""
for property_name in \
  ro.product.device \
  ro.build.product \
  ro.product.system.device \
  ro.product.vendor.device; do
  property_value="$(adb_run shell getprop "${property_name}" 2>/dev/null | strip_cr || true)"
  if [[ -n "${property_value}" ]]; then
    device_name="${property_value}"
    break
  fi
done
case "${device_name}" in
  raphael|raphaelin)
    ;;
  *)
    printf 'ERROR: expected raphael/raphaelin recovery, got %q.\n' "${device_name}" >&2
    exit 1
    ;;
esac

resolve_partition() {
  local name="$1"
  local resolved

  resolved="$(adb_run shell \
    "for p in /dev/block/by-name/${name} /dev/block/bootdevice/by-name/${name}; do
       if [ -e \"\$p\" ]; then readlink -f \"\$p\"; exit 0; fi
     done
     exit 1" 2>/dev/null | strip_cr || true)"

  case "${resolved}" in
    /dev/block/*)
      printf '%s\n' "${resolved}"
      ;;
    *)
      return 1
      ;;
  esac
}

partition_size() {
  local remote_path="$1"
  local size

  size="$(adb_run shell \
    "blockdev --getsize64 '${remote_path}' 2>/dev/null ||
     { b=\$(basename '${remote_path}'); s=\$(cat /sys/class/block/\$b/size 2>/dev/null) && echo \$((s * 512)); }" \
    2>/dev/null | strip_cr || true)"

  [[ "${size}" =~ ^[0-9]+$ ]] || return 1
  [[ "${size}" -gt 0 ]] || return 1
  printf '%s\n' "${size}"
}

inventory() {
  local name remote_path size

  printf 'partition\tbytes\n'
  while IFS= read -r name; do
    [[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    remote_path="$(resolve_partition "${name}" || true)"
    [[ -n "${remote_path}" ]] || continue
    size="$(partition_size "${remote_path}" || true)"
    printf '%s\t%s\n' "${name}" "${size:-unknown}"
  done < <(adb_run shell 'ls -1 /dev/block/by-name 2>/dev/null || ls -1 /dev/block/bootdevice/by-name 2>/dev/null' | strip_cr | LC_ALL=C sort -u)
}

if [[ "${MODE}" == "--inventory" ]]; then
  printf 'Verified ephemeral TWRP %s on %s; device access is read-only.\n' \
    "${twrp_version}" "${device_name}" >&2
  inventory
  exit 0
fi

# modemst*/fsg/fsc hold modem NV state; persist* may hold Wi-Fi, sensor and
# biometric calibration; devinfo holds device boot state. Missing optional
# aliases are recorded rather than synthesized.
preservation_partitions=(
  modemst1
  modemst2
  fsg
  fsc
  persist
  persistbak
  devinfo
)

# These are either overwritten by the selected U-Boot layout or are small,
# adjacent boot-chain recovery assets. userdata is deliberately absent.
safety_partitions=(
  boot
  cache
  dtbo
  vbmeta
  recovery
  vendor
  cust
  logo
  splash
  modem
  bluetooth
  dsp
)

selected_partitions=("${preservation_partitions[@]}")
declare -A required_partitions=(
  [modemst1]=1
  [modemst2]=1
  [fsg]=1
  [fsc]=1
  [persist]=1
  [persistbak]=1
  [devinfo]=1
)
if [[ "${MODE}" == "--backup-safety-set" ]]; then
  selected_partitions+=("${safety_partitions[@]}")
  required_partitions[boot]=1
  required_partitions[cache]=1
  required_partitions[dtbo]=1
  required_partitions[vbmeta]=1
  required_partitions[recovery]=1
  required_partitions[vendor]=1
  required_partitions[cust]=1
  required_partitions[logo]=1
  required_partitions[splash]=1
  required_partitions[modem]=1
  required_partitions[bluetooth]=1
  required_partitions[dsp]=1
fi

readonly BACKUP_ROOT="${BACKUP_ROOT:-${DEFAULT_PRIVATE_ROOT}}"
timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
output_dir="${BACKUP_ROOT}/${timestamp}-raphael"
mkdir -p -- "${output_dir}"
chmod 0700 -- "${BACKUP_ROOT}" "${output_dir}"

manifest="${output_dir}/manifest.tsv"
printf 'partition\tbytes\tsha256\tstatus\n' > "${manifest}"
chmod 0600 -- "${manifest}"

printf 'TWRP %s on %s; raw output: %s\n' \
  "${twrp_version}" "${device_name}" "${output_dir}"
printf 'The phone will only be read; userdata is excluded.\n'

failures=0
for name in "${selected_partitions[@]}"; do
  if [[ "${name}" == "userdata" ]]; then
    printf 'ERROR: internal allowlist unexpectedly contains userdata.\n' >&2
    exit 1
  fi

  remote_path="$(resolve_partition "${name}" || true)"
  if [[ -z "${remote_path}" ]]; then
    if [[ -n "${required_partitions[${name}]:-}" ]]; then
      printf '%s\t-\t-\tmissing-required\n' "${name}" >> "${manifest}"
      printf 'ERROR %-12s required partition is not present\n' "${name}" >&2
      failures=$((failures + 1))
    else
      printf '%s\t-\t-\tmissing-optional\n' "${name}" >> "${manifest}"
      printf 'SKIP  %-12s optional partition is not present\n' "${name}"
    fi
    continue
  fi

  expected_size="$(partition_size "${remote_path}" || true)"
  if [[ -z "${expected_size}" ]]; then
    printf '%s\t-\t-\tsize-error\n' "${name}" >> "${manifest}"
    printf 'ERROR %-12s could not determine block size\n' "${name}" >&2
    failures=$((failures + 1))
    continue
  fi

  final_path="${output_dir}/${name}.img"
  partial_path="$(mktemp --tmpdir="${output_dir}" ".${name}.partial.XXXXXX")"
  chmod 0600 -- "${partial_path}"

  printf 'READ  %-12s %s bytes\n' "${name}" "${expected_size}"
  if ! adb_run exec-out "dd if='${remote_path}' bs=1048576 2>/dev/null" > "${partial_path}"; then
    printf '%s\t%s\t-\tread-error\n' "${name}" "${expected_size}" >> "${manifest}"
    printf 'ERROR %-12s adb/dd read failed; partial file retained as %s\n' \
      "${name}" "${partial_path}" >&2
    failures=$((failures + 1))
    continue
  fi

  actual_size="$(stat -c '%s' -- "${partial_path}")"
  if [[ "${actual_size}" != "${expected_size}" ]]; then
    printf '%s\t%s\t-\tsize-mismatch:%s\n' \
      "${name}" "${expected_size}" "${actual_size}" >> "${manifest}"
    printf 'ERROR %-12s expected %s bytes, received %s; partial retained\n' \
      "${name}" "${expected_size}" "${actual_size}" >&2
    failures=$((failures + 1))
    continue
  fi

  digest="$(sha256sum -- "${partial_path}" | awk '{print $1}')"
  mv -- "${partial_path}" "${final_path}"
  chmod 0600 -- "${final_path}"
  printf '%s\t%s\t%s\tok\n' "${name}" "${actual_size}" "${digest}" >> "${manifest}"
  printf 'OK    %-12s sha256=%s\n' "${name}" "${digest}"
done

if [[ "${failures}" -ne 0 ]]; then
  printf 'ERROR: %s partition backup(s) failed. Do not flash anything.\n' "${failures}" >&2
  exit 1
fi

printf 'Backup read completed. Keep this directory private and device-bound:\n%s\n' "${output_dir}"
