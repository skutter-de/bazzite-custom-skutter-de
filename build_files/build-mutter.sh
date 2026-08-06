#!/bin/bash
# Rebuilds mutter with the Wacom ghost-cursor fix (patches/mutter-wacom-ghost-cursor.patch)
# applied via the standard RPM Patch0/%autopatch mechanism, against whatever
# mutter version this image's Fedora repos currently provide.
# Runs in the builder stage. Leaves mutter+mutter-common (for the final image)
# and mutter-devel (needed by build-gnome-rounded-blur.sh, same stage) installed.
set -ouex pipefail

WORKDIR="$(mktemp -d)"
cd "${WORKDIR}"

dnf5 install -y rpm-build 'dnf5-command(builddep)' 'dnf5-command(download)'

dnf5 download --source -y mutter
rpm -i --define "_topdir ${WORKDIR}/rpmbuild" ./mutter-*.src.rpm

SPEC="${WORKDIR}/rpmbuild/SPECS/mutter.spec"
cp /ctx/patches/mutter-wacom-ghost-cursor.patch "${WORKDIR}/rpmbuild/SOURCES/"

# Add our patch after Source0 and bump the release so this build is always
# considered newer than the stock package it replaces.
sed -i '/^Source0:/a Patch0:         mutter-wacom-ghost-cursor.patch' "${SPEC}"
sed -i 's/^\(Release:[[:space:]]*\)\(.*\)$/\1\2.ghostcursorfix/' "${SPEC}"

dnf5 builddep -y "${SPEC}"
rpmbuild -bb --define "_topdir ${WORKDIR}/rpmbuild" --nocheck "${SPEC}"

RPMDIR="${WORKDIR}/rpmbuild/RPMS/x86_64"
mkdir -p /rpms
cp "${RPMDIR}"/mutter-[0-9]*.rpm "${RPMDIR}"/mutter-common-*.rpm /rpms/
# mutter-devel is needed later in this same builder stage (gnome-rounded-blur),
# but must not end up in the final image, so install it here rather than
# copying it to /rpms.
dnf5 install -y "${RPMDIR}"/mutter-[0-9]*.rpm "${RPMDIR}"/mutter-common-*.rpm "${RPMDIR}"/mutter-devel-*.rpm

rm -rf "${WORKDIR}"
