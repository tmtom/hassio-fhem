# AGENTS.md

Guidance for AI agents (and humans) working on **hassio-fhem** — a Home
Assistant *app* (add-on) that runs FHEM 6.5 for eQ-3 MAX! radiator valves and
window contacts via a NanoCUL USB stick, bridged to Home Assistant over MQTT
(including MQTT discovery). Keep this file updated as knowledge changes.

## Repo map

- `fhem/` — the app: `config.yaml` (manifest), `Dockerfile`, `run.sh`
  (entrypoint wrapper), `README.md` (rendered on the app **Info** tab),
  `DOCS.md` (rendered on the **Documentation** tab — keep it short),
  `CHANGELOG.md` (shown in the update dialog — must be in the app folder,
  the Supervisor does not look at the repo root), `USER_GUIDE.md` (full
  reference, linked from GitHub), `translations/en.yaml`
  (Configuration-tab labels/hints), `apparmor.txt`, `rootfs/` (seed config
  template + vendored `99_myUtils.pm`).
- Root: `LICENSE` (MIT for our files), `AGENTS.md`, `repository.yaml`,
  `.github/workflows/` (CI).
- Public repo `tmtom/hassio-fhem`. Licensing: our files MIT; FHEM is GPL and
  redistributed via the official `fhem/fhem-minimal-docker` base image and the
  pinned fhem.de tarball; `99_myUtils.pm` is fhemMAX2HASS (AGPL-3.0, vendored).
- Supported arch: `amd64`, `aarch64`. Version scheme `0.x.y-fhem6.5`
  (embeds the pinned FHEM release).

## Architecture (read before changing anything)

- **Image**: `ghcr.io/fhem/fhem-minimal-docker:5.2.0-bookworm` (pinned;
  `5.5.1-bookworm` does not exist — see CHANGELOG). FHEM 6.5 is baked into the
  image as a frozen tree (`/usr/src/fhem-frozen`, `FHEM_SEEDED_VERSION`) and
  seeded into `/opt/fhem` on first start, so `/entry.sh` skips its unpinned svn
  export. `/entry.sh start` is the process supervisor (manifest `init: false`).
- **Persistence**: everything lives in the `app_config` map at `/opt/fhem`
  (host: `/addon_configs/<repo>_fhem`) and is included in HA backups.
  Uninstalling the app does **not** delete this folder (observed on HAOS
  2026-10-30) — a reinstall reattaches the old config; move the folder aside
  for a genuinely clean install. SIGTERM = FHEM `shutdown` → saves state
  (`log/fhem.save`) before exit, which is what makes `backup: cold` snapshots
  consistent. `backup_exclude` only `log/*.log` — **never** exclude
  `log/fhem.save` (the FHEM state file) or `FHEM/FhemUtils/uniqueID`
  (MQTT password keystore).
- **`run.sh`** (order matters): options via Perl `JSON::PP` (`opt()` helper);
  timezone (hidden `timezone` option → HA Core API `time_zone`, which is why
  `homeassistant_api: true` → UTC fallback); first-start seeding of the frozen
  tree + seed config (with `fhem.cfg.bak` restore safety net and md5
  fingerprint logging — the config-loss forensics); auto-append
  `include web-auth.cfg` to `fhem.cfg` when missing;
  generate `mqtt-connection.cfg` (Supervisor `/services/mqtt` with `mqtt:want`,
  manual `mqtt_*` fallback) and `web-auth.cfg`; install vendored
  `99_myUtils.pm` (marker-guarded, `{{FHEM_URL}}` substitution); `exec
  /entry.sh start`.
- **Health**: the manifest `watchdog` key is **obsolete** (the official app
  linter rejects it) — the native Docker `HEALTHCHECK` is the health signal.
  It accepts HTTP `200`/`401` from FHEMWEB:8083 (401 = alive *and* auth
  working; `curl -f` would treat 401 as failure and flip the app to unhealthy
  whenever the web login is enabled). FHEMWEB must listen on 8083 (the
  exposed port).
- **Manifest conventions** (enforced by `frenck/action-addon-linter` in the CI
  `Lint` workflow): omit keys that equal their defaults (`apparmor`, `boot`,
  `init` set explicitly only when non-default…), no `watchdog`, prefer
  `translations/` over `ports_description`.
- **Config UX**: Configuration tab for options (labels/hints in
  `translations/en.yaml`); `fhem.cfg` is edited in FHEMWEB's *Edit files*
  editor, which is enabled together with the web login (`web-auth.cfg` →
  `editConfig 1`) and never without it. FHEMWEB's Save runs `rereadcfg`
  natively (see `01_FHEMWEB.pm`) — no restart needed after edits.

## Hard-won FHEM knowledge (do not re-learn these the hard way)

- `MQTT2_CLIENT`'s `define` takes **only** `host:port`. Credentials go via
  `attr <name> username` + `set <name> password` (stored in
  `FHEM/FhemUtils/uniqueID`). Credentials on the define line are silently
  ignored — and a test broker that allows anonymous connections masks this.
- FHEM 6.5 **removed** `attr WEB basicAuth`. Authentication is an `allowed`
  device: `define <x> allowed` + `attr <x> validFor <FHEMWEB-name>` +
  `set <x> basicAuth <user> <pass>` (salted SHA256). Without `validFor` it
  never authenticates. `noCheckFor` exempts paths from auth.
- `editConfig 1` on the FHEMWEB device enables the config editor; saving
  `fhem.cfg` there auto-runs `rereadcfg`, saving `*.pm` runs `reload`.
- MAX! `Activity` readings (`alive`) are set only when a device actually sends
  something; `MAX2HASSdiscovery` is event-driven. A boot-time discovery snippet
  is in `USER_GUIDE.md`.
- The NanoCUL MAX! firmware enforces an airtime credit (868 MHz duty cycle,
  ~1 unit/second). Right after a restart the resync backlog delays commands
  ("not enough credit ... Waiting N seconds") — self-healing, not a bug.
- FHEM never watches `fhem.cfg` — restart the app or `rereadcfg`.
- `define`/`attr`/`set` work fine inside included config files (the generated
  snippets rely on this).
- FHEM 6.x requires a CSRF token (`fwcsrf`) for `?cmd=...` requests.

## Development & testing (WSL2 + Docker)

- Build: `docker build -t hassio-fhem-test:0.1.0 ./fhem`.
  **`docker restart` keeps the old image** — always `docker rm -f` + `docker run`.
- Test rig: `/tmp/opencode/fhem-test/` — `data/options.json` bind-mounted to
  `/data/options.json`, `volume/` → `/opt/fhem`, a mock Supervisor API
  (`mock/services/mqtt`) and a test Mosquitto on the `fhem-test-net` network.
  **The test broker must require auth** (`mosquitto_passwd -b ...`, `touch` the
  file first — `-b` needs it to exist): an anonymous broker masked the MQTT
  credential bug for a whole release.
- Smoke checks: `bash -n fhem/run.sh`; run the container; `docker logs | grep
  run.sh`; auth checks with `curl -w '%{http_code}'` (expect 401 anon /
  200 authed); the FHEMWEB edit-page check needs the CSRF token (`fwcsrf`
  scraped from the page HTML).
- Personal data stays out of the repo: `/fhem.cfg.*` is gitignored (root-
  anchored so `fhem/rootfs/usr/src/templates/fhem.cfg.seed` stays tracked).
  No personal defaults (timezone, URLs): follow Home Assistant / generic HAOS
  names like `homeassistant.local` (the standard HAOS mDNS name).

## Release procedure (every user-visible change)

1. Bump `version` in `fhem/config.yaml` (`0.x.y-fhem6.5`). **HA only offers an
   update when the version changes** — a docs-only push without a bump is
   invisible to installed users (this has bitten us once).
2. Add a `fhem/CHANGELOG.md` entry on top.
3. Rewrite the doc links in `fhem/{README,DOCS,USER_GUIDE}.md`
   (`blob/<old-tag>/` → `blob/<new-tag>/`) so links match the released docs.
4. Commit, tag `v<version>`, `git push origin main --tags`. The tag must exist
   on the remote — the doc links point at it.

## Development flow

- **Debug locally first** (the WSL2 test rig above) — the fast iteration loop.
  CI is validation, not a debugger.
- **Branch + PR for app content** (`fhem/` changes): the `Builder` workflow
  builds PRs (both arches) and lints **without publishing** (`publish` is only
  true on push). Merge when green. Docs-only (`*.md`) and workflow-only pushes
  to `main` do not trigger builds — the monitored-files filter watches
  `config.yaml`, `Dockerfile`, `rootfs/`, `run.sh`, `apparmor.txt`,
  `translations/`.
- **Merge to `main` = release:** run the release procedure above in the same
  commit. Never push app-content changes without a version bump — CI would
  re-push the existing version tag with a different digest (mutable tag).
- **Real-HA testing happens on the update** (it pulls the pre-built image).
  For a change that must be validated on hardware before merging: sideload the
  branch as a local app with `image:` temporarily commented (forces an
  on-device build), or merge and fix forward — CI releases take ~1–2 minutes.

## Roadmap / status

- **Done — Phases 0–4:** environment; scaffold + image + seed + docs;
  standalone WSL tests (mock Supervisor, fake MAX devices, persistence); on-HA
  acceptance (NanoCUL, 8 devices, MQTT discovery, set-temperature round-trip,
  backup round-trip); config UX (Configure-tab options, FHEMWEB editor with
  login, timezone follows HA, translations, docs split).
- **Phase 5 (CI/CD) — done:** `.github/workflows/` from
  `home-assistant/apps-example` (`builder` + `build-app` with pinned
  `home-assistant/builder` actions → multi-arch `ghcr.io/tmtom/hassio-fhem`,
  publicly pullable, `lint` green); `bump-fhem.yaml` automates the release
  procedure (weekly probe for new FHEM/base releases → bump PR; tag created on
  merge). `image:` enabled — installs pull the pre-built image. *(Exit test:
  user update to 0.2.6 pulls without on-device build.)*
- **Phase 6 (optional):** FHEMWEB ingress experiment (proxying is tricky —
  absolute URLs), telnet option docs, forum post, Renovate/Dependabot.

## User-facing principles (keep these!)

- Users must be able to install **and configure** without extra tools (no
  VS Code/Samba/host SSH required — the Configure tab + FHEMWEB editor cover
  it). VS Code/Samba stay documented as power-user alternatives.
- Security: FHEMWEB is LAN-exposed; the web login is strongly recommended and
  gates the config editor — never expose config editing without a login.
- The in-app Documentation tab must stay a **short** setup guide; deep content
  lives in `USER_GUIDE.md` on GitHub.
