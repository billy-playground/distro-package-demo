#!/usr/bin/env bash

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
	# Push and tag the artifact as 'crafted' (no digest file written anymore)
	if ! digest=$(oras push --artifact-platform "$platform" --oci-layout "${layout_root}:crafted" "${files[@]}" --format go-template='{{.digest}}' 2> >(tee /dev/stderr)); then
		echo "Error: oras push failed" >&2
		return 1
	fi
}

## Craft a platform specific image
# Arguments:
#   $1 - platform (e.g. linux/amd64, linux/arm64)
#   $2 - distribution_root (root folder containing repository artifacts: rpm, deb, metadata, etc.)
#   $3 - layout_root (destination root for OCI image layout; MUST be an absolute path to avoid ambiguity and ensure oras places blobs where expected)
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
# Creates a multi-platform OCI manifest index by 
# 1) scanning per-platform layout dirs
# 2) fetching each tag’s manifest digest (linux/amd64)
# 3) copying those manifests into a target layout
# 4) building an index tagged with the provided version
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

	# collect digests by enumerating tags in each per-platform layout (no deduplication)
	local digests=()
	for layout_root in "$prepare_root"/*/; do
		[ -d "$layout_root" ] || continue
		# list tags in this local layout
		local tags
		if ! tags=$(oras repo tags --oci-layout "$layout_root" 2> >(tee /dev/stderr)); then
			echo "Warning: failed to list tags for $layout_root; skipping" >&2
			continue
		fi
		if [ -z "$tags" ]; then
			echo "Warning: no tags found in $layout_root; skipping" >&2
			continue
		fi
		while IFS= read -r tag; do
			[ -n "$tag" ] || continue
			local digest
			if ! digest=$(oras manifest fetch --oci-layout "${layout_root}:${tag}" --platform linux/amd64 --format go-template='{{.digest}}' 2> >(tee /dev/stderr)); then
				echo "Warning: failed to fetch digest for ${layout_root}:${tag}; skipping tag" >&2
				continue
			fi
			# copy manifest into aggregate layout (duplicates allowed; oras cp should be idempotent)
			if ! oras cp --from-oci-layout "${layout_root}@${digest}" --to-oci-layout "${output_layout_root}" 2> >(tee /dev/stderr); then
				echo "Error: oras cp failed for $layout_root@$digest" >&2
				return 1
			fi
			digests+=("$digest")
		done <<< "$tags"
	done
	if [ ${#digests[@]} -eq 0 ]; then
		echo "Error: no digests collected from tags under prepare_root: $prepare_root" >&2
		return 1
	fi

	# Create multi-platform index
	if ! oras manifest index create --oci-layout "${output_layout_root}:${version}" "${digests[@]}" 2> >(tee /dev/stderr); then
		echo "Error: failed to create manifest index" >&2
		return 1
	fi
}