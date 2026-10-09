# M2.22 — Native provenance report acceptance

Status: acceptance audit complete with scoped native and same-handler results; remaining recovery/native coverage is partial. Production mutation scope remains empty.

## Build and environment

Packaged the current M2.21 source using `scripts/package-app`; release build and strict code-signature verification passed. Bundle version 0.0.1/1, identifier `local.itile.app`, arm64, ad-hoc signature, no TeamIdentifier. Executable SHA-256: `bd8f2a7da660befa0b54b72064dc737daa3d8e5640eac835fc35fefadfe6a08a`.

The old iTile process was stopped and the rebuilt bundle launched with the existing `--show-probe-report` entry point. No diagnostic age policy or new permission was configured. Successful real inspection establishes effective read access for this request; it does not establish future permission stability.

OS: macOS 27.0.1, build 26A434. The user previously described a closed laptop with two connected monitors. This report actually enumerates two logical displays, both scale 1.0:

| Display | Usable rectangle (logical points) |
| --- | --- |
| 0 | (0, 30, 1920, 991) |
| 1 | (-1920, 30, 1920, 1050) |

This validates enumeration for this snapshot, not hotplug, mixed scale, desktop membership, or live mutation in that topology.

## Native focused report — captured

The UI tool could attach to the report window but not the accessory app's status menu. The operator was asked to choose the native focused inspection and replied “done.” The report was read from iTile's native text view through the UI tool; this was not the targeted backend driver.

Requested `2026-10-09T17:03:41Z`; app-1/window-1, epoch 2, worker sequence 1. Source application identity/version remains to be confirmed: the sampled frame and positive tab group differ from the small disposable fixture baseline, so this record does not label the observation as fixture coverage.

- Frame: (0, 30, 1920, 987); ordinary AX window; minimized/fullscreen/modal false; position/size settable true.
- Direct sheets 0, scan complete. Nested sample: 39 nodes, one tab group, no sheets/dialogs, complete.
- One complete uncorrelated on-screen bounds candidate; no visibility proof.
- Destruction notification registered; sampled focus unchanged; no historical expected token requested.
- Eligibility ineligible, exclusion `tabGroupPresent`; all three desktop/tab/dialog safety requirements remain unproven.
- Acquisition interval 225327.38573–225327.42361225002 (0.03788225000607781 seconds). This is the enclosing non-atomic request interval, not a control-latency or stability guarantee.

The new provenance section was present and internally consistent:

| Requirement | Source / revision | Coverage | Sample |
| --- | --- | --- | --- |
| Current desktop visibility | uncorrelatedCGBounds / 1 | unsupportedRequirement | findings |
| Native-tab safety | boundedAXStructure / 1 | positiveExclusionOnly | findings |
| Nested-dialog safety | boundedAXStructure / 1 | positiveExclusionOnly | noFinding |

All rows used `enclosingRequest` attribution and no issues. Owner request 3, activation revision 5, revocation generation 8. Historical sample accepted with no rejection reasons; freshness explicitly unmeasured with no diagnostic age policy. The report retained the no-enrollment/no-mutation and report-focus warnings.

No setter/action implementation was found in `Sources` during this check. Actual source-window geometry comparison awaits a second native observation; the absence of setter source is not reported as an independent before/after measurement.

## Remaining checks

The initial native historical-token revalidation was requested from the same source but a desktop/display/sleep invalidation was observed instead of a captured matching sample. Follow-up results are recorded below. Record source identity/version if available without content harvesting. Keep new native results separate from fixed test-driver handler results.

A pre-existing disposable fixture bundle was also opened. Its version is 0.0.1 and executable SHA-256 `af46327b1777f9f5831ef03cf05799b3083dd40671b293e553700c370c7caeb8`. Its binary lacks the newer desktop-status command; no ground-truth desktop result was received or claimed. It is not the current rebuilt fixture, and this setup attempt does not establish fixture coverage.

Latest source verification remains M2.21's 195 passing tests. No source edits or new source verification are part of this acceptance run so far. No permission refresh, desktop/display reconfiguration, window setter, or keyboard interception was performed.

## Captured follow-up results

The operator performed the three requested menu actions without returning to chat between them. The timed capture missed the intermediate matched revalidation: that native result is not accepted from the operator's “done” alone. Re-arming captured the final **native blocked preview**, although the temporary file was initially named `fresh.txt`; it was preserved separately as `native-preview.txt` and is classified by its actual contents.

Native preview requested `2026-10-09T17:27:54Z`: app-1/window-1, epoch 0, sequence 3, frame (410, 48, 1486, 937). Nested scan 41 nodes with one positive tab group; eligibility ineligible, all three unknown requirements retained. Provenance accepted, freshness unmeasured; owner request 3, activation revision 10, revocation generation 13. The proposed frame (0, 30, 1920, 991) was rejected as `planRejected / invalidPlan`. The source app/version remains unconfirmed, so this is native frontend acceptance for an unnamed operator-selected source, not owned-fixture or representative-app eligibility coverage. The first report's differing frame is not treated as a before/after nonmovement measurement.

A local controller then launched the same release bundle with its existing `--manual-probe` driver and a pre-existing owned fixture. These are **same foreground-handler checks**, not native menu clicks and not the targeted `fixture` backend command. The parent waited for the fixture's own activation confirmation before issuing `inspect` or `revalidate` and exported only fixed redacted report data. Sampling/retries were bounded, and test children were stopped afterward.

| Handler check | Captured result |
| --- | --- |
| Fresh inspect, 17:35:12 UTC | app-1/window-1, epoch 0, sequence 1; unknown eligibility; provenance accepted, unmeasured |
| Historical revalidation | Same token, epoch 0, sequence 2; expected-token-match true; provenance accepted |
| Geometry across those two reads | Both (200, 722, 420, 158); no observed geometry change in this scoped pair |
| Pause and attempted inspect | Paused report retained; no new focused report produced |
| Resume followed by fresh inspect | app-1/window-2, epoch 2, sequence 3; new context, owner request 5 / activation 5 / revocation 12; provenance accepted and unmeasured |
| Controlled focus loss | Owned fixture's focused accessor hid its own app; captured “Focus changed during inspection. Result discarded; inspect again.” |
| Recovery after controlled focus loss | Not accepted: fixture activation-confirmation event was not received within the controller deadline |

The fixture ordinary samples exposed zero tab groups and retained unknown eligibility. This complements the positive tab exclusion in the unnamed native samples; neither outcome clears safety requirements. Resume did not revive the old token. Report display 0's usable height was 990 in the fixture handler run rather than 991 in the earlier native snapshots; no stable display-area or geometry tolerance guarantee is inferred from that difference.

Earlier controller attempts are also retained as limitations: one expected preview report did not arrive before the capture deadline; another Resume attempt was overwritten by the desktop/display/sleep invalidation message. A subsequent run captured fresh Resume successfully and the controlled focus-loss rejection, but its post-focus reactivation still failed. The cause of the missing activation confirmation is unresolved; it is not claimed to be a production recovery success or attributed to a particular OS event without tracing.

## Review outcome and next task

Scoped native provenance inspection and blocked preview are accepted. Same-handler token revalidation, unchanged owned-fixture geometry, Pause rejection, fresh Resume, and controlled focus-loss rejection are recorded. Native matched revalidation/Pause coverage and recovery after the controlled focus-loss case remain partial. This completes the acceptance **audit**, not all platform gates.

Next: diagnose the owned-fixture post-focus reactivation failure with bounded event tracing and separately capture fresh recovery, without widening eligibility. Avoid repeating already accepted checks unless that diagnosis changes source behavior. No source behavior was edited in M2.22; latest source verification remains 195 passing tests. Local documentation links and whitespace checks are run after this audit. No permission refresh, source-window setter, or display configuration change was made.

## M2.23 follow-up

[Bounded fixture tracing](m2-focus-recovery.md) subsequently captured fresh recovery with both the existing and rebuilt fixture artifacts. The earlier timeout was not reproduced; its cause remains unresolved. This adds scoped foreground-handler recovery evidence without completing native-menu or broader platform coverage.
