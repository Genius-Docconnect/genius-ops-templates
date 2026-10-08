# Versioning

Semver tags (`v1.2.3`), plus moving major tags (`v1`, `v2`) that always
point at the latest release in that major line — the same convention
GitHub itself recommends for actions.

## What counts as breaking (major)

- `monitoring/`: renaming/removing a `__PLACEHOLDER__` token, renaming or
  restructuring `new-monitoring-stack.sh`'s arguments, removing a compose
  service or changing a volume name in a way that isn't a clean upgrade.
- `.github/workflows/`: removing or renaming a `workflow_call` input,
  changing an input's meaning, removing an output.

## What's minor/patch

- Adding a new optional input with a sensible default.
- Adding an alert rule, a datasource, a dashboard provider.
- Bumping a pinned image tag (Prometheus, Grafana, etc.) that doesn't
  require config changes.
- Fixing a bug in the instantiation script or a workflow step.

## How projects consume this

- **CI workflows**: pin to the major tag (`@v1`). You get patch/minor
  fixes automatically on the next run; a major bump requires reading
  `CHANGELOG.md` and updating the `uses:` line deliberately.
- **Monitoring template**: there's no "pin" in the CI sense — the
  instantiation script copies files once. To pick up a change, re-run
  `scripts/new-monitoring-stack.sh` from the version of this repo you want
  and re-apply your project-specific edits (diff the two, don't blindly
  overwrite). Note the version you instantiated from somewhere in the
  target project (e.g. a comment at the top of `monitoring/README.md` or
  the commit message) so a future diff has a baseline.

## Releasing

1. Update `CHANGELOG.md`.
2. Tag: `git tag v1.2.3 && git push origin v1.2.3`.
3. Move the major tag: `git tag -f v1 v1.2.3 && git push -f origin v1`.
