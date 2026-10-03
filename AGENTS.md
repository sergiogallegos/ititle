# Working on iTile

Read README.md and docs/architecture.md before changing behavior.
- Use Swift and Apple frameworks only. No external packages, vendored libraries, private APIs, or code injection.
- Keep layout/state logic independent of AppKit and Accessibility objects.
- Keep blocking Accessibility calls off the main thread and Swift cooperative executor.
- Distinguish implemented behavior from proposed designs in documentation.
- Preserve user window control: explicit opt-in for window mutation; always provide pause and quit.
- Do not log window titles, typed keys, or document paths by default.
- Run scripts/verify for source changes. Real window integration requires separate manual checks.
- Study upstream concepts; do not copy upstream code without reviewing licensing and attribution.
