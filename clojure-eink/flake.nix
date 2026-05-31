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
        fbink =
          pkgs:
          pkgs.callPackage ./nix/pkgs/fbink/package.nix {
            src = fbink-src;
            version = "clojure-eink-poc";
            device = "LINUX";
          };
        fbink-kobo =
          pkgs:
          pkgs.pkgsCross.armv7l-hf-multiplatform.callPackage ./nix/pkgs/fbink/package.nix {
            src = fbink-src;
            version = "clojure-eink-poc";
            device = "KOBO";
          };
        clojure-eink-fbink-bridge =
          pkgs:
          pkgs.callPackage ./nix/pkgs/clojure-eink-fbink-bridge/package.nix {
            src = ./.;
            fbink = self.packages.${pkgs.system}.fbink;
          };
        clojure-eink-fbink-bridge-kobo =
          pkgs:
          pkgs.pkgsCross.armv7l-hf-multiplatform.callPackage ./nix/pkgs/clojure-eink-fbink-bridge/package.nix
            {
              src = ./.;
              fbink = self.packages.${pkgs.system}.fbink-kobo;
            };
        clojure-eink-skia-bridge =
          pkgs:
          pkgs.callPackage ./nix/pkgs/clojure-eink-skia-bridge/package.nix {
            src = ./.;
            skia = self.packages.${pkgs.system}.skia-native;
          };
        clojure-eink-skia-bridge-kobo =
          pkgs:
          pkgs.pkgsCross.armv7l-hf-multiplatform.callPackage ./nix/pkgs/clojure-eink-skia-bridge/package.nix
            {
              src = ./.;
              skia = self.packages.${pkgs.system}.skia;
            };
        native = pkgs: self.packages.${pkgs.system}.clojure-eink-fbink-bridge;
        native-kobo = pkgs: self.packages.${pkgs.system}.clojure-eink-fbink-bridge-kobo;
        skia =
          pkgs:
          pkgs.pkgsCross.armv7l-hf-multiplatform.callPackage ./nix/pkgs/skia/package.nix {
            stdenv = pkgs.pkgsCross.armv7l-hf-multiplatform.clangStdenv;
          };
        skia-native = pkgs: pkgs.callPackage ./nix/pkgs/skia/package.nix { stdenv = pkgs.clangStdenv; };
        kobo-jdk25-ffm =
          pkgs: pkgs.pkgsCross.armv7l-hf-multiplatform.callPackage ./nix/pkgs/kobo-jdk25-ffm/package.nix { };
        kobo-jdk25-clojure-java2d-ext2 =
          pkgs:
          let
            targetPkgs = pkgs.pkgsCross.armv7l-hf-multiplatform;
            koboJdk25Ffm = targetPkgs.callPackage ./nix/pkgs/kobo-jdk25-ffm/package.nix { };
          in
          pkgs.callPackage ./nix/pkgs/kobo-jdk25-clojure-java2d-ext2/package.nix {
            inherit koboJdk25Ffm;
            qemu = pkgs.qemu-user;
            targetBintools = targetPkgs.stdenv.cc.bintools.bintools;
            targetRuntimeDeps = with targetPkgs; [
              alsa-lib
              freetype
              lcms2
              libffi
              libjpeg_turbo
              zlib
            ];
          };
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
