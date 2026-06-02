{
  stdenvNoCC,
  janet,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "jeep";
  version = "local";
  src = fetchFromGitHub {
    owner = "pyrmont";
    repo = "jeep";
    rev = "a44f6afbabbcfddf2b1e4976433e39c408e447df";
    hash = "sha256-uaSjO1opoaC9vWhQQG47+XR48WpeDXRMOxSP+yJPonM=";
  };
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/jeep"
    cp -R deps lib res "$out/jeep/"
    install -m 0755 bin/jeep "$out/bin/jeep"
    substituteInPlace "$out/bin/jeep" \
      --replace-fail '#!/usr/bin/env janet' '#!${janet}/bin/janet'

    runHook postInstall
  '';
}
