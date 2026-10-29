# Changelog

All notable changes to the FHEM app are documented here. The `version` in
`fhem/config.yaml` is the source of truth; the baked FHEM version is tracked in
`fhem/Dockerfile` (`ARG FHEM_VERSION`) and noted per release.

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
