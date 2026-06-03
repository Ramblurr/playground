{
  description = "Barebones Janet build for ARMv7l/Kobo";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    fbink-src.url = "path:/home/ramblurr/src/github.com/NiLuJe/FBInk";
    fbink-src.flake = false;
  };

  outputs =
    {
      nixpkgs,
      fbink-src,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      armv7lPkgs = pkgs.pkgsCross.armv7l-hf-multiplatform;
      koboInstallPath = "/mnt/onboard/janet-eink-demo/janet";

      jeep = pkgs.callPackage ./nix/pkgs/jeep/package.nix { };
      janet-spork = pkgs.callPackage ./nix/pkgs/janet-spork/package.nix { };
      jfmt = pkgs.callPackage ./nix/pkgs/jfmt/package.nix {
        inherit janet-spork;
      };

      otterFonts = pkgs.callPackage ./nix/pkgs/otter-fonts/package.nix {
        inherit (pkgs) noto-fonts;
      };

      skia = pkgs.callPackage ./nix/pkgs/skia/package.nix {
        stdenv = pkgs.clangStdenv;
      };

      janetOtterSdl = pkgs.callPackage ./nix/pkgs/janet-otter-sdl/package.nix {
        src = ./.;
        janet = pkgs.janet;
        SDL2 = pkgs.SDL2;
        inherit skia;
      };

      fbinkKobo = armv7lPkgs.callPackage ./nix/pkgs/fbink/package.nix {
        src = fbink-src;
        version = "janet-eink-poc";
        device = "KOBO";
      };

      janet-fbink-bridge-kobo = armv7lPkgs.callPackage ./nix/pkgs/janet-fbink-bridge/package.nix {
        src = ./.;
        janet = armv7lPkgs.janet;
        fbink = fbinkKobo;
      };

      skiaKobo = armv7lPkgs.callPackage ./nix/pkgs/skia/package.nix {
        stdenv = armv7lPkgs.clangStdenv;
      };

      janet-skia-bridge-kobo = armv7lPkgs.callPackage ./nix/pkgs/janet-skia-bridge/package.nix {
        stdenv = armv7lPkgs.clangStdenv;
        src = ./.;
        pkg-config = pkgs.pkg-config;
        qemu-user = pkgs.qemu-user;
        janet = armv7lPkgs.janet;
        fbink = fbinkKobo;
        skia = skiaKobo;
      };

      janet-spork-kobo = armv7lPkgs.callPackage ./nix/pkgs/janet-spork/package.nix {
        janet = armv7lPkgs.janet;
      };

      spork-netrepl-kobo = armv7lPkgs.callPackage ./nix/pkgs/spork-netrepl/package.nix {
        inherit koboInstallPath;
        janet-spork = janet-spork-kobo;
      };
    in
    {
      packages.${system} = {
        default = armv7lPkgs.janet;
        jeep = jeep;
        jfmt = jfmt;
        janet-spork = janet-spork;
        janet-otter-sdl = janetOtterSdl;
        otter-fonts = otterFonts;
        inherit skia;
        janet-armv7l = armv7lPkgs.janet;
        fbink-kobo = fbinkKobo;
        janet-fbink-bridge-kobo = janet-fbink-bridge-kobo;
        skia-kobo = skiaKobo;
        janet-skia-bridge-kobo = janet-skia-bridge-kobo;
        spork-netrepl-kobo = spork-netrepl-kobo;
        janet-spork-kobo = janet-spork-kobo;
        kobo-bundle = pkgs.callPackage ./nix/pkgs/janet-kobo-bundle/package.nix {
          inherit koboInstallPath;
          targetJanet = armv7lPkgs.janet;
          targetGlibc = armv7lPkgs.glibc;
          targetLibgcc = armv7lPkgs.stdenv.cc.cc.lib;
          bundledNativeLibPackages = [
            janet-skia-bridge-kobo
            skiaKobo
          ];
          bundledTreePackages = [
            otterFonts
            spork-netrepl-kobo
          ];
          bundledJanetBundles = [
            {
              name = "otter";
              src = ./.;
            }
          ];
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.janet
          pkgs.gcc
          pkgs.gnumake
          pkgs.pkg-config
          pkgs.SDL2
          skia
          jeep
          jfmt
          janet-spork
          janetOtterSdl
          otterFonts
        ];

        shellHook = ''
          export JANET_EINK_JANET_TREE="$PWD/.dev-janet-tree"
          mkdir -p "$JANET_EINK_JANET_TREE"
          export JANET_SPORK_TREE="${janet-spork}/share/janet"

          case ":''${JANET_PATH-}:" in
            *:"$JANET_SPORK_TREE":*) ;;
            *) export JANET_PATH="$JANET_SPORK_TREE''${JANET_PATH:+:$JANET_PATH}" ;;
          esac


          case ":''${JANET_PATH-}:" in
            *:"$JANET_EINK_JANET_TREE":*) ;;
            *) export JANET_PATH="''${JANET_PATH:+$JANET_PATH:}$JANET_EINK_JANET_TREE" ;;
          esac

          case ":$PATH:" in
            *:"$JANET_EINK_JANET_TREE/bin":*) ;;
            *) export PATH="$PATH:$JANET_EINK_JANET_TREE/bin" ;;
          esac

          export OTTER_SKIA_NATIVE="${janetOtterSdl}/lib/janet-skia.so"
          export OTTER_FONT_DIR="${otterFonts}/share/otter/fonts"
          export SDL_VIDEODRIVER=wayland


          echo "Janet dev shell"
          echo "  janet: $(command -v janet)"
          echo "  jeep:  $(command -v jeep)"
          echo "  jfmt:  $(command -v jfmt)"
          echo "  local Janet tree: $JANET_EINK_JANET_TREE"
          echo "  janet-spork: $JANET_SPORK_TREE"
          if command -v janet-netrepl >/dev/null 2>&1; then
            echo "  janet-netrepl: $(command -v janet-netrepl)"
          else
            echo "  janet-netrepl: not installed"
          fi
          echo "  skia native: $OTTER_SKIA_NATIVE"
          echo "  font dir: $OTTER_FONT_DIR"
        '';
      };
    };
}
