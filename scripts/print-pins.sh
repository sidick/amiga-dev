#!/bin/sh
# Prints exactly what's pinned into the current tree's image, read straight
# from the Dockerfile/submodule rather than hand-copied into the README
# (which would just go stale the next time a pin moves).
set -eu
cd "$(dirname "$0")/.."

echo "compiler-base commit: $(git -C vendor/container-amiga-gcc rev-parse HEAD)"
echo "compiler-base remote: $(git -C vendor/container-amiga-gcc remote get-url origin)"
grep -E '^ARG (BUILD_GCC_BRANCH|BUILD_GCC_VERSION)=' vendor/container-amiga-gcc/Containerfile
grep -E '^ARG (COPPERLINE_VERSION|AMITOOLS_VERSION)=' Dockerfile
