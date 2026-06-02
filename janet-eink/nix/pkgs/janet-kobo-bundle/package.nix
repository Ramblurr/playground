{
  lib,
  runCommand,
  closureInfo,
  file,
  patchelf,
  qemu-user,
  targetJanet,
  targetGlibc,
  targetLibgcc,
  bundledNativeLibPackages ? [ ],
  bundledTreePackages ? [ ],
  bundledPrograms ? [ ],
  koboInstallPath ? "/mnt/onboard/janet-eink-demo/janet",
}:

let
  bundledLibClosure = closureInfo {
    rootPaths = [
      targetJanet
      targetLibgcc
    ] ++ bundledNativeLibPackages ++ bundledTreePackages;
  };

  copyBundledNativeLibPackages = lib.concatMapStringsSep "\n" (pkg: ''
    for lib in ${pkg}/lib/*.so*; do
      copy_lib "$lib"
    done
  '') bundledNativeLibPackages;

  copyBundledTreePackages = lib.concatMapStringsSep "\n" (pkg: ''
    cp -RL ${pkg}/. "$out/"
  '') bundledTreePackages;

  copyBundledPrograms = lib.concatMapStringsSep "\n" (program:
    let
      name = program.name or (baseNameOf (toString program.src));
      destination = program.destination or "share/janet-eink/${name}";
      mode = program.mode or "0644";
    in
    ''
      install -D -m ${mode} ${program.src} "$out/${destination}"
    '') bundledPrograms;
in
runCommand "janet-kobo-armv7l-bundle"
  {
    nativeBuildInputs = [
      file
      patchelf
      qemu-user
    ];
  }
  ''
    set -euo pipefail

    mkdir -p "$out/bin" "$out/lib" "$out/include" "$out/share"

    copy_lib() {
      local lib=$1
      [ -e "$lib" ] || return 0
      case "$lib" in *.py) return 0 ;; esac
      if ! file -b "$lib" | grep -q ELF; then
        return 0
      fi

      local soname
      soname=$(patchelf --print-soname "$lib" 2>/dev/null || true)
      if [ -z "$soname" ]; then
        soname=$(basename "$lib")
      fi

      local dest="$out/lib/$soname"
      rm -f "$dest"
      cp -L "$lib" "$dest"
      chmod u+w "$dest"
    }

    cp -L ${targetJanet}/bin/janet "$out/bin/"
    for lib in ${targetJanet}/lib/libjanet.so*; do
      copy_lib "$lib"
    done
    cp -RL ${targetJanet}/include/. "$out/include/"
    cp -RL ${targetJanet}/share/. "$out/share/"

    ${copyBundledNativeLibPackages}

    ${copyBundledTreePackages}

    while IFS= read -r storePath; do
      case "$storePath" in
        *-glibc-*)
          continue
          ;;
      esac
      if [ -d "$storePath/lib" ]; then
        while IFS= read -r lib; do
          copy_lib "$lib"
        done < <(find -L "$storePath/lib" -maxdepth 1 \( -type f -o -type l \) -name '*.so*' -print)
      fi
    done < ${bundledLibClosure}/store-paths

    ${copyBundledPrograms}

    for lib in \
      ld-linux-armhf.so.3 \
      libc.so.6 \
      libm.so.6 \
      libdl.so.2 \
      libpthread.so.0 \
      librt.so.1 \
      libresolv.so.2 \
      libnss_files.so.2 \
      libnss_dns.so.2; do
      copy_lib ${targetGlibc}/lib/$lib
    done

    for lib in ${targetLibgcc}/lib/*.so*; do
      copy_lib "$lib"
    done

    chmod u+w "$out/bin/janet"
    find "$out" -type f -name '*.so*' -exec chmod u+w {} +

    patchelf \
      --set-interpreter "${koboInstallPath}/lib/ld-linux-armhf.so.3" \
      --set-rpath "${koboInstallPath}/lib" \
      "$out/bin/janet"

    while IFS= read -r elf; do
      case "$(basename "$elf")" in
        ld-linux-armhf.so.3|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libnss_*.so.*|libgcc_s.so.*)
          continue
          ;;
      esac
      if file -b "$elf" | grep -q ELF; then
        patchelf --set-rpath "${koboInstallPath}/lib" "$elf"
      fi
    done < <(find "$out" -type f -name '*.so*' -print)

    qemu-arm "$out/lib/ld-linux-armhf.so.3" \
      --library-path "$out/lib" \
      "$out/bin/janet" \
      -e '(print "janet kobo bundle smoke ok")'
  ''
