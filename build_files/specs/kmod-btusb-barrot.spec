# kver is passed in via `rpmbuild --define "kver <version>"` at build time.
%{!?kver: %define kver %(uname -r)}

# Disable post-install stripping — it would remove the Secure Boot signature
# appended past the ELF sections, turning this into an unsigned module.
%global __os_install_post %{nil}

Name:           kmod-btusb-barrot
Version:        1.0
Release:        1%{?dist}
Summary:        Patched btusb kernel module for Barrot Technology BT adapters

License:        GPL-2.0-only
URL:            https://github.com/skutter-de/bazzite-custom-skutter-de
Source0:        btusb.ko

BuildArch:      x86_64
AutoReqProv:    no

%description
Patched btusb.ko for kernel %{kver} with Barrot Technology chip support
(UGREEN SKU 45134, VID 33fa:0010). Intercepts LE extended scan disable,
forces Filter Duplicates off, and fake-succeeds Accept/Resolv list commands
while the chip is scanning to prevent EBUSY crash loops.

Installed to extra/ so depmod search order (updates > extra > built-in)
gives it priority over the stock btusb.ko without file conflicts.

%install
mkdir -p %{buildroot}/usr/lib/modules/%{kver}/extra
install -m 0644 %{SOURCE0} %{buildroot}/usr/lib/modules/%{kver}/extra/btusb.ko

%files
/usr/lib/modules/%{kver}/extra/btusb.ko

%post
depmod -a %{kver} || true

%postun
depmod -a %{kver} || true
