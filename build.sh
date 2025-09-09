#!/usr/bin/env bash
## Craft a platform specific image
# Arguments:
#   $1 - platform (e.g. linux/amd64, linux/arm64)
#   $2 - distribution_root (root folder containing repository artifacts: rpm, deb, metadata, etc.)
#   $3 - layout_root (destination root for OCI image layout; MUST be an absolute path to avoid ambiguity and ensure oras places blobs where expected)

# Source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/helpers.sh"

_craft_platform_specific_inner() {
	# Args: $1 platform, $2 layout_root
	local platform="$1"; local layout_root="$2"
	# Collect ALL regular files relative to current directory (distribution_root)
	local files=()
	while IFS= read -r -d '' f; do
		files+=("$f")
	done < <(find . -type f -print0 2>/dev/null)
	if [ ${#files[@]} -eq 0 ]; then
		echo "Error: No files found in distribution_root: $(pwd)" >&2
		return 1
	fi
	local digest
	# add debug output for next line
	if ! digest=$(oras push --artifact-platform "$platform" --oci-layout "$layout_root" "${files[@]}" --format go-template='{{.digest}}' 2> >(tee /dev/stderr)); then
		echo "Error: oras push failed" >&2
		return 1
	fi
	echo "${digest}" > "${layout_root}/digest"
}

craft_platform_specific() {
	local platform="$1"; local distribution_root="$2"; local layout_root="$3"
	# NOTE: layout_root should be an absolute path. Relative paths can cause oras to resolve layout state wrongly.

	ensure_oras || return 1
	if [ -z "$platform" ]; then echo "Error: platform argument missing" >&2; return 1; fi
	if [ -z "$distribution_root" ]; then echo "Error: distribution_root directory argument missing" >&2; return 1; fi
	if [ ! -d "$distribution_root" ]; then echo "Error: distribution_root directory does not exist: $distribution_root" >&2; return 1; fi

	# Enter directory, run inner logic, always popd
	pushd "$distribution_root" >/dev/null 2>&1 || { echo "Error: cannot enter distribution_root: $distribution_root" >&2; return 1; }
	_craft_platform_specific_inner "$platform" "$layout_root"
	local rc=$?
	popd >/dev/null 2>&1 || true
	return $rc
}

## Craft a multi platform index
# Behavior:
#   1. Auto-discovers all immediate subdirectories under $prepare_root.
#      Each subdirectory is expected to represent a platform-specific OCI layout
#      and must contain a file named 'digest' whose content is a raw manifest digest (sha256:...).
#   2. For each valid subdirectory it reads the digest value and performs:
#        oras cp --from-oci-layout <platform_layout_dir>@<digest> --to-oci-layout <local_layout>
#      This ensures the referenced manifest is present in the aggregate local layout store.
#   3. After collecting all digests it creates a multi-platform index referencing them:
#        oras manifest index create --oci-layout <local_layout>:<version> <digest...>
# Requirements:
#   - oras CLI must be available (checked via ensure_oras).
# Arguments:
#   $1 - prepare_root  : Root directory containing per-platform subdirectories (each with a 'digest' file).
#   $2 - output_layout_root  : Destination OCI layout directory to assemble the index (created if missing).
#   $3 - version       : Tag applied to the created index inside local_layout.
# Output:
#   (Currently no explicit echo of the created reference; update implementation if external callers expect it.)
craft_multi_platform_index() {
	local prepare_root="$1"; local output_layout_root="$2"; local version="$3"

	# validate arguments
	ensure_oras || return 1
	if [ -z "$prepare_root" ]; then
		echo "Error: prepare_root argument missing" >&2
		return 1
	fi
	if [ ! -d "$prepare_root" ]; then
		echo "Error: prepare_root directory does not exist: $prepare_root" >&2
		return 1
	fi
	if [ -z "$version" ]; then
		echo "Error: version argument missing" >&2
		return 1
	fi

	# collect digests
	local digests=()
	for layout_root in "$prepare_root"/*/; do
		# skip non directories
		[ -d "$layout_root" ] || continue
		local digest_file="$layout_root/digest"
		if [ ! -f "$digest_file" ]; then
			echo "Warning: skipping $layout_root as no digest file found" >&2
			continue
		fi
		local digest
		digest="$(<"$digest_file")"
		# Copy manifest into aggregate local layout
		if ! oras cp --from-oci-layout "${layout_root}@${digest}" --to-oci-layout "${output_layout_root}" 2> >(tee /dev/stderr); then
			echo "Error: oras cp failed for $layout_root@$digest" >&2
			return 1
		fi
		digests+=("$digest")
	done
	if [ ${#digests[@]} -eq 0 ]; then
		echo "Error: no valid digests collected under prepare_root: $prepare_root" >&2
		return 1
	fi

	# Create multi-platform index
	if ! oras manifest index create --oci-layout "${output_layout_root}:${version}" "${digests[@]}" 2> >(tee /dev/stderr); then
		echo "Error: failed to create manifest index" >&2
		return 1
	fi
}