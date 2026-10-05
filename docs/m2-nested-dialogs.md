# M2.4: Bounded read-only nested-dialog evidence

Implemented source behavior with scoped owned-fixture and native TextEdit sheet observations; see [validation](validation.md). Foreground/menu and nested-read lifecycle acceptance remains partial. Window mutation remains disabled and the production eligibility scope remains empty.

Explicit focused inspection now samples the selected window's `AXChildren` graph on the existing dedicated application worker. It reads fixed role vocabulary and window subroles, child counts, and bounded child links. It never requests titles, values, document paths, text, or actions. The existing direct-sheet diagnostic remains available; application-wide inspection still uses that direct-only diagnostic.

## Bounds and outcomes

The pure `NestedDialogScanner` limits each sample to 64 unique elements including the root and six child-link levels (root depth zero). It requests no more child links than the remaining capacity, or one link at a boundary to distinguish a leaf. Repeated element identities, including shared graph links, conservatively record `cycle`. Child enumeration is count-checked; malformed or partial responses record `invalidType`.

The focused adapter gives this scan at most one second of scheduling budget, capped at four seconds after the overall request began, leaving time for final focus revalidation within the existing five-second request limit. It checks cancellation and uptime before each IPC and configures a 0.2-second messaging timeout on each examined handle. A synchronous call can finish after the scheduling deadline; this is not a hard wall-clock guarantee or cancellation of an in-flight call. Late overall requests are still discarded by the existing worker/request guards.

The content-free summary contains observed sheet/dialog counts, examined node count, and unique issue codes: `notScanned`, `unsupported`, `readFailure`, `invalidType`, `cycle`, `depthLimit`, `nodeLimit`, `budget`, and `cancelled`. Ordinary controls need only their role; `AXWindow` descendants also require a subrole to detect `AXDialog` and `AXSystemDialog`. An unsupported child-list accessor is incomplete, even if an application might use it for a leaf. Unknown reads do not prove absence.

A positive descendant sheet produces `sheetPresent`; a positive dialog role or subrole produces `dialogPresent`. Findings survive failures and limits on subsequent reads and exclude the focused parent even in incomplete scans. Sheets already found by the direct scan do not duplicate the exclusion. The root's classification remains handled by the existing eligibility assessment.

A complete sample describes only the examined graph at that time. Children can change between reads; hidden dialogs may be exposed through other relationships or omitted by an application's AX implementation. Completeness does not clear `nestedDialogSafety`, `nativeTabSafety`, or `currentDesktopVisibility`, supply lifecycle continuity, enroll a window, or permit a setter.

## Verification and separate manual acceptance

Deterministic core tests cover nested sheets, dialog subroles, unique counts, cycles/shared links, node/depth bounds, unsupported and malformed branches, unknown role reads, budget/cancellation, retained positive findings, and conservative eligibility projection.

Owned-fixture checks now cover positive findings, limits, cycles, budget, synchronized pause, and two-worker isolation. Native AppKit and TextEdit sheet samples are recorded. The targeted backend driver bypasses foreground delivery checks, so these are scoped reader observations. The complete acceptance checklist remains:

1. Inspect an ordinary owned fixture and record structural outcomes without assuming unsupported leaf attributes prove absence.
2. Expose a direct sheet, a sheet under an intermediate structural element, and a window descendant with a dialog/system-dialog subrole. Confirm positive parent exclusion and content-free reports. Record any fixture tree differences from real AppKit windows.
3. Exercise a wide/deep fixture graph and delayed child accessors. Confirm explicit limit/budget outcomes, responsiveness of another application worker, and pause discarding late results.
4. Close/change the sheet during inspection, switch focus, and revoke permission. Confirm existing stale-result and permission guards still reject invalid observations.
5. Check native AppKit sheets and representative application dialogs separately; report unsupported or absent relationships without claiming generic coverage. Confirm no window frame changes or keyboard capture.

Next: establish foreground/menu delivery and sheet-transition, focus-loss, and effective permission-loss behavior specifically during nested reads. Supported lifecycle evidence and tab/desktop visibility remain separate gates before any mutation integration.

## Reproducing explicit lab samples

Package with `scripts/package-app` and `scripts/package-ax-fixture`. Quit the ordinary iTile instance before starting the test driver. Run each executable with retained stdin/stdout (a local parent controller is required for subsecond race timing):

```sh
dist/iTile.app/Contents/MacOS/iTile --manual-probe --show-probe-report
"dist/iTile AX Fixture.app/Contents/MacOS/iTileAXFixture" --focused-probe --nested-probe
"dist/iTile AX Control Fixture.app/Contents/MacOS/iTileAXFixture" --focused-probe --nested-probe
```

The driver visibly identifies manual mode in its menu and emits `manual-ready trusted=true/false`. Fixed commands are `fixture`, `fixture-control`, `native-editor`, `inspect`, `revalidate`, `pause`, `resume`, `status`, `report`, and `quit`. The first three target only the corresponding fixed bundle identifiers and deliberately bypass foreground coordinator admission for read-only backend sampling. They clear historical references and do not populate a revalidation candidate. Never treat them as enrollment or future setter admission. `inspect` and `revalidate` use the existing foreground menu handlers. `status` performs the menu trust refresh. Wait for `manual-fixture-finished` or `manual-fixture-discarded` before requesting `report`; these marker names also apply to the native editor command. A busy/missing-target/blocked request has no backend completion marker, so a controller must bound its wait and inspect the visible report. `report` explicitly exports the redacted in-memory report to stdout; defaults still export nothing. EOF and `quit` terminate the driver and stop its workers.

The fixture accepts `tree-ordinary`, `tree-direct-sheet`, `tree-nested-sheet`, `tree-dialog`, `tree-system-dialog`, `tree-wide`, `tree-deep`, `tree-cycle`, `tree-budget`, `tree-focus-loss`, `tree-stall`, `native-sheet`, and `close-sheet` only with `--nested-probe`. Wait for the matching `*-ready` acknowledgment. Scenario changes close only its own native sheet and release old synthetic links. `activate` and `quit` retain their existing focused-fixture meanings. Tree faults emit fixed begin/end events; no content is logged. Use no other AX client on the armed fixture until a one-shot fault completes.

For a pause race, configure `tree-stall`, admit `fixture`, wait for `nested-stall-begin`, then send `pause` immediately. Require Pause and discard timestamps inside the known server interval, the paused report surviving recovery, and a fresh sample after `resume`. For two-worker isolation, admit `fixture-control` after the first worker's stall begins and require its healthy report before the delayed server's end event. Controllers must correlate fresh acknowledgments/completions and reject old queued reports; a timeout or stale report is an incomplete run.

The `native-editor` command inspects TextEdit's sampled focused element even when TextEdit is not foreground. Use an explicitly prepared blank document/sheet and cancel it afterward. It tests the AX reader, not app foreground delivery. Relaunch iTile without either flag when finished; stop both disposable fixtures. These lab commands do not change application or window mutation consent.

Permission tests must use the packaged app's LaunchServices context. A terminal-launched executable can report trusted while iTile's settings entry is off and is unsuitable evidence of effective bundle revocation. LaunchServices supports `open -W --stdin <private FIFO> --stdout <private report file> dist/iTile.app --args --manual-probe --show-probe-report`; the parent must hold the FIFO open, bound completion waits, and clean up on EOF/quit. Refresh only the same authorized bundle entry when an ad-hoc rebuild invalidates its grant. System authentication is performed by the user directly. The recorded LaunchServices check establishes untrusted-start blocking and fresh recovery, not mid-read revocation.
