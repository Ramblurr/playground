{
  pkgs ? import <nixpkgs> { },
}:
let
  nixpkgs = import (
    fetchTarball "https://github.com/NixOS/nixpkgs/archive/6201e203d09599479a3b3450ed24fa81537ebc4e.tar.gz" 
  ) {};
  jdk = nixpkgs.jdk25;
  clojure = nixpkgs.clojure.override { inherit jdk; };
  libs = [ nixpkgs.lmdb ];
in
pkgs.mkShell {
  packages = [
    jdk
    clojure
  ];
  KONSERVE_LMDB_LIB = "${nixpkgs.lmdb.out}/lib/liblmdb.so";
}
