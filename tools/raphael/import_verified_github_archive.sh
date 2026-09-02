#!/usr/bin/env bash
# Import a GitHub-generated source archive only when its reconstructed Git tree
# matches an independently obtained tree object ID.
set -euo pipefail

usage()
{
	printf 'Usage: %s ARCHIVE EXPECTED_TOP_DIR EXPECTED_TREE_SHA DESTINATION\n' "$0" >&2
	exit 2
}

die()
{
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 4 ] || usage
archive=$(realpath -- "$1")
expected_top=$2
expected_tree=$3
destination=$(realpath -m -- "$4")

[[ "$expected_top" =~ ^[A-Za-z0-9._-]+$ ]] || die 'unsafe expected top-level directory name'
[[ "$expected_tree" =~ ^[0-9a-f]{40}$ ]] || die 'expected tree SHA must be 40 lowercase hex characters'
[ -f "$archive" ] || die "archive does not exist: $archive"
[ ! -e "$destination" ] || die "destination already exists: $destination"

for tool in find git gzip mv readlink realpath sha256sum tar; do
	command -v "$tool" >/dev/null 2>&1 || die "missing host tool: $tool"
done

gzip -t "$archive"

# Reject members outside the single expected GitHub archive directory before
# extraction.  GNU tar also rejects dangerous '..' member traversal, but this
# explicit check leaves a reviewable policy in the build chain.
member_count=0
while IFS= read -r member; do
	member_count=$((member_count + 1))
	case "$member" in
		"$expected_top"|"$expected_top/"|"$expected_top/"*) ;;
		*) die "archive member escapes expected top-level directory: $member" ;;
	esac
	case "/$member/" in
		*/../*|*/./*) die "archive member contains a traversal component: $member" ;;
	esac
done < <(tar -tzf "$archive")
(( member_count > 0 )) || die 'archive is empty'

stage=$(mktemp -d /tmp/raphael-source-import.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
tar -xzf "$archive" --no-same-owner -C "$stage"
source_root=$stage/$expected_top
[ -d "$source_root" ] || die 'expected source root was not extracted'

mapfile -d '' -t top_entries < <(find "$stage" -mindepth 1 -maxdepth 1 -print0)
[ "${#top_entries[@]}" -eq 1 ] || die 'archive produced more than one top-level entry'
[ "${top_entries[0]}" = "$source_root" ] || die 'unexpected extracted top-level entry'

unexpected_type=$(find "$source_root" ! -type d ! -type f ! -type l -print -quit)
[ -z "$unexpected_type" ] || die "unsupported special file in archive: $unexpected_type"

# Symlinks are valid Git objects, including relative links containing '..'.
# Accept them only when their normalized targets remain inside this source tree.
while IFS= read -r -d '' link; do
	target=$(readlink -- "$link")
	case "$target" in
		/*) die "absolute symlink target in archive: $link -> $target" ;;
	esac
	resolved=$(realpath -m -- "$(dirname -- "$link")/$target")
	case "$resolved" in
		"$source_root"|"$source_root/"*) ;;
		*) die "symlink target escapes source tree: $link -> $target" ;;
	esac
done < <(find "$source_root" -type l -print0)

# A fresh external object database avoids modifying the imported source.  The
# index is built from every file regardless of .gitignore, preserving symlink
# and executable modes so git write-tree can reproduce the upstream tree ID.
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

mkdir -p -- "$(dirname -- "$destination")"
mv -- "$source_root" "$destination"

printf 'archive_sha256=%s\n' "$(sha256sum "$archive" | awk '{print $1}')"
printf 'verified_git_tree=%s\n' "$actual_tree"
printf 'imported_to=%s\n' "$destination"
