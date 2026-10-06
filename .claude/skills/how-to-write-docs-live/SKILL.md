---
name: how-to-write-docs-live
description: Rules for writing or editing Markdown docs or inline code comments in this repo (README.md, docs/, comments). Use before writing or editing any doc or inline comment.
---

This repo defers to the catalog repo's
[`how-to-write-docs-catalog` skill](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/.claude/skills/how-to-write-docs-catalog/SKILL.md)
for source-of-truth guidance and house style rules. Read it before writing or editing any doc
here. It applies as written.

## Doc Types in This Repo

- **Layer-index** (what a whole directory of things is): `README.md`
- **Operational guide** (procedural, task-oriented): `docs/ci-cd.md`, `docs/add-a-staging-environment.md`,
  `docs/troubleshoot.md`, `docs/release-an-iac-change.md`
- **Config inventory** (file-by-file breakdown of the shared HCL files in the catalog and live):
  lives in the catalog repo, published at
  https://eks-forge.readthedocs.io/latest/docs/reference/hcl_configuration/
