# Testing and measurement

Run `scripts/format` after Swift edits. Run `scripts/verify` for strict official swift-format lint, the current build (including P3 tools), core/platform tests, bundle metadata lint, and script syntax checks. The separate [P3 lab](p3-lab.md) is packaged with `scripts/package-p3-lab`; real measurements require running that app with its own explicit Accessibility permission. Run `scripts/package-app` to validate release compilation and ad-hoc app packaging. The app must be opened separately to validate its menu; compilation alone is not UI verification.

## Current automated coverage

The latest recorded source verification passed 116 tests (91 core, 25 platform), including pure control-model, focused evidence, preview projection, registry replacement/retirement, and dedicated-worker scenarios. Existing coverage includes nested geometry and gap conservation; invalid geometry and duplicate rejection; token retention/retirement and process generations; coordinate round trips; latency summaries; incomplete sheet evidence; dedicated worker ownership, isolation, bounded admission, stop and reuse; and fixture pipe short-message delivery/EOF. See [validation](validation.md) for the run history. No AX mutation, desktop integration, or performance claim is covered by these tests.

Five M2.3 value tests cover retained unsupported-scope requirements, exclusions alongside missing evidence, unsupported/malformed reads, invalid geometry including edge overflow, and invalid observation intervals/sequences. Valid negative origins and zero-duration intervals remain projectable. See the [eligibility decision](decisions/0003-focused-eligibility.md).

The focused stopped-worker test additionally verifies opt-in trace start before backend entry, trace finish despite suppressed result delivery, and no execution trace for rejected requests. Real lifecycle timing requires the separately enabled [focused request trace](m2-focused-probe.md#opt-in-request-lifecycle-trace); fake-worker success does not prove permission or desktop event ordering on macOS.

## Planned fake-platform tests

[M2.1 control model and simulated admission](m2-control-model.md) now covers deterministic event interleavings. Actor integration, synchronized worker admission, and real setters remain separate work; focused read-only platform revalidation is implemented in source with [partial manual acceptance and remaining race checks](m2-focused-probe.md).

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

The [M2.10 contract](m2-delivery-admission.md) lists required pure-state and barrier-controlled fake-backend checks for retained receipts, exact acknowledgment, bounded shared draining, overload, and safety revocation. The read-only receipt/transport subset is implemented and verified in [M2.11](m2-read-only-delivery.md); the remaining semantic command/revocation and live admission requirements are proposed. Real handler and setter acceptance remain separate.
