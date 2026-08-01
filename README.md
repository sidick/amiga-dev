# amiga-dev

The shared cross-compiler + test-harness toolchain image for classic AmigaOS
projects: one versioned `ghcr.io/sidick/amiga-dev` image (amd64 + arm64),
built natively per architecture, so a downstream project's CI is a ~10-line
caller and a toolchain upgrade is one tag bump. See
[`docs/phase0-decisions.md`](docs/phase0-decisions.md) for the reasoning
behind what is and isn't in this image.

## What's inside

Run `scripts/print-pins.sh` for the exact, current pins — that's the source
of truth; nothing here is hand-copied because hand-copied version lists go
stale the moment a pin moves. In short:

- The m68k-amigaos GCC cross-toolchain, from a pinned commit of
  [`sidick/container-amiga-gcc`](https://github.com/sidick/container-amiga-gcc)
  (`vendor/container-amiga-gcc`, a submodule) at `/opt/amiga`.
- `amitools[vamos]`, pinned to a specific PyPI release (needed by 2+
  downstream repos' host-side tests).
- `mesa-vulkan-drivers` (lavapipe), for Copperline's headless Vulkan init
  (needed by 2+ downstream repos' on-target smoke tests).
- Copperline, on `PATH` at `/opt/copperline/bin/copperline`.

## Pin-bump procedure

Every pin lives in exactly one of two places:

- **Compiler toolchain** (GCC branch/version, vasm/vlink/binutils/etc.): the
  `vendor/container-amiga-gcc` submodule commit, plus
  `BUILD_GCC_BRANCH`/`BUILD_GCC_VERSION` in `.github/workflows/publish.yml`
  and the local build command below. Bump by pointing the submodule at a new
  commit (`cd vendor/container-amiga-gcc && git fetch && git checkout
  <sha>`), not by editing files inside it.
- **Everything else** (Copperline, amitools): an `ARG ..._VERSION` default
  near the top of `Dockerfile`.

After bumping any pin: build locally first (below), then push a `vX.Y.Z`
tag to trigger `publish.yml`, which builds both architectures natively,
runs the smoke tests, checks the cross-arch reproducibility gate, and (only
if all of that passes) publishes the multi-arch manifest and moves the
floating `vX`/`vX.Y`/`latest` tags.

## Building locally on the Mac

Docker Desktop on Apple Silicon runs the `linux/arm64` daemon natively, so a
local build exercises the same arm64 path CI does - debug Containerfile
breakage here, not through CI logs:

```sh
git submodule update --init --recursive

docker build \
  -f vendor/container-amiga-gcc/Containerfile \
  -t amiga-dev-compiler-base:local \
  --build-arg BUILD_GCC_BRANCH=amiga6 \
  --build-arg BUILD_GCC_VERSION=6.5.0b \
  vendor/container-amiga-gcc

docker build -t amiga-dev:local --build-arg BASE_IMAGE=amiga-dev-compiler-base:local .
```

Pulling the published image is architecture-transparent - Docker resolves
the right manifest automatically:

```sh
docker pull ghcr.io/sidick/amiga-dev:v1   # arm64 natively on the Mac, amd64 in CI
```

## Consuming this image

Downstream project CI should pin a specific `vX.Y.Z` (or float on `vX` once
the toolchain has proven stable) - see `sidick/amiga-workflows` for the
reusable `build-test.yml` that wraps this image behind the verb contract
(`make build` / `test-host` / `test-target` / `lint` / `dist`).
