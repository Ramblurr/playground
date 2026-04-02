{ pkgs ? import <nixpkgs> {} }:

let
  jdk = pkgs.jdk25;
  clojure = pkgs.clojure.override { inherit jdk; };
in
pkgs.mkShell {
  packages = [
    jdk
    clojure
  ];
}
