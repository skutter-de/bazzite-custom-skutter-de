#!/bin/bash
# Fetches Lenovo's proprietary libmodemauth.so (FCC-unlock challenge-response
# crypto for the Fibocom L860-GL/XMM7560, from Lenovo's own official
# lenovo-wwan-unlock tooling) into the image. Runs in the final stage - no
# build secrets needed, it's a plain download+verify, not something we can
# build from source (no public source for the vendor algorithm exists).
#
# Pinned to a specific tag + sha256 rather than committing the binary to
# this git repo, so provenance/updates stay auditable via this script
# instead of an opaque blob in the git history.
set -ouex pipefail

LENOVO_TAG="v3.1.0"
LENOVO_SHA256="7cd1717dbc3f5d0f50436f9f76758fdf12477e16cfdafb301e67d8b70bf79ca4"
DEST=/usr/libexec/xmm-l860/libmodemauth.so

mkdir -p "$(dirname "${DEST}")"
curl -fsSL \
    "https://raw.githubusercontent.com/lenovo/lenovo-wwan-unlock/${LENOVO_TAG}/libmodemauth.so" \
    -o "${DEST}"

echo "${LENOVO_SHA256}  ${DEST}" | sha256sum -c -
chmod 0644 "${DEST}"
