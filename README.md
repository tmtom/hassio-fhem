# FHEM app for Home Assistant

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/configure_start_repository/?repository_url=https://github.com/tmtom/hassio-fhem)

A maintained Home Assistant [app (add-on)](https://contributors.home-assistant.io/apps/)
that runs [FHEM](https://fhem.de) — controlling eQ-3 **MAX!** radiator valves
and window contacts via a **NanoCUL** USB stick and exposing them to Home
Assistant over **MQTT** (with MQTT discovery), with the FHEM web UI available
from the app's info page.

## Features

- **FHEMWEB** on port 8083 with an **Open Web UI** button, health monitoring
  and an optional web login — which also enables the built-in config editor
  (*Edit files*, applies on save without a restart).
- **MAX! via NanoCUL** (CUL + CUL_MAX) — serial device access for
  `/dev/serial/by-id/...`, with an optional device picker to pin the adapter.
- **MQTT bridge** with automatic broker credential discovery from the
  Supervisor (Mosquitto app), manual fallback options included.
- **Home Assistant MQTT discovery** for MAX! devices via the vendored
  [fhemMAX2HASS](https://github.com/danielrheinbay/fhemMAX2HASS) helper —
  climate entities (eco/comfort/boost), window sensors, battery/signal
  diagnostics, availability.
- **Pre-built multi-arch images** from GitHub Actions — installs and updates
  pull from GHCR in seconds, no build on the device.
- **Persistent configuration** in the app config folder
  (`/addon_configs/<repo>_fhem`), included in Home Assistant backups.
- **Pinned FHEM release** (6.5) seeded on first start — reproducible installs,
  updates via FHEM's own `update` command.
- Clean stock configuration — bring your own FHEM config with the included
  porting guide. Options come with readable labels and hints in the
  Configuration tab; timezone follows Home Assistant automatically.

## Supported architectures

`amd64` and `aarch64`. armv7/armhf are **not** built (deprecated in Home
Assistant app configs).

## Installation & documentation

Add this repository in **Settings → Apps → ⋮ → Repositories**
(`https://github.com/tmtom/hassio-fhem`), install **FHEM** and see the
Documentation tab, or read [`fhem/DOCS.md`](fhem/DOCS.md). The full reference
— options, MQTT setup, porting an existing FHEM configuration, update
behavior, security notes, troubleshooting — is in
[`fhem/USER_GUIDE.md`](fhem/USER_GUIDE.md).

## Repository layout

- `fhem/` — the app: manifest, Dockerfile, entrypoint, docs (`README`,
  `DOCS`, `USER_GUIDE`, `CHANGELOG`), translations
- `AGENTS.md` — project knowledge for contributors (and AI agents): architecture,
  hard-won FHEM facts, testing, release procedure
- `.github/workflows/` — CI: multi-arch image builds to GHCR, lint, automated
  FHEM version bumps
- `repository.yaml` — repository metadata for the Supervisor

## Development

Pre-built multi-arch images (`ghcr.io/tmtom/hassio-fhem`) are built by GitHub
Actions on every release (amd64 + aarch64, published to GHCR) — installs and
updates pull the image instead of building on the device.

High-level flow (details in [`AGENTS.md`](AGENTS.md)):

1. **Debug locally** with the Docker test rig — CI is validation, not a
   debugger.
2. **Branch + PR** for app content: CI builds both architectures and lints,
   without publishing.
3. **Merge to `main` = release**: version bump + `fhem/CHANGELOG.md` entry +
   doc links + tag — CI builds and publishes automatically. The scheduled
   `bump-fhem` workflow keeps the FHEM/base-image pins current via pull
   requests.

Read [`AGENTS.md`](AGENTS.md) before contributing — it documents the
architecture, the FHEM pitfalls already paid for, and the release procedure.

## Licensing

- App glue (scripts, templates, docs): [MIT](LICENSE)
- Vendored `99_myUtils.pm` ([fhemMAX2HASS](https://github.com/danielrheinbay/fhemMAX2HASS)):
  AGPL-3.0 (license text included in the image)
- [FHEM](https://fhem.de) (GPL) is redistributed inside the image via the
  official [fhem-docker](https://github.com/fhem/fhem-docker) base image
- Icon/logo: the official FHEM logo from
  [fhem-mirror](https://github.com/fhem/fhem-mirror/blob/main/fhem/docs/fhem.svg)
  (GPL-2.0 project), used to identify this FHEM app
