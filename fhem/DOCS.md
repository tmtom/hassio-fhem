# FHEM

[FHEM](https://fhem.de) is a Perl-based home automation system. This app runs
FHEM inside Home Assistant, with a battle-tested setup for **eQ-3 MAX!**
radiator valves and window contacts via a **NanoCUL** USB stick, bridged to
Home Assistant over **MQTT** (including Home Assistant MQTT discovery).

- FHEM web interface (FHEMWEB) available through the **Open Web UI** button.
- FHEM configuration lives in the app's config folder and is included in
  Home Assistant backups.
- MQTT broker credentials are picked up automatically from the Supervisor
  (e.g. the Mosquitto app) — no manual credential juggling needed.
- Ships a clean stock FHEM setup. Port your own configuration with the
  [porting guide](https://github.com/tmtom/hassio-fhem/blob/v0.2.9-fhem6.5/fhem/USER_GUIDE.md#porting-an-existing-fhem-config).

## Installation

1. Install the **Mosquitto** app (or any MQTT broker) in Home Assistant.
2. Add this repository (**Settings → Apps → ⋮ → Repositories**):
   `https://github.com/tmtom/hassio-fhem`
3. Install **FHEM**, configure the options below and start it.
4. Open the web interface with **Open Web UI** (or browse to
   `http://<your-ha>:8083/fhem`).

> **Architectures:** `amd64` and `aarch64` only. armv7/armhf are not built.

## Configuration

What you should set on the **Configuration** tab (then restart):

- **FHEMWEB login** (`web_auth_user`, `web_auth_password`) — a login for the
  web interface. Strongly recommended: without it, anyone on your network can
  control your heating. The login also enables the configuration editor
  (below).
- **Timezone** — follows your Home Assistant setting automatically; no need
  to set anything. (The hidden `timezone` option under *Show unused optional
  configuration options* overrides it.)

Everything else has working defaults: MQTT is discovered automatically, and
the `device` option is only needed if your NanoCUL is not picked up.

## Configure FHEM

After the restart: open **Web UI** → *Edit files* → `fhem.cfg` → edit →
**Save**. Saved changes apply immediately — no restart needed. (This editor is
enabled by the FHEMWEB login above.)

## Backups

Your whole FHEM installation (configuration, modules, device state) lives in
the app config folder and is part of Home Assistant backups. Backups are taken
with FHEM stopped (`backup: cold`), so they are consistent.

## Licensing

- The app's own files (scripts, config templates, docs) are **MIT** (see
  `LICENSE`).
- The vendored `99_myUtils.pm` comes from
  [fhemMAX2HASS](https://github.com/danielrheinbay/fhemMAX2HASS) and is
  **AGPL-3.0**; the license text ships next to it in the image.
- **FHEM** itself is **GPL** and is redistributed inside the image via the
  official [fhem-docker](https://github.com/fhem/fhem-docker) base image and
  the pinned [fhem.de](https://fhem.de) release tarball.
- The app icon/logo is the official FHEM logo (GPL-2.0 project).

## Full documentation

Options reference, MQTT bridge setup, porting an existing FHEM config,
troubleshooting and more — in
**[USER_GUIDE.md](https://github.com/tmtom/hassio-fhem/blob/v0.2.9-fhem6.5/fhem/USER_GUIDE.md)**.
