{
  stdenv,
  fbink,
  src,
  version ? "0.0.1",
}:

stdenv.mkDerivation {
  pname = "clojure-eink-fbink-bridge";
  inherit version src;

  strictDeps = true;

  buildInputs = [
    fbink
  ];

  buildPhase = ''
    runHook preBuild

    $CC -std=c11 -Wall -Wextra -O2 -fPIC \
      -I ${fbink}/include/fbink -L ${fbink}/lib \
      -Wl,-rpath,'$ORIGIN' \
      -shared -o libclojure_eink.so \
      src/native/eink_native.c -lfbink

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libclojure_eink.so "$out/lib/"
    cp -P ${fbink}/lib/libfbink.so* "$out/lib/"

    runHook postInstall
  '';
}
