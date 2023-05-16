FROM nginx:alpine

MAINTAINER Gissehel <public-docker-local-dev-dl-maintainer@gissehel.org>

ARG BUILD_DATE
ARG VCS_REF

LABEL \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.authors="gissehel" \
      org.opencontainers.image.url="https://github.com/gissehel/locattps" \
      org.opencontainers.image.source="https://github.com/gissehel/locattps" \
      org.opencontainers.image.version="1.0.0-${VCS_REF}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.vendor="gissehel" \
      org.opencontainers.image.ref.name="locattps" \
      org.opencontainers.image.title="locattps" \
      org.opencontainers.image.description="A nginx based proxy server for local test of https apps" \
      org.label-schema.build-date="${BUILD_DATE}" \
      org.label-schema.vcs-ref="${VCS_REF}" \
      org.label-schema.name="locattps" \
      org.label-schema.version="1.0.0-${VCS_REF}" \
      org.label-schema.vendor="gissehel" \
      org.label-schema.vcs-url="https://github.com/gissehel/locattps" \
      org.label-schema.schema-version="1.0"

COPY create-image-script.sh /tmp/create-image-script.sh
COPY --chmod=755 on-start-locattps.sh /docker-entrypoint.d/05-on-start-locattps.sh
RUN /bin/sh /tmp/create-image-script.sh && rm -f /tmp/create-image-script.sh
