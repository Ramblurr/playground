(def fbink-module (native "/mnt/onboard/janet-eink-demo/janet/lib/janet-fbink.so"))
(def fbink-print-centered ((fbink-module (quote print-centered)) :value))

(fbink-print-centered "Hello REPL!")
