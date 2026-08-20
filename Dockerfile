# syntax=docker/dockerfile:1
#
# Tool layer: everything downstream Amiga project CI needs beyond the raw
# m68k cross-compiler. The compiler-base image produced by
# vendor/container-amiga-gcc's own Containerfile (see README.md for the
# two-step local build) is used only as a build stage here: its own cleanup
# steps (rm -rf of the GCC build tree, apt purges) run in later layers than
# the multi-GB build tree they're removing, so none of that space is
# actually reclaimed in that image - FROM-ing it directly inherits all of
# it. Copying out just the toolchain output (/opt/amiga-*, /bin/gencrc,
# /usr/bin/lha) onto a fresh base avoids that. Only dependencies needed by
# two or more
# downstream repos live here — see docs/phase0-decisions.md, "Survey per-repo
# CI dependencies" for the rule and the survey behind it.
ARG BASE_IMAGE=amiga-dev-compiler-base:local
FROM ${BASE_IMAGE} AS compiler-base

FROM ubuntu:25.10

ARG TARGETARCH
ARG COPPERLINE_VERSION=0.16.0
ARG AMITOOLS_VERSION=0.8.1
ARG BUILD_GCC_VERSION=6.5.0b

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/amiga/bin:/opt/copperline/bin:$PATH

# The host-side package list compiler-base's own Containerfile installs and
# never purges (only libgmp-dev/libmpfr-dev/libmpc-dev/rsync/texinfo are
# purged there) - mirrored here rather than trimmed, since downstream repos
# depend on parts of it beyond just the m68k toolchain (e.g. `make dist`
# git-clones and autoreconf/gcc/make-builds a pinned lha from source; see
# docs/plan.md). This also transitively pulls every shared library the
# m68k-amigaos-gcc/gdb binaries under /opt/amiga-* link against (per `ldd`)
# except libc6/libstdc++6/libgcc-s1 (already in ubuntu:25.10) and
# libpython3.13 - compiler-base's own `apt-get install` (no
# --no-install-recommends there) pulls it in as a Recommends of python3;
# added explicitly here since this Dockerfile installs with
# --no-install-recommends throughout.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      apt-utils ca-certificates curl file git python3 python3-pip srecord \
      wget autoconf automake bison flex g++ gcc gettext libgmpxx4ldbl \
      libmpfr6 libmpc3 libncurses-dev libpython3.13 make patch perl zip && \
    rm -rf /var/lib/apt/lists/*

COPY --from=compiler-base /opt/amiga-${BUILD_GCC_VERSION} /opt/amiga-${BUILD_GCC_VERSION}
COPY --from=compiler-base /bin/gencrc /bin/gencrc
COPY --from=compiler-base /usr/bin/lha /usr/bin/lha
RUN ln -s /opt/amiga-${BUILD_GCC_VERSION} /opt/amiga

# amitools[vamos], pinned. The compiler-base layer already installs amitools
# from git main (unpinned) as a build-time dependency of its own; this
# reinstalls a fixed release so the image has one reproducible version
# rather than "whatever HEAD was on build day". Needed by sana2loop (host
# tests) and amiauth (asm-crypto-tests) - two consumers, so it belongs here
# rather than as a repo-local pip install. Its machine68k/musashi dependency
# has a C extension against Python.h - gcc is already installed above, but
# the Python headers aren't, so python3-dev is added just for this step and
# purged straight after since nothing at runtime needs it.
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-dev && \
    pip3 install --break-system-packages --force-reinstall "amitools[vamos]==${AMITOOLS_VERSION}" && \
    apt-get purge -y python3-dev && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

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
        # curl/git/ca-certificates are kept installed (not purged below),
        # matching amd64 - which never purges them either, since they're
        # inherited unremoved from the compiler-base layer. Both consumer
        # repos' `make dist` git-clones a pinned lha commit; parity here
        # means that works the same on a native arm64 Mac pull as it does
        # in amd64 CI, instead of only working on one architecture.
        build_only_deps="build-essential pkg-config \
          libasound2-dev libudev-dev libx11-dev libxcursor-dev \
          libxrandr-dev libxi-dev libxkbcommon-dev libwayland-dev" && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
          curl git ca-certificates ${build_only_deps} && \
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
          | sh -s -- -y --profile minimal --default-toolchain stable && \
        . "$HOME/.cargo/env" && \
        /tmp/install-copperline.sh arm64 && \
        rustup self uninstall -y && \
        apt-get purge -y ${build_only_deps} && \
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
