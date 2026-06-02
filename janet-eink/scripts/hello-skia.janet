(def skia-module (native "/mnt/onboard/janet-eink-demo/janet/lib/janet-skia.so"))
(def skia-render-hello ((skia-module (quote render-hello)) :value))

(skia-render-hello)
