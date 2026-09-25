#!/usr/bin/env bash
# Instantiate the monitoring/ template into a target project.
#
# This copies files — it does not create a live dependency on ops-templates.
# Re-run it deliberately (against a newer tag of this repo) when you want to
# pull in template changes; nothing pulls them in automatically.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/new-monitoring-stack.sh <slug> <app-target> <dest-dir> [app-label] [db-container-regex]

  slug                 Short lowercase project identifier (e.g. "fntec",
                        "ecitoyen-api"). Used for container names and the
                        compose project name.
  app-target            host:port of the app's Actuator /actuator/prometheus
                        endpoint, reachable on the app's Docker network
                        (e.g. "fntec-api:8081"). The app must expose a
                        stable network alias with this name.
  dest-dir              Where to write the instantiated monitoring/ folder
                        (e.g. ../my-project/monitoring). Must not exist yet.
  app-label             Human label used in alert summaries.
                        Default: same as <slug>.
  db-container-regex    Regex matched against DB container names, for the
                        DbContainerDown alert (e.g. 'mysql-(prod|staging)').
                        Omit to drop that alert entirely (e.g. managed DB).

Example:
  scripts/new-monitoring-stack.sh myapp myapp-api:8081 \
      ../myapp/monitoring "MyApp API" 'postgres-(prod|staging)'
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

SLUG="$1"
APP_TARGET="$2"
DEST="$3"
APP_LABEL="${4:-$SLUG}"
DB_REGEX="${5:-}"
APP_JOB="$SLUG"

if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "slug must be lowercase alphanumeric/hyphen (got: $SLUG)" >&2
  exit 1
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/monitoring"

if [[ -e "$DEST" ]]; then
  echo "Refusing to overwrite existing path: $DEST" >&2
  exit 1
fi

# Escape backslash, & and the sed delimiter (|) so values containing regex
# metacharacters (e.g. a db-container-regex like 'postgres-(prod|staging)')
# survive as literal text in the replacement.
sed_escape() { printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'; }

cp -r "$SRC" "$DEST"

if [[ -n "$DB_REGEX" ]]; then
  find "$DEST" -type f -print0 | xargs -0 sed -i \
    "s|__DB_CONTAINER_REGEX__|$(sed_escape "$DB_REGEX")|g"
else
  # No DB container to watch (e.g. managed/external DB) — drop the block
  # rather than ship a placeholder regex that matches nothing meaningful.
  find "$DEST" -type f -print0 | xargs -0 sed -i \
    '/# BEGIN DB_DOWN_ALERT/,/# END DB_DOWN_ALERT/d'
fi

find "$DEST" -type f -print0 | xargs -0 sed -i \
  -e "s|__SLUG__|$(sed_escape "$SLUG")|g" \
  -e "s|__APP_JOB__|$(sed_escape "$APP_JOB")|g" \
  -e "s|__APP_TARGET__|$(sed_escape "$APP_TARGET")|g" \
  -e "s|__APP_LABEL__|$(sed_escape "$APP_LABEL")|g"

echo "Monitoring stack written to $DEST"
echo
echo "Next steps:"
echo "  1. cd $DEST && cp .env.monitoring.example .env.monitoring, then fill it in."
echo "  2. Make sure the app's own docker-compose.yml creates the network named"
echo "     in APP_NETWORK, and gives the app container a stable network alias"
echo "     matching '$APP_TARGET'."
echo "  3. docker compose --env-file .env.monitoring -f docker-compose.monitoring.yml up -d"
echo "  4. Commit $DEST to the project's repo (it's now that project's file, not ops-templates')."
