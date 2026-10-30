# Changelog

All notable changes to the FHEM app are documented here. The `version` in
`fhem/config.yaml` is the source of truth; the baked FHEM version is tracked in
`fhem/Dockerfile` (`ARG FHEM_VERSION`) and noted per release.

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
