# M2.24 — Reproducible foreground recovery lab

Status: checked-in Swift lab implemented; scoped environment-invalidation recovery observed. Focus-specific discard capture in this lab remains inconclusive. Earlier [M2.23 focus-specific recovery](m2-focus-recovery.md) remains separately recorded. Production mutation scope stays empty.

## Run

From the repository root, package the current source with `scripts/package-app` and `scripts/package-ax-fixture`. Quit existing iTile and fixture instances yourself; the lab refuses to replace them. Keep the desktop and focus undisturbed while it runs. The packaged iTile needs its existing Accessibility permission; the lab does not request permission or inspect another app directly.

```sh
xcrun swift -swift-version 6 scripts/focus-recovery-lab.swift --self-test
xcrun swift -swift-version 6 scripts/focus-recovery-lab.swift --run
```

The explicit `--run` mode launches the fixed packaged iTile and owned disposable fixture executables with parent-only stdin/stdout pipes. It exercises the same foreground handlers as the menu, not native menu clicks or the targeted backend driver. Only the fixture hides/unhides its own window. Existing user windows receive no setters. The normal app is not automatically reopened by the lab.

Output contains fixed protocol events, parent submission uptime, and redacted diagnostic reports. No transcript is saved automatically. Redirect stdout yourself if you want a record; the reports contain session tokens, geometry, and OS metadata, without window titles, keys, or document paths. GUI launch/permission behavior can depend on how the process is started; successful local execution is not universal LaunchServices acceptance.

## Acceptance and failure outcomes

The lab checks trust, fixture activation, and its own active-Space/focused-window ground truth before inspection. Its desktop-status command calls the fixture focused accessor, so it finishes this check **before arming** the one-shot fault. It then requires the fixture's focused-read begin/hide/end events, a conservative rejection report, reactivation, and a new explicitly submitted inspection. The recovery must retain unknown eligibility and all three unproven requirements, accepted historical provenance with unmeasured freshness, the baseline app token and frame, a greater owner request and worker sequence, and an acquisition start at or after the recovery submission. Rejected reads need not issue a sequence; a two-sequence gap is not required.

Two successful outcomes are deliberately distinct:

- `lab-scoped-focus-recovery-passed`: captured the focus-change discard and fresh recovery.
- `lab-scoped-environment-recovery-passed; focus-specific capture inconclusive`: captured desktop/display/sleep invalidation and fresh recovery after the owned fault. This is not acceptance of a focus-specific discard.

Either successful recovery plus orderly child exits returns status 0. Consumers must inspect the outcome string for the accepted scope. Unknown/overwritten reports, changed geometry, stale samples, permission failure, missing events, and forced cleanup return status 1 with `lab-incomplete`. `activation-not-frontmost` and an event deadline have different reasons. No automatic activation or inspection retry is performed.

Bounds: 30-second workflow deadline, five-second event deadlines, 60 report polls per sample, 2,048 received lines, 16 KiB partial-line/report bounds, and 128 lines per report. The first exhausted bound wins, so event limits can end a sample before its polling deadline. Nonblocking pipe reads use short waits on this standalone host thread. These workflow bounds are not hard deadlines for OS process-launch calls. At most two owned children exist. Cleanup sends Quit, closes input, waits three seconds per child, then uses termination and at most one second before killing only a still-running owned child; forced cleanup is incomplete. It never stops an existing app by bundle identifier.

`scripts/format` and `scripts/verify` include this script. Verification runs only `--self-test`, which opens no GUI and tests stale/request/time correlation, one-step sequence advancement, wrong app/geometry, duplicate fields, nonfinite time, and rejected provenance. It does not replace real-window checks.

## Local validation — 2026-10-09

Final formatting, compilation and `scripts/verify` passed: 195 existing core/platform tests plus the lab parser self-check. The existing-instance refusal returned status 1 without launching children. The real run used the M2.22 iTile artifact and M2.23 rebuilt fixture on macOS 27.0.1 build 26A434, with two reported scale-1 displays; exact hashes are recorded in [M2.23](m2-focus-recovery.md).

Baseline at 17:51:56 UTC: app-1/window-1, epoch 0, sequence 1, owner request 1. Owned focused-read begin/hide/end were observed. The captured rejection was desktop/display/sleep invalidation. Fresh recovery at 17:51:57 UTC: app-1/window-2, epoch 1, sequence 2, owner request 4, activation revision 5, revocation generation 9. Both frames were (200, 722, 420, 158); provenance accepted, freshness unmeasured, eligibility unknown. Both children exited normally. The normal read-only app was restored separately after the run.

Development failures were retained as incomplete: desktop-status initially consumed the armed fault; strict focus-only capture was overwritten by environment invalidation; an incorrect two-sequence-gap assumption rejected a valid recovery. The final lab corrects the arming order, distinguishes capture scope, and requires only greater sequence/request plus submission-time correlation. No production behavior was changed to accommodate the lab. The earlier M2.22 activation timeout cause remains unresolved, and no broad repeatability or native menu result is claimed.

Next: review supported-window evidence providers for the remaining desktop/tab/dialog safety gates before proposing any live tiling scope. This lab provides reproducible recovery diagnostics; it does not establish eligibility.

## Provider-review follow-up

[M2.25](m2-provider-feasibility.md) completes the safety-provider review and specifies a read-only owned-fixture snapshot as the next source experiment. No production scope was opened.
