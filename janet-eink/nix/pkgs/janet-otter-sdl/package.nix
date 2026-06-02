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

    make native

    runHook postBuild
  '';

  doCheck = true;

  checkPhase = ''
    runHook preCheck

    export LD_LIBRARY_PATH="$PWD/build:${janet}/lib:${SDL2}/lib:${skia}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ${janet}/bin/janet -e '
      (def desktop-module (native "./build/janet-otter-sdl.so"))
      (def render-self-test ((desktop-module (quote render-self-test)) :value))
      (def stats (render-self-test))
      (unless (= 1680 (get stats :width))
        (error (string/format "expected width 1680, got %v" (get stats :width))))
      (unless (= 1264 (get stats :height))
        (error (string/format "expected height 1264, got %v" (get stats :height))))
      (unless (= "HELLO SKIA" (get stats :text))
        (error (string/format "expected HELLO SKIA text, got %v" (get stats :text))))
      (unless (> (get stats :black-pixels) 1000)
        (error (string/format "expected Skia render smoke to draw ink, got %d black pixels" (get stats :black-pixels))))
    '
    echo "janet-otter-sdl render smoke ok"

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp build/janet-otter-sdl.so "$out/lib/"

    runHook postInstall
  '';
}
