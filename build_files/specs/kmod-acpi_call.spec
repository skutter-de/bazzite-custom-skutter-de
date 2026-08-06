# kver is passed in via `rpmbuild --define "kver <version>"` at build time,
# so this always matches the kernel actually shipped in this image build.
%{!?kver: %define kver %(uname -r)}

Name:           kmod-acpi_call
Version:        1.2.2
Release:        1%{?dist}
Summary:        Prebuilt acpi_call kernel module for %{kver}

License:        GPL-2.0-or-later
URL:            https://github.com/nix-community/acpi_call
Source0:        acpi_call.ko

BuildArch:      x86_64
AutoReqProv:    no

%description
Prebuilt acpi_call.ko for kernel %{kver}, built via DKMS during the image
build and signed for Secure Boot with the image's own MOK key, then
packaged so it can be installed as a normal RPM (rpm-ostree can only write
into /usr as part of a proper package transaction, not via a live
`dkms install`).

%install
mkdir -p %{buildroot}/usr/lib/modules/%{kver}/extra
install -m 0644 %{SOURCE0} %{buildroot}/usr/lib/modules/%{kver}/extra/acpi_call.ko
mkdir -p %{buildroot}/usr/lib/modules-load.d
echo acpi_call > %{buildroot}/usr/lib/modules-load.d/acpi_call.conf

%files
/usr/lib/modules/%{kver}/extra/acpi_call.ko
/usr/lib/modules-load.d/acpi_call.conf

%post
depmod -a %{kver} || true

%postun
depmod -a %{kver} || true
