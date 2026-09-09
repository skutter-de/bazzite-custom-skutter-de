#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# Lenovo's proprietary libmodemauth.so (FCC-unlock for the L860-GL WWAN
# modem) - downloaded+verified here rather than committed to this repo,
# see the script for why.
/ctx/fetch-libmodemauth.sh

### Install packages

dnf5 install -y libvirt qemu-kvm virt-viewer gtk4-layer-shell

# Wacom ghost-cursor fix (patched mutter/mutter-common), gnome-rounded-blur
# (for Blur my Shell's rounded-corner support) and the signed acpi_call
# kernel module were all built in the builder stage; install the results.
# rpmbuild's --define "_rpmdir /rpms" (used by gnome-rounded-blur and
# kmod-acpi_call) always creates an arch subdirectory under it, unlike
# build-mutter.sh's flat `cp ... /rpms/`, so a plain /rpms/*.rpm glob misses
# them - find every *.rpm anywhere under /rpms instead.
dnf5 install -y $(find /rpms -name '*.rpm' ! -name '*-debuginfo-*' ! -name '*-debugsource-*')

# The base image ships terra-mesa enabled by default (for its own mesa
# packages, already installed above - nothing here still needs it fetched
# again). Leaving it enabled in the shipped image breaks bootc-image-builder's
# ISO manifest depsolve: it fails to read the repo's local file://
# gpgkey from within its own build sandbox ("Could not read a file:// file
# for .../RPM-GPG-KEY-terra44-mesa"), even though that key is present and
# correct in the actual running system. Switch it back off now that we're
# done with it - doesn't affect already-installed packages, next image
# build re-enables+uses it fresh from the base image regardless.
#
# `dnf5 config-manager setopt terra-mesa.enabled=0` does NOT persist this
# to the repo file (verified: enabled=1 was still there in the shipped
# image after using it) - it only affects dnf5's own runtime view, which
# bootc-image-builder's separate depsolve process never reads anyway.
# Edit the repo file directly instead.
sed -i '0,/^enabled=1$/{s/^enabled=1$/enabled=0/}' /etc/yum.repos.d/terra-mesa.repo
grep -A10 '^\[terra-mesa\]$' /etc/yum.repos.d/terra-mesa.repo | grep -m1 '^enabled=0$' || \
    { echo "terra-mesa.repo: enabled=0 did not take, aborting" >&2; exit 1; }

### Enable services

systemctl enable fprintd-lid-watch.service
