# M2.43 — Delivered environment callback identity

**Status: source implemented and verified; no native collection was performed.** Implements [M2.42's source-only attribution scope](m2-fixture-ack-review.md). The laboratory monitor preserves the notification source in typed event values, and a schema-5 diagnostic reader/collector validates that attribution. An inert AppKit-name mapping check runs before permission/application setup. No native schema-5 collection mode is added.

[M2.44](m2-environment-source-review.md) reviews the attribution/bounds result and selects a separate one-shot live-child EOF experiment, now implemented in [M2.45](m2-fixture-output-eof.md). Its schema-6 native result records no host callbacks, so it supplies no additional native source-delivery acceptance for this source-only task.

## Implemented boundary

The Foundation-only `FixtureEnvironmentSource` has four closed cases. The laboratory adapter maps the actual registered Apple notification names to these values:

| Source | Notification | Event code |
| --- | --- | --- |
| nativeSpace | `NSWorkspace.activeSpaceDidChangeNotification` | nativeSpace |
| screenParameters | `NSApplication.didChangeScreenParametersNotification` | environment |
| willSleep | `NSWorkspace.willSleepNotification` | environment |
| didWake | `NSWorkspace.didWakeNotification` | environment |

All four still reduce to the existing environment invalidation. They retain the callback-handling monotonic timestamp and resulting host context; source identity does not change revocation, pending-work rejection, failure precedence or eligibility. The adapter shares its registration names and mapping with the inert check. Unknown names have no mapping. Human-readable laboratory events also include the closed source value; no notification payload is exported.

This records which callback the adapter handled. It supplies no physical onset clock, complete notification coverage, desktop membership proof or explanation of why the callback arrived. In particular, a screenParameters value would not prove physical hotplug. M2.41's historical shared environment event remains unattributed.

## Versioned diagnostics and historical compatibility

`FixtureTimingManifest` selects schema 5 only when its new `eventSources=environmentCallbacks` contract is explicitly supplied. Validity requires the existing one-shot acknowledgment-delay control configuration, including six-second delay, five-second response wait, fixed deadline/budgets and controlled setup failure. The contract is forbidden in schemas 2/3/4. Schema 5 uses a matching terminal version, schema-3 embedded first stop and schema-2 fixture snapshots. No source-bearing pair envelope or production provider is introduced.

Every schema-5 environment event requires a `source` matching its code. Other event codes must omit source. Activation direction/relation requirements remain independent: activation events require both fields, and other events reject them. Unknown, absent, explicit-null or mismatched source metadata cannot establish attribution. Validation occurs before internal normalization to the historical host replay. Exact host context, revocation and pending-request replay still apply. Nonfinite/regressing event clocks and events after the first stop are rejected.

Historical schema-2/3/4 readers reject added source/contract metadata; they never backfill a notification identity. The existing native modes still declare schema 3 or 4, and their timing sink explicitly omits source when serializing the monitor's in-memory events. Their clocks, context and activation metadata are preserved. A future source-bearing native mode requires a separate experiment declaration; the current CLI offers no such mode.

Schema-5 collector admission is disabled independently of replay. The fault/replay guards require zero attempts, pair records and occupancy, incomplete collection and unsuitable calibration. Timeout linkage, observed versus missing markers, partial setup, liveness and cleanup retain the schema-4 rules. Late callbacks, cleanup failure and an optimistic passed flag cannot replace the first stop, revive collection or make the control complete.

## Bounds

The existing reservation is retained, including newline bytes:

| Type | Count × cap | Bytes |
| --- | --- | --- |
| Declared pair capacity; no admission in this control | 28 × 6,144 | 172,032 |
| Host event | 128 × 512 | 65,536 |
| Setup | 14 × 512 | 7,168 |
| Manifest | 1 × 1,280 | 1,280 |
| Setup fault | 1 × 512 | 512 |
| Summary | 1 × 14,592 | 14,592 |
| First stop | 1 × 512 | 512 |
| Terminal | 1 × 512 | 512 |
| Total | At most 175 rows | **262,144** |

Tests encode all source-bearing event variants with full identity/context, maximal counters/pending request and a maximal finite clock, then check a conservative 32-character quoted clock placeholder. They also check the schema-5 manifest with maximal counters, 128-byte unescaped OS metadata, fixed contract and conservative clock placeholders. All fit the existing event/manifest caps. Existing schema-4 fault/setup/closure bounds remain applicable, and synthetic schema-5 rows and total overflow rejection are checked. Output is never truncated or given reserve from another row type.

## Deterministic and adapter verification

Eight new tests cover:

- All four source mappings to unchanged host invalidation, retained pending work and rejection after revocation.
- Synthetic schema-5 replay with all sources, activation metadata, timeout linkage and orderly/failed cleanup while retaining incomplete/unsuitable flags.
- Absent, unknown, null, mismatched and forbidden sources, plus activation metadata rejection.
- Manifest/terminal/contract mismatch, missing fault configuration, false completion/suitability and nonzero admission/occupancy claims.
- All eight retained schema-2/3/4 archives and rejection of added historical source/contract fields.
- Nonfinite/regressing/out-of-run/post-stop clocks and exact context/request/revocation replay.
- Collector protocol failure, first-stop preservation, closed output and no late admission/revival.
- Maximal encoded source/manifest values, every synthetic row cap and total byte/row overflow.

Synthetic records are constructed only in tests with a fixed test identity, synthetic OS label and placeholder hashes; no native file is rewritten or relabelled. Existing exact-input age-comparison tests preserve M2.39's hashes, five candidates and original flags/results.

The inert adapter command is:

```sh
.build/debug/iTileSafetySnapshotLab --self-check-environment-sources
```

It checks the actual registered notification names, all four mappings, an unknown name and an unrelated activation notification. It exits before constructing a monitor, sampling trust, initializing an application, posting notifications or launching a fixture. Its observed output is:

```json
{"kind":"environmentSourceSelfCheck","passed":true,"synthetic":true,"nativeCollection":false}
```

`scripts/verify` now runs this command after the Swift tests. `scripts/format` and final verification pass **275 tests** (130 core, 65 platform, 80 fixture diagnostics), plus the inert adapter check and existing parser/plist/shell checks. The final rerun used the approved unrestricted SwiftPM context after the manifest sandbox was blocked. Its debug lab/replayer SHA-256 is `47d2b8f5bb4b5489f38104eee715f1b3c85819fceec07dffc6d02426f6f0a8c1`. The retained M2.41 control, packaged fixture, three M2.39 inputs and comparison report hashes are unchanged. The rebuilt executable is a source-verification identity, not another native collection identity.

No new native callback, physical display/sleep action, AX watchdog, pipe/EOF fault or production mutation is accepted. The source task ends here; next is a review of the attribution/bounds result and selection of a separately declared failure experiment. Changes remain local; no commit or push was requested.
