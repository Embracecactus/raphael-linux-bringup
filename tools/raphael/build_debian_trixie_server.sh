#!/usr/bin/env bash
# Build a minimal, key-only Debian 13 arm64 system for Redmi K20 Pro.
#
# Output layout matches the least-invasive community chain:
#   boot     -> source-built U-Boot (built separately)
#   cache    -> FAT filesystem produced here (GRUB EFI + kernel + DTB)
#   userdata -> ext4 root filesystem produced here
#
# This script never accesses a phone and never flashes a partition.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

SUITE=${SUITE:-trixie}
DEBIAN_MIRROR=${DEBIAN_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/debian}
SECURITY_MIRROR=${SECURITY_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/debian-security}
OUTPUT_DIR=${OUTPUT_DIR:-$REPO_ROOT/artifacts/build/debian-trixie-server-c526}
ROOTFS_SIZE=${ROOTFS_SIZE:-3G}
CACHE_SIZE=${CACHE_SIZE:-256M}
CACHE_VOLUME_ID=${CACHE_VOLUME_ID:-52415048}
ROOTFS_UUID=${ROOTFS_UUID:-ee8d3593-59b1-480e-a3b6-4fefb17ee7d8}
TARGET_HOSTNAME=${TARGET_HOSTNAME:-raphael-linux}
USER_NAME=${USER_NAME:-raphael}
SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:-}
KERNEL_DEB=${KERNEL_DEB:-$REPO_ROOT/artifacts/downloads/community-audit/kernel-v7.0/linux-image-xiaomi-raphael.deb}
BUILDER_SOURCE=${BUILDER_SOURCE:-$REPO_ROOT/third_party/raphael-kernel-builder}
ALLOW_CLEAN=${ALLOW_CLEAN:-0}
RESUME_FROM_IMAGES=${RESUME_FROM_IMAGES:-0}
OUTPUT_UID=${OUTPUT_UID:-1000}
OUTPUT_GID=${OUTPUT_GID:-1000}

EXPECTED_KERNEL_SHA256=9f1a0ca50c7e0035c0ec8fea84e46dd9e5b04869e3f3506d7aae83ea9d7f230e
EXPECTED_BUILDER_TREE=ee3e9a20ba8b20b438ff649e4ced707d54611bb1
KERNEL_SOURCE_COMMIT=c526b7bf7ebc3fbfee244be252a2c1bd061ca749
EXPECTED_KERNEL_RELEASE=7.0.0-sm8150-gc526b7bf7ebc-dirty
BINFMT_MOUNTED_BY_US=0
BINFMT_ENABLED_BY_US=0

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

cleanup_binfmt()
{
	if [ "$BINFMT_ENABLED_BY_US" = 1 ]; then
		update-binfmts --disable qemu-aarch64 >/dev/null 2>&1 || true
	fi
	if [ "$BINFMT_MOUNTED_BY_US" = 1 ]; then
		umount /proc/sys/fs/binfmt_misc >/dev/null 2>&1 || true
	fi
}

prepare_binfmt()
{
	if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
		mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
		BINFMT_MOUNTED_BY_US=1
	fi
	if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
		update-binfmts --enable qemu-aarch64 >/dev/null
		BINFMT_ENABLED_BY_US=1
	fi
	[ -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || \
		die 'qemu-aarch64 binfmt registration is unavailable'
	grep -q '^enabled' /proc/sys/fs/binfmt_misc/qemu-aarch64 || \
		die 'qemu-aarch64 binfmt registration is disabled'
}

write_rootfs_configuration()
{
	local root=$1 pubkey=$2

	printf '%s\n' "$TARGET_HOSTNAME" >"$root/etc/hostname"
	cat >"$root/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $TARGET_HOSTNAME
::1 localhost ip6-localhost ip6-loopback
EOF

	cat >"$root/etc/fstab" <<'EOF'
PARTLABEL=userdata / ext4 defaults,noatime,errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=cache /boot vfat ro,nofail,umask=0077 0 2
EOF

	ln -snf /usr/share/zoneinfo/Asia/Shanghai "$root/etc/localtime"
	printf 'Asia/Shanghai\n' >"$root/etc/timezone"
	printf 'LANG=C.UTF-8\n' >"$root/etc/default/locale"
	: >"$root/etc/machine-id"
	rm -f -- "$root"/etc/ssh/ssh_host_*

	if ! chroot "$root" getent passwd "$USER_NAME" >/dev/null; then
		local extra_groups= group
		local -a useradd_args=(-m -u 1000 -s /bin/bash)
		for group in sudo adm audio video plugdev input dialout netdev systemd-journal; do
			if chroot "$root" getent group "$group" >/dev/null; then
				extra_groups=${extra_groups:+$extra_groups,}$group
			fi
		done
		if [ -n "$extra_groups" ]; then
			useradd_args+=(-G "$extra_groups")
		fi
		chroot "$root" useradd "${useradd_args[@]}" "$USER_NAME"
	fi
	chroot "$root" usermod -L root
	chroot "$root" usermod -L "$USER_NAME"

	install -d -m 0700 -o 1000 -g 1000 "$root/home/$USER_NAME/.ssh"
	install -m 0600 -o 1000 -g 1000 "$pubkey" \
		"$root/home/$USER_NAME/.ssh/authorized_keys"
	install -d -m 0755 "$root/etc/ssh/sshd_config.d"
	cat >"$root/etc/ssh/sshd_config.d/10-raphael-key-only.conf" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF

	cat >"$root/etc/sudoers.d/90-raphael" <<EOF
$USER_NAME ALL=(ALL:ALL) NOPASSWD: ALL
EOF
	chmod 0440 "$root/etc/sudoers.d/90-raphael"

	install -d -m 0755 "$root/etc/NetworkManager/conf.d"
	cat >"$root/etc/NetworkManager/conf.d/20-raphael-usb0.conf" <<'EOF'
[keyfile]
unmanaged-devices=interface-name:usb0
EOF

	install -d -m 0755 "$root/etc/dnsmasq.d"
	cat >"$root/etc/dnsmasq.d/usb-ncm.conf" <<'EOF'
interface=usb0
bind-dynamic
port=0
dhcp-authoritative
dhcp-range=172.16.42.2,172.16.42.2,255.255.255.0,1h
dhcp-option=3,172.16.42.1
EOF

	install -d -m 0755 "$root/usr/local/sbin"
	cat >"$root/usr/local/sbin/setup-raphael-usb-gadget" <<'EOF'
#!/bin/sh
set -eu

modprobe libcomposite
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
gadget=/sys/kernel/config/usb_gadget/raphael
mkdir -p "$gadget"
printf '0x1d6b\n' >"$gadget/idVendor"
printf '0x0104\n' >"$gadget/idProduct"
printf '0x0200\n' >"$gadget/bcdUSB"
mkdir -p "$gadget/strings/0x409"
printf 'Raphael Linux\n' >"$gadget/strings/0x409/manufacturer"
printf 'USB console and NCM\n' >"$gadget/strings/0x409/product"
serial=$(cat /etc/machine-id 2>/dev/null || true)
[ -n "$serial" ] || serial=raphael-linux
printf '%s\n' "$serial" >"$gadget/strings/0x409/serialnumber"

mkdir -p "$gadget/configs/c.1/strings/0x409"
printf 'ACM + NCM\n' >"$gadget/configs/c.1/strings/0x409/configuration"
mkdir -p "$gadget/functions/acm.GS0" "$gadget/functions/ncm.usb0"
ln -snf "$gadget/functions/acm.GS0" "$gadget/configs/c.1/acm.GS0"
ln -snf "$gadget/functions/ncm.usb0" "$gadget/configs/c.1/ncm.usb0"

tries=0
while [ "$tries" -lt 30 ]; do
	udc=$(find /sys/class/udc -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | head -n 1)
	[ -n "$udc" ] && break
	tries=$((tries + 1))
	sleep 1
done
[ -n "${udc:-}" ]
printf '%s\n' "$udc" >"$gadget/UDC"

tries=0
while [ "$tries" -lt 10 ] && [ ! -e /sys/class/net/usb0 ]; do
	tries=$((tries + 1))
	sleep 1
done
ip link set usb0 up
ip address replace 172.16.42.1/24 dev usb0
systemctl try-restart dnsmasq.service || true
EOF
	chmod 0755 "$root/usr/local/sbin/setup-raphael-usb-gadget"

	cat >"$root/usr/local/sbin/raphael-boot-marker" <<'EOF'
#!/bin/sh
set -eu
marker=/var/lib/raphael-bringup/boot-ok
mkdir -p "$(dirname "$marker")"
{
	printf 'RAPHAEL_LINUX_BOOT_OK\n'
	uname -a
	cat /etc/os-release
} >"$marker"
logger -t raphael-bringup RAPHAEL_LINUX_BOOT_OK
EOF
	chmod 0755 "$root/usr/local/sbin/raphael-boot-marker"

	install -d -m 0755 "$root/etc/systemd/system"
	install -m 0755 "$SCRIPT_DIR/raphael-hw-snapshot" \
		"$root/usr/local/sbin/raphael-hw-snapshot"
	install -m 0644 "$SCRIPT_DIR/raphael-hw-snapshot.service" \
		"$root/etc/systemd/system/raphael-hw-snapshot.service"

	cat >"$root/etc/systemd/system/raphael-usb-gadget.service" <<'EOF'
[Unit]
Description=Raphael USB ACM and CDC-NCM gadget
After=systemd-modules-load.service sys-kernel-config.mount local-fs.target
Before=ssh.service serial-getty@ttyGS0.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/setup-raphael-usb-gadget
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

	cat >"$root/etc/systemd/system/raphael-ssh-hostkeys.service" <<'EOF'
[Unit]
Description=Generate per-device SSH host keys
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF

	cat >"$root/etc/systemd/system/raphael-boot-marker.service" <<'EOF'
[Unit]
Description=Record successful Raphael Linux userspace boot
After=multi-user.target raphael-usb-gadget.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/raphael-boot-marker

[Install]
WantedBy=multi-user.target
EOF

	systemctl --root="$root" enable NetworkManager.service >/dev/null
	systemctl --root="$root" enable chrony.service >/dev/null
	systemctl --root="$root" enable dnsmasq.service >/dev/null
	systemctl --root="$root" enable raphael-usb-gadget.service >/dev/null
	systemctl --root="$root" enable raphael-ssh-hostkeys.service >/dev/null
	systemctl --root="$root" enable ssh.service >/dev/null
	systemctl --root="$root" enable serial-getty@ttyGS0.service >/dev/null
	systemctl --root="$root" enable raphael-boot-marker.service >/dev/null
	systemctl --root="$root" enable raphael-hw-snapshot.service >/dev/null
}

build_grub_efi()
{
	local root=$1 config=$2 output=$3
	local grub_standalone=/usr/bin/grub-mkstandalone
	[ -x "$root$grub_standalone" ] || die 'grub-mkstandalone is absent from rootfs'
	cat >"$config" <<'EOF'
set timeout=0
set default=0

search --no-floppy --label --set=bootfs RAPHAELBOOT

menuentry 'Debian 13 Raphael bring-up' {
	linux ($bootfs)/linux.efi root=PARTLABEL=userdata rw rootwait console=ttyMSM0,115200 console=tty0 loglevel=7 ignore_loglevel clk_ignore_unused pd_ignore_unused
	initrd ($bootfs)/initramfs
	devicetree ($bootfs)/dtbs/qcom/sm8150-xiaomi-raphael.dtb
}
EOF
	install -m 0644 "$config" "$root/tmp/raphael-grub.cfg"
	chroot "$root" "$grub_standalone" \
		-O arm64-efi \
		-o /tmp/BOOTAA64.EFI \
		--modules='part_gpt part_msdos fat ext2 normal linux search search_label configfile echo reboot' \
		--fonts='' --locales='' \
		'boot/grub/grub.cfg=/tmp/raphael-grub.cfg'
	install -m 0644 "$root/tmp/BOOTAA64.EFI" "$output"
}

build_initramfs()
{
	local root=$1 release=$2
	install -d -m 0755 "$root/etc/initramfs-tools/hooks"
	cat >"$root/etc/initramfs-tools/hooks/raphael-firmware" <<'EOF'
#!/bin/sh
PREREQS=''
case ${1:-} in prereqs) echo "$PREREQS"; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions

for pattern in \
	'/usr/lib/firmware/qcom/a6*' \
	'/usr/lib/firmware/qcom/ipa*' \
	'/usr/lib/firmware/qcom/sm8150/Xiaomi/raphael/a6*' \
	'/usr/lib/firmware/qcom/sm8150/Xiaomi/raphael/ad*' \
	'/usr/lib/firmware/qcom/sm8150/Xiaomi/raphael/cd*'; do
	for firmware in $pattern; do
		[ -e "$firmware" ] && copy_file firmware "$firmware"
	done
done
EOF
	chmod 0755 "$root/etc/initramfs-tools/hooks/raphael-firmware"
	if grep -q '^COMPRESS=' "$root/etc/initramfs-tools/initramfs.conf"; then
		sed -i 's/^COMPRESS=.*/COMPRESS=gzip/' "$root/etc/initramfs-tools/initramfs.conf"
	else
		printf 'COMPRESS=gzip\n' >>"$root/etc/initramfs-tools/initramfs.conf"
	fi
	chroot "$root" update-initramfs -c -k "$release"
}

install_kernel_payload()
{
	local root=$1 deb=$2 stage unexpected
	stage=$OUTPUT_DIR/.kernel-payload
	mkdir -p "$stage"
	dpkg-deb -x "$deb" "$stage"

	# The pinned community package predates Debian 13's merged-/usr layout and
	# carries modules below /lib.  Extracting it directly over the rootfs would
	# replace the /lib -> usr/lib symlink and make every arm64 dynamic binary
	# unstartable.  Validate the package shape, then place modules in /usr/lib.
	unexpected=$(find "$stage" -mindepth 1 -maxdepth 1 \
		! -name boot ! -name lib ! -name usr -printf '%f\n')
	[ -z "$unexpected" ] || die "unexpected top-level kernel payload: $unexpected"
	unexpected=$(find "$stage/lib" -mindepth 1 -maxdepth 1 \
		! -name modules -printf '%f\n')
	[ -z "$unexpected" ] || die "unexpected /lib kernel payload: $unexpected"
	unexpected=$(find "$stage/usr" -mindepth 1 -maxdepth 1 \
		! -name lib ! -name share -printf '%f\n')
	[ -z "$unexpected" ] || die "unexpected /usr kernel payload: $unexpected"
	unexpected=$(find "$stage/usr/lib" -mindepth 1 -maxdepth 1 \
		! -name "linux-image-$EXPECTED_KERNEL_RELEASE" -printf '%f\n')
	[ -z "$unexpected" ] || die "unexpected /usr/lib kernel payload: $unexpected"
	unexpected=$(find "$stage/usr/share" -mindepth 1 -maxdepth 1 \
		! -name doc -printf '%f\n')
	[ -z "$unexpected" ] || die "unexpected /usr/share kernel payload: $unexpected"
	unexpected=$(find "$stage/usr/share/doc" -mindepth 1 -maxdepth 1 \
		! -name "linux-image-$EXPECTED_KERNEL_RELEASE" -printf '%f\n')
	[ -z "$unexpected" ] || die "unexpected kernel documentation payload: $unexpected"
	[ -d "$stage/boot" ] || die 'kernel payload has no /boot directory'
	[ -d "$stage/lib/modules" ] || die 'kernel payload has no /lib/modules directory'
	[ -d "$stage/usr/lib/linux-image-$EXPECTED_KERNEL_RELEASE" ] || \
		die 'kernel payload has no versioned /usr/lib DTB directory'

	install -d -m 0755 "$root/boot" "$root/usr/lib/modules"
	cp -a "$stage/boot/." "$root/boot/"
	cp -a "$stage/lib/modules/." "$root/usr/lib/modules/"
	cp -a "$stage/usr/." "$root/usr/"
	rm -rf -- "$stage"
	[ -L "$root/lib" ] || die 'kernel installation broke merged-/usr /lib symlink'
}

build_cache_image()
{
	local image=$1 efi=$2 kernel=$3 initramfs=$4 dtb=$5 grub_cfg=$6
	truncate -s 0 "$image"
	truncate -s "$CACHE_SIZE" "$image"
	mkfs.fat -F 16 -S 4096 -s 1 -i "$CACHE_VOLUME_ID" \
		-n RAPHAELBOOT "$image" >/dev/null
	export MTOOLS_SKIP_CHECK=1
	mmd -i "$image" ::/EFI
	mmd -i "$image" ::/EFI/BOOT
	mmd -i "$image" ::/dtbs
	mmd -i "$image" ::/dtbs/qcom
	mcopy -o -i "$image" "$efi" ::/EFI/BOOT/BOOTAA64.EFI
	mcopy -o -i "$image" "$grub_cfg" ::/EFI/BOOT/grub.cfg
	mcopy -o -i "$image" "$kernel" ::/linux.efi
	mcopy -o -i "$image" "$initramfs" ::/initramfs
	mcopy -o -i "$image" "$dtb" ::/dtbs/qcom/sm8150-xiaomi-raphael.dtb
	mdir -i "$image" ::/EFI/BOOT/BOOTAA64.EFI >/dev/null
	mdir -i "$image" ::/linux.efi >/dev/null
	mdir -i "$image" ::/initramfs >/dev/null
	mdir -i "$image" ::/dtbs/qcom/sm8150-xiaomi-raphael.dtb >/dev/null
}

for tool in awk chown chroot cp date dpkg-deb dpkg-query e2fsck fdtget fdtput file find git \
	grep id install mcopy mdir mmd mkfs.fat mke2fs mmdebstrap mount mountpoint \
	readlink realpath resize2fs sed sha256sum sort ssh-keygen stat systemctl tar tune2fs \
	umount update-binfmts; do
	need "$tool"
done
[ "$(id -u)" -eq 0 ] || die 'run as root (the script uses a foreign-architecture chroot)'
[ "$SUITE" = trixie ] || die 'this reviewed script currently accepts SUITE=trixie only'
[[ "$OUTPUT_UID" =~ ^[0-9]+$ ]] || die 'OUTPUT_UID must be numeric'
[[ "$OUTPUT_GID" =~ ^[0-9]+$ ]] || die 'OUTPUT_GID must be numeric'
[[ "$RESUME_FROM_IMAGES" = 0 || "$RESUME_FROM_IMAGES" = 1 ]] || \
	die 'RESUME_FROM_IMAGES must be 0 or 1'
[[ "$CACHE_VOLUME_ID" =~ ^[0-9A-Fa-f]{8}$ ]] || \
	die 'CACHE_VOLUME_ID must be exactly eight hexadecimal digits'
trap cleanup_binfmt EXIT

OUTPUT_DIR=$(realpath -m -- "$OUTPUT_DIR")
case "$OUTPUT_DIR/" in
	"$REPO_ROOT/artifacts/build/"*) ;;
	*) die 'OUTPUT_DIR must remain below artifacts/build/' ;;
esac

verify_sha256 "$KERNEL_DEB" "$EXPECTED_KERNEL_SHA256"
[ -d "$BUILDER_SOURCE" ] || die "missing kernel builder source: $BUILDER_SOURCE"
actual_builder_tree=$($SCRIPT_DIR/verify_git_tree.sh "$BUILDER_SOURCE" "$EXPECTED_BUILDER_TREE")

# 每次构建由使用者显式提供自己的公钥，不创建、读取或共享私钥。
[ -n "$SSH_PUBLIC_KEY" ] || die 'set SSH_PUBLIC_KEY to your own public key file'
[ -f "$SSH_PUBLIC_KEY" ] || die 'SSH_PUBLIC_KEY is not a regular file'
ssh-keygen -lf "$SSH_PUBLIC_KEY" >/dev/null || die 'invalid SSH public key'
grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/=]+([[:space:]].*)?$' "$SSH_PUBLIC_KEY" || \
	die 'SSH_PUBLIC_KEY must contain an OpenSSH public key'

root=$OUTPUT_DIR/rootdir
firmware_deb=$OUTPUT_DIR/inputs/firmware-xiaomi-raphael.deb
alsa_deb=$OUTPUT_DIR/inputs/alsa-xiaomi-raphael.deb
build_mode=full-clean
bootstrap_reused=false
if [ "$RESUME_FROM_IMAGES" = 1 ]; then
	[ "$ALLOW_CLEAN" = 0 ] || die 'ALLOW_CLEAN cannot be combined with RESUME_FROM_IMAGES=1'
	[ -d "$root" ] || die 'resume requested but rootdir is absent'
	[ -s "$firmware_deb" ] || die 'resume requested but firmware package is absent'
	[ -s "$alsa_deb" ] || die 'resume requested but ALSA package is absent'
	[ -L "$root/lib" ] && [ "$(readlink "$root/lib")" = usr/lib ] || \
		die 'resume rootdir does not have the expected /lib -> usr/lib layout'
	grep -Eq '^ID=debian$' "$root/etc/os-release" || \
		die 'resume rootdir is not Debian'
	grep -Eq '^VERSION_CODENAME=trixie$' "$root/etc/os-release" || \
		die 'resume rootdir is not Debian trixie'
	[ "$(stat -c %u "$root/etc/passwd")" = 0 ] || \
		die 'resume rootdir no longer preserves target root ownership'
	[ -s "$root/etc/ssh/sshd_config.d/10-raphael-key-only.conf" ] || \
		die 'resume rootdir lacks the key-only SSH policy'
	build_mode=resume-images-from-validated-staging
	bootstrap_reused=true
else
	prepare_binfmt
	if [ -e "$OUTPUT_DIR" ]; then
		[ "$ALLOW_CLEAN" = 1 ] || \
			die "output exists; set ALLOW_CLEAN=1 to replace it: $OUTPUT_DIR"
		rm -rf -- "$OUTPUT_DIR"
	fi
	mkdir -p "$OUTPUT_DIR/inputs" "$OUTPUT_DIR/rootdir" "$OUTPUT_DIR/boot-staging"
	dpkg-deb --build --root-owner-group \
		"$BUILDER_SOURCE/firmware-xiaomi-raphael" "$firmware_deb" >/dev/null
	dpkg-deb --build --root-owner-group \
		"$BUILDER_SOURCE/alsa-xiaomi-raphael" "$alsa_deb" >/dev/null

	packages=systemd-sysv,udev,dbus,kmod,initramfs-tools,openssh-server,sudo,network-manager,iproute2,iputils-ping,dnsmasq,nftables,ca-certificates,locales,tzdata,chrony,procps,less,nano,curl,wget,usbutils,ethtool,rfkill,wpasupplicant,iw,zstd,busybox,e2fsprogs,dosfstools,alsa-utils,alsa-ucm-conf,rmtfs,protection-domain-mapper,tqftpserv,grub-common,grub-efi-arm64-bin

	mmdebstrap \
		--mode=root \
		--architectures=arm64 \
		--variant=minbase \
		--aptopt='Acquire::ForceIPv4 "true"' \
		--aptopt='APT::Install-Recommends "false"' \
		--include="$packages" \
		"$SUITE" "$root" \
		"deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] $DEBIAN_MIRROR $SUITE main contrib non-free non-free-firmware" \
		"deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] $DEBIAN_MIRROR $SUITE-updates main contrib non-free non-free-firmware" \
		"deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] $SECURITY_MIRROR $SUITE-security main contrib non-free non-free-firmware"

	install_kernel_payload "$root" "$KERNEL_DEB"
	dpkg-deb -x "$firmware_deb" "$root"
	dpkg-deb -x "$alsa_deb" "$root"
fi

# Configuration is intentionally refreshed in both full and validated-resume
# modes so fixes to services, hostname policy and SSH do not require another
# package bootstrap.
write_rootfs_configuration "$root" "$SSH_PUBLIC_KEY"

kernel=$(find "$root/boot" -maxdepth 1 -type f -name 'vmlinuz-*' -print -quit)
config=$(find "$root/boot" -maxdepth 1 -type f -name 'config-*' -print -quit)
[ -n "$kernel" ] || die 'kernel package did not install a vmlinuz file'
[ -n "$config" ] || die 'kernel package did not install a config file'
release=${kernel##*/vmlinuz-}
[ "$release" = "$EXPECTED_KERNEL_RELEASE" ] || die "unexpected kernel release: $release"
base_dtb=$root/boot/dtbs/qcom/sm8150-xiaomi-raphael.dtb
[ -f "$base_dtb" ] || die 'kernel package lacks Raphael DTB'
grep -qx 'CONFIG_EFI_STUB=y' "$config" || die 'kernel lacks EFI stub'
grep -qx 'CONFIG_SCSI_UFS_QCOM=y' "$config" || die 'Qualcomm UFS is not built in'
grep -qx 'CONFIG_EXT4_FS=y' "$config" || die 'ext4 is not built in'

initramfs=$root/boot/initrd.img-$release
[ "$RESUME_FROM_IMAGES" = 1 ] || build_initramfs "$root" "$release"
[ -s "$initramfs" ] || die 'initramfs was not produced'

grub_cfg=$OUTPUT_DIR/boot-staging/grub.cfg
grub_efi=$OUTPUT_DIR/boot-staging/BOOTAA64.EFI
[ "$RESUME_FROM_IMAGES" = 1 ] || build_grub_efi "$root" "$grub_cfg" "$grub_efi"
[ -s "$grub_cfg" ] || die 'GRUB configuration is absent'
file "$grub_efi" | grep -q 'PE32+ executable.*Aarch64' || die 'GRUB output is not AArch64 EFI'

runtime_dtb=$OUTPUT_DIR/boot-staging/sm8150-xiaomi-raphael-runtime.dtb
"$SCRIPT_DIR/prepare_runtime_dtb.sh" "$base_dtb" "$runtime_dtb" >/dev/null

cache_img=$OUTPUT_DIR/raphael-cache-boot.img
build_cache_image "$cache_img" "$grub_efi" "$kernel" "$initramfs" "$runtime_dtb" "$grub_cfg"
[ "$(stat -c %s "$cache_img")" -le 268435456 ] || die 'cache image exceeds live partition size'

rootfs_img=$OUTPUT_DIR/raphael-userdata-rootfs.img
truncate -s 0 "$rootfs_img"
truncate -s "$ROOTFS_SIZE" "$rootfs_img"
mke2fs -q -F -t ext4 -L raphael-rootfs -U "$ROOTFS_UUID" -m 0 \
	-d "$root" "$rootfs_img"
e2fsck -f -y "$rootfs_img" >/dev/null
resize2fs -M "$rootfs_img" >/dev/null
e2fsck -f -y "$rootfs_img" >/dev/null
[ "$(stat -c %s "$rootfs_img")" -le 247304531968 ] || die 'rootfs image exceeds live userdata partition size'

dpkg-query --admindir="$root/var/lib/dpkg" \
	--show --showformat='${Package}\t${Version}\t${Architecture}\n' \
	| LC_ALL=C sort >"$OUTPUT_DIR/package-manifest.tsv"
sha256sum "$root"/var/lib/apt/lists/*InRelease 2>/dev/null \
	>"$OUTPUT_DIR/apt-inrelease.sha256" || true

manifest=$OUTPUT_DIR/manifest.txt
{
	printf 'format=raphael-debian-server-v2\n'
	printf 'build_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'build_mode=%s\n' "$build_mode"
	printf 'bootstrap_reused=%s\n' "$bootstrap_reused"
	printf 'target_architecture=arm64\n'
	printf 'distribution=Debian\n'
	printf 'suite=%s\n' "$SUITE"
	printf 'debian_mirror=%s\n' "$DEBIAN_MIRROR"
	printf 'security_mirror=%s\n' "$SECURITY_MIRROR"
	printf 'kernel_source_commit=%s\n' "$KERNEL_SOURCE_COMMIT"
	printf 'kernel_release=%s\n' "$release"
	printf 'kernel_deb_sha256=%s\n' "$(sha256sum "$KERNEL_DEB" | awk '{print $1}')"
	printf 'kernel_builder_tree=%s\n' "$actual_builder_tree"
	printf 'firmware_deb_sha256=%s\n' "$(sha256sum "$firmware_deb" | awk '{print $1}')"
	printf 'alsa_deb_sha256=%s\n' "$(sha256sum "$alsa_deb" | awk '{print $1}')"
	printf 'ssh_policy=key-only;root-disabled;password-disabled\n'
	printf 'ssh_public_fingerprint=%s\n' "$(ssh-keygen -lf "$SSH_PUBLIC_KEY" | awk '{print $2}')"
	printf 'rootfs_uuid=%s\n' "$ROOTFS_UUID"
	printf 'cache_volume_id=%s\n' "$CACHE_VOLUME_ID"
	printf 'cache_filesystem=fat16;logical_sector_bytes=4096\n'
	printf 'console_policy=tty0-and-ttyMSM0;bringup-verbose\n'
	printf 'runtime_dtb_policy=display-normal-modeset;usb-wrapper-and-core-peripheral;role-switch-disabled\n'
	printf 'base_dtb_sha256=%s\n' "$(sha256sum "$base_dtb" | awk '{print $1}')"
	printf 'runtime_dtb_sha256=%s\n' "$(sha256sum "$runtime_dtb" | awk '{print $1}')"
	printf 'rootfs_bytes=%s\n' "$(stat -c %s "$rootfs_img")"
	printf 'rootfs_sha256=%s\n' "$(sha256sum "$rootfs_img" | awk '{print $1}')"
	printf 'cache_bytes=%s\n' "$(stat -c %s "$cache_img")"
	printf 'cache_sha256=%s\n' "$(sha256sum "$cache_img" | awk '{print $1}')"
	printf 'grub_efi_sha256=%s\n' "$(sha256sum "$grub_efi" | awk '{print $1}')"
	printf 'grub_config_sha256=%s\n' "$(sha256sum "$grub_cfg" | awk '{print $1}')"
} >"$manifest"

chown "$OUTPUT_UID:$OUTPUT_GID" "$OUTPUT_DIR" "$manifest" \
	"$OUTPUT_DIR/package-manifest.tsv" "$OUTPUT_DIR/apt-inrelease.sha256" \
	"$cache_img" "$rootfs_img"
chown -R "$OUTPUT_UID:$OUTPUT_GID" "$OUTPUT_DIR/inputs" \
	"$OUTPUT_DIR/boot-staging"
printf 'Built Raphael Debian system without accessing the phone:\n'
cat "$manifest"
printf 'SSH uses the public key supplied by the builder; keep its private key private.\n'
