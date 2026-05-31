{
  lib,
  stdenv,
  autoconf,
  automake,
  gnum4,
  gnumake,
  libtool,
  src,
  version ? "unstable-local",

  # One of "KOBO", "LINUX", "KINDLE", "KINDLE_LEGACY", "CERVANTES",
  # "REMARKABLE", or "POCKETBOOK".
  device ? "KOBO",

  buildShared ? true,
  buildStatic ? false,
}:
let
  validDevices = [
    "KOBO"
    "LINUX"
    "KINDLE"
    "KINDLE_LEGACY"
    "CERVANTES"
    "REMARKABLE"
    "POCKETBOOK"
  ];
  isLegacyKindle = device == "KINDLE_LEGACY";
  deviceFlag = if isLegacyKindle then "KINDLE" else device;
in
assert lib.assertMsg (builtins.elem device validDevices)
  "fbink: device must be one of ${lib.concatStringsSep ", " validDevices}";
assert lib.assertMsg (
  buildShared || buildStatic
) "fbink: at least one of buildShared/buildStatic must be true";
stdenv.mkDerivation {
  pname = "fbink";
  inherit version src;

  strictDeps = true;

  nativeBuildInputs = [
    autoconf
    automake
    gnum4
    gnumake
    libtool
  ];

  makeFlags = [
    "${deviceFlag}=1"
    "FBINK_VERSION=${version}"
  ]
  ++ lib.optional isLegacyKindle "LEGACY=1";

  dontConfigure = true;
  buildFlags = lib.optionals buildShared [ "sharedlib" ] ++ lib.optionals buildStatic [ "staticlib" ];
  enableParallelBuilding = true;

  postUnpack = ''
    chmod -R u+w "$sourceRoot"
    rm -rf "$sourceRoot/Release"
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 fbink.h "$out/include/fbink/fbink.h"
    install -Dm644 CLI.md "$out/share/doc/fbink/CLI.md"

    mkdir -p "$out/lib"
    if [ -e Release/libfbink.so ]; then
      cp -P Release/libfbink.so* "$out/lib/"
    fi
    if [ -e Release/libfbink.a ]; then
      install -Dm644 Release/libfbink.a "$out/lib/libfbink.a"
    fi

    runHook postInstall
  '';

  meta = {
    description = "FrameBuffer eInker library for e-ink Linux framebuffers";
    homepage = "https://github.com/NiLuJe/FBInk";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
