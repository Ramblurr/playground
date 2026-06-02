{
  runCommand,
  noto-fonts,
}:

runCommand "otter-fonts" { } ''
  set -euo pipefail
  mkdir -p "$out/share/otter/fonts"
  cp ${noto-fonts}/share/fonts/noto/NotoSans.ttf "$out/share/otter/fonts/NotoSans.ttf"
  cp ${noto-fonts}/share/fonts/noto/NotoSerif.ttf "$out/share/otter/fonts/NotoSerif.ttf"
''
