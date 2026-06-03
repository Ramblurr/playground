{
  stdenv,
  janet,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "janet-spork";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "janet-lang";
    repo = "spork";
    rev = "993887a8dbc9387af3b037418f02ef8e2b42b275";
    hash = "sha256-4oKmRjwDMRwlnntHOh3k2XG3pNxQ239Hgvw7zlokoCQ=";
  };

  strictDeps = true;

  buildInputs = [ janet ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cc_module() {
      local name=$1
      shift
      $CC -std=c99 -Wall -Wextra -O2 -fPIC \
        -I ${janet}/include \
        -shared -o "$name.so" \
        "$@"
    }

    cc_module base64 src/base64.c
    cc_module crc src/crc.c
    cc_module json src/json.c
    cc_module rawterm src/rawterm.c
    cc_module tarray src/tarray.c
    cc_module utf8 src/utf8.c
    cc_module cmath src/cmath.c -lm
    cc_module zip -D_LARGEFILE64_SOURCE -Ideps/miniz src/zip.c deps/miniz/miniz.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/janet/spork" "$out/share/janet-spork/bin"

    for module in spork/*.janet; do
      install -Dm644 "$module" "$out/share/janet/$module"
    done

    for native in base64 crc json rawterm tarray utf8 cmath zip; do
      install -Dm755 "$native.so" "$out/share/janet/spork/$native.so"
    done

    install -Dm644 src/tarray.h "$out/include/tarray.h"
    install -Dm644 src/tarray.h "$out/share/janet/tarray.h"

    for script in janet-format janet-netrepl janet-pm; do
      install -Dm755 "bin/$script" "$out/share/janet-spork/bin/$script"
      install -Dm755 "bin/$script" "$out/bin/$script"
      substituteInPlace "$out/bin/$script" \
        --replace-fail '#!/usr/bin/env janet' '#!${janet}/bin/janet'
      sed -i '2i(put root-env :syspath "'"$out/share/janet"'")' "$out/bin/$script"
    done

    runHook postInstall
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  installCheckPhase = ''
    runHook preInstallCheck

    ${janet}/bin/janet --syspath "$out/share/janet" -e '
      (import spork/fmt)
      (import spork/rawterm)
      (def formatted (string (fmt/format "(defn foo [x](+ x 1))\n")))
      (unless (= formatted "(defn foo [x] (+ x 1))\n")
        (error "spork/fmt smoke failed"))
    '

    runHook postInstallCheck
  '';
}
