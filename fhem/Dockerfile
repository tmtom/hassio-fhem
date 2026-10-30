ARG BUILD_FROM=ghcr.io/fhem/fhem-minimal-docker:5.2.0-bookworm
FROM ${BUILD_FROM}

# Pin the FHEM release baked into the image. It is seeded into the persistent
# /opt/fhem volume on first start only; afterwards FHEM's own `update` command
# maintains the installation inside the volume.
ARG FHEM_VERSION=6.5

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && curl -fsSL "https://fhem.de/fhem-${FHEM_VERSION}.tar.gz" -o /tmp/fhem.tgz \
 && mkdir -p /usr/src/fhem-frozen \
 && tar -xzf /tmp/fhem.tgz -C /usr/src/fhem-frozen --strip-components=1 \
 && rm -f /tmp/fhem.tgz \
 && rm -rf /var/lib/apt/lists/*

# Vendored third-party bits (fhemMAX2HASS 99_myUtils.pm, AGPL-3.0 — keep attribution)
# and the generic seed configuration. See rootfs/usr/src/.
COPY rootfs/ /

# Entrypoint wrapper: options -> seed -> MQTT snippet -> exec /entry.sh start
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Pinned FHEM release this image seeds (surfaced in the log and the version).
ENV FHEM_SEEDED_VERSION=${FHEM_VERSION}

# Health check: probe FHEMWEB directly. The base image's /health-check.sh needs
# FHEM-side DockerHealthCheck attributes and stays permanently unhealthy with
# stock/ported configs — which also kept the app in "starting" for minutes in
# the HA UI (the Supervisor resolves app state via container health). The tight
# interval makes the app flip to "started" soon after FHEM is up.
# Healthy when FHEMWEB answers — with web auth configured, a 401 proves both
# FHEMWEB and the login are up (curl -f would treat it as a failure).
# Short interval so the "running" state in the UI flips quickly.
HEALTHCHECK --interval=3s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -sS -o /dev/null --max-time 8 -w '%{http_code}' http://localhost:8083/fhem | grep -qE '^(200|401)$' || exit 1

# HA OS dialout group GID fix (from ZwergNase/KastB addon-fhem): the device nodes
# mapped into the container are group-owned by GID 18 (dialout on HA OS), so the
# `fhem` user can open the NanoCUL after entry.sh adds it to the dialout group.
RUN sed -i "s/^dialout\:.*/dialout\:x\:18/" /etc/group

# The base image's entrypoint (/entry.sh) is FHEM's supervisor: we wrap it with
# /run.sh which seeds the volume, generates the MQTT snippet, then execs it.
ENTRYPOINT ["/run.sh"]
CMD ["start"]
