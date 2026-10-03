# Testing and measurement

Run `scripts/verify` for the current build, pure layout tests, and bundle metadata lint. Run `scripts/package-app` to validate release compilation and ad-hoc app packaging. The app must be opened separately to validate its menu; compilation alone is not UI verification.

## Current automated coverage

Nested horizontal/vertical geometry, gap conservation, negative display origin, duplicate identity rejection, invalid bounds/ratios/gaps, and a sweep of split ratios. No AX mutation, desktop integration, or performance claim is covered by these tests.

## Planned fake-platform tests

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

These are planned tests; the four existing geometry cases do not cover them.
