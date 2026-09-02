#!/bin/sh
# Read-only Redmi K20 Pro (raphael) Fastboot inventory.
#
# Deliberately excludes unique identifiers such as serialno, IMEI and MEID.
# This script must never contain flash, erase, format, boot, set_active or
# flashing lock/unlock operations.

set -u

if [ "$#" -ne 1 ] || [ ! -x "$1" ]; then
  echo "usage: $0 /absolute/path/to/fastboot" >&2
  exit 2
fi

raphael_fastboot="$1"

for raphael_var in \
  product \
  unlocked \
  secure \
  anti \
  current-slot \
  slot-count \
  is-userspace \
  version-bootloader \
  version-baseband \
  max-download-size \
  has-slot:boot \
  has-slot:system \
  partition-type:boot \
  partition-size:boot \
  partition-size:dtbo \
  partition-size:vbmeta \
  partition-size:recovery \
  partition-size:cache \
  partition-size:vendor \
  partition-size:userdata \
  partition-size:cust
do
  printf '[%s]\n' "$raphael_var"
  "$raphael_fastboot" getvar "$raphael_var" 2>&1 || true
done

printf '[oem device-info]\n'
"$raphael_fastboot" oem device-info 2>&1 || true
