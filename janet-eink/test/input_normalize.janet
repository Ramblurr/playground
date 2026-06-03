(use ../deps/testament)
(import ../lib/input/raw :as raw)
(import ../lib/input/normalize :as normalize)

(defn event-summary
  [event]
  (when event
    @{:event (get event :event)
      :key (get event :key)
      :pressed? (get event :pressed?)
      :repeat? (get event :repeat?)
      :modifiers (get event :modifiers)
      :source (get event :source)
      :native-code (get event :native-code)}))

(defn system-summary
  [event]
  (when event
    @{:event (get event :event)
      :system (get event :system)
      :active? (get event :active?)
      :phase (get event :phase)
      :native-code (get event :native-code)}))

(deftest normalize-kobo-page-buttons-to-semantic-key-events
  (let [state (normalize/new-state)
        source (raw/source :evdev @{:path "/dev/input/event0" :name "Kobo Buttons"})
        down (event-summary (normalize/record state (raw/make :ev-key :page-forward 1 @{:source source})))
        repeat (event-summary (normalize/record state (raw/make :ev-key :page-forward 2 @{:source source})))
        up (event-summary (normalize/record state (raw/make :ev-key :page-forward 0 @{:source source})))
        back (event-summary (normalize/record state (raw/make :ev-key :page-back 1 @{:source source})))
        observed @{:down down
                   :repeat repeat
                   :up up
                   :back back}]
    (is (deep= @{:down @{:event :key
                         :key :page-forward
                         :pressed? true
                         :repeat? false
                         :modifiers @{}
                         :source :evdev
                         :native-code 194}
                 :repeat @{:event :key
                           :key :page-forward
                           :pressed? true
                           :repeat? true
                           :modifiers @{}
                           :source :evdev
                           :native-code 194}
                 :up @{:event :key
                       :key :page-forward
                       :pressed? false
                       :repeat? false
                       :modifiers @{}
                       :source :evdev
                       :native-code 194}
                 :back @{:event :key
                         :key :page-back
                         :pressed? true
                         :repeat? false
                         :modifiers @{}
                         :source :evdev
                         :native-code 193}}
               observed)
        "normalization maps Kobo page keys to semantic key press/release/repeat events")))

(deftest normalize-tracks-basic-keyboard-modifiers
  (let [state (normalize/new-state)
        source (raw/source :sdl @{:device "keyboard"})]
    (normalize/record state (raw/make :ev-key :left-shift 1 @{:source source}))
    (let [a-down (event-summary (normalize/record state (raw/make :ev-key :a 1 @{:source source})))
          shift-up (event-summary (normalize/record state (raw/make :ev-key :left-shift 0 @{:source source})))
          a-up (event-summary (normalize/record state (raw/make :ev-key :a 0 @{:source source})))
          observed @{:a-down a-down
                     :shift-up shift-up
                     :a-up a-up}]
      (is (deep= @{:a-down @{:event :key
                             :key :a
                             :pressed? true
                             :repeat? false
                             :modifiers @{:shift true}
                             :source :sdl
                             :native-code 30}
                   :shift-up @{:event :key
                               :key :left-shift
                               :pressed? false
                               :repeat? false
                               :modifiers @{}
                               :source :sdl
                               :native-code 42}
                   :a-up @{:event :key
                           :key :a
                           :pressed? false
                           :repeat? false
                           :modifiers @{}
                           :source :sdl
                           :native-code 30}}
                 observed)
          "normalization tracks basic keyboard modifiers independently from key identity"))))

(deftest normalize-fake-system-codes-without-ui-callbacks
  (let [state (normalize/new-state)
        source (raw/source :evdev @{:path "fake"})
        observed @{:charging (system-summary (normalize/record state (raw/make :ev-key :charging 1 @{:source source})))
                   :not-charging (system-summary (normalize/record state (raw/make :ev-key :not-charging 1 @{:source source})))
                   :ready-suspend (system-summary (normalize/record state (raw/make :ev-key :ready-to-suspend 1 @{:source source})))}]
    (is (deep= @{:charging @{:event :system
                             :system :charging
                             :active? true
                             :phase nil
                             :native-code 10020}
                 :not-charging @{:event :system
                                 :system :charging
                                 :active? false
                                 :phase nil
                                 :native-code 10021}
                 :ready-suspend @{:event :power
                                  :system nil
                                  :active? nil
                                  :phase :ready-to-suspend
                                  :native-code 10031}}
               observed)
        "fake/system codes normalize to system or power records without invoking UI callbacks")))

(deftest normalize-kobo-touch-button-codes-to-known-low-level-names
  (let [state (normalize/new-state)
        source (raw/source :kobo-fbink-scan @{:path "/dev/input/event1" :name "cyttsp5_mt"})
        tool-down (event-summary (normalize/record state (raw/make :ev-key :touch-tool-finger 1 @{:source source})))
        contact-down (event-summary (normalize/record state (raw/make :ev-key :touch-contact 1 @{:source source})))
        contact-up (event-summary (normalize/record state (raw/make :ev-key :touch-contact 0 @{:source source})))
        tool-up (event-summary (normalize/record state (raw/make :ev-key :touch-tool-finger 0 @{:source source})))
        observed @{:tool-down tool-down
                   :contact-down contact-down
                   :contact-up contact-up
                   :tool-up tool-up}]
    (is (deep= @{:tool-down @{:event :key
                              :key :touch-tool-finger
                              :pressed? true
                              :repeat? false
                              :modifiers @{}
                              :source :kobo-fbink-scan
                              :native-code 325}
                 :contact-down @{:event :key
                                 :key :touch-contact
                                 :pressed? true
                                 :repeat? false
                                 :modifiers @{}
                                 :source :kobo-fbink-scan
                                 :native-code 330}
                 :contact-up @{:event :key
                               :key :touch-contact
                               :pressed? false
                               :repeat? false
                               :modifiers @{}
                               :source :kobo-fbink-scan
                               :native-code 330}
                 :tool-up @{:event :key
                            :key :touch-tool-finger
                            :pressed? false
                            :repeat? false
                            :modifiers @{}
                            :source :kobo-fbink-scan
                            :native-code 325}}
               observed)
        "Kobo touch panel BTN_TOOL_FINGER/BTN_TOUCH events are identified instead of reported as unknown keys")))

(deftest normalize-sdl-key-events-by-sdl-keycode-not-evdev-code
  (let [state (normalize/new-state)
        source-a (raw/source :sdl @{:device "keyboard" :sdl-keycode 97 :sdl-scancode 4})
        source-b (raw/source :sdl @{:device "keyboard" :sdl-keycode 98 :sdl-scancode 5})
        source-shift (raw/source :sdl @{:device "keyboard" :sdl-keycode 1073742049 :sdl-scancode 225})
        a-down (event-summary (normalize/record state (raw/make :ev-key 97 1 @{:source source-a})))
        b-down-from-legacy-pseudo-code (event-summary (normalize/record state (raw/make :ev-key 28677 1 @{:source source-b})))
        shift-down (event-summary (normalize/record state (raw/make :ev-key 1073742049 1 @{:source source-shift})))
        b-down-with-shift (event-summary (normalize/record state (raw/make :ev-key 98 1 @{:source source-b})))
        observed @{:a-down a-down
                   :b-down-from-legacy-pseudo-code b-down-from-legacy-pseudo-code
                   :shift-down shift-down
                   :b-down-with-shift b-down-with-shift}]
    (is (deep= @{:a-down @{:event :key
                           :key :a
                           :pressed? true
                           :repeat? false
                           :modifiers @{}
                           :source :sdl
                           :native-code 97}
                 :b-down-from-legacy-pseudo-code @{:event :key
                                                   :key :b
                                                   :pressed? true
                                                   :repeat? false
                                                   :modifiers @{}
                                                   :source :sdl
                                                   :native-code 98}
                 :shift-down @{:event :key
                               :key :left-shift
                               :pressed? true
                               :repeat? false
                               :modifiers @{:shift true}
                               :source :sdl
                               :native-code 1073742049}
                 :b-down-with-shift @{:event :key
                                      :key :b
                                      :pressed? true
                                      :repeat? true
                                      :modifiers @{:shift true}
                                      :source :sdl
                                      :native-code 98}}
               observed)
        "SDL keyboard normalization uses SDL keycodes from native source metadata instead of Linux evdev code lookup")))

(deftest normalize-ignores-non-key-records-and-preserves-unknown-key-codes
  (let [state (normalize/new-state)
        observed @{:abs-result (normalize/record state (raw/make :ev-abs :abs-mt-position-x 42))
                   :unknown-key (event-summary (normalize/record state (raw/make :ev-key 4242 1)))}]
    (is (deep= @{:abs-result nil
                 :unknown-key @{:event :key
                                :key :unknown
                                :pressed? true
                                :repeat? false
                                :modifiers @{}
                                :source nil
                                :native-code 4242}}
               observed)
        "low-level key normalization ignores non-key records while preserving unknown native key codes")))

(run-tests!)
