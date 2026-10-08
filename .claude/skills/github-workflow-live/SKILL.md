---
name: github-workflow-live
description: End-to-end process for a live change, from issue to branch, edit, PR, production plan review, and merge. Use when starting a change that needs an issue or a branch, or when asked to commit, push, open a PR, or merge.
---

# GitHub Workflow

Never hardcode a GitHub owner, this repo is forked. Run `gh` from the repo's directory so it infers
the repo from `origin`. Read the owner with `gh repo view --json owner -q .owner.login` when you
need a cross-repo reference (`<owner>/<repo>#<N>`).

Live only pins tags. A catalog or app of apps change is merged and tagged in its own repo before
this workflow starts.

## 1. Issue

Skip if the user gives an existing issue.
Search existing issue, if one exists skip too.

1. Read similar issues and match their title and body style:
   ```bash
   gh issue list --state all -L 10
   gh issue view <N>
   ```
2. Draft a minimal issue: a title, and a body of one or two sentences or a few bullets saying what is needed. No implementation detail the user didn't give.
3. **Wait** for the user to validate the draft. If they asked for an autonomous run, skip the wait.
4. Post it with `gh issue create --title "<title>" --body "<body>"` and report the link.

## 2. Branch

Kebab-case, never `/`.

```bash
git checkout main && git pull && git checkout -b <branch>
```

## 3. Implement

Pick every guide that fits, as in
[Update the Live Fork](../../../docs/release-a-change-to-production.md#update-the-live-fork):

- **Catalog bump**: the `version-bump-live` skill.
- **Live configuration**: [`docs/edit-live-configuration.md`](../../../docs/edit-live-configuration.md).
- **Infrastructure test**: [`tests/README.md`](../../../tests/README.md).

Make the same change in `staging` and `prod`. CI only tests `staging`. Mark a value that must
differ with a `# STAGING:` or `# PROD:` comment saying why.

**Wait** on any meaningful design decision. In an autonomous run, pick the option closest to
existing patterns and report it.

## 4. Test on Staging

**Wait**, even in an autonomous run: ask the user whether to deploy `staging` locally first, or
let CI's `run-terratest` be the test.

If local, follow the `working-against-live-infra-live` skill. Destroy what you applied before
opening the PR. CI deploys to the same `staging`.

## 5. Pull Request

1. Draft the PR:
   - Title: the main commit subject.
   - Body: `Closes #<issue>` when the issue is in this repo, otherwise
     `Part of <owner>/<repo>#<issue>`. Then one or two lines or bullets.
   - Labels: `run-terratest` by default. `skip-terratest` and `skip-cd` together when the change
     only touches docs, skills, or comments.
2. **Wait** for the user to validate the draft. If they asked for an autonomous run, skip the wait.
3. Commit and push with `git push -u origin <branch>`.
4. Open it with `gh pr create --title "<title>" --body "<body>" --label <label>` and report the
   link.

Labels go on the PR, never on the issue. CI fails without exactly one of `run-terratest` and
`skip-terratest`.

Never open it as a draft, CI fails on draft PRs.

## 6. Review the Production Plan

With `run-terratest`, CI takes around 1 hour. Watch it with `gh pr checks <N> --watch`.

With `skip-cd`, stop here. The merge applies nothing to `prod`, so there is no plan to read.

Each push posts a new **Production Plan Available** comment. Read the latest one and check its
**Commit** matches `git rev-parse --short HEAD`. Then download the plan from that run:
```bash
gh run download <run-id> -n terragrunt-prod-plan
```

Report every `Plan:` line of `prod-plan-output.html`, and each resource it destroys or replaces.
Never summarize a plan you haven't read.

## 7. Merge

**Wait** for the user's explicit go-ahead, always, even in an autonomous run and even with
`skip-cd`. A merge to `main` without `skip-cd` applies the plan to `prod`.

Never merge on a failed check, or on a plan from an older commit.

```bash
gh pr merge <N> --merge --subject "<PR title> #<N>" --body "" --delete-branch
git checkout main && git pull
```

Merge commit (not squash), subject `<PR title> #<N>`, empty body, head branch deleted.

## 8. After CD

Skip with `skip-cd`.

Follow [Check Prod](../../../docs/release-a-change-to-production.md#check-prod) and
[Clean Up After the Rollout](../../../docs/release-a-change-to-production.md#clean-up-after-the-rollout).

Never destroy a removed unit yourself. Tell the user which units need a manual destroy in `prod`.
