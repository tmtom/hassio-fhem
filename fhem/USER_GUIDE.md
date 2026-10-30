# FHEM app — user guide

The complete documentation for the **hassio-fhem** app. The in-app
**Documentation** tab shows the short setup guide
([DOCS.md](https://github.com/tmtom/hassio-fhem/blob/v0.2.4-fhem6.5/fhem/DOCS.md));
everything else is here.

- [Options reference](#options-reference)
- [Where the configuration lives](#where-the-configuration-lives)
- [Editing the configuration](#editing-the-configuration)
- [Backups](#backups)
- [MQTT bridge to Home Assistant (MAX!)](#mqtt-bridge-to-home-assistant-max)
- [Porting an existing FHEM config](#porting-an-existing-fhem-config)
- [Updates: the app vs. FHEM](#updates-the-app-vs-fhem)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)

## Options reference

| Option | Default | Description |
|---|---|---|
| `web_auth_user` | *(empty)* | Login for FHEMWEB (with `web_auth_password`): the app configures FHEM's `allowed` device in `web-auth.cfg` (salted SHA256). Also enables the FHEMWEB config editor. Whitespace is not allowed in the password. |
| `web_auth_password` | *(empty)* | Password for FHEMWEB. |
| `mqtt_automatic` | `true` | Discover the MQTT broker via the Supervisor `mqtt` service (recommended with the Mosquitto app). |
| `mqtt_host` | *(empty)* | Manual broker host (fallback when `mqtt_automatic` is `false` or discovery fails). Other apps reach Mosquitto as `core-mosquitto`. |
| `mqtt_port` | `1883` | Manual broker port. |
| `mqtt_user` | *(empty)* | Manual broker user name. |
| `mqtt_password` | *(empty)* | Manual broker password. |
| `fhemmax2hass` | `true` | Install the vendored [fhemMAX2HASS](https://github.com/danielrheinbay/fhemMAX2HASS) helper (`99_myUtils.pm`) for Home Assistant MQTT discovery of MAX! devices. |
| `fhem_url` | `http://homeassistant.local:8083/fhem` | Base URL of FHEMWEB used in Home Assistant → FHEM deep links (fhemMAX2HASS). `homeassistant.local` is the standard Home Assistant OS mDNS name — change it if your HA is reachable under a different name. |
| `device` | *(unset, hidden)* | Serial device of the NanoCUL (dropdown of `/dev/serial/by-id/...` paths). `uart: true` already maps serial devices; setting this pins a specific one. |
| `timezone` | *(unset, hidden)* | Timezone override. When unset, the app follows Home Assistant's timezone (read from the Home Assistant Core API; the app requests `homeassistant_api` for this read-only lookup). FHEM's clock is what the MAX! thermostats sync their weekly program to. |
| `fhem_cfg` | *(unset, hidden, advanced)* | The complete FHEM configuration text as the source of truth (edited via *Edit in YAML* in the Configuration tab). When set, the app materializes `fhem.cfg` from it on every start (write-on-change) — the file becomes derived state and can never be lost, and the config is covered twice by Home Assistant backups. When unset (recommended), `fhem.cfg` in the config folder governs and is edited in FHEMWEB. |

Hidden options appear behind **Show unused optional configuration options**
in the Configuration tab.

## Where the configuration lives

The app's config folder is mounted at `/opt/fhem` inside the container. On the
host you find it at **`/addon_configs/<repo>_fhem`** (shown as
`app_configs/<repo>_fhem` in the Samba/SSH/VS Code apps). Everything FHEM keeps
lives there: `fhem.cfg`, `FHEM/`, `log/`, `mqtt-connection.cfg`, `web-auth.cfg`,
… — all of it is persistent and part of Home Assistant backups.

`/run.sh` generates two snippets in that folder on every start:
**`mqtt-connection.cfg`** with a ready-made `define mqtt MQTT2_CLIENT ...` line
(broker credentials from the Supervisor service; credentials must not contain
whitespace) and **`web-auth.cfg`** with the FHEMWEB login/editor settings from
the app options. The app makes sure `fhem.cfg` includes `web-auth.cfg`; include
`mqtt-connection.cfg` yourself (or copy the lines into your own definitions).

## Editing the configuration

The comfortable default — **no extra tools**:

1. Set `web_auth_user`/`web_auth_password` (the login) and restart once. This
   also enables the configuration editor in FHEMWEB.
2. Open **Web UI** → *Edit files* → `fhem.cfg` → edit → **Save**.
   Saving the config file re-reads it immediately (FHEMWEB runs `rereadcfg`
   automatically) — no restart needed.

The editor is never exposed without a login.

Alternatives for power users:

- **VS Code or Samba app** on the `..._fhem` folder under `addon_configs`
  (also for editing included files and custom Perl modules). Note: the
  built-in *File editor* app only shows Home Assistant's own `/config`, not
  app configuration folders.
- **`fhem_cfg` option (advanced):** paste the complete config into the option
  (*Edit in YAML* in the Configuration tab) and the app keeps `fhem.cfg` in
  sync with it. Handy for keeping the config in a versioned options backup;
  awkward for large pastes (YAML block scalars need indentation).

FHEM does not watch `fhem.cfg`: changes are picked up when FHEM reads the
config — the FHEMWEB editor does that on Save; for edits made with other
tools, **restart the app** or run `rereadcfg` in FHEMWEB.

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

1. Get your old `fhem.cfg` into the app. Easiest: copy the file (and any
   `99_myUtils.pm`, plus `./log` state you want to keep) into the app config
   folder (`/opt/fhem`), or paste the content into the `fhem_cfg` option
   (advanced, see above). Relative paths (`modpath .`, `./log/...`,
   `statefile ./log/fhem.save`) keep working unchanged — `/opt/fhem` is both
   working directory and persistent volume. Tip for the copy path: do it
   *before* the first start — the seed `fhem.cfg` is only installed when none
   exists.
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
- The app version embeds the pinned FHEM release (e.g. `0.2.2-fhem6.5`), so the
  FHEM version is visible on the app info page. The actually running FHEM
  version may be newer after using FHEM's `update` command — the log shows
  `Featurelevel: <version>` at startup.

## Security notes

- **FHEMWEB has no authentication by default.** Port 8083 is mapped to your
  LAN and anyone there can control your heating. Set `web_auth_user` and
  `web_auth_password` in the app options (generated into `web-auth.cfg`, which
  the app appends to `fhem.cfg` automatically), or unmap the port in the app
  configuration and reach FHEM through other means. The FHEMWEB configuration
  editor is only enabled together with this login.
- The telnet console (port 7072) is disabled by default; enable the port in the
  app configuration if you need it.
- The app requests `homeassistant_api` to read Home Assistant's timezone
  (read-only usage in `run.sh`); the hidden `timezone` option avoids the lookup
  entirely.
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
