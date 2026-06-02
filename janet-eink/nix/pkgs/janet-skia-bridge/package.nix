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
      src/janet_skia.cc src/otter_skia_hello.cc -ljanet -lfbink -lskia

    export LD_LIBRARY_PATH="$PWD:${janet}/lib:${fbink}/lib:${skia}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    qemu-arm ${janet}/bin/janet -e '
      (def skia-module (native "./janet-skia.so"))
      (def skia-self-test ((skia-module (quote self-test)) :value))
      (def black-pixels (skia-self-test))
      (when (<= black-pixels 1000)
        (error (string/format "expected Skia render smoke to draw ink, got %d black pixels" black-pixels)))
    '
    echo "janet-skia qemu smoke ok"

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
