# Clojure e-ink PoC status

## Summary

The Kobo rendering path works:

```text
Clojure -> Java2D grayscale BufferedImage -> Java FFM -> libclojure_eink.so -> FBInk -> /dev/fb0
```

Cold startup remains slow, but a long-lived JVM is acceptable for the target app. Warm rendering looks viable when `TextLayout` results are cached and the render target image is reused.

## Current finding

On Kobo (`1264 x 1680`):

- default `LineBreakMeasurer` warm renders: about `0.8-1.1 s`;
- cached-layout warm renders: about `20-50 ms`;
- cached-layout plus reused `BufferedImage`: latest warm render about `18.5 ms`;
- cached-layout plus reused image with `--no-wait --no-flash` present: about `18.5 ms` render + `192.5 ms` present;
- cached-layout final present with default wait: about `793 ms` present after a `~22 ms` render.

See [`PERF_NOTES.md`](PERF_NOTES.md) for benchmark commands and detailed timings.

## Current workflow

Build and deploy:

```sh
scripts/package-kobo-dist.sh
rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ \
  root@kobo-lan:/mnt/onboard/clojure-eink-demo/
```

Run one-shot benchmarks:

```sh
cd /mnt/onboard/clojure-eink-demo
./run-demo.sh --renders 5 --present-last --render-mode cached-layout
```

Run the long-lived reload loop:

```sh
cd /mnt/onboard/clojure-eink-demo
./run-loop.sh --render-mode cached-layout --reuse-image --no-wait --no-flash
```

Loop commands:

```text
render --renders 1 --no-present
reload
render --renders 1 --present-last
quit
```

`reload` loads `src/clj/ol/project.clj` from the deployed source tree, so development can rsync new Clojure code and reload without restarting the JVM.

## Next work

- Turn cached layouts into a real page cache or display list.
- Add a small control protocol that is easier to drive remotely than stdin.
- Decide whether Java2D text quality/performance is good enough before exploring native FreeType/HarfBuzz.
