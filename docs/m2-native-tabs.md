# M2.5: Read-only tab evidence and conservative exclusion

Source implemented with scoped owned native-AppKit tab and focused-handler acceptance. Scoped Finder/TextEdit production-reader coverage is also recorded; native frontend/menu delivery remains unvalidated. Window mutation remains disabled and the eligible production scope remains empty.

## Implemented evidence

Focused inspection now recognizes the public `AXTabGroup` role in the existing bounded `AXChildren` traversal. The report adds a content-free `tab-groups` count. A positive count produces `tabGroupPresent` in the pure eligibility assessment, including when later reads fail, encounter a cycle, exhaust the budget, or are cancelled. The projected control observation remains ineligible and the simulated Tile request rejects it.

This deliberately excludes any observed tab group, including application content tabs. The AX role does not prove that a group represents native window tabs. Radio buttons alone are not interpreted as tabs. No tab labels, selected values, titles, document paths, or `AXTabs` contents are requested. Recognition adds no IPC calls and uses the existing dedicated worker, 64-node/six-level bounds, per-handle timeouts, cancellation checks, and shared structural budget.

Zero groups, unsupported branches, and even complete samples never clear `nativeTabSafety`. Tabs may be omitted, represented differently, hidden deeper than the traversal bounds, or change between reads. A single tab can retain a tab bar. App names, matching geometry, and user declarations cannot establish absence. Sampled positive evidence establishes an exclusion; sampled absence establishes no eligible scope. Historical token mismatch continues to exclude with `tokenChanged`, without inferring that a tab transition caused the mismatch.

Desktop visibility and nested-dialog lifecycle safety remain unproven. The two external displays with the laptop lid closed are the user's current test environment, not a validated mutation scope. This task does not validate mixed-scale geometry, hotplug, sleep/wake, or window writes in that arrangement.

## Owned fixture

Package with `scripts/package-app` and `scripts/package-ax-fixture`. Launch the owned fixture with `--focused-probe --nested-probe --tab-probe` and retain stdin. Only tab mode makes its ordinary window resizable and enables an explicitly constructed native AppKit tab group. Commands modify only this disposable app:

- `native-tabs-open`: create a second owned window and join it with public `addTabbedWindow`.
- `native-tabs-first` and `native-tabs-second`: select the corresponding owned tab.
- `native-tabs-close`: close the second owned tab and return to the first.
- `tree-tab-group` and `tree-tab-group-cycle`: synthetic positive role samples, with the latter incomplete through a repeated child link.
- `close-sheet`: clear a synthetic tree before returning to native-tab scenarios.
- `quit` or stdin EOF: exit the fixture.

Native-tab commands reject an active synthetic tree or sheet. Ground-truth `native-tabs-count` events use the owned `NSWindowTabGroup` only; production cannot consult another application's AppKit windows. Native mode and synthetic structural samples must be recorded separately.

## Acceptance

Unit checks cover multiple tab groups, radio-button non-detection, retained findings after cycle/unsupported/budget outcomes, undetected groups beyond a depth limit, and simulated control rejection for complete/incomplete positive evidence. Existing absence and identity tests retain unknown requirements and same-bounds token rejection.

Separate live checks must record OS/build, effective bundle trust, user-described display setup, and native ground-truth tab count alongside each focused report:

1. Baseline ordinary owned window, then native tab creation, first/second tab selection, and second-tab closure. Record exposed groups, completeness, and token changes without interpreting absence as safety.
2. Synthetic tab group and cyclic group: verify positive exclusion in complete/incomplete reports.
3. Ordinary focused handler and historical revalidation around tab switches: record rejected delivery or changed tokens explicitly; backend-only samples do not validate the foreground coordinator.
4. Finder and TextEdit native tabs separately, using disposable windows/documents without modifying existing user work. Broader native coverage is untested until these checks are recorded.
5. Pause/quit, permission and focus invalidation remain governed by the existing worker/coordinator guards. New tab lifecycle continuity is not inferred from earlier scoped nested-dialog checks.

Scoped owned native-tab exposure and token rejection are recorded in [validation](validation.md). [M2.6 now provides focused on-screen bounds evidence](m2-desktop-visibility.md), without clearing visibility. Next gate: same-app/same-size windows across native desktops and an enforceable supported scope. Native application frontend/menu delivery and mid-read tab transitions remain separate acceptance limits. The live coordinator and setters remain separate work after those gates.


## Scoped native acceptance — 2026-10-05

After refreshing the existing iTile bundle grant, LaunchServices startup reported effective trust. Two sequential owned-fixture runs exercised native AppKit tab creation/selection/closure and synthetic groups. Both apps exited normally after each run.

The native ordinary window reported zero groups; opening a second native tab reported one group and `tabGroupPresent` for both tab selections. Closing the second tab reported zero groups while retaining unknown tab safety. The normal focused handler retained the first token when adding a second tab, rejected historical comparison on switching to the second token, rejected subsequent revalidation without a fresh reference, and recovered on fresh inspection. Closing the second tab retired the previous identity; revalidation reported a mismatch, and a fresh read recovered as unknown. A synthetic cyclic group retained its positive exclusion with `outcomes=cycle`.

The focused reports observed two scale-1.0 displays, including an external display with negative x origin. The user described the laptop lid as closed. No physical lid/display transitions or mixed-scale arrangement were tested. Native ground truth came only from the owned fixture. These handler calls use the same methods as the menu but do not establish a new actual-menu delivery check. They do not validate generic application coverage or lifecycle continuity; Finder and TextEdit tab checks remain separate.


## Finder/TextEdit reader acceptance — 2026-10-06

A targeted temporary helper used the existing release production worker for Finder 27.0 (1865) and TextEdit 1.21 (419). Both exposed native tab groups and different tokens when selecting a second tab. Fresh inspection recovered the first token. Closing the second tab preserved the first token in both apps; this differs from the owned fixture and does not establish a universal identity rule.

TextEdit retained positive group evidence with one visible tab, then reported zero groups and unknown eligibility after hiding the tab bar. Finder samples reached the 64-node bound even in empty test folders: positive native groups remained excluded with `nodeLimit`, while zero-group samples remained unknown. No traversal bounds were raised.

An initial ordinary-handler attempt inspected another foreground app while CUA changed TextEdit in the background; those reports are discarded. Accepted results are reader-only and do not validate iTile's frontend/menu context or permission lifecycle. Temporary blank documents/window were closed, and both helpers exited. Exact samples, setup failure, versions, and limits are in [validation](validation.md).
