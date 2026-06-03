(use ../deps/testament)
(import ../lib/input/constants :as constants)

(deftest input-constants-resolve-linux-kobo-and-fake-codes
  (let [observed @{:ev-key (constants/event-type-code :ev-key)
                   :ev-abs (constants/event-type-code :ev-abs)
                   :syn-report (constants/syn-code :syn-report)
                   :abs-mt-slot (constants/abs-code :abs-mt-slot)
                   :page-forward-code (constants/key-code :page-forward)
                   :page-forward-name (constants/key-name 194)
                   :sleep-cover-name-35 (constants/key-name 35)
                   :sleep-cover-name-59 (constants/key-name 59)
                   :touch-tool-finger-name (constants/key-name 325)
                   :touch-contact-name (constants/key-name 330)
                   :touch-contact-label (constants/key-label 330)
                   :charging-code (constants/fake-system-code :charging)
                   :charging-name (constants/fake-system-name 10020)
                   :usb-out-name (constants/fake-system-name 10011)}]
    (is (deep= @{:ev-key 1
                 :ev-abs 3
                 :syn-report 0
                 :abs-mt-slot 47
                 :page-forward-code 194
                 :page-forward-name :page-forward
                 :sleep-cover-name-35 :sleep-cover
                 :sleep-cover-name-59 :sleep-cover
                 :touch-tool-finger-name :touch-tool-finger
                 :touch-contact-name :touch-contact
                 :touch-contact-label "BTN_TOUCH"
                 :charging-code 10020
                 :charging-name :charging
                 :usb-out-name :usb-plug-out}
               observed)
        "input constants resolve first Linux, Kobo, and fake/system codes")))

(deftest input-constants-reject-unknown-names
  (let [observed @{:unknown-event-rejected? (not (get (protect (constants/event-type-code :ev-nope)) 0))
                   :unknown-key-rejected? (not (get (protect (constants/key-code :nope)) 0))
                   :unknown-fake-rejected? (not (get (protect (constants/fake-system-code :nope)) 0))
                   :unknown-key-name (constants/key-name 424242)}]
    (is (deep= @{:unknown-event-rejected? true
                 :unknown-key-rejected? true
                 :unknown-fake-rejected? true
                 :unknown-key-name nil}
               observed)
        "input constant lookups reject unknown names and leave unknown numeric codes unnamed")))

(run-tests!)
