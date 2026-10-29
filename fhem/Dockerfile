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

# HA OS dialout group GID fix (from ZwergNase/KastB addon-fhem): the device nodes
# mapped into the container are group-owned by GID 18 (dialout on HA OS), so the
# `fhem` user can open the NanoCUL after entry.sh adds it to the dialout group.
RUN sed -i "s/^dialout\:.*/dialout\:x\:18/" /etc/group

# The base image's entrypoint (/entry.sh) is FHEM's supervisor: we wrap it with
# /run.sh which seeds the volume, generates the MQTT snippet, then execs it.
ENTRYPOINT ["/run.sh"]
CMD ["start"]
