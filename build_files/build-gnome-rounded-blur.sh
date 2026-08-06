#!/bin/bash
# Builds gnome-rounded-blur.rpm against this image's own (patched) mutter,
# so the "Blur my Shell" extension can support rounded-corner blur.
# Runs in the builder stage, after build-mutter.sh has installed the
# patched mutter + mutter-devel into this stage.
set -ouex pipefail

VERSION="1.0.1"
WORKDIR="$(mktemp -d)"

dnf5 install -y meson ninja-build gcc gobject-introspection-devel

git clone --depth 1 --branch "v${VERSION}" \
    https://github.com/kancko/gnome-rounded-blur.git "${WORKDIR}/src"

mkdir -p "${WORKDIR}/SOURCES"
git -C "${WORKDIR}/src" archive --format=tar.gz \
    --prefix="gnome-rounded-blur-${VERSION}/" "v${VERSION}" \
    -o "${WORKDIR}/SOURCES/gnome-rounded-blur-${VERSION}.tar.gz"

mkdir -p /rpms
rpmbuild -bb \
    --define "_sourcedir ${WORKDIR}/SOURCES" \
    --define "_rpmdir /rpms" \
    /ctx/specs/gnome-rounded-blur.spec

rm -rf "${WORKDIR}"
