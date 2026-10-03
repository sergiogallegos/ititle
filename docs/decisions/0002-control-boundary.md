# ADR 0002: Conservative enrollment and bounded control

Status: accepted design, not implemented. Date: 2026-10-02.

## Context

The second pass found that automatic current-desktop discovery was assumed before proving AX/window-list correlation. It also found incomplete pause semantics, undefined command coalescing, and accessibility shortcut conflicts.

## Decision

1. Proceed with read-only experiments; do not start frame mutation until identity, enrollment, and worker behavior meet their gates.
2. M2 begins with explicit focused-window enrollment. Invalidate enrollment on desktop/display epoch changes. Bulk enrollment remains conditional on measured visibility coverage.
3. Use a serialized coordinator, per-application AX workers, and a separate bounded admission mailbox. Only immutable values cross the platform boundary.
4. Revoke write admission on pause, trust loss, sleep, or topology/desktop invalidation. An already admitted call may still complete; no rollback or cancellation guarantee is made.
5. Preserve ordered user commands; coalesce absolute pending frame targets and invalidation events only. Never silently discard a swap, toggle, or focus command.
6. Install no keyboard bindings by default. Offer an opt-in physical-key profile and validate normalized chord collisions. Menu controls remain usable when hotkeys fail.
7. Use strict, versioned JSON with bindings represented as a list. Do not build a custom JSON parser solely to reject duplicate object members.
8. Keep the first release paused at launch and without session restoration. Zero third-party dependencies and public-API constraints remain unchanged.

## Consequences

The first usable workflow takes explicit enrollment and provides less automation. It exposes platform limitations early and avoids making private window identity a hidden requirement. The design specifies failure behavior before adding complexity. See [control contracts](../control-contracts.md) and [experiments](../platform-experiments.md).
