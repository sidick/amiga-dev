# Phase 0 decisions

Answers to the Phase 0 TODOs from the shared-toolchain plan. Each entry is a
decision plus the evidence it's based on, so it can be checked later without
re-doing the research.

## Pin the compiler base

**Decision:** vendor `container-amiga-gcc` as a submodule pinned to commit
`7f39626c0b6c8d71400f5e4112978007c62b1344` — the head of
`reinauer/container-amiga-gcc#4` ("Build gencrc from source instead of
downloading the release binary", branch `sidick:build-gencrc-from-source`,
open, mergeable). This PR is what makes the base arm64-capable at all: the
current `main` installs a prebuilt `gencrc` release binary that is x86_64
only, which would silently break the arm64 leg of the image. Left a note on
the PR that it's now load-bearing downstream.

Also open on the same upstream repo and worth tracking: PR #3 (OCI image
labels, unrelated/independent) and PR #2 (macOS Tahoe / GCC 16.1 build fix,
unrelated to the arch question).

## Verify the toolchain prefix

**Decision:** confirmed. The pinned Containerfile builds into
`/opt/amiga-${BUILD_GCC_VERSION}` and symlinks `/opt/amiga` → that directory,
with `PATH=/opt/amiga/bin:$PATH`. The plan's assumed `COPY --from` prefix
(`/opt/amiga`) is correct as-is — no changes needed to the drafted
Dockerfile on this point.

Default build args on the pinned commit: `BUILD_GCC_BRANCH=amiga6`,
`BUILD_GCC_VERSION=6.5.0b`, `NDK_VERSION` defaults to 3.2 in-recipe. GCC
13.4 and 16.1 branches exist as commented alternatives if a version bump is
ever wanted.

## Resolve Copperline arm64

**Decision:** no aarch64 asset exists upstream and none is coming for free —
fall back to the pinned `cargo install`/build-from-source stage, as the plan
already anticipated. Checked `CopperlineHQ/Copperline` releases through
v0.13.0: Linux ships only an `x86_64.AppImage`; macOS ships a
`macos-universal.dmg` (Apple Silicon capable, but that's not the Linux arm64
target this image needs); Windows is x64 only. No CI workflow in that repo
(`appimage.yml`, `linux-present.yml`, etc.) builds aarch64 Linux either, so
this isn't a "hasn't gotten to it yet" gap worth waiting on. Copperline is
Rust/GPL-3.0, so building from source is straightforward; pin to a tagged
release commit, not a branch tip.

## Survey per-repo CI dependencies

Surveyed `amiauth` and `sana2loop`'s current `ci.yml` (both already run
against `ghcr.io/reinauer/container-amiga-gcc:latest` directly — a floating
upstream tag, which the new pinned image also fixes). Applying the plan's
own rule ("two repos need it → image; one repo → stays local"):

| Dependency | Needed by | Verdict |
|---|---|---|
| `amitools[vamos]` | sana2loop (host tests), amiauth (`asm-crypto-tests`) | **→ image** (two consumers) |
| `mesa-vulkan-drivers` (lavapipe, for Copperline's headless wgpu init) | sana2loop (`copperline-smoke`), amiauth (gui-smoke) | **→ image** (two consumers) |
| `libssl-dev`, `pkg-config` (amiauth's differential fuzz vs OpenSSL) | amiauth only | stays a repo-local `apt install` step |
| Python RFB client | amirfb | **no dependency needed** — `tools/rfb_client.py` is hand-rolled on `socket`/`struct` only, stdlib. The plan's assumption that this needs a pip package doesn't hold; nothing to add for it. |
| `tools/docs-requirements.txt` (mkdocs) | sana2loop, amiauth | shared via the `docs.yml` reusable workflow (Phase 2), not the toolchain image — different layer, no action here |

amirfb has no `.github/workflows` yet at all (confirmed by directory listing) —
it's still pre-CI, consistent with Phase 5 treating it as the next
conversion target rather than an extraction source.

## Note for when harness/ extraction resumes (Phase 3/4)

Per you (2026-07-31, refined same day): from Copperline 0.14, `hostfs`
(`[[filesys]]`) is expected to be both bootable *and* usable on all
Kickstart 2.0+ setups — `CopperlineHQ/Copperline#312` (the
68000-hangs-on-`[[filesys]]` bug amiauth's current boot method works
around, see above) is a Kickstart-1.3-specific issue, not a general one.
So for every downstream repo except sana2loop, the converged design once
0.14 lands is simpler than "floppy-boot + hostfs-data": boot straight off
a hostfs mount, no ADF/xdftool step needed at all. Don't build the shared
boot-config abstraction around either repo's *current* method — wait for
0.14 and design the general case around boot-from-hostfs directly.

**sana2loop is a Kickstart 1.3 exception, not the general case.** You're
separately working on getting hostfs itself working under *real Kickstart
1.3* — which only sana2loop needs, since validating real KS1.3 fidelity is
that project's whole point, and is the one setup where 0.14 doesn't just
fix hostfs outright. Every other downstream repo (amiauth, amirfb, amiqr,
...) targets Kickstart 2.0+ and has no such constraint. So the general
boot-from-hostfs design above should be built for KS2.0+, with sana2loop
carved out as an explicit exception (still floppy-boot, or whatever KS1.3
ends up needing) in the verb contract/harness rather than folding KS1.3's
constraints into the general case — and the general design shouldn't be
blocked on KS1.3 hostfs support landing.

## Choose the canonical AROS test ROM build

**Decision: nothing to vendor.** The plan assumed sana2loop bundles its own
AROS ROM that should move to `amiga-dev/vendor/`. It doesn't — re-reading
`sana2loop`'s `ci.yml` comments: Copperline itself "bundles the emulator,
its libs, and the redistributable AROS Kickstart replacement (no licensed
ROM needed)." The ROM ships inside Copperline (AppImage or, per the arm64
decision above, the from-source build), not as a separate file sana2loop
carries. `AMIGA_TEST_ROM` in the verb contract should resolve to "whatever
Copperline boots by default," not a vendored file — there's no separate
provenance/checksum to track. `AMIGA_REAL_ROM` remains the opt-in path,
gated behind a `KICK=`/secret-supplied real Kickstart 1.3 image, exactly as
sana2loop already does it (`copperline-smoke-tools-aros` explicitly can't
run without one — SanaDump/SanaSend are V36+ tools).

## Vendor dated vasm/vlink snapshots

**Decision: nothing to vendor here either.** The Bebbo/`m68k-amigaos-gcc`
build system the pinned Containerfile drives already pins every sub-tool by
commit SHA via its own `bin/.revisions/*` mechanism, fetched during
`make update`/`make branch`:

- `leffmann/vasm` → `eac09b8c417432e2559a96d08fa94d0a3ddb8633`
- `leffmann/vlink` → `1c20c24c0b366f3c0bd3ad6f60a70f5c8c589693`
- `bebbo/amiga-gcc` → `b4bd527d66d02e5c82a7c6d2adba7a45bdeb51c9`
- `AmigaPorts/libSDL12` → `324f6bc150eea7fbf25a0fb9a4d26f1ef6b9d984`

Reproducibility already falls out of pinning the `container-amiga-gcc`
submodule commit (above) plus the `BUILD_GCC_BRANCH`/`BUILD_GCC_VERSION`
args — vendoring a second, separate snapshot into `amiga-dev/vendor/` would
just be a duplicate, driftable copy of state the submodule pin already
fixes. Drop this line item from the plan.

## Corrections to plan assumptions worth flagging

- **Scope correction (from you, mid-Phase-0): arm64 isn't for downstream CI
  at all.** No project's `build-test.yml` caller is meant to run on arm64
  GitHub runners — every consumer repo's CI stays amd64-only. arm64 exists
  for two things only: (1) `docker pull ghcr.io/sidick/amiga-dev:v1` on the
  MacBook resolving natively, and (2) the image-build pipeline itself having
  to produce that arm64 layer, which includes building Copperline for arm64
  (the earlier "resolve Copperline arm64" decision) since it needs to run
  natively on the Mac too. This removes the risk I'd flagged about `amirfb`
  and `amiqr` paying for arm64 CI minutes — they were never going to run
  build/test jobs on arm64 runners, so their private-repo status is
  irrelevant there.
- **What the correction put in scope: `sidick/amiga-dev` itself.** Its own
  publish workflow is the one place arm64 GitHub-hosted runners actually get
  used (building the arm64 layer of the toolchain image natively rather than
  emulating it under QEMU), and private-repo arm64 runners are billed, not
  free. Resolved: **`sidick/amiga-dev` is now public** (confirmed via
  `gh repo view`), so its publish workflow gets free native arm64 runners
  like everything else — no local-Mac-build workaround needed for this.
- **`container-amiga-gcc`'s own publish workflow is single-arch.** Its
  `.github/workflows/publish.yml` builds on `ubuntu-latest` with no
  `platforms:` matrix — amd64 only, no arm64 tag published upstream at all.
  This doesn't block the plan (amiga-dev builds the compiler-base layer
  itself from the vendored submodule rather than pulling a published tag),
  but it means there's no upstream arm64 image to diff against for the
  cross-arch reproducibility gate — that gate's baseline has to be
  amiga-dev's own two native builds against each other, not a comparison to
  upstream.

## Resolved by user decision

- **Default GCC version:** `6.5.0b` (`BUILD_GCC_BRANCH=amiga6`) — the pinned
  Containerfile's own default, kept rather than moving to 13.4/16.1 for the
  v1.0.0 baseline. Revisit once there's a concrete reason (a repo needing a
  newer-C-standard feature) rather than speculatively.
- **Note on PR #4 being load-bearing downstream:** skipped for now. Revisit
  before or at the v1.0.0 tag — worth doing once the submodule pin is
  actually in place and this is true rather than prospective.

## Open

- Canonical GHCR image name confirmed available: `ghcr.io/sidick/amiga-dev`
  (no existing package of that name found).
