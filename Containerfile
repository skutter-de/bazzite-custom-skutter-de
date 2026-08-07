# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image
FROM ghcr.io/ublue-os/bazzite-gnome:stable AS base

### BUILDER
## Builds everything that needs compiling against this image's own package
## versions (patched mutter, gnome-rounded-blur, signed acpi_call kernel
## module). None of the build tools used here end up in the final image -
## only the resulting RPMs, copied out of /rpms below.

FROM base AS builder

# All three build scripts run in a single RUN/layer on purpose: splitting
# them across layer boundaries repeatedly hit real RPM-database corruption
# on the build runner ("rpmdb: damaged header", "database disk image is
# malformed") once a layer with heavy package activity got snapshotted and
# the next RUN step started from it. Keeping everything in one layer avoids
# that boundary entirely.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=mok_key \
    --mount=type=secret,id=mok_key_passphrase \
    --mount=type=secret,id=mok_pub \
    /ctx/build-mutter.sh && /ctx/build-gnome-rounded-blur.sh && /ctx/build-acpi_call.sh

### FINAL IMAGE
## Installs the RPMs built above plus everything else, as recommended by
## the template.

FROM base

COPY --from=builder /rpms /rpms

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    rm -rf /rpms

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
