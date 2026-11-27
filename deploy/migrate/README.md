# campus-migrate — break-glass production migration job

The dormant production service that runs Campus migrations out-of-band.
The **primary production migration surface is the campus-admin
Migrations view** (#1169); this job is break-glass: the service cannot
boot far enough to serve its own routes, ledger surgery, stamping /
baseline bootstrap, or the initial per-DB baselining. Runbook:
`docs/migration-protocol.md` (campus repo); trigger:
[`scripts/prod_migrate.sh`](../../scripts/prod_migrate.sh).

Invariants (prod-migration-ops epic campus#1172):

- created **explicitly** into the `production` environment — never by
  duplicating an environment (#1109 ghost hazard);
- **no domains**, no dependents (nothing references it → no cascade
  redeploy waves);
- **deploy triggers paused** (auto-deploy off): it runs ONLY when
  `scripts/prod_migrate.sh` triggers it;
- restart policy **off**; no healthcheck (it is a batch job — a
  migration failure exits nonzero → deployment CRASHED → visible);
- builds from the **`weekly` branch** of the campus repo via
  `Dockerfile.migrate` (railpack ignores start commands, #1131 — the
  entrypoint must be the image CMD), so it always carries the current
  `weekly`-tip migrations (migrations run BEFORE the release merge).

## One-time creation (superadmin)

1. Dashboard → `production` environment → **New service** (or
   `railway add`): name `campus-migrate`, source = GitHub repo
   `nyjc-computing/campus`, branch `weekly`.
2. Build: **Dockerfile**, path `Dockerfile.migrate` (NOT railpack).
3. Deploy triggers: **auto-deploy OFF** (pause; the script triggers
   explicitly).
4. Restart policy: off. Remove any default domain (there should be
   none).
5. Variables (Railway references resolve per environment):

   | Variable | Value |
   |---|---|
   | `MIGRATE_JOB_MODE` | `plan` (default; the script flips it per run) |
   | `MIGRATE_JOB_AUTH_POSTGRESDB_URI` | `${{auth-postgres.DATABASE_URL}}` |
   | `MIGRATE_JOB_API_POSTGRESDB_URI` | `${{api-postgres.DATABASE_URL}}` |
   | `MIGRATE_JOB_AUDIT_POSTGRESDB_URI` | `${{audit-postgres.DATABASE_URL}}` |
   | `MIGRATE_JOB_AUTH_MONGODB_URI` | `${{auth-mongodb.MONGODB_URI}}` (optional, for backfills) |
   | `MIGRATE_JOB_API_MONGODB_URI` | `${{api-mongodb.MONGODB_URI}}` (optional) |
   | `MIGRATE_JOB_AUDIT_MONGODB_URI` | `${{audit-mongodb.MONGODB_URI}}` (optional) |
   | `MIGRATION_BACKUP_BUCKET` | the backups bucket (durable envelopes, #1170) |

   > **Reference syntax gotcha (verified 2026-11-27):** the `${{<service>.<VAR>}}`
   > form only resolves when `<service>` has no dot in its name. The
   > 2026-11-19 service renames (`campus.auth-postgres`, `campus.auth-mongodb`,
   > …) broke every dotted example above — Railway stores the literal
   > reference string unresolved, so the job boots with an EMPTY URI and
   > crash-loops (observed: a one-off dbfix job got `len==0` from
   > `${{campus.auth-mongodb-dev.MONGODB_URI}}`; the campus.auth service
   > itself carries a literal `mongodb://…` URI for the same reason).
   > Paste the literal value from the source service's variables instead
   > (they rotate only on a coordinated DB-credential rotation).

   Credentials-before-first-boot rules apply (#1105): wire the DB
   references before the service's first deploy; verify connectivity
   with a temporary tcp-proxy if in doubt, then delete it.

## Run procedure

```bash
scripts/prod_migrate.sh plan              # read-only delta → review in logs
scripts/prod_migrate.sh apply             # apply every pending migration, all scopes
scripts/prod_migrate.sh apply 008         # staged window: apply up to 008 only
```

The script flips `MIGRATE_JOB_MODE` (skip-deploys), triggers the
deployment, polls for a NEW row (#1106 SKIPPED-trap recovery), and
tails the logs; exit code follows the job. Verify afterwards via the
ledger (the Migrations view, or `runner.py status` in any service
context) and the absence of the startup pending-WARNING on the next app
boots.
