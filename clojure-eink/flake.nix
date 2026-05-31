{
  description = "dev env";
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # tracks nixpkgs unstable branch
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    devenv.url = "https://flakehub.com/f/ramblurr/nix-devenv/*";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    clojure-nix-locker.url = "github:bevuta/clojure-nix-locker";
    clojure-nix-locker.inputs.nixpkgs.follows = "nixpkgs";
    fbink-src.url = "path:/home/ramblurr/src/github.com/NiLuJe/FBInk";
    fbink-src.flake = false;
  };
  outputs =
    inputs@{
      clojure-nix-locker,
      fbink-src,
      self,
      devenv,
      devshell,
      ...
    }:
    let
      jdk = "jdk25";
      mkNativeLib =
        hostPkgs: targetPkgs: device:
        targetPkgs.stdenv.mkDerivation {
          pname = "clojure-eink-native";
          version = "0.0.1";
          src = ./.;
          fbinkSource = fbink-src;

          nativeBuildInputs = [
            hostPkgs.autoconf
            hostPkgs.automake
            hostPkgs.coreutils
            hostPkgs.file
            hostPkgs.findutils
            hostPkgs.gnum4
            hostPkgs.gnumake
            hostPkgs.libtool
          ];

          buildPhase = ''
            runHook preBuild

            cp -R --no-preserve=mode,ownership "$fbinkSource" fbink
            chmod -R u+w fbink
            rm -rf fbink/Release

            make -C fbink sharedlib ${device}=1 FBINK_VERSION=clojure-eink-poc

            $CC -std=c11 -Wall -Wextra -O2 -fPIC \
              -I fbink -L fbink/Release \
              -Wl,-rpath,'$ORIGIN' \
              -shared -o libclojure_eink.so \
              src/native/eink_native.c -lfbink

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p "$out/lib"
            cp libclojure_eink.so "$out/lib/"
            cp -P fbink/Release/libfbink.so* "$out/lib/"

            runHook postInstall
          '';
        };
    in
    devenv.lib.mkFlake ./. {
      inherit inputs;
      withOverlays = [
        devshell.overlays.default
        devenv.overlays.default
      ];
      packages = {
        default =
          pkgs:
          let
            jdkPackage = pkgs.${jdk};
            lockerPkgs = pkgs // {
              clojure = pkgs.clojure.override { jdk = jdkPackage; };
            };
            clojure = pkgs.clojure.override { jdk = jdkPackage; };
            gitRev =
              if self ? rev then
                self.rev
              else if self ? dirtyRev then
                self.dirtyRev
              else
                "dirty";
            clojureLocker = (import "${clojure-nix-locker}/default.nix" { pkgs = lockerPkgs; }).lockfile {
              src = ./.;
              lockfile = "./deps-lock.json";
              extraPrepInputs = [ pkgs.git ];
            };
          in
          pkgs.stdenv.mkDerivation {
            pname = "TODO";
            version = "0.0.TODO";
            src = ./.;
            nativeBuildInputs = [
              clojure
              pkgs.coreutils
              pkgs.findutils
              pkgs.git
              jdkPackage
            ];
            GIT_REV = gitRev;
            JAVA_HOME = jdkPackage.home;
            buildPhase = ''
              runHook preBuild

              source ${clojureLocker.shellEnv}
              export JAVA_HOME="${jdkPackage.home}"
              export JAVA_CMD="${jdkPackage}/bin/java"

              clojure -Srepro -M:kaocha
              clojure -Srepro -T:build jar

              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall

              mkdir -p $out
              cp "$(find target -type f -name '*.jar' -print | head -n 1)" $out/

              runHook postInstall
            '';
          };
        native = pkgs: mkNativeLib pkgs pkgs "LINUX";
        native-kobo = pkgs: mkNativeLib pkgs pkgs.pkgsCross.armv7l-hf-multiplatform "KOBO";
        locker =
          pkgs:
          let
            jdkPackage = pkgs.${jdk};
            lockerPkgs = pkgs // {
              clojure = pkgs.clojure.override { jdk = jdkPackage; };
            };
            clojure = pkgs.clojure.override { jdk = jdkPackage; };
            clojureLocker = (import "${clojure-nix-locker}/default.nix" { pkgs = lockerPkgs; }).lockfile {
              src = ./.;
              lockfile = "./deps-lock.json";
              extraPrepInputs = [ pkgs.git ];
            };
          in
          clojureLocker.commandLocker ''
            export HOME="$tmp/home"
            export GITLIBS="$tmp/home/.gitlibs"
            unset CLJ_CACHE CLJ_CONFIG XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME

            ${clojure}/bin/clojure -Srepro -X:deps prep :aliases "[:kaocha]"
            ${clojure}/bin/clojure -Srepro -P -M:kaocha
            ${clojure}/bin/clojure -Srepro -P -T:build jar
          '';
      };
      devShell =
        pkgs:
        pkgs.devshell.mkShell {
          imports = [
            devenv.capsules.base
            devenv.capsules.clojure
          ];
          # https://numtide.github.io/devshell
          commands = [
            # { package = pkgs.bazqux; }
          ];
          packages = [
            (if self ? packages then self.packages.${pkgs.system}.locker else pkgs.deps-lock)
            pkgs.jdk25
            pkgs.gnumake
            pkgs.file
          ];

        };
    };
}
