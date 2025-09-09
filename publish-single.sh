#!/usr/bin/env bash
## Publish a single-platform apt repository as an OCI artifact
# Arguments:
#   $1 - root (directory containing Packages/Packages.gz and .deb files)
#   $2 - repository (including registry and repository path)
# Returns:
#   (implementation-defined)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/helpers.sh"

publish() {
  local root="$1"; local repository="$2"
  # Basic argument checks
  if [ -z "$root" ]; then
    echo "Error: root directory argument missing" >&2
    return 1
  fi
  if [ ! -d "$root" ]; then
    echo "Error: root directory does not exist: $root" >&2
    return 1
  fi
  if [ -z "$repository" ]; then
    echo "Error: repository argument missing" >&2
    return 1
  fi
  _validate_repository "$repository" || return 1
  ensure_oras || return 1

  # Fetch tags from local OCI layout
  local tags
  if ! tags=$(oras repo tags --oci-layout "$root" 2> >(tee /dev/stderr)); then
    echo "Error: failed to list tags for local OCI layout: $root" >&2
    return 1
  fi

  # Normalize whitespace and split into array
  read -r -a tag_array <<<"$tags"
  if [ ${#tag_array[@]} -eq 0 ]; then
    echo "Error: no tags found in local OCI layout: $root" >&2
    return 1
  fi

  # Copy each tag to remote repository
  local tag
  for tag in "${tag_array[@]}"; do
    echo "Publishing tag: $tag" >&2
    if ! oras cp -r --oci-layout "${root}:${tag}" "${repository}:${tag}" 2> >(tee /dev/stderr); then
      echo "Error: failed to publish tag $tag" >&2
      return 1
    fi
  done
  echo "Published ${#tag_array[@]} tag(s) to $repository" >&2
}
