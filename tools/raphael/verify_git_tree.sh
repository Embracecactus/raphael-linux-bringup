#!/usr/bin/env bash
# Reconstruct and verify the Git tree object ID of an unpacked source tree.
set -euo pipefail

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || die "usage: $0 SOURCE_DIRECTORY EXPECTED_TREE_SHA"
source_root=$(realpath -- "$1")
expected_tree=$2
[ -d "$source_root" ] || die "source directory does not exist: $source_root"
[[ "$expected_tree" =~ ^[0-9a-f]{40}$ ]] || die 'expected tree SHA must be 40 lowercase hex characters'
[ ! -e "$source_root/.git" ] || die 'source directory must be an archive tree without .git metadata'

stage=$(mktemp -d /tmp/raphael-tree-verify.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
verify_git=$stage/verify.git
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init --bare --quiet "$verify_git"
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
	git --git-dir="$verify_git" config core.autocrlf false
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
	git --git-dir="$verify_git" config core.filemode true
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
	git --git-dir="$verify_git" config core.symlinks true
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
	git --git-dir="$verify_git" --work-tree="$source_root" add --all --force -- .
actual_tree=$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
	git --git-dir="$verify_git" write-tree)
[ "$actual_tree" = "$expected_tree" ] || \
	die "Git tree mismatch: expected $expected_tree, reconstructed $actual_tree"
printf '%s\n' "$actual_tree"
