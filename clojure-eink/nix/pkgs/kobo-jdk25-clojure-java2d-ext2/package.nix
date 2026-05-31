{
  lib,
  stdenvNoCC,
  closureInfo,
  coreutils,
  dejavu_fonts,
  e2fsprogs,
  fetchurl,
  file,
  findutils,
  gnugrep,
  jdk25_headless,
  patchelf,
  qemu,
  targetBintools,
  koboJdk25Ffm,
  # Extra target-side runtime libraries whose references can be hidden inside
  # jmods until jlink extracts them. Add their closures to the ext2 image and
  # to the build sandbox so qemu smoke tests can load java.desktop natives.
  targetRuntimeDeps ? [ ],
}:

let
  runtimeName = "kobo-jdk25-clojure-fast-uberwarm-ffm-java2d";
  imageName = "nix-${runtimeName}.ext2";
  runtimePath = "/nix/${runtimeName}";

  clojureJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/clojure/1.12.4/clojure-1.12.4.jar";
    sha256 = "0xx1kna6lbnjvq0gycsgf7qckf3281kkq0jqrkclb353dnxfk0ab";
  };

  specAlphaJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/spec.alpha/0.5.238/spec.alpha-0.5.238.jar";
    sha256 = "0xshsz467dphrwbxgrcbbbp9klvf7dj0m1plgbrl35k3xav9kkcl";
  };

  coreSpecsAlphaJar = fetchurl {
    url = "https://repo1.maven.org/maven2/org/clojure/core.specs.alpha/0.4.74/core.specs.alpha-0.4.74.jar";
    sha256 = "1nwxxc7nx53qin00i51x6daaav1k27pvwrxsi0689fj9rw4aqwzb";
  };

  runtimeClosure = closureInfo {
    rootPaths = [ koboJdk25Ffm ] ++ targetRuntimeDeps;
  };
in
stdenvNoCC.mkDerivation {
  pname = "${runtimeName}-image";
  version = "25.0.4-1.12.4";

  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [
    coreutils
    e2fsprogs
    file
    findutils
    gnugrep
    jdk25_headless
    patchelf
    qemu
  ];

  buildPhase = ''
    runHook preBuild

    export SOURCE_DATE_EPOCH="''${SOURCE_DATE_EPOCH:-315532800}"
    epoch="$SOURCE_DATE_EPOCH"

    root="$PWD/root"
    runtimePath="/nix/${runtimeName}"
    app="$root$runtimePath"
    mkdir -p "$app" "$root/nix/store"

    armjdk=${koboJdk25Ffm}
    hostjdk=${jdk25_headless}

    test -e "$armjdk/lib/openjdk/lib/libfallbackLinker.so"
    test -e "$armjdk/lib/openjdk/lib/libffi.so.8"
    test -e "$armjdk/lib/openjdk/jmods/java.desktop.jmod"

    "$hostjdk/bin/jlink" \
      --module-path "$armjdk/lib/openjdk/jmods" \
      --add-modules jdk.compiler,jdk.unsupported,java.logging,java.desktop \
      --no-header-files \
      --no-man-pages \
      --output "$app/jdk"

    test -e "$app/jdk/lib/libfallbackLinker.so"
    test -e "$app/jdk/lib/libffi.so.8"
    test -e "$app/jdk/lib/libfontmanager.so"
    test -e "$app/jdk/lib/libawt_headless.so"
    test -e "$app/jdk/lib/liblcms.so"
    test -e "$app/jdk/lib/libjavajpeg.so"

    mkdir -p "$app/jdk/lib/fonts"
    cp ${dejavu_fonts}/share/fonts/truetype/DejaVuSans*.ttf "$app/jdk/lib/fonts/"
    cp ${dejavu_fonts}/share/fonts/truetype/DejaVuSerif*.ttf "$app/jdk/lib/fonts/"

    write_fontconfig() {
      local out=$1
      local font_dir=$2
      cat > "$out" <<EOF_FONTCONFIG
    version=1

    dialog.plain.latin-1=DejaVu Sans
    dialog.bold.latin-1=DejaVu Sans Bold
    dialog.italic.latin-1=DejaVu Sans Oblique
    dialog.bolditalic.latin-1=DejaVu Sans Bold Oblique

    sansserif.plain.latin-1=DejaVu Sans
    sansserif.bold.latin-1=DejaVu Sans Bold
    sansserif.italic.latin-1=DejaVu Sans Oblique
    sansserif.bolditalic.latin-1=DejaVu Sans Bold Oblique

    serif.plain.latin-1=DejaVu Serif
    serif.bold.latin-1=DejaVu Serif Bold
    serif.italic.latin-1=DejaVu Serif Italic
    serif.bolditalic.latin-1=DejaVu Serif Bold Italic

    monospaced.plain.latin-1=DejaVu Sans Mono
    monospaced.bold.latin-1=DejaVu Sans Mono Bold
    monospaced.italic.latin-1=DejaVu Sans Mono Oblique
    monospaced.bolditalic.latin-1=DejaVu Sans Mono Bold Oblique

    dialoginput.plain.latin-1=DejaVu Sans Mono
    dialoginput.bold.latin-1=DejaVu Sans Mono Bold
    dialoginput.italic.latin-1=DejaVu Sans Mono Oblique
    dialoginput.bolditalic.latin-1=DejaVu Sans Mono Bold Oblique

    sequence.allfonts=latin-1
    sequence.fallback=latin-1

    filename.DejaVu_Sans=$font_dir/DejaVuSans.ttf
    filename.DejaVu_Sans_Bold=$font_dir/DejaVuSans-Bold.ttf
    filename.DejaVu_Sans_Oblique=$font_dir/DejaVuSans-Oblique.ttf
    filename.DejaVu_Sans_Bold_Oblique=$font_dir/DejaVuSans-BoldOblique.ttf
    filename.DejaVu_Serif=$font_dir/DejaVuSerif.ttf
    filename.DejaVu_Serif_Bold=$font_dir/DejaVuSerif-Bold.ttf
    filename.DejaVu_Serif_Italic=$font_dir/DejaVuSerif-Italic.ttf
    filename.DejaVu_Serif_Bold_Italic=$font_dir/DejaVuSerif-BoldItalic.ttf
    filename.DejaVu_Sans_Mono=$font_dir/DejaVuSansMono.ttf
    filename.DejaVu_Sans_Mono_Bold=$font_dir/DejaVuSansMono-Bold.ttf
    filename.DejaVu_Sans_Mono_Oblique=$font_dir/DejaVuSansMono-Oblique.ttf
    filename.DejaVu_Sans_Mono_Bold_Oblique=$font_dir/DejaVuSansMono-BoldOblique.ttf
    EOF_FONTCONFIG
    }

    write_fontconfig "$app/jdk/lib/fontconfig.properties" "$runtimePath/jdk/lib/fonts"
    write_fontconfig "$app/jdk/lib/fontconfig-local.properties" "$app/jdk/lib/fonts"

    mapfile -t dep_dirs < <(
      {
        while IFS= read -r -d ''' f; do
          if file -b "$f" | grep -q ELF; then
            patchelf --print-rpath "$f" 2>/dev/null | tr ':' '\n' || true
          fi
        done < <(find "$app/jdk" -type f -print0)
      } \
        | sed '/^$/d' \
        | grep '^/nix/store/' \
        | grep -v "^$armjdk/" \
        | sort -u
    )
    rpath_common=$(printf '%s\n' "''${dep_dirs[@]}" | paste -sd: -)

    find "$app/jdk" -type f -exec sh -c '
      stripdir=$1; shift
      for f; do
        if file -b "$f" | grep -q ELF; then
          "$stripdir/armv7l-unknown-linux-gnueabihf-strip" --strip-unneeded "$f" || true
        fi
      done
    ' sh ${targetBintools}/bin {} +

    while IFS= read -r -d ''' f; do
      if file -b "$f" | grep -q ELF; then
        case "$f" in
          */bin/*) patchelf --set-rpath "\$ORIGIN/../lib:\$ORIGIN/../lib/server:$rpath_common" "$f" ;;
          */lib/server/*) patchelf --set-rpath "\$ORIGIN:\$ORIGIN/..:$rpath_common" "$f" ;;
          */lib/*) patchelf --set-rpath "\$ORIGIN:\$ORIGIN/server:$rpath_common" "$f" ;;
        esac
      fi
    done < <(find "$app/jdk" -type f -print0)

    mkdir -p "$app/lib"
    jarwork=$(mktemp -d)

    mkdir -p "$jarwork/uber"
    for jarfile in \
      ${clojureJar} \
      ${specAlphaJar} \
      ${coreSpecsAlphaJar}; do
      (cd "$jarwork/uber" && "$hostjdk/bin/jar" xf "$jarfile")
    done
    find "$jarwork/uber/META-INF" -type f \( -name '*.SF' -o -name '*.RSA' -o -name '*.DSA' \) -delete 2>/dev/null || true
    (cd "$jarwork/uber" && "$hostjdk/bin/jar" cf0 "$app/lib/clojure-uber-1.12.4.jar" .)
    sha256sum "$app/lib/clojure-uber-1.12.4.jar" > "$app/lib/clojure-uber.sha256"

    find "$app" -exec touch -h -d "@$epoch" {} +

    arm_java() {
      ${qemu}/bin/qemu-arm "$app/jdk/bin/java" "$@"
    }
    arm_javac() {
      ${qemu}/bin/qemu-arm "$app/jdk/bin/javac" "$@"
    }

    arm_java -Xshare:dump
    touch -h -d "@$epoch" "$app/jdk/lib/server/classes.jsa"
    touch -h -d "@$epoch" "$app/lib/clojure-uber-1.12.4.jar"

    warmup="${./appcds-warmup.clj}"

    (cd "$app/lib" && arm_java \
      -XX:TieredStopAtLevel=1 \
      -XX:ArchiveClassesAtExit=clojure-dynamic.jsa \
      -cp clojure-uber-1.12.4.jar \
      clojure.main "$warmup" >/dev/null)

    find "$app" -exec touch -h -d "@$epoch" {} +

    mkdir -p "$app/bin"
    install -m 0755 ${./java-wrapper.sh} "$app/bin/java"
    ln -s ../jdk/bin/javac "$app/bin/javac"
    ln -s ../jdk/bin/keytool "$app/bin/keytool"
    ln -s ../jdk/bin/serialver "$app/bin/serialver"

    install -m 0755 ${./clojure-wrapper.sh} "$app/bin/clojure"
    ln -s clojure "$app/bin/clj"
    find "$app" -exec touch -h -d "@$epoch" {} +

    # Local qemu smoke tests use temporary build-only files. Nothing from
    # $smoke is copied into root/nix or into the ext2 image.
    smoke="$PWD/smoke-tests"
    mkdir -p "$smoke"
    arm_java -version
    arm_javac -version
    (cd "$app/lib" && arm_java -cp clojure-uber-1.12.4.jar clojure.main -e '(println (clojure-version))')
    (cd "$app/lib" && arm_java -cp clojure-uber-1.12.4.jar clojure.main -e '(println (+ 40 2))')

    testsrc="$smoke/TestFFM.java"
    cp ${./TestFFM.java} "$testsrc"
    mkdir -p "$smoke/testffm-classes"
    arm_javac -d "$smoke/testffm-classes" "$testsrc"
    arm_java --enable-native-access=ALL-UNNAMED -cp "$smoke/testffm-classes" TestFFM > "$smoke/ffm-default.log"
    arm_java --enable-native-access=ALL-UNNAMED -Djdk.internal.foreign.CABI=FALLBACK -cp "$smoke/testffm-classes" TestFFM > "$smoke/ffm-forced-fallback.log"
    grep -q 'native linker = jdk.internal.foreign.abi.fallback.FallbackLinker' "$smoke/ffm-default.log"
    grep -q 'native linker = jdk.internal.foreign.abi.fallback.FallbackLinker' "$smoke/ffm-forced-fallback.log"

    java2dsrc="$smoke/TestJava2D.java"
    cp ${./TestJava2D.java} "$java2dsrc"
    mkdir -p "$smoke/testjava2d-classes"
    arm_javac -d "$smoke/testjava2d-classes" "$java2dsrc"
    arm_java \
      -Djava.awt.headless=true \
      -Dsun.awt.fontconfig="$app/jdk/lib/fontconfig-local.properties" \
      -cp "$smoke/testjava2d-classes" \
      TestJava2D > "$smoke/java2d.log"
    grep -q 'headless     = true' "$smoke/java2d.log"
    grep -q 'pixels       = ' "$smoke/java2d.log"

    (cd "$app/lib" && arm_java \
      -Xlog:cds=info \
      -XX:SharedArchiveFile="$app/jdk/lib/server/classes.jsa:$app/lib/clojure-dynamic.jsa" \
      -cp clojure-uber-1.12.4.jar \
      clojure.main -e '(println :cds-check)' \
      > "$smoke/cds-check.log" 2>&1)
    grep -q 'Mapped dynamic region' "$smoke/cds-check.log"
    grep -q ':cds-check' "$smoke/cds-check.log"
    if grep -qE 'timestamp has changed|shared class paths mismatch|Required classpath entry does not exist' "$smoke/cds-check.log"; then
      echo "CDS validation failed" >&2
      sed -n '1,160p' "$smoke/cds-check.log" >&2
      exit 1
    fi

    rm -rf "$smoke"

    while IFS= read -r storePath; do
      if [ "$storePath" != "$armjdk" ]; then
        cp -a --no-preserve=ownership "$storePath" "$root/nix/store/"
      fi
    done < ${runtimeClosure}/store-paths
    find "$root/nix/store" -exec touch -h -d "@$epoch" {} +

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"

    used_mib=$(du -sm --apparent-size root/nix | awk '{print $1}')
    img_mib=$((used_mib + 48))
    if [ "$img_mib" -lt 240 ]; then
      img_mib=240
    fi

    img="$out/${imageName}"
    truncate -s "''${img_mib}M" "$img"
    mke2fs -q -t ext2 -F -L KOBOJDK25J2D -d root/nix "$img"

    runHook postInstall
  '';

  meta = {
    description = "Ext2 /nix image for Kobo OpenJDK 25, Clojure, FFM, and headless Java2D";
    platforms = lib.platforms.linux;
  };
}
