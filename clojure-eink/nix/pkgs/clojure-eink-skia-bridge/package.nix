{
  stdenv,
  src,
  version ? "0.0.1",
}:

stdenv.mkDerivation {
  pname = "clojure-eink-skia-bridge";
  inherit version src;

  strictDeps = true;

  buildPhase = ''
    runHook preBuild

    $CXX -std=c++20 -Wall -Wextra -Werror -O2 -fPIC \
      -I src/native \
      -Wl,-soname,libclojure_eink_skia.so \
      -shared -o libclojure_eink_skia.so \
      src/native/eink_skia_native.cpp

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/include"
    cp libclojure_eink_skia.so "$out/lib/"
    cp src/native/eink_skia_native.h "$out/include/"

    runHook postInstall
  '';
}
