# Testing and measurement

Run `scripts/format` after Swift edits. Run `scripts/verify` for strict official swift-format lint, the current build (including P3 tools), core/platform tests, bundle metadata lint, and script syntax checks. The separate [P3 lab](p3-lab.md) is packaged with `scripts/package-p3-lab`; real measurements require running that app with its own explicit Accessibility permission. Run `scripts/package-app` to validate release compilation and ad-hoc app packaging. The app must be opened separately to validate its menu; compilation alone is not UI verification.

## Current automated coverage

The latest recorded source verification passed 195 tests (130 core, 65 platform), including pure control-model, focused evidence, preview projection, registry replacement/retirement, dedicated-worker scenarios, the isolated [M2.12 command/revocation simulation](m2-command-revocation.md), [M2.13 owner/model cleanup](m2-simulation-owner.md), [M2.14 shared simulation delivery](m2-shared-simulation-delivery.md), [M2.15 fake-worker readback](m2-fake-worker-readback.md), and [M2.16 same-app plans](m2-same-app-plans.md). Existing coverage includes nested geometry and gap conservation; invalid geometry and duplicate rejection; token retention/retirement and process generations; coordinate round trips; latency summaries; incomplete sheet evidence; dedicated worker ownership, isolation, bounded admission, stop and reuse; and fixture pipe short-message delivery/EOF. [M2.18 exhaustion checks](m2-counter-exhaustion.md) cover atomic token rejection, terminal model cleanup, and worker admission closure after snapshot exhaustion. See [validation](validation.md) for the run history. No AX mutation, desktop integration, or performance claim is covered by these tests.

Five M2.3 value tests cover retained unsupported-scope requirements, exclusions alongside missing evidence, unsupported/malformed reads, invalid geometry including edge overflow, and invalid observation intervals/sequences. Valid negative origins and zero-duration intervals remain projectable. See the [eligibility decision](decisions/0003-focused-eligibility.md).

The focused stopped-worker test additionally verifies opt-in trace start before backend entry, trace finish despite suppressed result delivery, and no execution trace for rejected requests. Real lifecycle timing requires the separately enabled [focused request trace](m2-focused-probe.md#opt-in-request-lifecycle-trace); fake-worker success does not prove permission or desktop event ordering on macOS.

## Planned fake-platform tests

[M2.1 control model and simulated admission](m2-control-model.md) now covers deterministic event interleavings. [M2.12](m2-command-revocation.md) adds isolated synchronized fake-operation admission. [M2.13](m2-simulation-owner.md) connects a manually driven simulation owner and matching model cleanup. [M2.14](m2-shared-simulation-delivery.md) adds shared simulation delivery and priority safety ingress. [M2.15](m2-fake-worker-readback.md) adds dedicated fake workers through readback and exact terminal acknowledgment. [M2.16](m2-same-app-plans.md) adds bounded same-app sequencing through exact readback and terminal acknowledgment. [M2.17 production adapter/eligibility review](m2-production-readiness.md) is complete as a documentation/source audit; real adapter wiring and setters remain separate work; focused read-only platform revalidation is implemented in source with [partial manual acceptance and remaining race checks](m2-focused-probe.md).

Record redacted events and replay them through the coordinator: create/destroy storms, stale generations, delayed writes, permission loss, PID reuse, observer failure, and app timeout. Check that destroyed windows receive no new writes, stale results cannot replace current state, pending work is bounded, and one failing app cannot stop another.

## Manual acceptance matrix

| Scenario | Required behavior |
| --- | --- |
| Launch without permission | Explain status; no prompt loop or mutation |
| App refuses size | Bounded attempts, then constrained/floating |
| Dialog or sheet appears | Remain usable; never tiled as a normal window |
| Window dragged manually | Yield; explicit re-tile resumes management |
| App freezes | Other apps and pause/quit remain responsive |
| Display disconnected | Invalidate plan, rediscover, avoid offscreen placement |
| Native desktop/fullscreen transition | Suspend and re-evaluate visibility |
| Sleep/wake | Rebuild stale observations before writing |
| Accessibility revoked | Stop control, expose degraded state |
| Event tap disabled or secure input | Do not swallow unrelated input; expose unavailable commands |
| Process crashes/restarts | Windows remain visible; no stale-ID replay |
| Mixed DPI and negative origins | Correct usable bounds without cumulative drift |

Use exact macOS build, hardware, app versions, monitor topology, and configuration in a test report. Do not publish titles or document paths.

## Performance protocol (not yet executed)

Release builds; 2, 10, and 20 windows; warm and cold runs; separate focus, resize, and lifecycle bursts. Report p50/p95/p99 internal planning time, AX request duration, observed completion, idle CPU, and memory trend. Run a controlled unresponsive-app case. A target of p95 <5 ms for internal planning excludes external app/WindowServer delay. Observe settled geometry as an approximation; it is not a measurement of physical display scanout.

## Second-pass acceptance additions

Before frame mutation, execute P1–P4 in [platform experiments](platform-experiments.md) and record real results. Test pause between two setters, stale completion after pause/epoch change, app termination/PID reuse, and overflow requiring reconciliation. Assert no new admissions after pause, not the impossible guarantee that an already admitted IPC call cannot finish.

Test ordered resize/focus/swap commands separately from coalesced absolute frame targets. Exercise finite bounds/depth limits, rounding, outer gaps, leaf removal, constraint rejection, and deterministic directional focus. Config tests must cover unknown fields/commands, normalized duplicate chords in the bindings list, malformed reload retention, and disabled keyboard defaults. Input tests cover balanced down/up handling and queue rejection passing events through.

Control state/admission interleavings are now covered by the M2.1 simulation tests. Platform write, input, configuration, and broader layout-policy tests remain planned. Neither these simulations nor the existing probe tests establish real write safety.

Bounded nested-dialog sampling has deterministic traversal and eligibility tests. Scoped live fixture/native-sheet checks are recorded; foreground and nested-read lifecycle checks remain separate and partial; see [M2.4 acceptance](m2-nested-dialogs.md). Unit success does not establish that application AX trees expose all dialogs or sheets.

## Planned delivery/admission checks

The [M2.10 contract](m2-delivery-admission.md) lists required pure-state and barrier-controlled fake-backend checks for retained receipts, exact acknowledgment, bounded shared draining, overload, and safety revocation. The read-only receipt/transport subset is implemented and verified in [M2.11](m2-read-only-delivery.md); semantic command/revocation and complete-plan admission are covered only by the M2.12–M2.16 simulation; their production wiring and live admission remain proposed. Real handler and setter acceptance remain separate.

## Proposed provenance acceptance

[M2.19](m2-evidence-provenance.md) specifies the next value-level tests for source mapping, unsupported coverage, enclosing intervals, explicit expiry boundaries, malformed/replayed/context-mismatched evidence, and unchanged unknown/ineligible projection. [M2.20](m2-evidence-values.md) implements eleven value tests covering these cases. [M2.21](m2-focused-provenance-report.md) wires historical focused report delivery and adds seven tests for scalar sequence acceptance, replacement isolation, formatting, shared revocation, and blocked preview. Rebuilt native menu delivery and measured freshness require separate acceptance. The latest 195-test source result does not establish eligibility.

## Scoped native provenance acceptance

[M2.22](m2-native-provenance-acceptance.md) records a rebuilt native inspection and blocked preview on two reported scale-1 displays, plus separate owned-fixture foreground-handler token/Pause/Resume/focus-loss checks. Native intermediate capture was incomplete and post-focus fixture reactivation missed its deadline. No broader recovery, app-specific eligibility, or performance acceptance is claimed. Source remains at the last 195-test verification.

## Foreground recovery lab

[The standalone Swift recovery lab](focus-recovery-lab.md) has an inert parser self-test included in verification and an explicit `--run` mode for packaged owned-process checks. Its focus and environment outcomes have separate acceptance scope; an incomplete capture or forced cleanup is not a pass. Native menu coverage remains separate.

## Owned-fixture snapshot lab

[The snapshot protocol and lab](m2-fixture-safety-snapshot.md) add five deterministic protocol tests included in `scripts/verify`. Its separately invoked owned-process run covers native tab/sheet/hide state and preservation of armed faults without AX calls. This does not validate cross-process identity or production safety coverage.

## Fixture AX identity experiment

[The opt-in identity lab](m2-fixture-ax-identity.md) brackets dedicated-thread AX identifier reads with fresh fixture snapshots. It records exact fixture run/window mapping, equal-frame peers, and selected-tab enumeration; two deterministic identity tests cover malformed/wrong-run/window values. Production eligibility and native menu coverage remain separate.

## Fixture lifecycle assessment

[Schema-2 lifecycle diagnostics](m2-fixture-lifecycle-assessment.md) add eleven deterministic tests for revision/registry authority, exact pair context, invalidation and synthetic expiry. The separate `--lifecycle-run` checks owned peer recreation, inactive-tab membership, stable pairs and tab/sheet reversal rejection. Native host Pause/trust/process/environment delivery remains separately unvalidated.

## Laboratory host event invalidation

[The host owner and monitor](m2-fixture-host-invalidation.md) add six deterministic tests for exact completion, immediate revocation, retained occupancy, fresh recovery, terminal attachments, failed-read replacement and exhaustion cleanup. `--host-run` separately exercises controller Pause, native activation, owned exit and sequential replacement recovery. Space/display/sleep and effective permission changes need separate native checks.

## Native host operator modes

[Bounded desktop and permission modes](m2-native-host-operator-checks.md) require recorded native Space/off-desktop state or effective reader-trust transitions. A first desktop attempt timed out; the scoped retry passed. The separate permission app records effective loss/restoration and fresh recovery under an explicitly approved temporary grant, which was removed afterward. Its earlier untrusted preflight alone is not permission-loss acceptance.

[M2.32's proposed timing collector](m2-fixture-timing-calibration.md) requires causal timestamp validation, independently attributable dispatch/delivery/assessment intervals, bounded terminal records including failures, and retained unfinished-worker occupancy. [M2.33](m2-fixture-timing-collector.md) implements eight timing tests and separate native delay/revocation/failure collection. Existing lifecycle tests cover synthetic expiry and policy change; no calibrated real age policy is selected.
