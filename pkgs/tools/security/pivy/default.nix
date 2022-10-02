{ stdenv, lib, fetchurl, autoPatchelfHook, dpkg, cryptsetup, json_c, libbsd, libedit, pam, pcsclite, pkg-config, zlib }:
stdenv.mkDerivation rec {
  pname = "pivy";
  version = "0.10.0";

  src = fetchurl {
    url = "https://github.com/arekinath/pivy/releases/download/v${version}/pivy_${version}-1_amd64_ubuntu2004.deb";
    sha256 = "sha256-p8yK/uyFGG4mB8hNWxZDjgFVJ0NTZkXVrwQioyrVoBI=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
  ];

  buildInputs = [
    cryptsetup
    libbsd
    pam
    pcsclite
    zlib
  ];

  autoPatchelfIgnoreMissingDeps = [
    "libedit.so.2"
    "libjson-c.so.4"
  ];

  unpackPhase = "dpkg-deb -x $src .";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp -R lib usr $out/
    # symlink binaries to bin/
    ln -s $out/usr/bin/pivy-agent $out/bin/pivy-agent
    ln -s $out/usr/bin/pivy-box $out/bin/pivy-box
    ln -s $out/usr/bin/pivy-ca $out/bin/pivy-ca
    ln -s $out/usr/bin/pivy-luks $out/bin/pivy-luks
    ln -s $out/usr/bin/pivy-tool $out/bin/pivy-tool
  '';

  meta = with lib; {
    homepage = https://github.com/arekinath/pivy;
    description = "Tools for using PIV tokens (like Yubikeys) as an SSH agent, for encrypting data at rest, and more";
    license = licenses.mpl20;
    platforms = platforms.linux;
    maintainers = [ "teutat3s" ];
  };
}
