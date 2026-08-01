# Plan: Shared Toolchain & CI Infrastructure (amiga-dev / amiga-workflows)

**Status:** Phases 0–2 complete. Phase 3 (sana2loop conversion) next.
**Companion:** [`docs/phase0-decisions.md`](phase0-decisions.md) — every
Phase 0 decision, corrected assumption, and open design note lives there;
this file tracks progress phase-by-phase rather than re-deriving the
reasoning.

## Goal

Every project consumes one versioned toolchain image
(`ghcr.io/sidick/amiga-dev`, amd64 + arm64) and one set of reusable
workflows (`sidick/amiga-workflows@v1`), so a project's CI is ~10 lines, a
toolchain upgrade is one tag bump raised as a PR per repo by automation,
and the MacBook and CI provably build identically.

## The verb contract

    make build        cross-compile everything
    make test-host     host-side tests (vectors, portable core, vamos runs)
    make test-target   Copperline harness; honours AMIGA_TEST_ROM / AMIGA_REAL_ROM
    make lint          style/static checks
    make dist          release archive into dist/

Document of record: `sidick/amiga-workflows` README.md. As of Phase 2, no
consuming repo has renamed its Makefile targets to match yet — that's
Phase 3/4 work, not retrofitted early.

## Phase 0 — Decisions and unknowns — ✅ done

All decisions, and every place the original plan's assumptions didn't
survive contact with the real repos, are in
[`docs/phase0-decisions.md`](phase0-decisions.md). Highlights: the
compiler-base pin (`reinauer/container-amiga-gcc#4`), Copperline arm64
resolved to build-from-source, no ROM or vasm/vlink vendoring needed
(already covered elsewhere), and the harness/boot-config question
deliberately deferred to Phase 3/4.

## Phase 1 — sidick/amiga-dev — ✅ done

`ghcr.io/sidick/amiga-dev:v1.0.0` published, multi-arch (amd64 + arm64,
built natively on each), smoke-tested, cross-arch reproducibility gate
passing, build provenance attested. Contents: the pinned m68k-amigaos GCC
toolchain, `amitools[vamos]` (pinned), `mesa-vulkan-drivers`, and Copperline
(prebuilt AppImage on amd64, built from source on arm64).

Two real bugs found only by actually running the publish workflow in CI
(not caught by local validation): missing `packages:write` on the build
job, and a broken digest-extraction one-liner for the attestation step.
Both fixed in `main`.

Deferred: `harness/` package extraction (Task tracked separately) — the
plan's premise (a JSON-RPC client, boot-config helpers ready to lift out of
sana2loop) didn't match reality. See phase0-decisions.md's "Note for when
harness/ extraction resumes" for the concrete design guidance to use when
this picks back up in Phase 3/4 (floppy-boot + hostfs-data for KS2.0+ once
Copperline 0.14 ships, sana2loop carved out as the KS1.3 exception).

## Phase 2 — sidick/amiga-workflows — ✅ done

Three reusable workflows, extracted from real (not assumed) inline CI in
sana2loop and amiauth:

- `build-test.yml` — the verb contract, one job per verb. Validated
  end-to-end in real CI against a throwaway fixture repo
  (`sidick/amiga-workflows-fixture`) — all five jobs green.
- `docs.yml` — extracted unchanged; was byte-identical between sana2loop
  and amiauth already.
- `aminet-release.yml` — wraps `aminet-release-action` with the same
  gated-environment (required reviewer) convention both repos already used
  independently. Deliberately doesn't try to parse each repo's own
  version-file format — the calling repo resolves its own version and
  passes it in, same as amiga-dev's own publish.yml does.

`v1.0.0` tagged, floating `v1` live, `scripts/release.sh` is the only
sanctioned way to move it.

Deferred: `setup-real-rom` composite action — no repo uses a real-ROM
secret in CI today (every project's CI runs against Copperline's bundled
AROS only), so there's nothing yet to de-duplicate.

Known gap: only `build-test.yml` got a live CI run. `docs.yml` and
`aminet-release.yml` need more setup than a throwaway fixture warrants
(Pages config, a real gated-environment reviewer, a real dist artifact) —
their first live exercise will be Phase 3.

## Phase 3 — First consumer: sana2loop — next

The extraction source converts first — its CI is the newest and most
complete, so this phase is mostly deletion:

- Makefile aligned to the verb contract (mostly renames from `make amiga`/
  `make test-harness`/`make docker` to `build`/`test-host`/`test-target`/
  `dist`).
- `.github/workflows/ci.yml`, `docs.yml`, `release.yml` replaced by ~10-line
  callers into `sidick/amiga-workflows@v1`.
- This is the first real test of `docs.yml` and `aminet-release.yml` in
  anger, not just a fixture.
- Coverage parity checked deliberately: every test that ran before runs
  after (compare the job lists, not vibes) — sana2loop's current CI has
  more jobs than the verb contract's five (e.g. two separate
  copperline-smoke jobs, a semgrep job) — decide per Phase 4's own escape
  hatch principle whether each folds into a verb, becomes a workflow input,
  or stays a documented local step.
- Real-KS1.3 runs move to the optional `AMIGA_REAL_ROM_B64` secret /
  `AMIGA_REAL_ROM` env var `build-test.yml` already plumbs through.
- Harness extraction (deferred from Phase 1) can resume here now that
  there's a real second consumer's actual needs to design against, subject
  to the KS1.3-exception guidance in phase0-decisions.md.

*Exit: sana2loop green on `@v1` with strictly less YAML and no lost
coverage; a toolchain bump PR (image v1.0.0 → v1.0.1) merges clean as a
rehearsal.*

## Phase 4 — Second consumer: AmiAuth

The assumption-flusher: a shipped, security-sensitive repo with the most
distinctive CI (RFC vectors host-side, differential fuzz vs OpenSSL, vamos
vector runs, Copperline gui-smoke, Aminet release gate) and its own
path-based change-detection (`changes` job) sana2loop's CI doesn't have.

- Convert to the callers; every place the shared layer doesn't fit is
  treated as a finding: either the workflow gains a *general* input, the
  image gains a dependency, or the repo keeps a documented local step. No
  project-specific clauses in shared code.
- `differential` (fuzz vs OpenSSL) and `catalog-lint` have no equivalent in
  the five-verb contract or in sana2loop — decide whether they fold into
  `lint`/`test-host` generically or stay local.
- Note: amiauth's current CI pins Copperline from a different source
  (`LinuxJedi/Copperline`, an old pre-transfer URL) and a different version
  (0.11.0) than sana2loop (`CopperlineHQ/Copperline` 0.13.0) — converting
  to `build-test.yml` fixes this divergence for free, since both then use
  whatever amiga-dev's image bundles.

*Exit: AmiAuth green on `@v1`; the shared layer's changelog shows what the
second consumer taught it.*

## Phase 5 — The rest of the actives (rolling, low urgency)

- **AmiRFB** next (in-flight project, biggest matrix, currently has no
  `.github/workflows` at all — confirmed in Phase 0's survey). Conversion
  is mechanical by this point: verbs, caller, delete.
- **Renovate (or Dependabot) config** added portfolio-wide so image-tag and
  workflow-ref bumps arrive as automatic PRs.

*Exit: no active repo carries bespoke build/test YAML beyond its caller
file and documented local steps.*

## Phase 6 — Template repo

`sidick/template-amiga-project`, marked as a GitHub template: verb-contract
Makefile skeleton, the three caller workflows, docs scaffold, CLAUDE.md
conventions, licence, Renovate config. Deliberately last — written after
two real consumers prove the shape, not before.

*Exit: a new project reaches green CI from "Use this template" in under an
hour.*

## Risks (updated from the original plan)

- **Debugging indirection:** a red build now has three suspects (code, verb
  contract, pinned toolchain). Mitigated by immutable `vX.Y.Z` tags for
  bisection.
- **Special per-repo needs vs shared purity:** the escape hatch is a
  repo keeping its own extra job/step rather than bending the shared layer
  — already exercised once (differential/catalog-lint are the first real
  candidates in Phase 4).
- **PR #4 limbo:** the submodule pin works indefinitely from the branch
  commit `7f39626c0b6c8d71400f5e4112978007c62b1344`; only cost is tracking
  upstream fixes manually.
- **Image size:** watched in the publish smoke test; currently ~7.5GB
  content size for the tool layer.
- ~~**Runner availability**~~: resolved — arm64 is scoped to native Mac
  pulls plus building the arm64 image layer itself (in the now-public
  `amiga-dev` repo), not to any downstream project's CI, which stays
  amd64-only everywhere. See phase0-decisions.md's "Corrections to plan
  assumptions" section.

## Success criteria

- A new project's entire CI is the caller file (~10 lines) plus its
  Makefile. *(Proven mechanically true for build-test.yml via the fixture
  repo; not yet proven against a real project.)*
- One toolchain upgrade = one amiga-dev tag + N auto-raised, individually
  green PRs; no repo left behind silently. *(Renovate/Dependabot config is
  Phase 5.)*
- The cross-arch reproducibility gate has blocked zero releases (or,
  better, has blocked one and caught something real). *(Currently: zero,
  and it has run for real exactly once, on v1.0.0.)*
- `make test-target` on the MacBook and in CI run the same image, same ROM,
  same harness. *(True today for the fixture repo; the real test is Phase
  3.)*
- Six months on: no repo has re-grown bespoke CI YAML, and the shared layer
  has gained no project-named special cases.
