# Monitoring stack template

Prometheus + Alertmanager (metrics and alerts), Loki + Alloy (logs), Tempo
(traces), Grafana (single UI over all three), cAdvisor + node-exporter
(containers and host). Extracted from `doconnect-api` (see its ADR-0001),
first reused as-is in `fntec-api`.

Targets **Spring Boot / Micrometer** apps specifically (Actuator
`/actuator/prometheus`, Hikari, OTLP tracing). A Node/frontend variant isn't
built yet — see the root README's rollout notes.

This is not a running stack: it's a template with `__PLACEHOLDER__` tokens.
You instantiate it into a target project with `scripts/new-monitoring-stack.sh`,
which copies it and fills in the placeholders. The result belongs to that
project — commit it there, edit it freely, it has no live link back here.

## What the app must expose

| Signal  | Where it comes from | Config |
|---------|---------------------|--------|
| Metrics | Actuator `/actuator/prometheus` on a dedicated management port (not published on the host) | `management.*` in `application.properties` |
| Traces  | Micrometer Tracing → OTLP → `http://tempo:4318/v1/traces` | `management.tracing.sampling.probability`, `OTLP_TRACING_ENDPOINT` |
| Logs    | stdout, JSON in staging/prod (with `traceId`/`spanId`), plain text elsewhere | `logback-spring.xml` |

The app's own `docker-compose.yml` must give the app container a **stable
network alias** (e.g. `myapp-api`) so `prometheus.yml` doesn't need to change
when the container name changes between environments — see `fntec-api`'s
`docker-compose.yml` for a worked example (`networks.<net>.aliases`).

## Instantiate

```bash
cd ops-templates
scripts/new-monitoring-stack.sh myapp myapp-api:8081 ../myapp/monitoring "MyApp API" 'postgres-(prod|staging)'
```

See `scripts/new-monitoring-stack.sh --help` for the full argument list
(the db-container-regex is optional — omit it for a managed/external DB).

Then, inside the target project:

```bash
cd monitoring
cp .env.monitoring.example .env.monitoring   # fill it in, never commit it
docker compose --env-file .env.monitoring -f docker-compose.monitoring.yml up -d
```

Grafana listens on `127.0.0.1:3000` of the server only:

```bash
ssh -L 3000:localhost:3000 <user>@<server>
# then open http://localhost:3000  (admin / GRAFANA_ADMIN_PASSWORD)
```

Prometheus, Loki, Tempo and Alertmanager are not published at all; explore
them through Grafana's Explore tab (datasources are provisioned).

## Useful queries (after instantiation)

- Errors in the last hour (Loki): `{container="myapp-api-prod"} | json | level="ERROR"`
- Every log line of one request: `{container="myapp-api-prod"} | json | traceId="<id>"`
  (or click the TraceID link on a log line to open the trace in Tempo)
- Request rate per endpoint (Prometheus):
  `sum by (uri) (rate(http_server_requests_seconds_count{job="myapp"}[5m]))`

## Dashboards

None provisioned out of the box. Quick start: Grafana → Dashboards → Import,
ID `4701` (JVM Micrometer) or `19004` (Spring Boot 3.x Statistics), datasource
Prometheus. Export any dashboard worth keeping as JSON into
`grafana/provisioning/dashboards/json/` in the target project (not here,
unless it's generic enough to belong in the template — see root README).

## Sizing

Memory limits add up to about 1.9 GB (Prometheus/Loki/Tempo 400 MB each,
Grafana 256 MB, Alertmanager/Alloy/cAdvisor 128 MB each, node-exporter 64 MB),
on top of the app and its DB. The stack must run on the same host as the app
(it joins its Docker network) — check the server has room before deploying.
Retention: 15 days metrics, 10 days logs, 5 days traces.

If several projects' monitoring stacks end up on the *same* host, container
names are already namespaced by slug so they won't collide — but you're then
paying ~1.9 GB per project. At that point, consider a single shared
Prometheus/Grafana/Loki/Tempo instance scraping all of them instead of one
stack per project (see root README, "Rollout" section) — a bigger change,
not something this script does for you.
