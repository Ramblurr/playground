{
  stdenvNoCC,
  janet,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "jfmt";
  version = "0.0.1";

  src = ./.;

  sporkSrc = fetchFromGitHub {
    owner = "janet-lang";
    repo = "spork";
    rev = "993887a8dbc9387af3b037418f02ef8e2b42b275";
    hash = "sha256-4oKmRjwDMRwlnntHOh3k2XG3pNxQ239Hgvw7zlokoCQ=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm644 "$sporkSrc/spork/fmt.janet" "$out/share/janet/spork/fmt.janet"
    install -Dm755 jfmt.janet "$out/bin/jfmt"
    substituteInPlace "$out/bin/jfmt" \
      --replace-fail '#!/usr/bin/env janet' '#!${janet}/bin/janet' \
      --replace-fail '@jfmtSyspath@' "$out/share/janet"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    formatted=$(printf '(defn foo [x](+ x 1))\n' | "$out/bin/jfmt")
    test "$formatted" = '(defn foo [x] (+ x 1))'

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    changed="$tmp/changed.janet"
    unchanged="$tmp/unchanged.janet"

    printf '(defn foo [x](+ x 1))\n' > "$changed"
    printf '(defn bar [y] (+ y 2))\n' > "$unchanged"
    jfmtOutput=$("$out/bin/jfmt" "$changed" "$unchanged")
    test "$jfmtOutput" = "$changed"
    test "$(cat "$changed")" = '(defn foo [x] (+ x 1))'

    jfmtOutput=$("$out/bin/jfmt" "$unchanged")
    test -z "$jfmtOutput"

    printf '(defn baz [z](+ z 3))\n' > "$changed"
    before=$(cat "$changed")
    jfmtOutput=$("$out/bin/jfmt" --check "$changed" "$unchanged")
    after=$(cat "$changed")
    test "$jfmtOutput" = "$changed"
    test "$after" = "$before"

    jfmtOutput=$("$out/bin/jfmt" -q "$changed")
    test -z "$jfmtOutput"

    runHook postInstallCheck
  '';
}
