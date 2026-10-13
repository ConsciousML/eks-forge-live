---
name: documentation-map-live
description: Map of every EKS Forge site page. Read before planning or implementing a change.
---

Read the map:
```bash
gh api repos/ConsciousML/eks-forge/contents/documentation-map.csv -H "Accept: application/vnd.github.raw"
```

One row per site page: `route`, `type`, `title`, `description`, and `source`.

Find the pages related to your task and read them first. A `source` containing
`eks-forge-live/` is a file of this repo. `route` is the page's path under
https://eks-forge.readthedocs.io/latest.
