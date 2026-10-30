# FHEM

[FHEM](https://fhem.de) is a Perl-based home automation system. This app runs
FHEM inside Home Assistant, with a battle-tested setup for **eQ-3 MAX!**
radiator valves and window contacts via a **NanoCUL** USB stick, bridged to
Home Assistant over **MQTT** (including Home Assistant MQTT discovery).

- FHEM web interface (FHEMWEB) available through the **Open Web UI** button.
- FHEM configuration lives in the app's config folder and is included in Home
  Assistant backups.
- MQTT broker credentials are picked up automatically from the Supervisor
  (e.g. the Mosquitto app) — no manual credential juggling needed.
- Ships a clean stock FHEM setup. Port your own configuration with the guide
  below.

## Installation

1. Install the **Mosquitto** app (or any MQTT broker) in Home Assistant.
2. Add this repository (**Settings → Apps → ⋮ → Repositories**):
   `https://github.com/tmtom/hassio-fhem`
3. Install **FHEM**, configure the options below and start it.
4. Open the web interface with **Open Web UI** (or browse to
   `http://<your-ha>:8083/fhem`).

> **Architectures:** `amd64` and `aarch64` only. armv7/armhf are not built.

## Configuration

| Option | Default | Description |
|---|---|---|
| `device` | *(unset)* | Serial device of the NanoCUL (dropdown of `/dev/serial/by-id/...` paths). Optional options are hidden in the UI — enable **Show unused optional configuration options** to see it. `uart: true` already maps serial devices; setting this pins a specific one. |
| `mqtt_automatic` | `true` | Discover the MQTT broker via the Supervisor `mqtt` service (recommended with the Mosquitto app). |
| `mqtt_host` | *(empty)* | Manual broker host (fallback when `mqtt_automatic` is `false` or discovery fails). Other apps reach Mosquitto as `core-mosquitto`. |
| `mqtt_port` | `1883` | Manual broker port. |
| `mqtt_user` | *(empty)* | Manual broker user name. |
| `mqtt_password` | *(empty)* | Manual broker password. |
| `fhemmax2hass` | `true` | Install the vendored [fhemMAX2HASS](https://github.com/danielrheinbay/fhemMAX2HASS) helper (`99_myUtils.pm`) for Home Assistant MQTT discovery of MAX! devices. |
| `fhem_url` | `http://homeassistant.local:8083/fhem` | Base URL of FHEMWEB used in Home Assistant → FHEM deep links (fhemMAX2HASS). |
| `timezone` | `Europe/Prague` | Container timezone (`TZ`). |

## Where the configuration lives

The app's config folder is mounted at `/opt/fhem` inside the container. On the
host you find it at **`/addon_configs/<repo>_fhem`** (shown as
`app_configs/<repo>_fhem` in the Samba/SSH/VS Code apps). Everything FHEM keeps
lives there: `fhem.cfg`, `FHEM/`, `log/`, `mqtt-connection.cfg`, … — all of it
is persistent and part of Home Assistant backups.

`/run.sh` generates **`mqtt-connection.cfg`** in that folder on every start,
containing a ready-made `define mqtt MQTT2_CLIENT ...` line with the discovered
broker credentials. Include it from `fhem.cfg` or copy the lines into your own
definition (credentials must not contain whitespace).

On startup, the app logs the serial devices visible in the container
(`/dev/serial/by-id/...`) — useful when defining the CUL device in `fhem.cfg`.
This is only a listing: no device is opened or reconfigured. FHEM communicates
exclusively with the device referenced in your `define CUL0 CUL ...` (if any) —
other serial devices present (Zigbee sticks, meter readers, …) stay untouched.

## MQTT bridge to Home Assistant (MAX!)

A complete MQTT → Home Assistant setup for MAX! devices consists of (all in
`fhem.cfg`):

```perl
# 1. The broker connection (or: include mqtt-connection.cfg)
define mqtt MQTT2_CLIENT core-mosquitto:1883 <user> <password>
attr mqtt lwt homeassistant/binary_sensor/fhem/availability offline
attr mqtt lwtRetain 1
attr mqtt msgAfterConnect -r homeassistant/binary_sensor/fhem/availability online
attr mqtt msgBeforeDisconnect -r homeassistant/binary_sensor/fhem/availability offline

# 2. The generic MQTT bridge (publish/subscribe per device)
define mqttGenericBridge MQTT_GENERIC_BRIDGE
attr mqttGenericBridge IODev mqtt
attr mqttGenericBridge globalDefaults base="homeassistant" qos=2 retain=1
attr mqttGenericBridge stateFormat dev: device-count in: incoming-count out: outgoing-count

# 3. Home Assistant discovery via fhemMAX2HASS (option fhemmax2hass installs
#    99_myUtils.pm; it is inert unless you call it like this)
define hass.MAXdiscovery DOIF ([":Activity",""]) ({MAX2HASSdiscovery("$DEVICE")})
attr hass.MAXdiscovery do always
```

Per device, the discovery and state transport needs attributes like:

```perl
attr MAX_bedroom_window actCycle 12:00
attr MAX_bedroom_window model ShutterContact
attr MAX_bedroom_window mqttPublish *:topic={"$base/$device/$name"}
attr MAX_bedroom_valve model HeatingThermostat
attr MAX_bedroom_valve mqttPublish *:topic={"$base/$device/$name"}
attr MAX_bedroom_valve mqttSubscribe desiredTemperature:stopic={"$base/$device/set"}
```

`actCycle 12:00` matters for two reasons: the `Activity` reading it creates is
what triggers the discovery DOIF above, and after 12 hours of inactivity the
device is marked unavailable in Home Assistant. See `fhemMAX2HASSdiscovery` in
[fhemMAX2HASS](https://github.com/danielrheinbay/fhemMAX2HASS) for details.

## Porting an existing FHEM config

The app ships a clean stock config; you port your own `fhem.cfg` into the app
config folder:

1. Copy the old `fhem.cfg` (and any `99_myUtils.pm`, plus `./log` state you
   want to keep) into the app config folder (`/opt/fhem`). Relative paths
   (`modpath .`, `./log/...`, `statefile ./log/fhem.save`) keep working
   unchanged — `/opt/fhem` is both working directory and persistent volume.
   Tip: copy the files in *before* the first start — the seed `fhem.cfg` is
   only installed when none exists.
2. Replace the MQTT endpoint (`define mqtt MQTT2_CLIENT localhost:1883`) with
   `include mqtt-connection.cfg`, or edit in the broker address manually (other
   apps reach Mosquitto as `core-mosquitto:1883`).
3. Replace the CUL device path with the by-id path the app logs at startup (e.g.
   `/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0@38400`). CUL key and
   `CUL_MAX` settings (`1234`, `123456`, `fakeSCaddr`, `fakeWTaddr`) are
   config-side values and carry over as-is.
4. If you use `MAX2HASSdiscovery`: no code copy needed — the app vendors
   `99_myUtils.pm` when `fhemmax2hass: true` (set the `fhem_url` option so the
   Home Assistant → FHEM deep links point at the right host:port). If you bring
   your own `99_myUtils.pm`, the app leaves it untouched. `actCycle 12:00` must
   be set on the MAX! devices (availability handling).
5. No re-pairing needed: MAX! device addresses live in `fhem.cfg` and the
   hardware; keeping the CUL key and `fakeSCaddr`/`fakeWTaddr` identical
   preserves all group/association state.
6. Restart the app and check the log tab: `CUL0` `opened`, `mqtt` connected,
   devices updating. In Home Assistant, MQTT discovery creates the entities.

Note on logs: FHEM writes its log wherever `attr global logfile` points. The
app follows that setting, so the log shows up in the app's log tab even with
ported configs that log monthly (`./log/fhem-%Y-%m.log`).

## Updates: the app vs. FHEM

Home Assistant app updates and FHEM updates are **separate things**:

- **App updates** replace the container. Your `/opt/fhem` volume is untouched —
  including your FHEM version and configuration.
- **FHEM itself** is updated from FHEMWEB with the `update` command (the
  default `controls` mechanism), and the changes persist in the volume.
- The pinned FHEM release baked into the image (see `CHANGELOG.md`) is only
  used to **seed brand-new installs**.
- The app version embeds the pinned FHEM release (e.g. `0.1.2-fhem6.5`), so the
  FHEM version is visible on the app info page. The actually running FHEM
  version may be newer after using FHEM's `update` command — the log shows
  `Featurelevel: <version>` at startup.

## Security notes

- **FHEMWEB has no authentication by default.** Port 8083 is mapped to your
  LAN and anyone there can control your heating. Enable `basicAuth` on the
  FHEMWEB definition (e.g. `attr WEB basicAuth user:password`) or unmap the
  port in the app configuration and reach FHEM through other means.
- The telnet console (port 7072) is disabled by default; enable the port in the
  app configuration if you need it.
- AppArmor is enabled with the profile shipped in this repository
  (`fhem/apparmor.txt`). The FHEM image's startup script needs broad file and
  capability access (user setup, chown on `/opt/fhem` and serial devices), so
  the profile is permissive in places. If the app misbehaves with AppArmor
  denials in the log, set `apparmor: false` in `fhem/config.yaml` for a local
  build (lowers the security rating) and please open an issue.

## Troubleshooting

- **CUL stays `disconnected`:** check the app log for the listed
  `/dev/serial/by-id/...` devices; verify the path in your CUL `define`; try
  setting the `device` option to pin the mapping. A NanoCUL usually shows up as
  `usb-1a86_USB2.0-Serial-if00-port0`.
- **MQTT not connecting:** check `mqtt-connection.cfg` in the config folder;
  with `mqtt_automatic: true` a running broker app providing the `mqtt` service
  is required. Fallback: `mqtt_automatic: false` plus manual `mqtt_*` options.
- **No entities in Home Assistant:** the discovery messages need the
  MQTT bridge snippet above, device `mqttPublish`/`mqttSubscribe` attributes,
  and device activity (fhemMAX2HASS publishes on `:Activity` events).
- **Watchdog turns the app unhealthy:** FHEM starts slowly on first boot; the
  watchdog checks `http://[HOST]:[PORT:8083]/fhem`. The app's health check
  probes the same URL, so FHEMWEB must listen on port 8083 (the port exposed
  by the manifest). Check the log tab for startup errors.
- **Scripting FHEMWEB commands (`?cmd=...`):** FHEM 6.x requires a CSRF token
  for commands. Either fetch and pass the token (`fwcsrf` parameter) or, for
  trusted local setups, disable it on the FHEMWEB definition:
  `attr WEB csrfToken none`.

## Licensing

- The app's own files (scripts, config templates, docs) are **MIT** (see
  `LICENSE`).
- The vendored `99_myUtils.pm` comes from
  [fhemMAX2HASS](https://github.com/danielrheinbay/fhemMAX2HASS) and is
  **AGPL-3.0**; the license text ships next to it in the image
  (`/usr/src/fhemMAX2HASS-LICENSE.txt`). Only the FHEM deep-link URL is
  parameterized (documented in the file header).
- **FHEM** itself is **GPL** and is redistributed inside the image via the
  official [fhem-docker](https://github.com/fhem/fhem-docker) base image and
  the pinned [fhem.de](https://fhem.de) release tarball. Source:
  https://fhem.de and https://svn.fhem.de.
- The app icon/logo is the official FHEM logo taken from
  [fhem-mirror](https://github.com/fhem/fhem-mirror/blob/main/fhem/docs/fhem.svg)
  (GPL-2.0 project), used to identify this FHEM app.
