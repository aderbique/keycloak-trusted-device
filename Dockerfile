# syntax=docker/dockerfile:1.6

ARG KEYCLOAK_VERSION=26.3
ARG KEYCLOAK_IMAGE=quay.io/keycloak/keycloak

############################
# Stage 1: Build (bake provider)
############################
FROM ${KEYCLOAK_IMAGE}:${KEYCLOAK_VERSION} AS builder

ENV KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true

# build.sh places this file next to the Dockerfile
ARG PROVIDER_JAR=keycloak-spi-trusted-device.jar
COPY ${PROVIDER_JAR} /opt/keycloak/providers/

# Build-time flags ONLY (no --log-level here)
# token-exchange is enabled by default in 26.2+, so not required to list
RUN /opt/keycloak/bin/kc.sh build \
    --db=postgres \
    --features-disabled=preview

############################
# Stage 2: Runtime
############################
FROM ${KEYCLOAK_IMAGE}:${KEYCLOAK_VERSION}

ENV KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75"

COPY --from=builder /opt/keycloak/ /opt/keycloak/
USER 1000

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
# Set log level at RUNTIME if you want (this is where --log-level belongs)
CMD ["start", "--optimized", "--log=console", "--log-level=info"]

