# genius-ops-templates

Reusable ops patterns shared across projects: a monitoring-stack template
and a handful of GitHub Actions reusable workflows. Extracted after the
Prometheus/Grafana/Loki/Tempo stack got hand-copied file-by-file from
`doconnect-api` into `fntec-api` — this repo is that copy, done once,
versioned, and meant to be reused deliberately rather than re-copied.

## Design choice: templates, not shared runtime

Nothing here runs by itself, and no project has a live dependency on this
repo at runtime:

- **`monitoring/`** is a template with `__PLACEHOLDER__` tokens. You run
  `scripts/new-monitoring-stack.sh` to copy it into a target project with
  the placeholders filled in. The result is that project's own file, from
  then on — edit it, commit it, diverge from the template if you need to.
  Re-run the script (against a newer tag of this repo) only when you
  deliberately want to pull in a template change.
- **`.github/workflows/`** are GitHub-native [reusable workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
  (`workflow_call`). A project's own workflow references one by tag
  (`uses: Genius-Docconnect/genius-ops-templates/.github/workflows/reusable-maven-build.yml@v1`)
  — GitHub resolves and runs it, no copying involved. This is the one place
  where projects *do* stay live-coupled to this repo, which is why versioning
  (see below) matters more here than for `monitoring/`.

This split is deliberate: a shared *runtime* stack (one compose file/module
literally shared across projects) was considered and rejected for now — it
would mean one bad change breaks every project's monitoring or CI at once.
Copy-and-pin is more work per adoption but keeps blast radius contained.
Revisit this if/when the pattern has proven stable across a few projects.

## Layout

```
monitoring/                    Monitoring stack template (Spring Boot / Micrometer apps)
  README.md                    How to instantiate it, what the app must expose
  docker-compose.monitoring.yml
  prometheus/ alertmanager/ alloy/ tempo/ loki/ grafana/
scripts/
  new-monitoring-stack.sh      Instantiates monitoring/ into a target project
.github/workflows/
  reusable-maven-build.yml     Spring Boot: checkout, JDK, mvn verify
  reusable-node-build.yml      Node: checkout, install, lint, typecheck, test
  reusable-docker-build-push.yml   Buildx + GHA cache + registry push
  reusable-promote-deploy.yml  Bump PR into genius-ops-delivery (replaces per-project SSH deploy jobs)
  reusable-version.yml         x.y.z version of a merge (main: middle digit +1; hotfix/X.Y: patch +1)
  reusable-release.yml         Retag unchanged images, push the vX.Y.Z tag, GitHub release with per-service changelog
```

## Quickstart

**Monitoring**, from inside this repo:

```bash
scripts/new-monitoring-stack.sh myapp myapp-api:8081 ../myapp/monitoring "MyApp API" 'postgres-(prod|staging)'
```

See `monitoring/README.md` for what the app needs to expose first, and what
to do with the result.

**CI**, from a project's own workflow file:

```yaml
jobs:
  build:
    uses: Genius-Docconnect/genius-ops-templates/.github/workflows/reusable-maven-build.yml@v1
    with:
      working-directory: .

  publish:
    needs: build
    uses: Genius-Docconnect/genius-ops-templates/.github/workflows/reusable-docker-build-push.yml@v1
    with:
      image: ghcr.io/fntec/fntecapi
      tags: staging,sha-${{ github.sha }}
    secrets:
      registry-username: ${{ github.actor }}
      registry-password: ${{ secrets.GITHUB_TOKEN }}
```

**Deploy**, after the images are pushed (tag by sha, never `latest`):

```yaml
  promote-staging:
    needs: publish
    uses: Genius-Docconnect/genius-ops-templates/.github/workflows/reusable-promote-deploy.yml@v1
    with:
      delivery-repo: Genius-Docconnect/genius-ops-delivery
      stack: staging/host-1/fntec
      images: ghcr.io/fntec/fntecapi=sha-${{ github.sha }}
      auto-merge: true
    secrets:
      delivery-token: ${{ secrets.OPS_DELIVERY_TOKEN }}
```

**Versions** (one `x.y.z` per merge, trunk-based; triggers: push on `main` and `hotfix/**`):

```yaml
jobs:
  version:
    uses: Genius-Docconnect/genius-ops-templates/.github/workflows/reusable-version.yml@v1
    with:
      first-version: 1.0.0
  # build: images tagged ${{ github.sha }} and ${{ needs.version.outputs.version }}
  release:
    needs: [version, build]
    uses: Genius-Docconnect/genius-ops-templates/.github/workflows/reusable-release.yml@v1
    permissions: { contents: read, packages: write, issues: write }
    with:
      app-name: FNTEC
      version: ${{ needs.version.outputs.version }}
      base: ${{ needs.version.outputs.base }}
      image-prefix: ghcr.io/fntec/
      services: '["fntecapi"]'
      built: '["fntecapi"]'
    secrets:
      release-token: ${{ secrets.RELEASE_TOKEN }}
```

Full reference: `docconnect-micro-api/.github/workflows/cicd.yml` (builds only the services changed
since the previous version). Rules: `genius-ops-delivery/decisions/2026-10-09-branches-versions-environnements.md`.

**Cross-org caveat**: the projects live in five GitHub orgs (Genius-Docconnect,
FNTEC, ecitoyen, eWorkPermit, GeniusTechnologies). A reusable workflow in a
*private* repo can only be called from the same org, so this repo has to be
public (it holds no secrets) for `uses:` to work everywhere.

Not tagged yet: `@v1` only resolves after the first release (see
VERSIONING.md). During the OPS-2 pilot, reference `@main` deliberately.

## Versioning

See [VERSIONING.md](VERSIONING.md). Short version: tag releases (`v1.0.0`
etc.), projects pin CI workflows to a major tag (`@v1`), and re-run the
monitoring script deliberately to pick up template changes — nothing is
pulled in automatically.

## Scope, on purpose

This is a first extraction, not a platform. It covers exactly the two
archetypes seen across the FNTEC/Docconnect/eCitoyen/eWorkPermit projects
(Spring Boot API + Node/React frontend) and exactly the piece that was
already being duplicated by hand (the monitoring stack). It does **not**
(yet) cover: app-level `docker-compose.yml` patterns (they vary more by
project — DB choice, ports — and weren't duplicated verbatim like monitoring
was) or a Node/frontend monitoring variant. Deployment is covered only by
`reusable-promote-deploy.yml`, which never touches a server: it opens a
version-bump PR in `genius-ops-delivery` (the runtime source of truth, one
folder per environment/host/app), and that repo's own CI deploys (OPS-2).
Add those when a second real instance of the duplication shows up, not
speculatively.

## Rollout

Nothing has been migrated onto this yet — it's freshly extracted from
`fntec-api`'s monitoring stack. Suggested order, one project at a time,
validating before moving to the next:

- [ ] `doconnect-api` — source of the original stack; re-point its
      `monitoring/` at a diff against this template to confirm nothing
      project-specific got lost in the extraction.
- [ ] `fntec-api` — already has the stack (hand-copied); diff against the
      template, adopt `scripts/new-monitoring-stack.sh` for the *next*
      update instead of hand-editing again.
- [ ] `ecitoyen-micro-api` — same Spring Boot / Actuator shape.
- [ ] eWorkPermit services (`auth-service`, `ew-permit-service`,
      `admin-permit-service`, `discovery-service`) — 4 services, biggest
      win if the pattern holds, but check first whether they're meant to
      share *one* monitoring stack (they likely run on the same host) rather
      than one per service.
- [ ] CI reusable workflows — pilot on one Spring Boot repo and one Node
      repo before asking every project to switch.
