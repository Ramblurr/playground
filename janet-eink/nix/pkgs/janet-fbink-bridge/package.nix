{
  stdenv,
  fbink,
  janet,
  src,
  version ? "0.0.1",
}:

stdenv.mkDerivation {
  pname = "janet-fbink-bridge";
  inherit version src;

  strictDeps = true;

  buildInputs = [
    fbink
    janet
  ];

  buildPhase = ''
    runHook preBuild

    $CC -std=c11 -Wall -Wextra -O2 -fPIC \
      -I ${janet}/include \
      -I ${fbink}/include/fbink \
      -L ${janet}/lib \
      -L ${fbink}/lib \
      -Wl,-rpath,'$ORIGIN' \
      -shared -o janet-fbink.so \
      src/native/janet_fbink.c -ljanet -lfbink

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp janet-fbink.so "$out/lib/"
    cp -P ${fbink}/lib/libfbink.so* "$out/lib/"

    runHook postInstall
  '';
}
