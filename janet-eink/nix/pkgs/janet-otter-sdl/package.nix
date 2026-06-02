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
      (def desktop-module (native "./build/janet-otter-sdl.so"))
      (def render-demo-self-test ((desktop-module (quote render-demo-self-test)) :value))
      (def stats (render-demo-self-test))
      (unless (= 1680 (get stats :width))
        (error (string/format "expected width 1680, got %v" (get stats :width))))
      (unless (= 1264 (get stats :height))
        (error (string/format "expected height 1264, got %v" (get stats :height))))
      (unless (= :gray8 (get stats :pixel-format))
        (error (string/format "expected gray8 pixel format, got %v" (get stats :pixel-format))))
      (unless (>= (get stats :gray-shades) 8)
        (error (string/format "expected at least 8 gray shades, got %d" (get stats :gray-shades))))
      (unless (> (get stats :non-white-pixels) 200000)
        (error (string/format "expected Skia render smoke to draw geometry, got %d non-white pixels" (get stats :non-white-pixels))))
    '
    echo "janet-otter-sdl gray shape render smoke ok"

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp build/janet-otter-sdl.so "$out/lib/"

    runHook postInstall
  '';
}
