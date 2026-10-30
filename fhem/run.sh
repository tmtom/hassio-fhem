#!/usr/bin/env bash
#
# /run.sh — Home Assistant app entrypoint wrapper for FHEM.
#
# Responsibilities (in order):
#   1. Read the Supervisor options from /data/options.json (Perl JSON::PP, core).
#   2. On first start, seed the pinned FHEM tree and the generic seed config
#      into the persistent /opt/fhem volume (the app_config mount).
#   3. Generate /opt/fhem/mqtt-connection.cfg with broker credentials from the
#      Supervisor services API (mqtt:want), falling back to the manual options.
#   4. Optionally install the vendored fhemMAX2HASS 99_myUtils.pm.
#   5. Hand over to the FHEM image's supervisor: exec /entry.sh start.
#
set -eu

OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"
FHEM_DIR="/opt/fhem"

log() { printf '[run.sh] %s\n' "$*"; }
warn() { printf '[run.sh] WARNING: %s\n' "$*" >&2; }

# opt <key> <default> — print the option value; booleans print as true/false.
opt() {
  perl -MJSON::PP -e '
    my ($file, $key, $default) = @ARGV;
    open my $fh, "<", $file or do { print $default; exit 0 };
    my $raw = do { local $/; <$fh> };
    my $json = eval { JSON::PP::decode_json($raw) } or do { print $default; exit 0 };
    my $v = $json->{$key};
    if (!defined $v) { print $default; exit 0; }
    if (ref $v eq "JSON::PP::Boolean") { print $v ? "true" : "false"; exit 0; }
    print $v;
  ' "$OPTIONS_FILE" "$1" "$2"
}

export TZ="$(opt timezone Europe/Prague)"
log "Timezone: ${TZ}"
log "Pinned FHEM version (image seed for new installs): ${FHEM_SEEDED_VERSION:-unknown}"

mkdir -p "${FHEM_DIR}"

# Fingerprint of the configuration for the log — makes "who overwrote my
# fhem.cfg?" answerable from the app log alone.
if [ -f "${FHEM_DIR}/fhem.cfg" ]; then
  log "fhem.cfg present ($(wc -c < "${FHEM_DIR}/fhem.cfg" | tr -d ' ') bytes, md5 $(md5sum "${FHEM_DIR}/fhem.cfg" | cut -c1-8))"
else
  log "fhem.cfg NOT present in ${FHEM_DIR} at startup"
fi

# Install the generic seed configuration — but prefer restoring a previous
# configuration (the FHEM image keeps fhem.cfg.bak on every start) so a user
# config is never replaced by the seed just because the file went missing.
install_seed_cfg() {
  if [ -f "${FHEM_DIR}/fhem.cfg.bak" ]; then
    log "fhem.cfg missing but fhem.cfg.bak found — restoring the backup instead of installing the seed"
    cp -f "${FHEM_DIR}/fhem.cfg.bak" "${FHEM_DIR}/fhem.cfg"
  else
    log "No fhem.cfg found: installing generic seed configuration"
    cp /usr/src/templates/fhem.cfg.seed "${FHEM_DIR}/fhem.cfg"
  fi
}

#-----------------------------------------------------------------------------
# 2. First-start seeding of the pinned FHEM tree and the generic configuration.
#    Seeding fhem.pl up front makes /entry.sh skip its unpinned svn export.
#-----------------------------------------------------------------------------
if [ ! -f "${FHEM_DIR}/fhem.pl" ]; then
  log "First start: seeding pinned FHEM into ${FHEM_DIR}"
  # Remember a config the user placed in the volume before the first start;
  # the frozen tree itself carries FHEM's stock fhem.cfg which is replaced by
  # our generic seed below. -n: never overwrite user files.
  USER_CFG_PRESENT=0
  [ -f "${FHEM_DIR}/fhem.cfg" ] && USER_CFG_PRESENT=1
  cp -an /usr/src/fhem-frozen/. "${FHEM_DIR}/"
  if [ "${USER_CFG_PRESENT}" = 0 ]; then
    install_seed_cfg
  fi
elif [ ! -f "${FHEM_DIR}/fhem.cfg" ]; then
  install_seed_cfg
fi

if [ -d "${FHEM_DIR}/FHEM" ] && [ ! -f "${FHEM_DIR}/FHEM/controls.txt" ]; then
  # FHEM update mechanism (same pointer /entry.sh writes on a clean install).
  echo 'http://fhem.de/fhemupdate/controls_fhem.txt' > "${FHEM_DIR}/FHEM/controls.txt"
fi

# Make /entry.sh tail the log file FHEM actually writes to (it streams the FHEM
# log to the app's log tab in HA). entry.sh would otherwise always follow its
# built-in daily default, which breaks ported configs that log monthly.
CFG_LOGFILE="$(sed -n 's/^attr global logfile \([^\r\n]*\)[[:space:]]*$/\1/p' "${FHEM_DIR}/fhem.cfg" | head -1)"
if [ -n "${CFG_LOGFILE}" ]; then
  export LOGFILE="${CFG_LOGFILE}"
fi

#-----------------------------------------------------------------------------
# 3. MQTT connection snippet (rewritten on every start).
#-----------------------------------------------------------------------------
MQTT_HOST=""
MQTT_PORT=""
MQTT_USER=""
MQTT_PASS=""

if [ "$(opt mqtt_automatic true)" = "true" ] && [ -n "${SUPERVISOR_TOKEN:-}" ]; then
  if curl -fsS -m 10 -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
       "http://supervisor/services/mqtt" -o /tmp/mqtt-service.json 2>/dev/null; then
    eval "$(perl -MJSON::PP -e '
      my ($file) = @ARGV;
      open my $fh, "<", $file or exit 0;
      my $raw = do { local $/; <$fh> };
      my $json = eval { JSON::PP::decode_json($raw) } or exit 0;
      # The Supervisor API wraps payloads in {"result": ..., "data": {...}};
      # accept a flat object as well.
      $json = $json->{data} if ref $json eq "HASH" && ref $json->{data} eq "HASH";
      ref $json eq "HASH" or exit 0;
      my %map = (MQTT_HOST => "host", MQTT_PORT => "port",
                 MQTT_USER => "username", MQTT_PASS => "password");
      for my $var (sort keys %map) {
        my $v = $json->{ $map{$var} };
        next unless defined $v && !ref $v;
        $v =~ s/'"'"'/\\'"'"'/g;
        print "$var='"'"'$v'"'"'\n";
      }
    ' /tmp/mqtt-service.json)"
    if [ -n "${MQTT_HOST}" ]; then
      log "MQTT broker discovered via Supervisor services API (${MQTT_HOST}:${MQTT_PORT})"
    else
      log "Supervisor MQTT service returned no usable host — using manual mqtt_* options"
    fi
  else
    log "Supervisor MQTT service unavailable — using manual mqtt_* options"
  fi
fi

# Manual options fill in whatever is still missing (complete fallback when
# mqtt_automatic is false or the API is unreachable).
[ -n "${MQTT_HOST}" ] || MQTT_HOST="$(opt mqtt_host '')"
[ -n "${MQTT_PORT}" ] || MQTT_PORT="$(opt mqtt_port 1883)"
[ -n "${MQTT_USER}" ] || MQTT_USER="$(opt mqtt_user '')"
[ -n "${MQTT_PASS}" ] || MQTT_PASS="$(opt mqtt_password '')"

if [ -n "${MQTT_HOST}" ]; then
  cat > "${FHEM_DIR}/mqtt-connection.cfg" <<EOF
# Generated by the FHEM app (run.sh) on every start — do not edit.
# Use it from your fhem.cfg with:  include mqtt-connection.cfg
# (or copy the lines below into your own mqtt device definition).
#
# Note: MQTT credentials must not contain whitespace.

define mqtt MQTT2_CLIENT ${MQTT_HOST}:${MQTT_PORT} ${MQTT_USER} ${MQTT_PASS}
attr mqtt lwt homeassistant/binary_sensor/fhem/availability offline
attr mqtt lwtRetain 1
attr mqtt msgAfterConnect -r homeassistant/binary_sensor/fhem/availability online
attr mqtt msgBeforeDisconnect -r homeassistant/binary_sensor/fhem/availability offline
EOF
  log "Wrote ${FHEM_DIR}/mqtt-connection.cfg"
else
  warn "No MQTT broker configured (no Supervisor service, mqtt_host empty)."
  warn "Wrote a commented template to ${FHEM_DIR}/mqtt-connection.cfg."
  cat > "${FHEM_DIR}/mqtt-connection.cfg" <<EOF
# Generated by the FHEM app (run.sh) on every start — do not edit.
# No MQTT broker was configured at startup. Set the manual mqtt_* options or
# install an MQTT broker app (e.g. Mosquitto) offering the mqtt service, then
# uncomment and adapt the following lines:

#define mqtt MQTT2_CLIENT host:port user password
#attr mqtt lwt homeassistant/binary_sensor/fhem/availability offline
#attr mqtt lwtRetain 1
#attr mqtt msgAfterConnect -r homeassistant/binary_sensor/fhem/availability online
#attr mqtt msgBeforeDisconnect -r homeassistant/binary_sensor/fhem/availability offline
EOF
fi

#-----------------------------------------------------------------------------
# 4. Vendored fhemMAX2HASS helper (99_myUtils.pm), AGPL-3.0 — only ever touches
#    a file it generated itself (marker); a user's own 99_myUtils.pm is kept.
#-----------------------------------------------------------------------------
UTILS_SRC="/usr/src/99_myUtils.pm"
UTILS_DST="${FHEM_DIR}/FHEM/99_myUtils.pm"
UTILS_MARKER="Vendored from fhemMAX2HASS"

if [ "$(opt fhemmax2hass true)" = "true" ]; then
  if [ ! -e "${UTILS_DST}" ] || grep -q "${UTILS_MARKER}" "${UTILS_DST}"; then
    FHEM_URL="$(opt fhem_url 'http://homeassistant.local:8083/fhem')"
    export FHEM_URL
    perl -pe 's/\{\{FHEM_URL\}\}/$ENV{FHEM_URL}/g' "${UTILS_SRC}" > /tmp/99_myUtils.pm.gen
    if ! cmp -s /tmp/99_myUtils.pm.gen "${UTILS_DST}"; then
      cp /tmp/99_myUtils.pm.gen "${UTILS_DST}"
      log "Installed vendored fhemMAX2HASS 99_myUtils.pm (fhem_url=${FHEM_URL})"
    fi
  else
    log "Existing FHEM/99_myUtils.pm is not managed by this app — leaving it untouched"
  fi
fi

#-----------------------------------------------------------------------------
# Startup hints for porting (the CUL device path is the classic pain point).
#-----------------------------------------------------------------------------
DEVICE="$(opt device '')"
if [ -n "${DEVICE}" ]; then
  log "Serial device option: ${DEVICE}"
fi
if [ -d /dev/serial/by-id ]; then
  log "Serial devices visible in this container:"
  ls -1 /dev/serial/by-id 2>/dev/null | sed 's|^|  /dev/serial/by-id/|'
fi

log "Handing over to FHEM (/entry.sh start)"
exec /entry.sh start
