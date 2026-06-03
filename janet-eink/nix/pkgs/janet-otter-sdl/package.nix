{
  stdenv,
  janet,
  pkg-config,
  SDL2,
  skia,
  src,
  version ? "0.0.1",
}:

stdenv.mkDerivation {
  pname = "janet-otter-sdl";
  inherit version src;

  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    janet
    SDL2
    skia
  ];

  buildPhase = ''
    runHook preBuild

    rm -rf build
    make native

    runHook postBuild
  '';

  doCheck = true;

  checkPhase = ''
    runHook preCheck

    export LD_LIBRARY_PATH="$PWD/build:${janet}/lib:${SDL2}/lib:${skia}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ${janet}/bin/janet -e '
      (def skia-module (native "./build/janet-skia.so"))
      (def create ((skia-module (quote create)) :value))
      (def clear ((skia-module (quote clear)) :value))
      (def draw-rect ((skia-module (quote draw-rect)) :value))
      (def draw-rounded-rect ((skia-module (quote draw-rounded-rect)) :value))
      (def sample-gray ((skia-module (quote sample-gray)) :value))
      (def stats-fn ((skia-module (quote stats)) :value))
      (def present-binding (skia-module (quote present)))
      (when (nil? present-binding)
        (error "expected desktop skia native module to export present"))
      (defn fill-gray [gray]
        (def value (/ gray 255.0))
        @{:style :fill
          :r value :g value :b value :a 1.0
          :anti-alias? false
          :skia-dither? false})
      (def canvas (create 32 32))
      (clear canvas (fill-gray 255))
      (draw-rect canvas 4 4 8 8 (fill-gray 96))
      (draw-rounded-rect canvas 16 16 8 8 2 (fill-gray 32))
      (unless (= 96 (sample-gray canvas 6 6))
        (error "expected primitive draw smoke to mutate gray8 pixels"))
      (unless (= 32 (sample-gray canvas 18 18))
        (error "expected rounded rectangle smoke to mutate gray8 pixels"))
      (def stats (stats-fn canvas))
      (unless (= :gray8 (get stats :pixel-format))
        (error (string/format "expected gray8 pixel format, got %v" (get stats :pixel-format))))
    '
    echo "janet-skia desktop primitive smoke ok"

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp build/janet-skia.so "$out/lib/"

    runHook postInstall
  '';
}
