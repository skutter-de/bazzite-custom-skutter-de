Name:           gnome-rounded-blur
Version:        1.0.1
Release:        1%{?dist}
Summary:        Standalone library providing Blur.BlurEffect with corner radius support for GNOME Shell extensions

License:        GPL-3.0-or-later
URL:             https://github.com/kancko/gnome-rounded-blur
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconfig(glib-2.0) >= 2.66
BuildRequires:  pkgconfig(gobject-2.0) >= 2.66
BuildRequires:  pkgconfig(mutter-clutter-18)
BuildRequires:  pkgconfig(mutter-cogl-18)
BuildRequires:  pkgconfig(libmutter-18)
BuildRequires:  gobject-introspection-devel

Requires:       mutter%{?_isa}

%description
GNOME Rounded Blur is a standalone library providing Blur.BlurEffect with
corner radius support for GNOME Shell extensions. It's essentially a copy of
GNOME Shell's own ShellBlurEffect with a corner mask and a different GIR
namespace (Blur). Used by the "Blur my Shell" GNOME Shell extension to
support rounded corners on blurred surfaces.

Built against libmutter API version 18 (mutter >= 50.0). Needs to be rebuilt
whenever the mutter/GNOME Shell ABI changes.

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install

%files
%license LICENSE
%{_libdir}/libblur-effect-1.0.so*
%{_libdir}/pkgconfig/blur-effect-1.0.pc
%{_libdir}/girepository-1.0/Blur-1.0.typelib
%{_datadir}/gir-1.0/Blur-1.0.gir
%{_includedir}/blur-effect-1.0/

%changelog
%autochangelog
