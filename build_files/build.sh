#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

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

### Enable services

systemctl enable fprintd-lid-watch.service
