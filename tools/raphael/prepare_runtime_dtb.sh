#!/usr/bin/env bash
# Apply the hardware-validated Raphael display and USB device-mode DT policy.
set -euo pipefail

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || die "usage: $0 INPUT_DTB OUTPUT_DTB"
input=$1
output=$2

for tool in awk fdtget fdtput install sha256sum; do
	command -v "$tool" >/dev/null 2>&1 || die "missing host tool: $tool"
done
[ -s "$input" ] || die "input DTB is absent or empty: $input"
[ "$input" != "$output" ] || die 'input and output DTB paths must differ'

install -m 0644 "$input" "$output"

# Raphael's legacy Qualcomm DWC3 wrapper reads dr_mode from its child, while
# the DWC3 core consumes the same property itself.  Set both and remove the
# Type-C role-switch request so the phone reliably exposes its USB gadget UDC.
fdtput -t s "$output" /soc@0/usb@a6f8800 dr_mode peripheral
fdtput -t s "$output" /soc@0/usb@a6f8800/usb@a600000 dr_mode peripheral
if fdtget "$output" /soc@0/usb@a6f8800/usb@a600000 usb-role-switch \
		>/dev/null 2>&1; then
	fdtput -d "$output" /soc@0/usb@a6f8800/usb@a600000 usb-role-switch
fi

# The community continuous-splash handoff assumes XBL still owns MDP state.
# U-Boot/GRUB does not preserve that contract.  Removing these opt-in flags
# lets DRM reset and modeset the panel normally; this restored the console.
for node in \
	/soc@0/display-subsystem@ae00000 \
	/soc@0/clock-controller@af00000; do
	if fdtget "$output" "$node" qcom,boot-display-on >/dev/null 2>&1; then
		fdtput -d "$output" "$node" qcom,boot-display-on
	fi
done

[ "$(fdtget -t s "$output" /soc@0/usb@a6f8800 dr_mode)" = peripheral ] || \
	die 'USB wrapper dr_mode validation failed'
[ "$(fdtget -t s "$output" /soc@0/usb@a6f8800/usb@a600000 dr_mode)" = peripheral ] || \
	die 'DWC3 core dr_mode validation failed'
if fdtget "$output" /soc@0/usb@a6f8800/usb@a600000 usb-role-switch \
		>/dev/null 2>&1; then
	die 'DWC3 core still has usb-role-switch'
fi
for node in \
	/soc@0/display-subsystem@ae00000 \
	/soc@0/clock-controller@af00000; do
	if fdtget "$output" "$node" qcom,boot-display-on >/dev/null 2>&1; then
		die "$node still has qcom,boot-display-on"
	fi
done

printf 'runtime_dtb=%s\n' "$output"
printf 'runtime_dtb_sha256=%s\n' "$(sha256sum "$output" | awk '{print $1}')"
