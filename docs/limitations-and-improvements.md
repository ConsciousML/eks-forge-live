{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
# Limitations & Improvements

EKS Forge's CI/CD is designed as a working solution for multi-environment IaC. This documentation will explain the limitations of its design, and how to improve it once you outgrow it.
For the full CI/CD flow, read the [CI/CD](/docs/ci-cd/) overview.

## One Writer per Environment

The core principle behind this design is that only one process writes to an environment at a time. When two runs write to the same environment, one run's plan goes stale as soon as the other applies, and the state stops matching what's on `main`.

Each environment follows it in its own way:
- `dev` is ephemeral, feature-scoped, and lives in the [catalog repository](https://github.com/ConsciousML/eks-forge-catalog).
- In the live repository, a single PR bumps `staging` and `prod` together. [Terratest](https://terratest.gruntwork.io/) tests the change on the shared `staging` environment, and runs are queued, so only one PR writes to it at a time.
- `prod` is written only by CD, after the prod plan is posted to the PR for review. Its applies are queued too.

## Why Ephemeral Staging

Terratest creates `staging` from scratch on each run, tests it, then destroys it. Each run starts clean, so `staging` gets the one-writer rule for free: there is no state shared between runs, no lock to manage, and no drift to reconcile.

It's also cheap: you pay for the `staging` cluster only while the tests run.

Every run also proves the whole stack can be rebuilt from scratch. If you ever lose an environment, you know the code can rebuild its infrastructure.

It trades coverage for simplicity: it catches most breakages, at the lowest cost to run and maintain.

## Limitations

The main gap is that `staging` only ever tests a fresh create. `prod` doesn't get rebuilt on each change: it gets a diff applied to its existing state. Resource replacements, addon upgrades, and other changes that only show up on existing infrastructure reach `prod` without ever being reproduced on `staging`.

Since `staging` is destroyed right after the tests, there is also no room for soak tests. Anything that needs to run for hours or days has no environment to run against before `prod`.

It's also slow. Each run builds a full EKS cluster before testing it, with a 90 minute timeout, and since runs are queued, a PR can wait behind others before its own run starts.

Finally, the plan reviewed on the PR isn't always the one applied to `prod`. CD plans again when the PR merges, and the live repository doesn't require PR branches to be up to date with `main` before merging. If another PR merged after yours was reviewed, `prod` applies a diff nobody reviewed.

```mermaid
---
title: A stale plan reaching prod
---
sequenceDiagram
    autonumber
    participant a as PR A
    participant b as PR B
    participant cd as CD
    participant prod
    a->>a: prod plan posted and reviewed
    b->>cd: Merges
    cd->>prod: Applies PR B
    a->>cd: Merges, not rebased on PR B
    cd->>prod: Plans again and applies
    Note over a,prod: The diff applied differs from the plan reviewed in step 1
```

## Signs You've Outgrown It

With the catalog and live split, you control how many features ship at once: a single version bump in the live repository can carry several catalog changes. For a small team, shipping one or two bumps a day keeps these limitations acceptable. You've outgrown this design when upgrade breakages start reaching `prod`, when you need tests that run for longer than a CI job, or when waiting on `staging` runs becomes the bottleneck of your delivery.

## Improvement: Persistent Staging

EKS Forge doesn't ship this. If you need it in your fork, here is the design we propose: keep `staging` running instead of rebuilding it on each run. The single live PR still bumps both environments, but PR CI only plans, and all applies move after the merge:

```text
on PR:
    plan staging
    plan prod

on merge to main:
    apply staging
    run tests on staging
    if tests pass:
        apply prod
    else:
        stop, prod is untouched, staging is left as the failed run applied it
        fix forward with a new PR
```

The one-writer rule still holds: only the pipeline running on `main` writes to `staging`, with runs queued, the same way CD alone writes to `prod` today.

### What It Solves

Since `staging` keeps its state, each merge applies a diff on existing infrastructure, the same diff `prod` gets right after. Resource replacements and addon upgrades are now reproduced on `staging` before they reach `prod`.

`staging` also stays up between merges, so soak tests have an environment to run against for as long as they need.

Runs get faster too: each one applies an incremental diff instead of building a full EKS cluster, so the queue clears sooner.

The stale plan is only partly solved. If `main` moved after review, the diff applied to `prod` is still unreviewed, but it has just been applied and tested on `staging` from the same commit. [Atlantis](#going-further-atlantis) closes that gap entirely.

### Tradeoffs

When a test fails on `staging`, `main` is ahead of `prod` until the fix merges. This gap is visible, since the failed run shows on `main`, and it's acceptable: `prod` never receives a change that failed its tests.

Persistent staging also loses the benefits of [ephemeral staging](#why-ephemeral-staging):
- You pay for the `staging` cluster 24/7, not only while tests run.
- Nothing proves the stack can still be rebuilt from scratch. A scheduled job that destroys and recreates `staging` brings that proof back.
- Each run no longer starts clean: `staging` can drift, and a manual change or a failed apply carries over to the next run.

## Going Further: Atlantis

If persistent staging isn't enough, for example when several teams ship to the same environments, or when you need a hard guarantee that `prod` applies exactly what was reviewed, consider [Atlantis](https://www.runatlantis.io/).

Atlantis runs plan and apply from PR comments, and applies before the merge instead of after. It can then merge the PR once every apply succeeds, with [automerging](https://www.runatlantis.io/docs/automerging).

It solves the stale plan: Atlantis applies the saved plan file, so the diff you reviewed is the diff that gets applied. Its `undiverged` [apply requirement](https://www.runatlantis.io/docs/command-requirements) also refuses an apply while the PR is behind `main`, so freshness is checked at apply time without requiring branches to be up to date before merging.

It also keeps one writer per environment with [locks](https://www.runatlantis.io/docs/locking): once a PR plans an environment, no other PR can plan it until the first one is merged or closed.

These guarantees come at a cost. Atlantis is a server you host and secure yourself, one that holds AWS credentials and receives GitHub webhooks. Running Terragrunt needs a [custom workflow](https://www.runatlantis.io/docs/custom-workflows) and a custom image, and Terratest has to be wired in as a workflow step.
