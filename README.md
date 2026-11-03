# campus-deploy

Deployment glue for Campus services and apps, shipped as a
PEP 420 namespace portion under `campus/deploy` — `campus.deploy`,
the single module every Campus deployment uses for app creation and
the route conventions (`/health`, `/`, OpenAPI serving).

Part of the Campus distribution split ([nyjc-computing/campus#970](https://github.com/nyjc-computing/campus/issues/970)):
apps that only need deployment glue (e.g. nyxchange's
`is_codespace`/`configure_for_codespace`) install this wheel instead of
the full `campus-suite` monolith.

## Install

Release wheels are consumed as version-pinned URLs (Poetry):

```toml
campus-deploy = {url = "https://github.com/nyjc-computing/campus-deploy/releases/download/v0.1.0/campus_deploy-0.1.0-py3-none-any.whl"}
```

Dependencies: `flask`, `werkzeug`, and the
[campus-common](https://github.com/nyjc-computing/campus-common) wheel.

## Public interface (`campus.deploy.__all__`)

| Symbol | Purpose |
|---|---|
| `create_app(*appmodules)` | Single entrypoint for creating a deployment app |
| `AppModule` | Protocol: app modules implement `init_app(app)` |
| `build_spec_from_module(appmodule, *, version)` | AppModule → OpenAPI 3 spec glue ([#1029](https://github.com/nyjc-computing/campus/issues/1029)) |
| `register_health` / `register_generic_landing` / `register_openapi` | The `/health`, `/`, `/{prefix}/openapi.json` conventions ([#842](https://github.com/nyjc-computing/campus/issues/842)) |
| `configure_for_development` / `configure_for_deployment` | Environment-specific app configuration |
| `configure_for_codespace` / `is_codespace` | GitHub Codespaces support |
| `get_public_prefix` / `get_service_prefix` / `has_rule` | Routing helpers (PUBLIC_PREFIX, DEPLOY-derived prefix) |

## Layering (read before importing)

`campus.deploy` sits **above** the consumer layer; the legal import
direction is deployment glue importing the consumer layer, never the
reverse. Its service-facing imports are lazy provider seams resolved
from the co-installed portions — importing `campus.deploy` never
touches them:

- `create_app` lazily imports `campus.audit.middleware` (tracing) and
  `campus.config` (the suite's `SESSION_COOKIE_NAMES` settings).
- `build_spec_from_module` lazily imports `campus.flask_campus.openapi`.

Today those providers come from `campus-suite`; after the flask-campus
carve ([#993](https://github.com/nyjc-computing/campus/issues/993))
they come from the flask-campus wheel. Pure functions
(`is_codespace`, `configure_for_codespace`, the register/configure
route helpers) need neither.

## Versioning

Strict 0.x: **patch** releases (`0.x.Y`) are additive or fix-only —
downstream flows them in at the next relock; **minor** releases
(`0.Y.0`) are the breaking line. Every interface change ships with a
CHANGELOG entry, a manifest regen
(`scripts/generate_interface_manifest.py`), and the version bump the
diff dictates. The interface manifest is enforced in CI.

## Development

```bash
poetry install
poetry run python -m unittest discover -s tests -t . -v
poetry run ruff check .
poetry run python scripts/generate_interface_manifest.py --check
```

Releases: merge to `main` (ruleset-protected PRs), tag `vX.Y.Z`,
`poetry build`, attach `dist/campus_deploy-X.Y.Z-py3-none-any.whl` to
the GitHub release.
