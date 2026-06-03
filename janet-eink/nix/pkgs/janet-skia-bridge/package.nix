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
      src/janet_skia.cc src/janet_skia_common.cc src/otter_drawing_backend.cc \
      -ljanet -lfbink -lskia -lskshaper -lskunicode_icu -lskunicode_core

    export LD_LIBRARY_PATH="$PWD:${janet}/lib:${fbink}/lib:${skia}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    qemu-arm ${janet}/bin/janet -e '
      (def skia-module (native "./janet-skia.so"))
      (def create ((skia-module (quote create)) :value))
      (def clear ((skia-module (quote clear)) :value))
      (def draw-rect ((skia-module (quote draw-rect)) :value))
      (def draw-rounded-rect ((skia-module (quote draw-rounded-rect)) :value))
      (def sample-gray ((skia-module (quote sample-gray)) :value))
      (def stats-fn ((skia-module (quote stats)) :value))
      (when (nil? (skia-module (quote present)))
        (error "expected kobo skia native module to export present"))
      (def canvas (create 32 32))
      (clear canvas 255)
      (draw-rect canvas 4 4 8 8 96)
      (draw-rounded-rect canvas 16 16 8 8 2 32)
      (unless (= 96 (sample-gray canvas 6 6))
        (error "expected primitive draw smoke to mutate gray8 pixels"))
      (unless (= 32 (sample-gray canvas 18 18))
        (error "expected rounded rectangle smoke to mutate gray8 pixels"))
      (def stats (stats-fn canvas))
      (when (not= :gray8 (get stats :pixel-format))
        (error (string/format "expected gray8 pixel format, got %v" (get stats :pixel-format))))
    '
    echo "janet-skia kobo primitive qemu smoke ok"

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
