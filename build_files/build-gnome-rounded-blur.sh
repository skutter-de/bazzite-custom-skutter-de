#!/bin/bash
# Builds gnome-rounded-blur.rpm against the stock mutter-devel from this
# image's Fedora repos. v1.0.2+ auto-detects the installed libmutter API
# version, so no custom mutter rebuild is needed.
# Runs in the builder stage, in the same RUN step as build-acpi_call.sh
# (see Containerfile).
set -ouex pipefail

VERSION="1.0.2"
WORKDIR="$(mktemp -d)"

dnf5 install -y rpm-build 'dnf5-command(builddep)' 'dnf5-command(config-manager)'

# Bazzite ships mesa from Terra (not stock Fedora repos) and sets
# excludepkgs=mesa* to prevent stock repos from overriding it. mutter-devel
# (a build dep of gnome-rounded-blur) pulls in mesa-*-devel transitively;
# without enabling terra-mesa and clearing the exclude filter, dnf can't
# satisfy those deps. This builder stage is ephemeral - none of these
# changes reach the final image.
dnf5 config-manager setopt terra.enabled=1
dnf5 config-manager setopt terra-mesa.enabled=1
sed -i 's/^excludepkgs=.*//' /etc/dnf/dnf.conf 2>/dev/null || true
dnf5 config-manager setopt "*.excludepkgs=" 2>/dev/null || true

# Bazzite also versionlocks mesa-* packages; clear them so mutter-devel's
# mesa-*-devel transitive deps resolve cleanly. Same for Xwayland.
dnf5 versionlock delete xorg-x11-server-Xwayland 2>/dev/null || true
dnf5 versionlock delete mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm mesa-vulkan-drivers 2>/dev/null || true

dnf5 install -y mutter-devel meson ninja-build gcc gobject-introspection-devel

git clone --depth 1 --branch "v${VERSION}" \
    https://github.com/kancko/gnome-rounded-blur.git "${WORKDIR}/src"

mkdir -p "${WORKDIR}/SOURCES"
git -C "${WORKDIR}/src" archive --format=tar.gz \
    --prefix="gnome-rounded-blur-${VERSION}/" "v${VERSION}" \
    -o "${WORKDIR}/SOURCES/gnome-rounded-blur-${VERSION}.tar.gz"

mkdir -p /rpms "${WORKDIR}/rpmbuild"/{BUILD,BUILDROOT,SPECS,SRPMS}
rpmbuild -bb \
    --define "_topdir ${WORKDIR}/rpmbuild" \
    --define "_sourcedir ${WORKDIR}/SOURCES" \
    --define "_rpmdir /rpms" \
    /ctx/specs/gnome-rounded-blur.spec

rm -rf "${WORKDIR}"
