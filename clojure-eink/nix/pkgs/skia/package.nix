{
  lib,
  stdenv,
  fetchgit,
  freetype,
  gn,
  harfbuzzFull,
  icu,
  libpng,
  ninja,
  python3,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "skia-kobo-raster-clang";
  # Keep this pinned to the nixpkgs Skia revision this package was derived from.
  version = "144-unstable-2025-12-02";

  src = fetchgit {
    url = "https://skia.googlesource.com/skia.git";
    # Tip of the chrome/m144 branch.
    rev = "ee20d565acb08dece4a32e3f209cdd41119015ca";
    hash = "sha256-0LiFK/8873gei70iVhNGRlcFeGIp7tjDEfxTBz1LYv8=";
  };

  postPatch = ''
    substituteInPlace BUILD.gn \
      --replace-fail 'rebase_path("//bin/gn")' '"gn"'
    # System zlib detection bug workaround, matching nixpkgs' Skia package.
    substituteInPlace BUILD.gn \
      --replace-fail '"//third_party/zlib",' ""
  '';

  strictDeps = true;

  nativeBuildInputs = [
    gn
    ninja
    python3
  ];

  buildInputs = [
    freetype
    harfbuzzFull
    icu
    libpng
    zlib
  ];

  gnFlags =
    let
      cpu =
        {
          "x86_64" = "x64";
          "i686" = "x86";
          "arm" = "arm";
          "armv7l" = "arm";
          "aarch64" = "arm64";
        }
        .${stdenv.hostPlatform.parsed.cpu.name}
          or (throw "Unsupported Skia target CPU: ${stdenv.hostPlatform.parsed.cpu.name}");
    in
    [
      "is_debug=false"
      "is_official_build=true"
      "is_component_build=true"
      "is_clang=true"

      # Cross compiler tools.
      "cc=\"${stdenv.cc.targetPrefix}cc\""
      "cxx=\"${stdenv.cc.targetPrefix}c++\""
      "ar=\"${stdenv.cc.targetPrefix}ar\""
      "target_cpu=\"${cpu}\""

      # CPU/raster-only build for Kobo. No display server or GPU backend.
      "skia_enable_ganesh=false"
      "skia_enable_graphite=false"
      "skia_use_gl=false"
      "skia_use_egl=false"
      "skia_use_x11=false"
      "skia_use_vulkan=false"
      "skia_use_dawn=false"
      "skia_use_metal=false"
      "skia_use_webgl=false"
      "skia_use_direct3d=false"
      "skia_use_angle=false"

      # Keep text shaping and Unicode; avoid system font discovery.
      "skia_use_freetype=true"
      "skia_use_fontconfig=false"
      "skia_enable_fontmgr_custom_directory=true"
      "skia_use_harfbuzz=true"
      "skia_use_icu=true"
      "skia_use_client_icu=false"
      "skia_use_bidi=false"
      "skia_use_libgrapheme=false"
      "skia_use_icu4x=false"
      "skia_enable_skunicode=true"
      "skia_use_system_freetype2=true"
      "skia_system_freetype2_include_path=\"${lib.getDev freetype}/include/freetype2\""
      "skia_system_freetype2_lib=\"freetype\""

      # Keep PNG. Drop heavier image/document/animation features for now.
      "skia_use_libpng_decode=true"
      "skia_use_libpng_encode=true"
      "skia_use_libjpeg_turbo_decode=false"
      "skia_use_libjpeg_turbo_encode=false"
      "skia_use_no_jpeg_encode=true"
      "skia_use_libwebp_decode=false"
      "skia_use_libwebp_encode=false"
      "skia_use_no_webp_encode=true"
      "skia_use_libavif=false"
      "skia_use_libjxl_decode=false"
      "skia_use_dng_sdk=false"
      "skia_use_wuffs=false"
      "skia_use_piex=false"
      "skia_use_xps=false"
      "skia_enable_pdf=false"
      "skia_enable_skottie=false"
      "skia_enable_svg=false"
      "skia_use_expat=false"
      "skia_use_perfetto=false"
      "skia_use_lua=false"
      "skia_build_fuzzers=false"
      "skia_enable_tools=false"

      # System dependencies. HarfBuzz headers are included as <hb.h> in places.
      "extra_cflags=[\"-I${lib.getDev harfbuzzFull}/include/harfbuzz\",\"-I${lib.getDev freetype}/include/freetype2\",\"-fvisibility=default\"]"
      "extra_cflags_cc=[\"-fvisibility=default\"]"
      "skia_use_system_zlib=true"
      "skia_use_system_harfbuzz=true"
      "skia_use_system_icu=true"
      "skia_use_system_libpng=true"
    ];

  # Build the core library plus text modules. The default all target pulls in a
  # lot of tests/tools; keep this package focused on the libraries we need.
  ninjaFlags = [
    "skia"
    "modules/skunicode:skunicode_core"
    "modules/skunicode:skunicode_icu"
    "modules/skshaper:skshaper"
    "modules/skparagraph:skparagraph"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    find . -maxdepth 1 -type f \( -name '*.so' -o -name '*.a' -o -name '*.dylib' \) -exec cp -P {} "$out/lib/" \;

    pushd ../../include
    find . -name '*.h' -exec install -Dm644 {} "$out/include/skia/{}" \;
    popd

    pushd ../../src
    find . -name '*.h' -exec install -Dm644 {} "$out/include/skia/src/{}" \;
    popd

    pushd ../../modules
    find . -name '*.h' -exec install -Dm644 {} "$out/include/skia/modules/{}" \;
    popd

    mkdir -p "$out/lib/pkgconfig"
    cat > "$out/lib/pkgconfig/skia.pc" <<EOF_PC
    prefix=$out
    exec_prefix=\''${prefix}
    libdir=\''${prefix}/lib
    includedir=\''${prefix}/include/skia
    Name: skia
    Description: CPU-only Skia raster library for Kobo
    URL: https://skia.org/
    Version: ${lib.versions.major finalAttrs.version}
    Libs: -L\''${libdir} -lskia
    Cflags: -I\''${includedir}
    EOF_PC

    if [ -e "$out/lib/libskparagraph.so" ]; then
      cat > "$out/lib/pkgconfig/skia-paragraph.pc" <<EOF_PC
    prefix=$out
    exec_prefix=\''${prefix}
    libdir=\''${prefix}/lib
    includedir=\''${prefix}/include/skia
    Name: skia-paragraph
    Description: Skia paragraph and shaping modules for Kobo
    URL: https://skia.org/
    Version: ${lib.versions.major finalAttrs.version}
    Requires: skia
    Libs: -L\''${libdir} -lskparagraph -lskshaper -lskunicode_icu -lskunicode_core
    Cflags: -I\''${includedir}
    EOF_PC
    fi

    runHook postInstall
  '';

  preFixup = ''
    # Some Skia includes are assumed to be under an include subdirectory by
    # other Skia includes.
    for file in $(grep -rl '#include "include/' "$out/include"); do
      substituteInPlace "$file" \
        --replace-fail '#include "include/' '#include "'
    done
  '';

  meta = {
    description = "CPU-only Skia build for Kobo ARMv7 e-ink rendering";
    homepage = "https://skia.org/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    pkgConfigModules = [
      "skia"
      "skia-paragraph"
    ];
  };
})
