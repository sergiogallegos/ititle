# M2.23 — Bounded owned-fixture focus recovery

Status: fresh recovery captured through the foreground handlers. The earlier activation timeout was not reproduced; its cause remains unresolved. Native menu recovery and broader platform gates remain partial.

## Method and artifacts

On 2026-10-09, a temporary parent controller launched only iTile and its disposable fixture, using their existing fixed stdin protocols. It retained parent commands, fixture events, and app command acknowledgments with monotonic arrival times. Bounds: 2,048 trace events, five seconds per event wait, 60 explicit report polls per sample, at most three explicit activation attempts, and three seconds for each owned child's orderly exit. Both runs recovered on the first post-fault activation attempt.

The controller distinguished `activation-not-frontmost` from an absent event rather than waiting exclusively for confirmation. It awaited the fixture's `focused-read-end` before requesting recovery, preserved the discard report separately, and checked that the recovery worker sequence exceeded the baseline. Report protocol command acknowledgments were filtered from the second run's report text. These controller changes improve diagnostic attribution; they do not establish the cause of M2.22's timeout. The app's optional focused trace uses OSLog, not stdout; no OSLog export or client IPC timing result is claimed here.

The first run used M2.22's existing fixture artifact and recovered successfully at 17:43:52 UTC. The second rebuilt the fixture from current source using `scripts/package-ax-fixture`; release build and strict ad-hoc signature verification passed. Fixture executable SHA-256: `070e48ccc528c0d8d9d1278824376925429e8bd2ab3be962e75f10a2feaa3fde`. iTile remained the M2.22 release artifact, SHA-256 `bd8f2a7da660befa0b54b72064dc737daa3d8e5640eac835fc35fefadfe6a08a`. No Swift source behavior changed.

## Current-fixture result

OS macOS 27.0.1, build 26A434; two scale-1 displays. The fixture's own `desktop-status` reported its original window on the active Space, focused and frontmost, before both baseline and recovery. This owned-process ground truth is not available to production for arbitrary applications and does not clear visibility eligibility.

| Step | Observed result |
| --- | --- |
| Baseline, 17:44:31 UTC | app-1/window-1, epoch 0, sequence 1; historical provenance accepted, freshness unmeasured |
| Armed focused-accessor fault | `focused-read-begin`, `focused-read-hide`, then `focused-read-end` |
| Fault result | “Focus changed during inspection. Result discarded; inspect again.” |
| Reactivation | `activation-requested`, then `activation-confirmed`; original window active/focused/frontmost |
| Fresh explicit inspection | app-1/window-2, epoch 1, sequence 3; owner request 5, activation revision 5, revocation generation 9; historical provenance accepted, freshness unmeasured |
| Geometry | Baseline and recovery both (200, 722, 420, 158) |
| Cleanup | Both owned children exited with status 0 |

Recovery acquisition interval: 227489.0750235417–227489.08833583334. Both observations retained unknown eligibility and all three unproven visibility/tab/dialog requirements. Display 0 usable height changed from 990 to 991 between reports; the environment epoch and token changed. The precise cause of the display-area notification is not attributed. Fresh recovery is accepted in this handler scope; old-token continuity is not claimed.

The earlier timeout remains a recorded failure with insufficient trace to identify its cause. Two successful runs do not establish repeatability under competing focus, Space changes, hotplug, or sleep. No permission refresh, user-window setter, display configuration change, or native menu click occurred. The normal read-only app was restored after cleanup.

## Next task

Make this recovery check reproducible as a checked-in, Apple-framework-only lab with strict report correlation, bounded event retention, distinct not-frontmost/deadline outcomes, and owned-child cleanup. Keep native menu acceptance separate and retain the empty production mutation scope. Latest source verification remains M2.21's 195 passing tests; this task changed documentation and packaged the existing fixture source only.

## M2.24 follow-up

The [checked-in recovery lab](focus-recovery-lab.md) now provides bounded capture, strict report correlation, distinct activation and invalidation outcomes, and owned-child cleanup. Its observed result is scoped environment-invalidation recovery; focus-specific capture remains separate from the M2.23 observations.
