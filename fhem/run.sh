#!/usr/bin/env bash
#
# /run.sh — Home Assistant app entrypoint wrapper for FHEM.
#
# Responsibilities (in order):
#   1. Read the Supervisor options from /data/options.json (Perl JSON::PP, core).
#   2. On first start, seed the pinned FHEM tree and the generic seed config
#      into the persistent /opt/fhem volume (the app_config mount).
#   3. Materialize /opt/fhem/fhem.cfg from the fhem_cfg option when set
#      (Configure tab = source of truth; otherwise the file itself governs).
#   4. Generate /opt/fhem/mqtt-connection.cfg with broker credentials from the
#      Supervisor services API (mqtt:want), falling back to the manual options.
#   5. Generate /opt/fhem/web-auth.cfg (FHEMWEB basicAuth / editConfig).
#   6. Optionally install the vendored fhemMAX2HASS 99_myUtils.pm.
#   7. Hand over to the FHEM image's supervisor: exec /entry.sh start.
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

#-----------------------------------------------------------------------------
# 2b. Configuration source of truth: the fhem_cfg option (Configure tab).
#     When set, fhem.cfg is derived state and is materialized from the option
#     on every start (write-on-change). When empty, the file itself governs and
#     content is never overwritten (the behavior of app versions <= 0.1.x).
#     Either way the generated web-auth.cfg include is appended when missing —
#     otherwise web auth / editConfig silently do nothing.
#-----------------------------------------------------------------------------
FHEM_CFG_OPT="$(opt fhem_cfg '')"
CFG_CANDIDATE=/tmp/fhem.cfg.candidate
if [ -n "${FHEM_CFG_OPT}" ]; then
  printf '%s\n' "${FHEM_CFG_OPT}" | tr -d '\r' > "${CFG_CANDIDATE}"
  CFG_MODE="option"
else
  cp "${FHEM_DIR}/fhem.cfg" "${CFG_CANDIDATE}"
  CFG_MODE="file"
fi
if ! grep -qE '^[[:space:]]*include[[:space:]]+web-auth\.cfg[[:space:]]*$' "${CFG_CANDIDATE}"; then
  printf '\ninclude web-auth.cfg\n' >> "${CFG_CANDIDATE}"
  CFG_APPENDED=1
fi
if cmp -s "${CFG_CANDIDATE}" "${FHEM_DIR}/fhem.cfg"; then
  [ "${CFG_MODE}" = "option" ] && log "fhem.cfg already matches the fhem_cfg option"
else
  cp "${CFG_CANDIDATE}" "${FHEM_DIR}/fhem.cfg"
  if [ "${CFG_MODE}" = "option" ]; then
    log "fhem.cfg materialized from the fhem_cfg option ($(wc -c < "${FHEM_DIR}/fhem.cfg" | tr -d ' ') bytes, md5 $(md5sum "${FHEM_DIR}/fhem.cfg" | cut -c1-8))"
  else
    log "appended 'include web-auth.cfg' to fhem.cfg (loads the generated web-auth.cfg)"
  fi
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
# Note: MQTT2_CLIENT takes credentials via 'attr mqtt username' and
# 'set mqtt password' (stored in FHEM/FhemUtils/uniqueID), not as define
# arguments. Passwords must not contain whitespace.

define mqtt MQTT2_CLIENT ${MQTT_HOST}:${MQTT_PORT}
EOF
  if [ -n "${MQTT_USER}" ]; then
    cat >> "${FHEM_DIR}/mqtt-connection.cfg" <<EOF
attr mqtt username ${MQTT_USER}
set mqtt password ${MQTT_PASS}
EOF
  fi
  cat >> "${FHEM_DIR}/mqtt-connection.cfg" <<EOF
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
#
# (MQTT2_CLIENT takes credentials via 'attr mqtt username' and
#  'set mqtt password', not as define arguments.)

#define mqtt MQTT2_CLIENT host:port
#attr mqtt username user
#set mqtt password password
#attr mqtt lwt homeassistant/binary_sensor/fhem/availability offline
#attr mqtt lwtRetain 1
#attr mqtt msgAfterConnect -r homeassistant/binary_sensor/fhem/availability online
#attr mqtt msgBeforeDisconnect -r homeassistant/binary_sensor/fhem/availability offline
EOF
fi

#-----------------------------------------------------------------------------
# 4. FHEMWEB auth / config-editing snippet (rewritten on every start).
#    FHEM 6.x has no 'attr WEB basicAuth' — authentication is done by an
#    'allowed' device bound to the FHEMWEB instance via validFor. Credentials
#    stay out of the user's fhem.cfg; it needs an `include web-auth.cfg` after
#    its WEB definition (the seed has it; configs materialized from fhem_cfg
#    get it appended automatically).
#-----------------------------------------------------------------------------
WEB_AUTH_USER="$(opt web_auth_user '')"
WEB_AUTH_PASS="$(opt web_auth_password '')"
# Bind to every FHEMWEB device declared in the config (usually just "WEB").
WEB_VALID_FOR="$(awk '$1=="define" && $3=="FHEMWEB" {print $2}' "${FHEM_DIR}/fhem.cfg" | sort -u | paste -sd, -)"
[ -n "${WEB_VALID_FOR}" ] || WEB_VALID_FOR="WEB"
{
  echo "# Generated by the FHEM app (run.sh) on every start — do not edit."
  echo "# Use it from your fhem.cfg with:  include web-auth.cfg"
  echo "#"
  if [ -n "${WEB_AUTH_USER}" ] && [ -n "${WEB_AUTH_PASS}" ]; then
    # 'set allowed basicAuth user pass' stores a salted SHA256 hash in the
    # attribute. Must not contain whitespace (FHEM set syntax).
    cat <<EOF
define fhemwebAuth allowed
attr fhemwebAuth validFor ${WEB_VALID_FOR}
set fhemwebAuth basicAuth ${WEB_AUTH_USER} ${WEB_AUTH_PASS}
EOF
  else
    echo "# No web auth configured. Set web_auth_user/web_auth_password in the"
    echo "# app options to require a login for FHEMWEB."
  fi
  if [ "$(opt web_edit_config false)" = "true" ]; then
    if [ -n "${WEB_AUTH_USER}" ] && [ -n "${WEB_AUTH_PASS}" ]; then
      # Guard: never expose the config editor without a login. With auth in
      # place the editor adds no privilege — a logged-in user could run any
      # FHEM command anyway (including enabling editConfig itself).
      for _dev in $(echo "${WEB_VALID_FOR}" | tr ',' ' '); do
        echo "attr ${_dev} editConfig 1"
      done
    else
      warn "web_edit_config ignored: set web_auth_user/web_auth_password first"
      warn "(editing config on an unauthenticated FHEMWEB would be open to the LAN)."
      echo "#attr WEB editConfig 1   (enable web_auth_user/web_auth_password first)"
    fi
  else
    echo "#attr WEB editConfig 1"
  fi
} > "${FHEM_DIR}/web-auth.cfg"
log "Wrote ${FHEM_DIR}/web-auth.cfg"

#-----------------------------------------------------------------------------
# 5. Vendored fhemMAX2HASS helper (99_myUtils.pm), AGPL-3.0 — only ever touches
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
