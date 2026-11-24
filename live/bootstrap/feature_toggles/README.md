{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
### Feature Toggles
This pipeline makes CI and CD deploy the optional features you enabled. It adds a GitHub Actions variable to your live fork for each `FEATURE_<NAME>_ENABLED` set to `true` in your shell, and removes the variable of each one that isn't. CI and CD export these variables before running Terragrunt, so `staging` and `prod` deploy the same features.

Your `.env` file holds the same toggles as your catalog fork's, as described in the [`FEATURE_GPU_ENABLED`](/docs/reference/environment_variable/#feature_gpu_enabled) reference:
```bash
export FEATURE_GPU_ENABLED=true
```

From the root of your live fork, run:
```bash
source .env
cd live/bootstrap/feature_toggles
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

Then, list the GitHub Actions variables of your live fork:
```bash
gh variable list
```

You should see a `FEATURE_<NAME>_ENABLED` variable for each feature you enabled, and none for the others.

:::warning
Rerun this pipeline each time you enable or disable a feature. To disable a feature, rerun it first, then destroy the feature in `prod`, as described in [Edit the Live Configuration](/docs/iac/edit-live-configuration/).
:::
