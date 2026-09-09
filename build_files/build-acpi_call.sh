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

# dkms add needs a real dkms.conf (module name + version) to know what it's
# adding; the repo only ships a dkms.conf.in template with the version
# substituted in by its own Makefile's `dkms-add` target at build time.
sed "s/@@VERSION@@/$(cat "${WORKDIR}/acpi_call/VERSION")/" \
    "${WORKDIR}/acpi_call/dkms.conf.in" > "${WORKDIR}/acpi_call/dkms.conf"

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

# Fail the build loudly here rather than shipping an unsigned module that
# only surfaces as "Key was rejected by service" at load time on a user's
# machine. A signed module has "~Module signature appended~" as its last 28
# bytes.
if [ "$(tail -c 28 "${WORKDIR}/acpi_call.ko")" != "~Module signature appended~" ]; then
    echo "acpi_call.ko is missing its Secure Boot signature after signing, aborting" >&2
    exit 1
fi

mkdir -p /rpms "${WORKDIR}/rpmbuild"/{BUILD,BUILDROOT,SPECS,SRPMS}
rpmbuild -bb \
    --define "_topdir ${WORKDIR}/rpmbuild" \
    --define "_sourcedir ${WORKDIR}" \
    --define "_rpmdir /rpms" \
    --define "kver ${KVER}" \
    /ctx/specs/kmod-acpi_call.spec

# Same check against the file the RPM actually packaged - catches the
# rpmbuild-strips-the-signature failure mode this used to have, not just a
# broken sign-file step. rpmbuild nests BUILDROOT under BUILD/<pkg>-build/,
# not directly under _topdir, so locate it instead of assuming the layout.
PACKAGED_KO="$(find "${WORKDIR}/rpmbuild/BUILD" -path '*/BUILDROOT/*/extra/acpi_call.ko' -print -quit)"
if [ -z "${PACKAGED_KO}" ] || [ "$(tail -c 28 "${PACKAGED_KO}")" != "~Module signature appended~" ]; then
    echo "acpi_call.ko lost its Secure Boot signature during RPM packaging, aborting" >&2
    exit 1
fi

rm -rf "${WORKDIR}"
