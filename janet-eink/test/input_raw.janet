(use ../deps/testament)
(import ../lib/input/raw :as raw)

(defn contains?
  [s needle]
  (not (nil? (string/find needle s))))

(deftest raw-input-records-use-canonical-shape
  (let [source (raw/source :evdev @{:path "/dev/input/event1" :name "Kobo Buttons"})
        record (raw/make :ev-key :page-forward 1 @{:time @{:sec 7 :usec 8}
                                                     :source source})
        observed @{:type (get record :type)
                   :code (get record :code)
                   :value (get record :value)
                   :time (get record :time)
                   :source (get record :source)
                   :raw? (raw/raw-record? record)}]
    (is (deep= @{:type 1
                 :code 194
                 :value 1
                 :time @{:sec 7 :usec 8}
                 :source @{:kind :evdev
                           :path "/dev/input/event1"
                           :name "Kobo Buttons"}
                 :raw? true}
               observed)
        "raw input records keep type/code/value/time/source in one canonical shape")))

(deftest raw-input-formatting-is-human-readable
  (let [source (raw/source :simulated-hardware @{:control :page-forward})
        record (raw/make :ev-key :page-forward 1 @{:time @{:sec 1 :usec 250}
                                                     :source source})
        formatted (raw/format-record record)
        observed @{:mentions-source? (contains? formatted "simulated-hardware")
                   :mentions-type? (contains? formatted "EV_KEY")
                   :mentions-code? (contains? formatted "page-forward")
                   :mentions-value? (contains? formatted "value=1")
                   :mentions-time? (contains? formatted "1.000250")}]
    (is (deep= @{:mentions-source? true
                 :mentions-type? true
                 :mentions-code? true
                 :mentions-value? true
                 :mentions-time? true}
               observed)
        "raw input formatter includes source, named type/code, value, and timestamp")))

(run-tests!)
