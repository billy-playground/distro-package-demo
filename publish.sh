#!/usr/bin/env bash
## Publish a single-platform apt repository as an OCI artifact
# Arguments:
#   $1 - layout_root (local OCI image layout directory containing versioned tags to publish)
#   $2 - repository  (including registry and repository path)
# Returns:
#   (implementation-defined)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/helpers.sh"

publish() {
  local layout_root="$1"; local repository="$2"
  # Basic argument checks
  if [ -z "$layout_root" ]; then
    echo "Error: layout_root directory argument missing" >&2
    return 1
  fi
  if [ ! -d "$layout_root" ]; then
    echo "Error: layout_root directory does not exist: $layout_root" >&2
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
  if ! tags=$(oras repo tags --oci-layout "$layout_root" 2> >(tee /dev/stderr)); then
    echo "Error: failed to list tags for local OCI layout: $layout_root" >&2
    return 1
  fi

  # Iterate over newline-delimited tags (oras prints one per line)
  local count=0
  while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    echo "Publishing tag: $tag" >&2
    if ! oras cp -r --from-oci-layout "${layout_root}:${tag}" "${repository}:${tag}" 2> >(tee /dev/stderr); then
      echo "Error: failed to publish tag $tag" >&2
      return 1
    fi
    count=$((count+1))
  done <<EOF
$tags
EOF

  if [ $count -eq 0 ]; then
    echo "Error: no tags found in local OCI layout: $layout_root" >&2
    return 1
  fi
  echo "Published ${count} tag(s) to $repository" >&2
}
