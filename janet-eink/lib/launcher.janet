(import ./demo/ui-hello-world :as hello)
(import ./input :as input)
(import ./device :as device)

(defn- usage-input-dump
  []
  (print "Usage: otter input-dump [--raw|--normalized] [--device PATH] [--limit N] [--timeout-ms N] [--idle-limit N] [--grab|--no-grab]")
  (print "")
  (print "Print raw evdev-shaped input records or normalized low-level key/system records."))

(defn- parse-int-option
  [name value]
  (when (nil? value)
    (error (string name " requires a value")))
  (let [parsed (scan-number value)]
    (unless (and (= :number (type parsed)) (= parsed (math/floor parsed)))
      (error (string name " requires an integer")))
    parsed))

(defn- parse-input-dump
  [args]
  (let [opts @{:normalized? false
               :limit 200
               :timeout-ms 1000
               :idle-limit 10
               :grab? false}]
    (var i 1)
    (while (< i (length args))
      (let [arg (get args i)]
        (case arg
          "--raw"
          (put opts :normalized? false)

          "--normalized"
          (put opts :normalized? true)

          "--device"
          (do
            (++ i)
            (put opts :path (get args i)))

          "--limit"
          (do
            (++ i)
            (put opts :limit (parse-int-option "--limit" (get args i))))

          "--timeout-ms"
          (do
            (++ i)
            (put opts :timeout-ms (parse-int-option "--timeout-ms" (get args i))))

          "--timeout"
          (do
            (++ i)
            (put opts :timeout-ms (parse-int-option "--timeout" (get args i))))

          "--idle-limit"
          (do
            (++ i)
            (put opts :idle-limit (parse-int-option "--idle-limit" (get args i))))

          "--grab"
          (put opts :grab? true)

          "--no-grab"
          (put opts :grab? false)

          "--help"
          (put opts :help? true)

          "-h"
          (put opts :help? true)

          (error (string "unknown input-dump option: " arg)))
        (++ i)))
    opts))

(defn- run-with-device
  [dev args]
  (case (get args 0 nil)
    "input-dump"
    (let [opts (parse-input-dump args)]
      (if (get opts :help? false)
        (do
          (usage-input-dump)
          0)
        (input/dump dev opts)))

    (do
      (hello/run dev ;args)
      0)))

(defn run
  [& args]
  (let [dev (device/detect)
        result (protect (run-with-device dev args))]
    (device/close dev)
    (if (get result 0)
      (os/exit (get result 1))
      (error (get result 1)))))
