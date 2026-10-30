# Changelog

All notable changes to the FHEM app are documented here. The `version` in
`fhem/config.yaml` is the source of truth; the baked FHEM version is tracked in
`fhem/Dockerfile` (`ARG FHEM_VERSION`) and noted per release.

## 0.2.9 (2026-10-30)

- **Removed the `fhem_cfg` option** (UX review: it added noise for a feature
  the primary flow replaced). `fhem.cfg` in the app config folder is the
  single source of truth, edited in FHEMWEB's *Edit files* (applies on save).
  If you had content stored in the option, paste it back into `fhem.cfg` once.

## 0.2.8 (2026-10-30)

- **Fix "No changelog found for app …" in the update dialog:** the Supervisor
  reads `CHANGELOG.md` from the *app folder* — it moved from the repository
  root to `fhem/CHANGELOG.md`, where the changelog dialog picks it up.

## 0.2.7 (2026-10-30)

- **Fix the boot-discovery snippet** in `USER_GUIDE.md`: the documented
  `hass.MAXdiscoveryBoot` `notify` used a multi-statement Perl block, which
  FHEM's command chain splits at every `;` (`Unknown command }, try help` in
  the log — found in a live install). The snippet is now a semicolon-free
  one-liner (`{... for LIST}`), verified against a real FHEM start, with a
  note on the `notify`/`;` pitfall.

## 0.2.6 (2026-10-30)

- **Manifest cleanups per the official app linter:** removed `boot` and
  `apparmor` (both match the defaults) and the `watchdog` key — it is
  obsolete; the native Docker `HEALTHCHECK` is the health signal (which
  accepts `200`/`401` since 0.2.4, so the web login no longer trips health
  checks). CI `Lint` workflow is green.

## 0.2.5 (2026-10-30)

- **Pre-built multi-arch images (CI/CD):** the app now installs from
  `ghcr.io/tmtom/hassio-fhem` (built by GitHub Actions per release for amd64
  and aarch64) instead of building on the device — much faster installs and
  updates. Repository builds (`/addons`) still work.
- CI workflows adapted from `home-assistant/apps-example` (`builder`,
  `build-app`, `lint`); the rebuild trigger also watches `run.sh`,
  `apparmor.txt` and `translations/`.

## 0.2.4 (2026-10-30)

- **Fix watchdog/health with web auth enabled:** the Supervisor's HTTP
  watchdog only counts status < 300 as healthy, but a login-protected FHEMWEB
  answers 401 — so the watchdog flagged the app as broken and **restarted it
  in a loop**. The manifest watchdog is now `tcp://` (auth-independent) and
  the container health check accepts `200`/`401` as alive.
- Added `AGENTS.md` — project knowledge for future development sessions.

## 0.2.3 (2026-10-30)

- **Fix the Info-tab documentation link:** the app's `README.md` used a
  relative `[DOCS.md](DOCS.md)` link, which the rendered Info tab resolved
  against the panel URL — a dead end. Links are now absolute GitHub URLs.
- **Documentation links are versioned:** they point at the release tag
  (`blob/v0.2.3-fhem6.5/...`) instead of the moving `main` branch, so the
  linked docs match the installed app version. Each release rewrites the links
  to its own tag (the in-app Documentation tab renders `DOCS.md` from the
  repository checkout and may still differ from the installed image).

## 0.2.2 (2026-10-30)

- **Config editing follows the FHEMWEB login:** the `web_edit_config` option is
  gone — the "Edit files" editor is enabled automatically whenever
  `web_auth_user`/`web_auth_password` are set (and never without a login).
- **Timezone follows Home Assistant:** the app reads HA's timezone via the
  Core API (`homeassistant_api: true`, read-only usage; hidden `timezone`
  option overrides). The personal `Europe/Prague` default is gone.
- **Translations:** readable names and descriptions for all options and ports
  in the Configuration tab (`translations/en.yaml`).
- **Docs split:** the Documentation tab is now a short setup guide; the full
  documentation (options reference, MQTT bridge, porting guide,
  troubleshooting) lives in `USER_GUIDE.md` on GitHub.
- Removed remaining personal-setup defaults; `.gitignore` now covers all
  personal `fhem.cfg.*` files (the shipped `fhem.cfg.seed` template stays
  tracked).

## 0.2.1 (2026-10-30)

- **Fix `web_edit_config` for file-based configs:** `web-auth.cfg` was only
  loaded when `fhem.cfg` included it manually — `run.sh` now appends
  `include web-auth.cfg` to `fhem.cfg` automatically when missing (idempotent,
  logged; both file-based and `fhem_cfg`-option configs).
- **Security guard:** `web_edit_config` is ignored unless web auth
  (`web_auth_user`/`web_auth_password`) is configured — the config editor is
  never exposed on an unauthenticated FHEMWEB.
- Docs: FHEMWEB's editor is now the recommended config path — its Save
  re-reads the config immediately (`rereadcfg` runs automatically), no restart
  needed.

## 0.2.0 (2026-10-30)

- **Configuration from Home Assistant — no extra tools:** new `fhem_cfg` option
  holds the complete FHEM configuration text (edited in the app's
  Configuration tab via **Edit in YAML**). When set, the app materializes
  `fhem.cfg` from it on every start (write-on-change): the file becomes derived
  state that cannot be lost, and the config is covered twice by Home Assistant
  backups (app options + config folder). When empty (default), `fhem.cfg` in
  the config folder governs exactly as in 0.1.x (back-compat).
- New options `web_auth_user`/`web_auth_password` (FHEMWEB login — FHEM 6.x
  `allowed` device with salted SHA256, generated into `web-auth.cfg`) and
  `web_edit_config` (enable FHEMWEB's own file editor). The seed config now
  includes `web-auth.cfg`.
- Docs: "Editing the configuration" leads with the Configure-tab flow;
  VS Code/Samba remain documented as power-user alternatives.

## 0.1.4 (2026-10-30)

- **Fix MQTT authentication:** `MQTT2_CLIENT` only takes `host:port` as the
  define argument — credentials passed on the `define` line were silently
  ignored and FHEM connected anonymously (rejected by brokers requiring auth,
  e.g. the Mosquitto app's service user). `mqtt-connection.cfg` now generates
  `attr mqtt username` + `set mqtt password` (the module's real credential
  mechanism; the password is stored in `FHEM/FhemUtils/uniqueID`). Found by
  the first authenticated on-HA run — the WSL test broker allowed anonymous
  connections, which masked it.

## 0.1.3 (2026-10-30)

- **Backups fix:** `backup_exclude: ["log/*"]` also excluded the FHEM state
  file `log/fhem.save` (and `log/eventTypes.txt`) — only `log/*.log` is
  excluded now. Also switched to `backup: cold`, so FHEM saves its state on
  shutdown before the snapshot is taken (consistent backups).
- Safety net: if `fhem.cfg` is missing but `fhem.cfg.bak` exists (the FHEM
  image keeps that copy on every start), the backup is restored instead of
  installing the seed — user configurations survive unexpected file loss.
- The startup log fingerprints `fhem.cfg` (size + md5) so configuration loss
  is diagnosable from the app log alone.
- Seed and docs: document editing the configuration (VS Code/Samba
  `app_configs` folder, FHEMWEB `editConfig` with `basicAuth`), the
  restart/`rereadcfg` pickup behavior, and the backup contents.

## 0.1.2 (2026-10-30)

- Fix the container health check: the base image's `/health-check.sh` needs
  FHEM-side `DockerHealthCheck` attributes and stayed **permanently unhealthy**
  with stock/ported configs. Since the Supervisor resolves the app state via
  container health, the app appeared "stopped/starting" for minutes in the HA
  UI. The health check now probes FHEMWEB directly on a tight cadence
  (5s interval) — the app flips to "started" soon after FHEM is up.
- The app version now carries the pinned FHEM release (e.g. `0.1.2-fhem6.5`),
  so the FHEM version is visible on the app info page.
- The startup log shows the pinned FHEM seed version.

## 0.1.1 (2026-10-30)

- Fix MQTT credential auto-discovery on real Home Assistant: the Supervisor
  services API wraps its payload in `{"result": ..., "data": {...}}` — parse
  that envelope (flat responses still accepted) and only claim success when a
  broker host was actually returned (found by the first on-HA test run).
- Docs: note that optional options (like the `device` dropdown) are hidden
  behind **Show unused optional configuration options**; clarify that the
  startup serial-device listing does not touch the devices.

## 0.1.0 (unreleased)

- Initial MVP of the FHEM app for Home Assistant.
- Base image: `ghcr.io/fhem/fhem-minimal-docker:5.2.0-bookworm`; seeds pinned
  FHEM **6.5** from the fhem.de release tarball into the persistent app config
  folder on first start (no unpinned svn checkout at boot).
- Persistence via `app_config` mounted at `/opt/fhem` (no privileged bind
  mount); included in Home Assistant backups (`backup: hot`, `log/*` excluded).
- MQTT credentials auto-discovered from the Supervisor `mqtt` service
  (`services: [mqtt:want]`), with manual `mqtt_*` fallback options; written to
  `mqtt-connection.cfg` on every start.
- Optional vendored fhemMAX2HASS `99_myUtils.pm` (AGPL-3.0) for Home Assistant
  MQTT discovery of MAX! devices; FHEM deep-link base URL configurable via the
  `fhem_url` option.
- FHEMWEB on port 8083 with **Open Web UI** button and Supervisor watchdog.
- Serial access for the NanoCUL (`uart: true`, optional `device` dropdown);
  dialout GID=18 fix for HA OS device nodes.
- Generic stock seed config only — no personal configuration is shipped.

Note: the planned base image tag `5.5.1-bookworm` from the design plan does not
exist upstream; the newest published fixed tag `5.2.0-bookworm` is pinned
instead.
