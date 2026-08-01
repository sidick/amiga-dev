# syntax=docker/dockerfile:1
#
# Tool layer: everything downstream Amiga project CI needs beyond the raw
# m68k cross-compiler. Built FROM the compiler-base image produced by
# vendor/container-amiga-gcc's own Containerfile (see README.md for the
# two-step local build). Only dependencies needed by two or more downstream
# repos live here — see docs/phase0-decisions.md, "Survey per-repo CI
# dependencies" for the rule and the survey behind it.
ARG BASE_IMAGE=amiga-dev-compiler-base:local
FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG COPPERLINE_VERSION=0.14.0
ARG AMITOOLS_VERSION=0.8.1

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/copperline/bin:$PATH

# amitools[vamos], pinned. The compiler-base layer already installs amitools
# from git main (unpinned) as a build-time dependency of its own; this
# reinstalls a fixed release so the image has one reproducible version
# rather than "whatever HEAD was on build day". Needed by sana2loop (host
# tests) and amiauth (asm-crypto-tests) - two consumers, so it belongs here
# rather than as a repo-local pip install.
RUN pip3 install --break-system-packages --force-reinstall "amitools[vamos]==${AMITOOLS_VERSION}"

# Software Vulkan (lavapipe), for Copperline's headless wgpu init. Needed by
# sana2loop (copperline-smoke) and amiauth (gui-smoke) - two consumers.
RUN apt-get update && \
    apt-get install -y --no-install-recommends mesa-vulkan-drivers && \
    rm -rf /var/lib/apt/lists/*

# Copperline itself. amd64 uses the upstream prebuilt AppImage (fast, no
# Rust toolchain needed). arm64 has no Linux release asset upstream, so it's
# built from the tagged release source instead - see
# docs/phase0-decisions.md, "Resolve Copperline arm64". Both paths install
# into the same /opt/copperline/bin + share/copperline/aros layout that
# Copperline's own romsearch.rs looks for relative to the executable, so no
# COPPERLINE_AROS_DIR override is needed either way.
COPY scripts/install-copperline.sh /tmp/install-copperline.sh
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) \
        apt-get update && \
        apt-get install -y --no-install-recommends \
          libasound2t64 libudev1 libx11-6 libxcursor1 libxrandr2 libxi6 \
          libxkbcommon0 libwayland-client0 && \
        rm -rf /var/lib/apt/lists/* && \
        /tmp/install-copperline.sh amd64 \
        ;; \
      arm64) \
        build_deps="build-essential curl git ca-certificates pkg-config \
          libasound2-dev libudev-dev libx11-dev libxcursor-dev \
          libxrandr-dev libxi-dev libxkbcommon-dev libwayland-dev" && \
        apt-get update && \
        apt-get install -y --no-install-recommends ${build_deps} && \
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
          | sh -s -- -y --profile minimal --default-toolchain stable && \
        . "$HOME/.cargo/env" && \
        /tmp/install-copperline.sh arm64 && \
        rustup self uninstall -y && \
        apt-get purge -y ${build_deps} && \
        apt-get install -y --no-install-recommends \
          libasound2t64 libudev1 libx11-6 libxcursor1 libxrandr2 libxi6 \
          libxkbcommon0 libwayland-client0 && \
        apt-get autoremove -y && \
        rm -rf /var/lib/apt/lists/* \
        ;; \
      *) \
        echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 \
        ;; \
    esac && \
    rm /tmp/install-copperline.sh

LABEL org.opencontainers.image.title="amiga-dev"
LABEL org.opencontainers.image.description="Shared cross-compiler + test-harness toolchain for classic AmigaOS projects"
LABEL org.opencontainers.image.source="https://github.com/sidick/amiga-dev"
LABEL amiga-dev.copperline_version="${COPPERLINE_VERSION}"
LABEL amiga-dev.amitools_version="${AMITOOLS_VERSION}"
