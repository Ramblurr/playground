{
  stdenv,
  fbink,
  skia,
  src,
  version ? "0.0.1",
}:

stdenv.mkDerivation {
  pname = "clojure-eink-skia-bridge";
  inherit version src;

  strictDeps = true;

  buildInputs = [
    fbink
    skia
  ];

  buildPhase = ''
    runHook preBuild

    $CXX -std=c++20 -Wall -Wextra -Werror -Wno-error=attributes -O2 -fPIC \
      -I src/native \
      -I ${fbink}/include/fbink \
      -I ${skia}/include/skia \
      -DSKIA_DLL \
      -L ${fbink}/lib \
      -L ${skia}/lib \
      -Wl,-soname,libclojure_eink_skia.so \
      -Wl,-rpath,'$ORIGIN' \
      -shared -o libclojure_eink_skia.so \
      src/native/eink_skia_native.cpp \
      -lskparagraph -lskshaper -lskunicode_icu -lskunicode_core -lskia -lfbink

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/include"
    cp libclojure_eink_skia.so "$out/lib/"
    cp -P ${skia}/lib/libsk*.so* "$out/lib/"
    cp -P ${fbink}/lib/libfbink.so* "$out/lib/"
    cp src/native/eink_skia_native.h "$out/include/"

    runHook postInstall
  '';
}
