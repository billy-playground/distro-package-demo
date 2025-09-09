# Distro Package Build Scripts

This repository contains helper functions to:

* Build a platform-specific OCI image layout from a Debian repository slice (`craft_platform_specific`).
* Aggregate multiple platform-specific layouts into a multi-platform OCI manifest index (`craft_multi_platform_index`).

Below are quick test instructions to exercise the workflow locally.

## Prerequisites

* Bash (recommended 4+)
* `oras` CLI installed and available in PATH (version 1.3.0 or later)


## 1. Clean test output folder

Removes any previous test artifacts and recreates needed directories.

```bash
rm -rf ./test && mkdir -p ./test
```

## 2. Craft a platform-specific artifact

This writes an OCI layout plus a `digest` file into `./test/prepare-output/linux_amd64_ubuntu22.04`.

```bash
source ./build.sh
craft_platform_specific ./testdata/debian/archives ./test/prepare-output/linux_amd64_ubuntu22.04
```

Expected result:

* `./test/prepare-output/linux_amd64_ubuntu22.04/` contains `oci-layout`, `blobs/`, and a `digest` file whose contents look like `sha256:<hex>` or `layout@sha256:<hex>` depending on implementation.

Quick check:

```bash
cat ./test/prepare-output/linux_amd64_ubuntu22.04/digest
```

## 3. Craft a multi-platform artifact (index)

Aggregate any platform subdirectories under `./test/prepare-output` into a manifest index tagged `v1.0.0` inside `./test/process-output`.

```bash
craft_multi_platform_index ./test/prepare-output ./test/process-output v1.0.0
```

(If you add more platform dirs, e.g. `linux_arm64_ubuntu22.04`, they are auto-discovered as long as each has a `digest` file.)

## 4. Inspect the resulting index (optional)

If you want to view the created index manifest:

```bash
oras manifest fetch --oci-layout ./test/process-output:v1.0.0 --pretty
```

## Cleanup

```bash
rm -rf ./test/
```
