#!/usr/bin/env bash
# Trigger the campus-migrate break-glass migration job in production and
# VERIFY it actually ran (#1106 trap: a deploy trigger can silently
# no-op while the stale row keeps "succeeding").
#
# Usage:
#   scripts/prod_migrate.sh plan|apply [UP_TO_REV] [timeout-seconds]
#
#   plan   run `runner.py status` per service scope — READ-ONLY; prints
#          the pending delta to the deploy logs (the approval artifact
#          a human reviews before apply).
#   apply  run `runner.py apply` per scope (auth → api → audit); pass
#          UP_TO_REV to stage a multi-window rollout.
#
# What it does:
#   1. sets MIGRATE_JOB_MODE (and MIGRATE_JOB_UP_TO) on the
#      campus-migrate service in production WITHOUT redeploying
#      (--skip-deploys),
#   2. triggers a fresh deployment (the service's deploy triggers are
#      paused — this script is the only trigger path),
#   3. polls until a NEW deployment row reaches SUCCESS — recovering
#      the SKIPPED trap (#1106) — then tails the job logs,
#   4. exits nonzero on CRASHED or timeout. A migration failure makes
#      the job exit nonzero → deployment CRASHED → this exits 1.
#
# PRODUCTION is superadmin-only with ONE ratified exception
# (docs/environment-access-policy.md, 2026-11-18 ruling): migration
# apply/abort/rollback for designated admins holding the per-service
# migrations grants. The primary production surface is the campus-admin
# Migrations view; this job is the BREAK-GLASS path (the service cannot
# boot far enough to serve its own routes, ledger surgery, stamping).
# Runbook: docs/migration-protocol.md in the campus repo.
#
# Requires: railway CLI logged in with an ACCOUNT token (project tokens
# are development-scoped and cannot see production). One-time service
# setup: deploy/migrate/README.md. Windows note: railway runs from bash
# directly; the inline python is JSON parsing only.

set -euo pipefail

MODE="${1:?usage: prod_migrate.sh plan|apply [UP_TO_REV] [timeout-seconds]}"
UP_TO="${2:-}"
TIMEOUT="${3:-900}"
POLL_INTERVAL=15
SVC="campus-migrate"
ENVIRONMENT="production"

case "$MODE" in
    plan|apply) ;;
    *) echo "usage: prod_migrate.sh plan|apply [UP_TO_REV] [timeout-seconds]" >&2; exit 2 ;;
esac
if [ -n "$UP_TO" ] && [ "$MODE" != "apply" ]; then
    echo "UP_TO_REV only applies with 'apply'" >&2
    exit 2
fi

echo "==> $SVC/$ENVIRONMENT: setting MIGRATE_JOB_MODE=$MODE ${UP_TO:+(up-to $UP_TO)} without redeploying"
railway variables -s "$SVC" -e "$ENVIRONMENT" --set "MIGRATE_JOB_MODE=$MODE" --skip-deploys >/dev/null
if [ -n "$UP_TO" ]; then
    railway variables -s "$SVC" -e "$ENVIRONMENT" --set "MIGRATE_JOB_UP_TO=$UP_TO" --skip-deploys >/dev/null
else
    # clear any stale bound from a previous staged apply — a leftover
    # UP_TO would silently cap this run
    railway variable delete MIGRATE_JOB_UP_TO -s "$SVC" -e "$ENVIRONMENT" >/dev/null 2>&1 || true
fi

# latest deployment row for one service: "<id>\t<createdAt>\t<status>"
# (empty when the service has never deployed). The service/env are
# passed to the inline python via `env` — a pipeline's `VAR=x cmd`
# prefix only applies to the first command.
snapshot_for() {
    railway status --json 2>/dev/null | env \
        RAILWAY_TARGET_ENV="$ENVIRONMENT" RAILWAY_TARGET_SVC="$SVC" \
        python -c '
import json, os, sys
data = json.load(sys.stdin)
for e in data["environments"]["edges"]:
    node = e["node"]
    if node["name"] != os.environ["RAILWAY_TARGET_ENV"]:
        continue
    for se in node["serviceInstances"]["edges"]:
        si = se["node"]
        if si.get("serviceName") == os.environ["RAILWAY_TARGET_SVC"]:
            ads = si.get("activeDeployments") or []
            if ads:
                a = ads[0]
                print("\t".join([a.get("id", ""), a.get("createdAt", ""),
                                 a.get("status", "")]))
            break
    break
'
}

echo "==> recording current deployment"
BEFORE=$(snapshot_for)
if [ -n "$BEFORE" ]; then
    echo "    active: $(echo "$BEFORE" | cut -f2) ($(echo "$BEFORE" | cut -f3))"
else
    echo "    none (service has never deployed)"
fi

echo "==> triggering job deploy (railway redeploy --from-source)"
railway redeploy --service "$SVC" --environment "$ENVIRONMENT" --yes --from-source

ELAPSED=0
RECOVERED=0
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
    CURRENT=$(snapshot_for || true)
    ID=$(echo "$CURRENT" | cut -f1)
    CREATED=$(echo "$CURRENT" | cut -f2)
    STATUS=$(echo "$CURRENT" | cut -f3)
    BEFORE_CREATED=$(echo "$BEFORE" | cut -f2)

    if [ -z "$CURRENT" ]; then
        echo "    [${ELAPSED}s] no deployment row yet"
        continue
    fi
    if [ -n "$BEFORE_CREATED" ] && [ "$CREATED" = "$BEFORE_CREATED" ]; then
        echo "    [${ELAPSED}s] still the old deployment ($STATUS) — no new row"
        continue
    fi

    case "$STATUS" in
        SKIPPED)
            if [ "$RECOVERED" -eq 0 ]; then
                RECOVERED=1
                echo "    [${ELAPSED}s] SKIPPED trap hit — recovering with a plain redeploy of the active deployment"
                if ! railway redeploy --service "$SVC" --environment "$ENVIRONMENT" --yes; then
                    echo "    recovery redeploy refused (no snapshot?) — retrying --from-source"
                    railway redeploy --service "$SVC" --environment "$ENVIRONMENT" --yes --from-source
                fi
                BEFORE="$CURRENT"   # wait for the NEXT row now
            else
                echo "    [${ELAPSED}s] SKIPPED again after recovery — manual intervention needed"
                exit 3
            fi
            ;;
        CRASHED|REMOVED)
            echo "==> job deployment $STATUS — a migration failed (or the job crashed)." >&2
            echo "    last logs:" >&2
            railway logs -s "$SVC" -e "$ENVIRONMENT" --lines 60 >&2 || true
            exit 1
            ;;
        SUCCESS)
            echo "==> job succeeded ($CREATED); last logs:"
            railway logs -s "$SVC" -e "$ENVIRONMENT" --lines 40 || true
            exit 0
            ;;
        *)
            echo "    [${ELAPSED}s] new deployment $STATUS ($CREATED)"
            ;;
    esac
done

echo "TIMEOUT after ${TIMEOUT}s: no new deployment row reached SUCCESS — the trigger is silently not happening. Check railway status." >&2
exit 2
