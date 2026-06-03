{
  stdenvNoCC,
  janet-spork,
  koboInstallPath ? "/mnt/onboard/janet-eink-demo/janet",
}:

stdenvNoCC.mkDerivation {
  pname = "spork-netrepl";
  version = janet-spork.version or "1.2.0";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/janet"
    cp -RL ${janet-spork}/share/janet/. "$out/share/janet/"

    install -Dm755 ${janet-spork}/share/janet-spork/bin/janet-netrepl "$out/bin/janet-netrepl"
    sed -i '1s|^#!.*|#!${koboInstallPath}/bin/janet|' "$out/bin/janet-netrepl"
    sed -i '2i(put root-env :syspath "${koboInstallPath}/share/janet")' "$out/bin/janet-netrepl"

    runHook postInstall
  '';

}
