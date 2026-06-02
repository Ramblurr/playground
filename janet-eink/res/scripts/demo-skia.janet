(def skia-module (native "/mnt/onboard/janet-eink-demo/janet/lib/janet-skia.so"))
(def skia-present-demo ((skia-module (quote present-demo)) :value))

(skia-present-demo true)
