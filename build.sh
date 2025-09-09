#!/usr/bin/env bash
## Craft a platform specific image
# Arguments:
#   $1 - distribution_root (root folder of the a repository archives distribution)
#   $2 - layout_root (destination root for OCI image layout)

# Source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/helpers.sh"

craft_platform_specific() {
	local distribution_root="$1"; local layout_root="$2"

	# Ensure oras CLI is available
	ensure_oras || return 1

	# Ensure packages root is valid
	if [ -z "$distribution_root" ]; then
		echo "Error: distribution_root directory argument missing" >&2
		return 1
	fi
	if [ ! -d "$distribution_root" ]; then
		echo "Error: distribution_root directory does not exist: $distribution_root" >&2
		return 1
	fi

	# load metadata files
	local files=()
	if [ -f "$distribution_root/Packages" ]; then
		files+=("$distribution_root/Packages")
	elif [ -f "$distribution_root/Packages.gz" ]; then
		files+=("$distribution_root/Packages.gz")
	else
		echo "Error: Neither Packages nor Packages.gz found in distribution_root: $distribution_root" >&2
		return 1
	fi

	# load .deb files
	while IFS= read -r -d '' deb; do
		files+=("$deb")
	done < <(find "$distribution_root" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null)

	local deb_count=0
	while IFS= read -r -d '' deb; do
		deb_count=$((deb_count + 1))
	done < <(find "$distribution_root" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null)
	if [ $deb_count -eq 0 ]; then
		echo "Error: No .deb files found in distribution_root: $distribution_root" >&2
		return 1
	fi

	# pack into OCI image layout
	local digest
	if ! digest=$(oras push --oci-layout "$layout_root" "${files[@]}" --format go-template='{{.digest}}' 2> >(tee /dev/stderr)); then
		echo "Error: oras push failed" >&2
		return 1
	fi
	echo "${digest}" > ${layout_root}/digest
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

