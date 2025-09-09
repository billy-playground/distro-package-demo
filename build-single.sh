#!/usr/bin/env bash
## Craft a platform specific image
# Arguments:
#   $1 - distribution_root (root folder of the apt repository distribution)
#   $2 - oci_layout_root (destination root for OCI image layout)
# Returns:
#   digest

# Source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/helpers.sh"

craft_platform_specific() {
	local distribution_root="$1"; local oci_layout_root="$2"

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

	local files=()
	[ -f "$distribution_root/Packages" ] && files+=("$distribution_root/Packages")
	[ -f "$distribution_root/Packages.gz" ] && files+=("$distribution_root/Packages.gz")
	while IFS= read -r -d '' deb; do
		files+=("$deb")
	done < <(find "$distribution_root" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null)

	if [ ${#files[@]} -eq 0 ]; then
		echo "Error: No files (Packages, Packages.gz, *.deb) found in distribution_root: $distribution_root" >&2
		return 1
	fi

	local digest
	if ! digest=$(oras push --oci-layout "$oci_layout_root" "${files[@]}" --format go-template '{{.digest}}' 2> >(tee /dev/stderr)); then
		echo "Error: oras push failed" >&2
		return 1
	fi
	echo "$digest"
}

## Craft a multi platform index
# Arguments:
#   $1 - root (no validation performed)
#   $2 - version
#   $@ - digests (all remaining arguments)
# Returns:
#   (output as needed)
craft_multi_platform_index() {
	local root="$1"; local version="$2"; shift 2
	local digests=("$@")

	# Ensure oras CLI is available
	ensure_oras || return 1

	if [ -z "$root" ]; then
		echo "Error: root argument missing" >&2
		return 1
	fi
	if [ ! -d "$root" ]; then
		echo "Error: root directory does not exist: $root" >&2
		return 1
	fi

	if [ -z "$version" ]; then
		echo "Error: version argument missing" >&2
		return 1
	fi
	if [ ${#digests[@]} -eq 0 ]; then
		echo "Error: at least one digest required" >&2
		return 1
	fi

	# Run oras manifest index create as requested
	oras manifest index create --oci-layout "${root}:${version}" "${digests[@]}"
}

