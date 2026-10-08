# Changelog

## Unreleased

- Initial extraction of the monitoring stack (Prometheus, Alertmanager,
  Loki + Alloy, Tempo, Grafana, cAdvisor, node-exporter) from
  `doconnect-api` / `fntec-api` into a parameterized template, plus
  `scripts/new-monitoring-stack.sh` to instantiate it.
- Added three GitHub Actions reusable workflows: `reusable-maven-build.yml`,
  `reusable-node-build.yml`, `reusable-docker-build-push.yml`.
- Added `reusable-promote-deploy.yml`: opens a version-bump PR in
  `genius-ops-delivery` instead of deploying over SSH (OPS-2, volet 2).
- Not yet tagged, not yet adopted by any project — see README "Rollout".
