# M2.18 — Lifecycle counter exhaustion

Status: source implemented and automated checks passed. Production remains read-only.

## Behavior

[LifecycleCounter](../Sources/ITileCore/LifecycleCounter.swift) advances a fixed-width integer only when representable. It preserves the last value on failure; callers choose conservative terminal handling. No issuer wraps or resets to accept stale work.

- The app checks inspection request, activation revision, and application generation advancement. Exhaustion clears focused references, stops the preview and current workers, rejects resume/new inspection, and exposes a restart message while Quit remains available.
- The dedicated AX reader checks adapter identities, focus notifications, observation sequence, and registry revision. Exhaustion latches for that attachment, expires identities, discards the result even when exhaustion occurs during final registry publication, and closes mailbox admission. The existing receipt remains acknowledgeable; acknowledgment cannot reopen admission. Quit can stop the thread without waiting for external IPC.
- The token registry preflights all distinct new identities before replacing its set. An exhausted batch issues no partial tokens, clears tracked tokens, and permanently rejects further reconciliation. Ordinary invalidation does not reset the serial watermark or exhaustion latch.
- The pure model checks environment epoch, layout revision, and admission generation. Failure enters stopping, clears observations/desired/pending work, revokes admission, and reports `counterExhausted`. Exact bound/admitted flights remain available for terminal cleanup; mismatched receipts cannot free them or resume control. Safety-triggered exhaustion still applies with an invalid timestamp.
- The preview propagates model exhaustion as a terminal stopped state. Existing checked read-receipt, semantic-command, per-app stamp, and simulated-operation issuers remain in place.

A maximum identifier may be issued once. Exhaustion means a later advancement cannot be represented; it does not make an already issued maximum identifier reusable. Restart recovery requires a new session/process attachment, never resetting an active issuer.

Bounded scan counts and cursor/round-robin indexes are not session identity issuers; their existing finite bounds remain unchanged. No eligibility reason is cleared and no AX setters/actions are added.

## Verification and limits

`scripts/format` and `scripts/verify` passed 177 tests (112 core, 65 platform). Six new core tests cover final-value issuance, signed identity overflow, atomic registry rejection, irreversible retirement, epoch safety handling, revision rejection, and retained exact operation cleanup after admission exhaustion. One production-worker fake-backend test covers both report and focused reads exhausting during final registry publication, exact receipt acknowledgment, subsequent admission rejection, and actual thread teardown.

The initial test compilation caught an unsupported equality comparison on `ControlEvent`; the test now supplies explicit event/time pairs. A later sandboxed SwiftPM attempt was blocked by nested sandbox setup; final required verification passed outside that restriction. No real AX read, UI exhaustion experiment, window mutation, packaging, permission refresh, or display change was performed. Tests exercise boundary values directly; they do not attempt billions of events.

The follow-up [M2.19 contract](m2-evidence-provenance.md) now specifies read-only evidence provenance and expiry for a future narrowed provider, with explicit unsupported coverage and invalidation rules. Implementing such metadata must preserve [the empty production scope](decisions/0004-supported-scope.md); provider acceptance and live wiring remain separate requirements in [M2.17](m2-production-readiness.md).
