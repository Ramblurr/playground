{
  stdenv,
  janet,
  src,
  koboInstallPath ? "/mnt/onboard/janet-eink-demo/janet",
  version ? "1.2.0",
}:

stdenv.mkDerivation {
  pname = "spork-netrepl";
  inherit version src;

  strictDeps = true;

  buildInputs = [ janet ];

  buildPhase = ''
    runHook preBuild

    $CC -std=c99 -Wall -Wextra -O2 -fPIC \
      -I ${janet}/include \
      -shared -o rawterm.so \
      src/rawterm.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/janet/spork"

    for module in \
      argparse \
      ev-utils \
      generators \
      getline \
      msg \
      netrepl; do
      install -Dm644 "spork/$module.janet" "$out/share/janet/spork/$module.janet"
    done

    install -Dm755 rawterm.so "$out/share/janet/spork/rawterm.so"

    install -Dm755 bin/janet-netrepl "$out/bin/janet-netrepl"
    substituteInPlace "$out/bin/janet-netrepl" \
      --replace-fail '#!/usr/bin/env janet' '#!${koboInstallPath}/bin/janet'
    sed -i '2i(put root-env :syspath "${koboInstallPath}/share/janet")' "$out/bin/janet-netrepl"

    runHook postInstall
  '';
  postFixup = ''
    sed -i '1s|^#!.*|#!${koboInstallPath}/bin/janet|' "$out/bin/janet-netrepl"
  '';

}
