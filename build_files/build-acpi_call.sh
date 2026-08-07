#!/bin/bash
# Builds a signed acpi_call kernel module and packages it as kmod-acpi_call.rpm.
# Runs in the builder stage only. Expects three build secrets to be mounted:
#   /run/secrets/mok_key            - MOK private key (AES256-encrypted PEM)
#   /run/secrets/mok_key_passphrase - passphrase for the above
#   /run/secrets/mok_pub            - matching public cert (DER), already enrolled
set -ouex pipefail

KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)"
WORKDIR="$(mktemp -d)"

dnf5 install -y dkms kernel-devel-"${KVER}" gcc make

git clone --depth 1 https://github.com/nix-community/acpi_call.git "${WORKDIR}/acpi_call"

dkms add "${WORKDIR}/acpi_call" --sourcetree "${WORKDIR}/dkms-src"
dkms build acpi_call/1.2.2 --sourcetree "${WORKDIR}/dkms-src" -k "${KVER}"

MODULE="$(find /var/lib/dkms/acpi_call/1.2.2/"${KVER}" -name 'acpi_call.ko*' | head -1)"
case "${MODULE}" in
  *.xz) unxz -k -c "${MODULE}" > "${WORKDIR}/acpi_call.ko" ;;
  *)    cp "${MODULE}" "${WORKDIR}/acpi_call.ko" ;;
esac

# sign-file can't take a passphrase itself, so decrypt the key into this
# stage's ephemeral filesystem only (never copied into the final image).
openssl pkey -in /run/secrets/mok_key -passin file:/run/secrets/mok_key_passphrase \
    -out "${WORKDIR}/mok_key.decrypted"

"/usr/src/kernels/${KVER}/scripts/sign-file" sha256 \
    "${WORKDIR}/mok_key.decrypted" /run/secrets/mok_pub "${WORKDIR}/acpi_call.ko"
shred -u "${WORKDIR}/mok_key.decrypted"

mkdir -p /rpms "${WORKDIR}/rpmbuild"/{BUILD,BUILDROOT,SPECS,SRPMS}
rpmbuild -bb \
    --define "_topdir ${WORKDIR}/rpmbuild" \
    --define "_sourcedir ${WORKDIR}" \
    --define "_rpmdir /rpms" \
    --define "kver ${KVER}" \
    /ctx/specs/kmod-acpi_call.spec

rm -rf "${WORKDIR}"
