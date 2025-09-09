#!/usr/bin/env bash
# Shared helper functions for build scripts

# Validate repository string against required pattern
_validate_repository() {
  local repo="$1"
  local pattern='^[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*(\/[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*)*$'
  if [[ ! $repo =~ $pattern ]]; then
    echo "Error: Invalid repository format: $repo" >&2
    return 1
  fi
  return 0
}


# Ensure oras is installed (returns 0 if yes)
ensure_oras() {
  if ! command -v oras >/dev/null 2>&1; then
    echo "Error: oras CLI not found in PATH" >&2
    return 1
  fi
  return 0
}
