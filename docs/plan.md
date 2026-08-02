# Plan: Shared Toolchain & CI Infrastructure (amiga-dev / amiga-workflows)

**Status:** Phases 0–4 complete. Phase 5 (AmiRFB + the rest) next.
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

## Phase 3 — First consumer: sana2loop — ✅ done

Converted for real, not just planned — `ci.yml`/`docs.yml`/`release.yml` are
now callers into `sidick/amiga-workflows@v1`, real CI is green
(`build`/`test-host`/`test-target`/`lint`/`docs-build` all passing on
`main`). Several places the original plan's assumptions didn't survive
contact with the real repo or the shared workflows' actual behavior:

- **Makefile: aliases, not renames.** The plan assumed renaming `make
  amiga`/`make test-harness`/`make docker` outright. In practice
  README.md, CLAUDE.md, and userdocs/Building-and-Testing.md all document
  those names already — renaming would have meant rewriting user-facing
  docs as part of a CI-plumbing change. The five verb-contract targets
  (`build`/`test-host`/`test-target`/`lint`/`dist`) were added as thin
  wrappers around the existing targets instead.
- **Coverage mapping, decided per-job:** `resolve-image` job is gone (the
  pinned toolchain is amiga-dev's own versioned image now, not a
  per-repo digest). The two `copperline-smoke-*-aros` jobs fold into one
  sequential `make test-target` (same two Copperline boot sessions, one
  job instead of two — build-test.yml's jobs don't share artifacts, so
  each verb job that needs binaries builds them itself, a real
  wall-clock/compute cost of standardizing that's worth knowing about
  going into Phase 4). `semgrep` folds into `make lint`. `docs-build`
  (strict MkDocs + AmigaGuide check) stays a **local** job in `ci.yml` by
  deliberate choice — doesn't fit any of the five verbs, and
  `build-test.yml` has no hook for an extra per-project job.
- **Real-ROM secret is structurally unusable, not just unused.** The
  original plan text here said real-KS1.3 runs would "move to" the
  optional `AMIGA_REAL_ROM_B64` secret. Checked sana2loop's own CLAUDE.md
  ("Why the real-1.3 ROM stays out of CI"): GitHub Actions secrets cap at
  48 KB; a real Kickstart 1.3 ROM dump is 256–512 KB. The secret mechanism
  physically cannot hold a real ROM. Real-KS1.3 validation stays a
  local/manual step (`make copperline-smoke KICK=...`) as sana2loop
  already documented — this isn't a Phase 3 gap, the plan's assumption was
  just wrong.
- **Two real bugs, both caught by an actual CI run, not review:**
  1. A reusable workflow's own `permissions:` block can only narrow, never
     widen, what the *calling* job already has. `docs.yml` and
     `aminet-release.yml` each declare `contents: write` internally (for
     `mike deploy --push` and `gh release create`), but the caller has to
     grant it too or it silently gets capped down. Added explicitly to
     sana2loop's `docs.yml`/`release.yml` callers — this applies to every
     future conversion that calls either workflow, not just sana2loop.
  2. `BUILD := build` in sana2loop's Makefile meant `$(BUILD)` was
     literally the identifier `build` — the pre-existing `$(BUILD):`
     directory-creation rule collided with the new verb-contract `build:`
     target, and Make silently merged their prerequisites. `make guide`'s
     order-only `| $(BUILD)` dependency ended up triggering the full m68k
     cross-build, breaking on `docs-build`'s plain runner (no
     `m68k-amigaos-gcc`). Fixed by having `guide` `mkdir` its own build
     dir, like every other target already did, instead of depending on a
     same-named target. Caught by the real CI run, not local validation —
     worth remembering that a green local Docker test doesn't fully
     stand in for the actual matrix of runners a workflow uses.
- **Also fixed in amiga-dev itself, surfaced by this phase:** the arm64
  tool-layer build purged `curl`/`git`/`ca-certificates` after building
  Copperline from source, while amd64 never did (nothing to purge there).
  `make dist`'s pinned `lha` fetch needs `git`, and that only worked on
  one architecture as a result — fixed so both arches keep them.
- Harness extraction (deferred from Phase 1) is **still** deferred — Phase
  3 didn't end up touching boot-config/harness code at all, just CI
  plumbing. Still parked for Phase 4, per the KS1.3-exception guidance in
  phase0-decisions.md.

Known gap: `docs.yml`'s permissions fix and the `release.yml` →
`aminet-release.yml` conversion are committed and actionlint-clean, but
haven't had a *live* tag-triggered run yet (no version tag was pushed this
session) — first real exercise of both is whenever sana2loop's next release
happens.

*Exit: sana2loop green on `@v1` — confirmed for real
(`build`/`test-host`/`test-target`/`lint`/`docs-build` all passing). Toolchain
bump rehearsal (image v1.0.0 → v1.0.1, Copperline 0.14.0 + build caching)
already happened earlier in this same session, ahead of Phase 3 itself.*

## Phase 4 — Second consumer: AmiAuth — ✅ done

The assumption-flusher, as planned: a shipped, security-sensitive repo with
the most distinctive CI of the two consumers so far, and the first with its
own path-based change-detection (`changes` job) skipping build/test jobs on
docs-only PRs — a mechanism sana2loop's CI never had.

- **Aliases, not renames — same call as Phase 3, bigger payoff.** The five
  verb-contract targets wrap the existing, already-documented ones
  (`test`/`cli`/`smoke`/`m68k`/`gui`/`copperline-smoke`/`check-catalog`/...).
- **The `changes` job stays local and feeds `build-test.yml`'s inputs
  directly** (`run-build: ${{ needs.changes.outputs.build == 'true' }}`,
  etc.) — no shared-workflow change needed, since those inputs are just
  booleans a caller sets. This preserves the skip-on-docs-only-PR behavior
  without any project-specific clause in the shared layer.
- **Coverage mapping:** `test-host` now covers what were two separate CI
  jobs — RFC vector tests + native CLI + e2e CLI smoke, *and* the
  vamos-validated m68k asm crypto tests — because "vectors, portable core,
  vamos runs" is the verb contract's own definition of `test-host`, and
  that job already runs inside the amiga-dev image (has `cc`,
  `m68k-amigaos-gcc`, and `vamos` all at once, so no more need for the old
  `asm-tests-docker`'s nested-container indirection). `test-target` matches
  today's `copperline-smoke` exactly (RFC 4226 HOTP core on real m68k) —
  deliberately **not** `gui-smoke`/`qr-onhw-smoke`/`arexx-onhw-smoke`/
  `catalog-onhw-smoke`, none of which actually run in CI today (they're
  dev-only Copperline checks needing more local setup than a fresh
  checkout provides) — coverage parity means matching what CI does today,
  not opportunistically wiring in more while in the neighborhood.
  `check-catalog` folds into `make lint` (the only static check this repo
  has). `differential` (opt-in OpenSSL fuzz) and `docs-build` stay separate
  local jobs, same shape as sana2loop's `docs-build`.
- Confirmed for free: amiauth's CI was pinning Copperline from a different
  source (`LinuxJedi/Copperline`, pre-transfer) and version (0.11.0) than
  sana2loop. Converting to `build-test.yml` fixes this divergence
  automatically — both now use whatever amiga-dev's image bundles.
- **Three real bugs found, none guessable from the plan text:**
  1. Same `$(BUILD)`/`build:` collision as sana2loop's Phase 3 bug, but
     *fifteen* order-only prerequisites deep, not one — reproduced and
     confirmed empirically before fixing this time (not just inferred from
     Phase 3), since a target as basic as `make test` would otherwise have
     silently started requiring the m68k cross-compiler.
  2. `src/cli/main.c` needed `#define _POSIX_C_SOURCE 200809L` before its
     includes — `fileno()` compiled fine on a bare `ubuntu-latest` runner
     (old CI) but not inside amiga-dev's own image (new CI), whose glibc is
     stricter about POSIX symbol visibility under `-std=c99`. A real
     application-source fix, not just CI plumbing — flagged as such rather
     than folded in silently.
  3. **Branch protection required status checks reference job names
     directly** (`"m68k Amiga build"`, `"Host vector tests"`, ...) — none
     of which exist once those jobs run inside a called reusable workflow
     (they report as `"ci / build"`, `"ci / test-host"`, etc. instead).
     Left unfixed, every future PR would block forever on checks that never
     report again. Updated to the new names — verified against a *real* PR
     first (not assumed from Phase 3's fixture-repo precedent), confirming
     both the exact context strings and that a job skipped via
     `run-test-host: false` (nested inside the called workflow, not a
     top-level `if:` anymore) still reports "skipped" and still satisfies
     the required check the same way the old top-level `if:`-gated jobs
     did.
- A real, unrelated release in flight during this same conversion: a
  locally-committed, unpushed "bump to v1.1" commit rode along through the
  conversion PR (rebase, not cherry-pick, so nothing was dropped) — flagged
  explicitly before pushing anything to `main`, sequenced by explicit
  choice (convert first, tag v1.1 after) rather than assumed.

*Exit: AmiAuth green on `@v1`, confirmed for real — every job
(`build`/`test-host`/`test-target`/`lint`/`differential`/`docs-build`) passing
on a live PR (#117), branch protection updated and independently verified
against a second, genuinely docs-only PR (#118) that showed the shared
jobs skip and still satisfy required checks.*

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
  — exercised for real in Phase 4: `differential` stayed local (opt-in,
  project-specific), `catalog-lint` folded into `make lint` instead (the
  better fit, not a special case). Zero project-specific clauses added to
  the shared workflows themselves across both conversions so far.
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
  Makefile. *(Proven against two real projects now. sana2loop's `ci.yml` is
  3 jobs: the build-test.yml caller, plus one deliberately-local
  `docs-build` job that doesn't fit the verb contract. AmiAuth's is a bit
  larger — a local `changes` job feeding the caller's inputs, plus
  `docs-build` and `differential` — proving the pattern scales to a repo
  with real per-project CI structure, not just the simple case.)*
- One toolchain upgrade = one amiga-dev tag + N auto-raised, individually
  green PRs; no repo left behind silently. *(Renovate/Dependabot config is
  Phase 5.)*
- The cross-arch reproducibility gate has blocked zero releases (or,
  better, has blocked one and caught something real). *(Currently: zero,
  and it has run for real exactly twice, on v1.0.0 and v1.0.1.)*
- `make test-target` on the MacBook and in CI run the same image, same ROM,
  same harness. *(True for the fixture repo and now for sana2loop's real
  CI; real-Kickstart-1.3 itself stays local/manual by design, not a CI
  path — see Phase 3's "Real-ROM secret is structurally unusable" note.)*
- Six months on: no repo has re-grown bespoke CI YAML, and the shared layer
  has gained no project-named special cases.
