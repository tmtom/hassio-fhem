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
| `web_auth_user` | *(empty)* | Login for FHEMWEB (with `web_auth_password`): the app configures FHEM's `allowed` device in `web-auth.cfg` (salted SHA256). Whitespace is not allowed in the password. |
| `web_auth_password` | *(empty)* | Password for FHEMWEB. |
| `web_edit_config` | `false` | Allow editing `fhem.cfg` from FHEMWEB ("Edit files" page). Requires `web_auth_user`/`web_auth_password` — ignored otherwise (the editor is never exposed without a login). Saving the config there applies it immediately (`rereadcfg` runs automatically) — no restart needed. |
| `fhem_cfg` | *(empty)* | The complete FHEM configuration text (see *Editing the configuration*). When set, it is the source of truth and `fhem.cfg` is written from it on every start. When empty, `fhem.cfg` in the config folder governs. |

## Where the configuration lives

The app's config folder is mounted at `/opt/fhem` inside the container. On the
host you find it at **`/addon_configs/<repo>_fhem`** (shown as
`app_configs/<repo>_fhem` in the Samba/SSH/VS Code apps). Everything FHEM keeps
lives there: `fhem.cfg`, `FHEM/`, `log/`, `mqtt-connection.cfg`, `web-auth.cfg`,
… — all of it is persistent and part of Home Assistant backups.

`/run.sh` generates two snippets in that folder on every start:
**`mqtt-connection.cfg`** with a ready-made `define mqtt MQTT2_CLIENT ...` line
(broker credentials from the Supervisor service; credentials must not contain
whitespace) and **`web-auth.cfg`** with the FHEMWEB login/edit settings from
the app options. Include them from `fhem.cfg`, or copy the lines into your own
definitions.

## Editing the configuration

No extra tools are needed — the app's own **Configuration** tab is the editor:

1. Open the app in Home Assistant → **Configuration** tab.
2. Switch to **Edit in YAML** (the visual form fields are single-line; the YAML
   editor is where the multi-line config text lives — a YAML block scalar:
   `fhem_cfg: |` followed by the indented config lines).
3. Put your complete FHEM configuration into the `fhem_cfg` field.
4. **Save** — Home Assistant prompts to restart the app; confirm. Done.

With `fhem_cfg` set, the option is the source of truth: the app writes
`fhem.cfg` from it on every start (the file becomes derived state and can never
be "lost" — and your config is covered twice by Home Assistant backups: in the
app's options and in the config folder).

Leave `fhem_cfg` empty (the default) to have `fhem.cfg` in the config folder
govern directly. Two comfortable ways to edit it:

- **FHEMWEB's built-in editor** (recommended — no extra tools): set
  `web_auth_user`/`web_auth_password` and `web_edit_config: true`, restart,
  then open the app's Web UI button → *Edit files* → `fhem.cfg` → edit →
  **Save**. Saving the config file re-reads it immediately (FHEMWEB runs
  `rereadcfg` automatically) — no restart needed. The editor is only enabled
  together with web auth; without a login it stays read-only.
- **VS Code or Samba app** on the `..._fhem` folder under `addon_configs`
  (power users; also for editing included files and custom Perl modules).
  Note: the built-in *File editor* app only shows Home Assistant's own
  `/config`, not app configuration folders.

FHEM does not watch `fhem.cfg`: changes are picked up when FHEM reads the
config — the FHEMWEB editor does that on Save; for edits made with other
tools, **restart the app** (the prompt after saving options does this) or run
`rereadcfg` in FHEMWEB.

As a safety net, the FHEM image keeps a `fhem.cfg.bak` copy of the config on
every start; if `fhem.cfg` ever goes missing (and `fhem_cfg` is not set), the
app restores that backup instead of installing the seed.

## Backups

Everything that makes up your FHEM installation lives in the app config
folder, so Home Assistant backups include it all: `fhem.cfg`, `FHEM/`
(modules), the pinned tree, and the state (`log/fhem.save`,
`log/eventTypes.txt`). Only `*.log` files are excluded.

The app uses `backup: cold`: FHEM is briefly stopped during the backup, saves
its state on shutdown, and the snapshot is taken — so the backup is consistent.
Restoring that backup brings back configuration, modules and device state.

On startup, the app logs the serial devices visible in the container
(`/dev/serial/by-id/...`) — useful when defining the CUL device in `fhem.cfg`.
This is only a listing: no device is opened or reconfigured. FHEM communicates
exclusively with the device referenced in your `define CUL0 CUL ...` (if any) —
other serial devices present (Zigbee sticks, meter readers, …) stay untouched.

Note on device paths: the `device` dropdown is populated by Home Assistant
(Supervisor) from the host's udev database and lists the stable
`/dev/serial/by-id/...` links. Custom udev symlinks (e.g. `/dev/nanocul` via
`SYMLINK+="nanocul"`) are not shown in the dropdown, but they work fine in
`fhem.cfg`: the host's `/dev` is mounted into the container and the option
validator accepts any udev-managed link. For adapters without a USB serial
number (identical by-id names), `udev`'s `/dev/serial/by-path/...` links or a
custom `SYMLINK+=` rule keyed on the USB port path are the robust choices.

## MQTT bridge to Home Assistant (MAX!)

A complete MQTT → Home Assistant setup for MAX! devices consists of (all in
`fhem.cfg`):

```perl
# 1. The broker connection (or: include mqtt-connection.cfg)
#    Note: MQTT2_CLIENT takes credentials via 'attr mqtt username' and
#    'set mqtt password' (stored in FHEM/FhemUtils/uniqueID) — not as
#    define arguments. Passwords must not contain whitespace.
define mqtt MQTT2_CLIENT core-mosquitto:1883
attr mqtt username <user>
set mqtt password <password>
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

Discovery is **event-driven**: it runs when a device reports `Activity`, i.e.
when the device actually sends something (open a window, press a button on a
thermostat) — not at FHEM startup. To publish discovery for all MAX! devices
right after startup as well, add:

```perl
define hass.MAXdiscoveryBoot notify global:INITIALIZED {foreach (devspec2array("TYPE=MAX")) { MAX2HASSdiscovery($_); } return "";}
```

## Porting an existing FHEM config

The app ships a clean stock config; you port your own `fhem.cfg` into the app
config folder:

1. Get your old `fhem.cfg` into the app. Easiest: paste it into the `fhem_cfg`
   option (app → Configuration → **Edit in YAML**) — the app keeps `fhem.cfg`
   in sync with it. Alternatively copy the file (and any `99_myUtils.pm`, plus
   `./log` state you want to keep) into the app config folder (`/opt/fhem`) and
   leave `fhem_cfg` empty. Relative paths
   (`modpath .`, `./log/...`, `statefile ./log/fhem.save`) keep working
   unchanged — `/opt/fhem` is both working directory and persistent volume.
   Tip for the copy path: do it *before* the first start — the seed `fhem.cfg`
   is only installed when none exists.
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
  LAN and anyone there can control your heating. Set `web_auth_user` and
  `web_auth_password` in the app options (generated into `web-auth.cfg`, which
  the app appends to `fhem.cfg` automatically), or unmap the port in the app
  configuration and reach FHEM through other means.
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
  and device activity (fhemMAX2HASS publishes on `:Activity` events). Trigger
  one: open a window or press a button on a thermostat, or run
  `setreading <device> Activity alive` in FHEMWEB (the same event the MAX!
  modules generate).
- **Commands seem ignored right after a restart** (`not enough credit ...
  Waiting N seconds` in the log): the NanoCUL's MAX! firmware enforces an
  airtime credit (868 MHz duty-cycle regulation, ~1 unit per second) and FHEM
  schedules its send queue around it. After a restart FHEM resyncs with all
  devices (SetGroupId housekeeping), which spends the credit pool — commands
  then queue up and drain over the next minutes. Normal and self-healing;
  steady-state commands go out within seconds.
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
