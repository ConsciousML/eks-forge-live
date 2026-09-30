---
name: version-bump-live
description: Bump version_catalog in the live staging and prod stack files and align live against the catalog at the new tag. Use when bumping the catalog version this repo depends on.
---

Follow [`docs/release-an-iac-change.md`](../../../docs/release-an-iac-change.md) for the steps.

On top of it:
- Do each section in order, top to bottom. Finish one section's changes before starting the next.
- Ask the user whether bootstrap should be checked this bump before reviewing `pipelines/bootstrap/`.
  Not every bump needs it.
- Never destroy a removed unit yourself. Tell the user which units need a manual destroy in `prod`.
- Align live's own docs with the catalog's equivalents at the new tag. Carry over content changes,
  but restate them through live's `# STAGING:` and `# PROD:` drifts rather than copying catalog
  prose verbatim, since live's docs describe live's stacks, not the dev pipeline.
