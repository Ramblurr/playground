Clojure e-ink PoC Kobo dist
===========================

Copy this directory to the Kobo onboard partition, for example:

  rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ root@kobo-lan:/mnt/onboard/clojure-eink-demo/

On the Kobo:

  cd /mnt/onboard/clojure-eink-demo
  time ./run-demo.sh --renders 5 --present-last --render-mode cached-layout

Long-lived reload loop:

  ./run-loop.sh --render-mode cached-layout --reuse-image --no-wait --no-flash

Membrane Skia render proof (production AOT classpath):

  ./run-membrane-skia-demo.sh --no-wait --no-flash

Source-loaded Skia render proof for development comparisons:

  ./run-membrane-skia-demo-source.sh --no-wait --no-flash

Membrane Java2D FBInk render proof:

  ./run-membrane-demo.sh --no-wait --no-flash

Long-lived Membrane Java2D loop with gray8 damage tracking:

  ./run-membrane-loop.sh --no-wait --no-flash

Loop commands:

  render --renders 1 --no-present
  reload
  render --renders 1 --present-last
  quit

The demo prints elapsed timings from inside Clojure. Compare those with shell
`time` to estimate JVM/Clojure startup overhead before ol.project/-main.
