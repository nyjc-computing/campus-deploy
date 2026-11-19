# Changelog
## 0.2.0 — 2026-11-19

**BREAKING (environmental):** create_app's auth/api tracing setup imports
the middleware from its new home — `campus.flask_campus.audit.init_tracing`
(was `campus.audit.middleware.init_app`; audit-namespace reorg,
flask-campus#31 / campus-api-python v0.10.9). Requires flask-campus
>= v0.2.0. Consumers: campus-suite relocks both in the same wave;
nyxchange stays on campus-deploy v0.1.3 + flask-campus v0.1.x, which
remain compatible.


## 0.1.2 — 2026-11-17

Pin-only rebuild: campus-common v0.4.0 → v0.5.0
(from_exception static-message fix, campus#1128). No code changes
per the pin-rebuild contract.

## 0.1.1 — 2026-11-17

Pin-only rebuild: campus-common v0.3.1 → v0.4.0 (policy error-surface
scrubs, campus-common#8). No code changes — direct-URL deps bake the
pinned wheel URL into this distribution's metadata, so the bump
requires a rebuild here per the pin-rebuild contract.

## 0.1.0 — 2026-11-04

Initial release: `campus.deploy` carved verbatim from the campus
monorepo (campus#1042, part of the #970 distribution split). A
single-module PEP 420 namespace portion under `campus/` — no
`__init__.py`, no subpackage.

- `create_app`, the `AppModule` protocol, the `/health` + `/` +
  `/{prefix}/openapi.json` route conventions (#842, #1029), Codespaces
  and development/deployment configuration, and `build_spec_from_module`
  (the AppModule-to-spec glue that keeps `campus.flask_campus.openapi`
  a pure generator core, #993 carve boundary).
- Interface kit from day one: closed-world `__all__`, checked-in
  interface manifest, strict-0.x versioning (README/CHANGELOG).
- Carve adaptation: `campus.config` (suite-internal
  `SESSION_COOKIE_NAMES`) is now a lazy import inside `create_app` —
  importing `campus.deploy` itself never touches suite-internal
  modules; `campus.audit.middleware` and `campus.flask_campus.openapi`
  remain lazy provider seams (see README layering section).
