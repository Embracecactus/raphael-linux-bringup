#!/usr/bin/env bash
# Install LLVM 22 built from the same LLVM source revision as the published
# Raphael v7 package.
# Package transport defaults to the TUNA llvm-apt mirror; repository metadata is
# authenticated with the official apt.llvm.org signing key.
set -euo pipefail

MIRROR=${MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/llvm-apt}
KEY_URL=${KEY_URL:-https://apt.llvm.org/llvm-snapshot.gpg.key}
SUITE=llvm-toolchain-jammy-22
KEY_FINGERPRINT=6084F3CF814B57C1CF12EFD515CF4D18AF4F7421
REFERENCE_CLANG_LINE='Ubuntu clang version 22.1.8 (++20260613092238+e80beda6e255-1~exp1~20260613092253.78)'
EXPECTED_PACKAGE_VERSION='1:22.1.8~++20260613092327+e80beda6e255-1~exp1~20260613092437.81'

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

[ "${EUID:-$(id -u)}" -eq 0 ] || die 'run as root'
for tool in apt-get awk curl dpkg-query gpg install mkdir mktemp rm sed sha256sum; do
	command -v "$tool" >/dev/null 2>&1 || die "missing host tool: $tool"
done

stage=$(mktemp -d /tmp/raphael-llvm22.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT

key=$stage/llvm-snapshot.gpg.key
curl -L --fail --show-error --silent "$KEY_URL" -o "$key"
fingerprint=$(gpg --batch --show-keys --with-colons "$key" 2>/dev/null | \
	awk -F: '$1 == "fpr" { print $10; exit }')
[ "$fingerprint" = "$KEY_FINGERPRINT" ] || \
	die "unexpected apt.llvm.org signing-key fingerprint: $fingerprint"

mkdir -p /etc/apt/keyrings
gpg --batch --yes --dearmor --output "$stage/llvm-snapshot.gpg" "$key"
install -m 0644 "$stage/llvm-snapshot.gpg" /etc/apt/keyrings/llvm-snapshot.gpg
printf 'deb [signed-by=/etc/apt/keyrings/llvm-snapshot.gpg] %s/jammy/ %s main\n' \
	"$MIRROR" "$SUITE" >"$stage/raphael-llvm22.list"
install -m 0644 "$stage/raphael-llvm22.list" /etc/apt/sources.list.d/raphael-llvm22.list

apt-get update \
	-o Dir::Etc::sourcelist=/etc/apt/sources.list.d/raphael-llvm22.list \
	-o Dir::Etc::sourceparts=- \
	-o APT::Get::List-Cleanup=0
apt-get install -y --no-install-recommends clang-22 lld-22 llvm-22

actual_clang_line=$(clang-22 --version | sed -n '1p')
actual_package_version=$(dpkg-query -W -f='${Version}' clang-22)
[ "$actual_package_version" = "$EXPECTED_PACKAGE_VERSION" ] || \
	die "LLVM package drift: $actual_package_version"
for tool in clang-22 ld.lld-22 llvm-ar-22 llvm-nm-22 llvm-objcopy-22 \
	llvm-objdump-22 llvm-readelf-22 llvm-strip-22; do
	command -v "$tool" >/dev/null 2>&1 || die "installed package lacks $tool"
done

printf 'llvm22_install=PASS\n'
printf 'mirror=%s\n' "$MIRROR"
printf 'suite=%s\n' "$SUITE"
printf 'signing_key_fingerprint=%s\n' "$fingerprint"
printf 'signing_key_sha256=%s\n' "$(sha256sum "$key" | awk '{print $1}')"
printf 'compiler=%s\n' "$actual_clang_line"
printf 'reference_compiler=%s\n' "$REFERENCE_CLANG_LINE"
printf 'compiler_source_revision_match=e80beda6e255\n'
printf 'compiler_package_binary_match=no; mirror package is build .81, reference is build .78\n'
dpkg-query -W -f='package=${binary:Package} version=${Version}\n' \
	clang-22 lld-22 llvm-22 libclang-cpp22 libllvm22
