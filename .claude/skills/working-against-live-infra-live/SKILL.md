---
name: working-against-live-infra-live
description: Rules for running Terragrunt or Terratest against live AWS from this repo. Use before running any `terragrunt` or `go test` command, and whenever a goal needs resources applied, verified, or destroyed on live AWS.
---

## Apply infra through Terragrunt only

Never create, modify, or delete a resource with the `aws` CLI or the console. Terragrunt is the
only path from a file to a live resource here. A live edit outside Terraform state drifts or gets
reverted on the next apply.

Read-only `aws` CLI calls (`describe-*`, `get-*`, `list-*`) are fine, they don't touch state.

## Authenticate first

Check first with `aws sts get-caller-identity`. If it resolves, skip this step.

Otherwise, ask the user to authenticate. `aws configure` and any SSO login are interactive and may
touch credentials you shouldn't handle.

## Before any command

- Run `source .env` from the repo root. Stack generation reads required vars (e.g.
  `SLACK_BOT_TOKEN`) via `get_env`, and fails without them.
- `.terragrunt-stack/` is generated output, treat it as read-only.
- Verify against the live AWS state (`aws ... describe`, `get`), not against the plan output.

## Prod

Never run `apply` or `destroy` on `prod`. CD is the only path, it applies on merge to `main`.
`.claude/hooks/guard-prod.sh` blocks both.

`plan`, `output`, and read-only `aws` calls are fine.

When `prod` needs a manual command (a removed unit to destroy, a stuck state), give the user the
exact command and its directory.

## Staging

CI deploys to the same `staging`. Check that no run is in progress first. This prints nothing when
none is:
```bash
gh run list --workflow ci.yaml --status in_progress
```

Deploy and verify as in [`docs/deploy-to-staging.md`](../../../docs/deploy-to-staging.md).

Only destroy what this session applied, and **wait** for the user before destroying. Disconnect
from Tailscale first with `tailscale down`, as in
[Destroy the Infrastructure](../../../docs/deploy-to-staging.md#destroy-the-infrastructure).

## Bootstrap

CI and CD never apply `live/bootstrap/`. Some of its resources are shared by `staging` and `prod`,
so a mistake there reaches `prod` before any review.

Plan, report the plan, and **wait** for the user before applying, as in
[Edit the Bootstrap Configuration](../../../docs/edit-live-configuration.md#edit-the-bootstrap-configuration).

## Terratest

Follow [Run the Test on Staging](../../../tests/README.md#run-the-test-on-staging).

Never interrupt `TestStack`. A run stopped halfway never reaches its destroy, and leaves a
`staging` cluster and a state lock behind. Pipe it through `tee`, the log is all that's left of a
failed run.
