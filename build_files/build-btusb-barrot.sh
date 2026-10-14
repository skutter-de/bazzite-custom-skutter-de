#!/bin/bash
# Builds a signed btusb kernel module (Barrot Technology patch) and packages
# it as kmod-btusb-barrot.rpm. Runs in the builder stage only.
# Expects three build secrets to be mounted:
#   /run/secrets/mok_key            - MOK private key (AES256-encrypted PEM)
#   /run/secrets/mok_key_passphrase - passphrase for the above
#   /run/secrets/mok_pub            - matching public cert (DER), already enrolled
set -ouex pipefail

KVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)"
WORKDIR="$(mktemp -d)"

dnf5 install -y kernel-devel-"${KVER}" gcc make

cp -a /ctx/src/btusb-barrot "${WORKDIR}/btusb-barrot"

make -C /usr/src/kernels/"${KVER}" M="${WORKDIR}/btusb-barrot" modules

openssl pkey -in /run/secrets/mok_key -passin file:/run/secrets/mok_key_passphrase \
    -out "${WORKDIR}/mok_key.decrypted"

"/usr/src/kernels/${KVER}/scripts/sign-file" sha256 \
    "${WORKDIR}/mok_key.decrypted" /run/secrets/mok_pub "${WORKDIR}/btusb-barrot/btusb.ko"
shred -u "${WORKDIR}/mok_key.decrypted"

if [ "$(tail -c 28 "${WORKDIR}/btusb-barrot/btusb.ko")" != "~Module signature appended~" ]; then
    echo "btusb.ko is missing its Secure Boot signature after signing, aborting" >&2
    exit 1
fi

cp "${WORKDIR}/btusb-barrot/btusb.ko" "${WORKDIR}/btusb.ko"

mkdir -p /rpms "${WORKDIR}/rpmbuild"/{BUILD,BUILDROOT,SPECS,SRPMS}
rpmbuild -bb \
    --define "_topdir ${WORKDIR}/rpmbuild" \
    --define "_sourcedir ${WORKDIR}" \
    --define "_rpmdir /rpms" \
    --define "kver ${KVER}" \
    /ctx/specs/kmod-btusb-barrot.spec

BUILT_RPM="$(find /rpms -name 'kmod-btusb-barrot-*.rpm' -print -quit)"
EXTRACT_DIR="${WORKDIR}/rpm-extract"
mkdir -p "${EXTRACT_DIR}"
rpm2cpio "${BUILT_RPM}" | (cd "${EXTRACT_DIR}" && cpio -idm --quiet)
EXTRACTED_KO="$(find "${EXTRACT_DIR}" -name 'btusb.ko' -print -quit)"
if [ -z "${EXTRACTED_KO}" ] || [ "$(tail -c 28 "${EXTRACTED_KO}")" != "~Module signature appended~" ]; then
    echo "btusb.ko lost its Secure Boot signature during RPM packaging, aborting" >&2
    exit 1
fi

rm -rf "${WORKDIR}"
