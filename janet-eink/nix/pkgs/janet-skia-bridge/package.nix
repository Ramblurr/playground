{
  stdenv,
  fbink,
  janet,
  qemu-user,
  skia,
  src,
  version ? "0.0.1",
}:

stdenv.mkDerivation {
  pname = "janet-skia-bridge";
  inherit version src;

  strictDeps = true;

  nativeBuildInputs = [
    qemu-user
  ];

  buildInputs = [
    fbink
    janet
    skia
  ];

  buildPhase = ''
    runHook preBuild

    $CXX -std=c++17 -Wall -Wextra -O2 -fPIC \
      -I ${janet}/include \
      -I ${fbink}/include/fbink \
      -I ${skia}/include/skia \
      -L ${janet}/lib \
      -L ${fbink}/lib \
      -L ${skia}/lib \
      -Wl,-rpath,'$ORIGIN' \
      -shared -o janet-skia.so \
      src/janet_skia.cc src/otter_drawing_backend.cc -ljanet -lfbink -lskia

    export LD_LIBRARY_PATH="$PWD:${janet}/lib:${fbink}/lib:${skia}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    qemu-arm ${janet}/bin/janet -e '
      (def skia-module (native "./janet-skia.so"))
      (def skia-self-test ((skia-module (quote self-test)) :value))
      (def stats (skia-self-test))
      (when (not= :gray8 (get stats :pixel-format))
        (error (string/format "expected gray8 pixel format, got %v" (get stats :pixel-format))))
      (when (< (get stats :gray-shades) 8)
        (error (string/format "expected at least 8 gray shades, got %d" (get stats :gray-shades))))
      (when (<= (get stats :non-white-pixels) 200000)
        (error (string/format "expected Skia render smoke to draw geometry, got %d non-white pixels" (get stats :non-white-pixels))))
    '
    echo "janet-skia gray shape qemu smoke ok"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp janet-skia.so "$out/lib/"
    cp -P ${fbink}/lib/libfbink.so* "$out/lib/"
    cp -P ${skia}/lib/*.so* "$out/lib/"

    runHook postInstall
  '';
}
