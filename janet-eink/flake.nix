{
  description = "Barebones Janet build for ARMv7l/Kobo";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    fbink-src.url = "path:/home/ramblurr/src/github.com/NiLuJe/FBInk";
    fbink-src.flake = false;
    spork-src.url = "path:/home/ramblurr/src/github.com/janet-lang/spork";
    spork-src.flake = false;
  };

  outputs = { nixpkgs, fbink-src, spork-src, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      armv7lPkgs = pkgs.pkgsCross.armv7l-hf-multiplatform;
      koboInstallPath = "/mnt/onboard/janet-eink-demo/janet";

      fbinkKobo = armv7lPkgs.callPackage ./nix/pkgs/fbink/package.nix {
        src = fbink-src;
        version = "janet-eink-poc";
        device = "KOBO";
      };

      janetFbinkBridgeKobo = armv7lPkgs.callPackage ./nix/pkgs/janet-fbink-bridge/package.nix {
        src = ./.;
        janet = armv7lPkgs.janet;
        fbink = fbinkKobo;
      };

      skiaKobo = armv7lPkgs.callPackage ./nix/pkgs/skia/package.nix {
        stdenv = armv7lPkgs.clangStdenv;
      };

      sporkNetreplKobo = armv7lPkgs.callPackage ./nix/pkgs/spork-netrepl/package.nix {
        inherit koboInstallPath;
        src = spork-src;
        janet = armv7lPkgs.janet;
      };
    in
    {
      packages.${system} = {
        default = armv7lPkgs.janet;
        janet-armv7l = armv7lPkgs.janet;
        fbink-kobo = fbinkKobo;
        janet-fbink-bridge-kobo = janetFbinkBridgeKobo;
        skia-kobo = skiaKobo;
        spork-netrepl-kobo = sporkNetreplKobo;
        kobo-bundle = pkgs.callPackage ./nix/pkgs/janet-kobo-bundle/package.nix {
          inherit koboInstallPath;
          targetJanet = armv7lPkgs.janet;
          targetGlibc = armv7lPkgs.glibc;
          targetLibgcc = armv7lPkgs.stdenv.cc.cc.lib;
          bundledNativeLibPackages = [
            janetFbinkBridgeKobo
            skiaKobo
          ];
          bundledTreePackages = [
            sporkNetreplKobo
          ];
          bundledPrograms = [
            {
              name = "hello-fbink.janet";
              src = ./scripts/hello-fbink.janet;
            }
          ];
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.janet
          pkgs.jpm
          pkgs.gcc
        ];

        shellHook = ''
          export JANET_EINK_JPM_TREE="$PWD/.dev-jpm-tree"
          export PATH="$JANET_EINK_JPM_TREE/bin:$PATH"
          export JANET_PATH="$JANET_EINK_JPM_TREE/lib''${JANET_PATH:+:$JANET_PATH}"
          echo "Janet dev shell"
          echo "  janet: $(command -v janet)"
          echo "  jpm:   $(command -v jpm)"
          echo "  local JPM tree: $JANET_EINK_JPM_TREE"
          if [ ! -x "$JANET_EINK_JPM_TREE/bin/janet-netrepl" ]; then
            echo "  spork netrepl not installed yet; run:"
            echo "    (cd /home/ramblurr/src/github.com/janet-lang/spork && jpm --tree=$JANET_EINK_JPM_TREE install)"
          fi
        '';
      };
    };
}
