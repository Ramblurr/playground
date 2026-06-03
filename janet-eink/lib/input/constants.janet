# Linux evdev and Otter low-level input constants.

(def event-types
  @{:ev-syn 0
    :ev-key 1
    :ev-rel 2
    :ev-abs 3
    :ev-msc 4})

(def event-type-labels
  @{:ev-syn "EV_SYN"
    :ev-key "EV_KEY"
    :ev-rel "EV_REL"
    :ev-abs "EV_ABS"
    :ev-msc "EV_MSC"})

(def syn-codes
  @{:syn-report 0})

(def syn-code-labels
  @{:syn-report "SYN_REPORT"})

(def abs-codes
  @{:abs-x 0
    :abs-y 1
    :abs-mt-slot 47
    :abs-mt-touch-major 48
    :abs-mt-touch-minor 49
    :abs-mt-width-major 50
    :abs-mt-width-minor 51
    :abs-mt-orientation 52
    :abs-mt-position-x 53
    :abs-mt-position-y 54
    :abs-mt-tool-type 55
    :abs-mt-blob-id 56
    :abs-mt-tracking-id 57
    :abs-mt-pressure 58
    :abs-mt-distance 59})

(def abs-code-labels
  @{:abs-x "ABS_X"
    :abs-y "ABS_Y"
    :abs-mt-slot "ABS_MT_SLOT"
    :abs-mt-touch-major "ABS_MT_TOUCH_MAJOR"
    :abs-mt-touch-minor "ABS_MT_TOUCH_MINOR"
    :abs-mt-width-major "ABS_MT_WIDTH_MAJOR"
    :abs-mt-width-minor "ABS_MT_WIDTH_MINOR"
    :abs-mt-orientation "ABS_MT_ORIENTATION"
    :abs-mt-position-x "ABS_MT_POSITION_X"
    :abs-mt-position-y "ABS_MT_POSITION_Y"
    :abs-mt-tool-type "ABS_MT_TOOL_TYPE"
    :abs-mt-blob-id "ABS_MT_BLOB_ID"
    :abs-mt-tracking-id "ABS_MT_TRACKING_ID"
    :abs-mt-pressure "ABS_MT_PRESSURE"
    :abs-mt-distance "ABS_MT_DISTANCE"})

(def key-codes
  @{:escape 1
    :a 30
    :q 16
    :left-ctrl 29
    :left-shift 42
    :right-shift 54
    :left-alt 56
    :right-alt 100
    :right-ctrl 97
    :left-meta 125
    :right-meta 126
    :enter 28
    :home 102
    :power 116
    :sleep-cover 35
    :light 90
    :touch-tool-pen 320
    :touch-tool-finger 325
    :touch-contact 330
    :touch-tool-doubletap 333
    :page-back 193
    :page-forward 194
    :eraser 331
    :highlighter 332})

(def extra-key-code-names
  @{59 :sleep-cover})

(def key-code-labels
  @{:escape "KEY_ESC"
    :a "KEY_A"
    :q "KEY_Q"
    :left-ctrl "KEY_LEFTCTRL"
    :left-shift "KEY_LEFTSHIFT"
    :right-shift "KEY_RIGHTSHIFT"
    :left-alt "KEY_LEFTALT"
    :right-alt "KEY_RIGHTALT"
    :right-ctrl "KEY_RIGHTCTRL"
    :left-meta "KEY_LEFTMETA"
    :right-meta "KEY_RIGHTMETA"
    :enter "KEY_ENTER"
    :home "KEY_HOME"
    :power "KEY_POWER"
    :sleep-cover "KEY_SLEEP_COVER"
    :light "KEY_LIGHT"
    :touch-tool-pen "BTN_TOOL_PEN"
    :touch-tool-finger "BTN_TOOL_FINGER"
    :touch-contact "BTN_TOUCH"
    :touch-tool-doubletap "BTN_TOOL_DOUBLETAP"
    :page-back "KEY_PAGEBACK"
    :page-forward "KEY_PAGEFORWARD"
    :eraser "KEY_ERASER"
    :highlighter "KEY_HIGHLIGHTER"})

(def fake-system-codes
  @{:into-screensaver 10000
    :out-of-screensaver 10001
    :exiting-screensaver 10002
    :usb-plug-in 10010
    :usb-plug-out 10011
    :charging 10020
    :not-charging 10021
    :wakeup-from-suspend 10030
    :ready-to-suspend 10031
    :usb-device-plug-in 10040
    :usb-device-plug-out 10041})

(def fake-system-code-labels
  @{:into-screensaver "IntoSS"
    :out-of-screensaver "OutOfSS"
    :exiting-screensaver "ExitingSS"
    :usb-plug-in "UsbPlugIn"
    :usb-plug-out "UsbPlugOut"
    :charging "Charging"
    :not-charging "NotCharging"
    :wakeup-from-suspend "WakeupFromSuspend"
    :ready-to-suspend "ReadyToSuspend"
    :usb-device-plug-in "UsbDevicePlugIn"
    :usb-device-plug-out "UsbDevicePlugOut"})

(def sdl-keycodes
  @{:escape 27
    :a 97
    :b 98
    :c 99
    :d 100
    :e 101
    :f 102
    :g 103
    :h 104
    :i 105
    :j 106
    :k 107
    :l 108
    :m 109
    :n 110
    :o 111
    :p 112
    :q 113
    :r 114
    :s 115
    :t 116
    :u 117
    :v 118
    :w 119
    :x 120
    :y 121
    :z 122
    :enter 13
    :home 1073741898
    :page-back 1073741899
    :page-forward 1073741902
    :left-ctrl 1073742048
    :left-shift 1073742049
    :left-alt 1073742050
    :left-meta 1073742051
    :right-ctrl 1073742052
    :right-shift 1073742053
    :right-alt 1073742054
    :right-meta 1073742055})

(def sdl-keycode-labels
  @{:escape "SDLK_ESCAPE"
    :a "SDLK_a"
    :b "SDLK_b"
    :c "SDLK_c"
    :d "SDLK_d"
    :e "SDLK_e"
    :f "SDLK_f"
    :g "SDLK_g"
    :h "SDLK_h"
    :i "SDLK_i"
    :j "SDLK_j"
    :k "SDLK_k"
    :l "SDLK_l"
    :m "SDLK_m"
    :n "SDLK_n"
    :o "SDLK_o"
    :p "SDLK_p"
    :q "SDLK_q"
    :r "SDLK_r"
    :s "SDLK_s"
    :t "SDLK_t"
    :u "SDLK_u"
    :v "SDLK_v"
    :w "SDLK_w"
    :x "SDLK_x"
    :y "SDLK_y"
    :z "SDLK_z"
    :enter "SDLK_RETURN"
    :home "SDLK_HOME"
    :page-back "SDLK_PAGEUP"
    :page-forward "SDLK_PAGEDOWN"
    :left-ctrl "SDLK_LCTRL"
    :left-shift "SDLK_LSHIFT"
    :left-alt "SDLK_LALT"
    :left-meta "SDLK_LGUI"
    :right-ctrl "SDLK_RCTRL"
    :right-shift "SDLK_RSHIFT"
    :right-alt "SDLK_RALT"
    :right-meta "SDLK_RGUI"})

(defn- number-value?
  [value]
  (= :number (type value)))

(defn- reverse-lookup
  [table code]
  (var found nil)
  (eachp [name value] table
    (when (and (nil? found) (= value code))
      (set found name)))
  found)

(defn- code-for
  [table label name]
  (if (number-value? name)
    name
    (let [code (get table name nil)]
      (if (nil? code)
        (error (string "unknown " label ": " name))
        code))))

(defn event-type-code
  [name]
  (code-for event-types "event type" name))

(defn event-type-name
  [code]
  (reverse-lookup event-types code))

(defn event-type-label
  [code]
  (let [name (event-type-name code)]
    (if name (get event-type-labels name) (string code))))

(defn syn-code
  [name]
  (code-for syn-codes "syn code" name))

(defn syn-name
  [code]
  (reverse-lookup syn-codes code))

(defn syn-label
  [code]
  (let [name (syn-name code)]
    (if name (get syn-code-labels name) (string code))))

(defn abs-code
  [name]
  (code-for abs-codes "abs code" name))

(defn abs-name
  [code]
  (reverse-lookup abs-codes code))

(defn abs-label
  [code]
  (let [name (abs-name code)]
    (if name (get abs-code-labels name) (string code))))

(defn key-code
  [name]
  (code-for key-codes "key code" name))

(defn key-name
  [code]
  (or (get extra-key-code-names code nil)
      (reverse-lookup key-codes code)))

(defn key-label
  [code]
  (let [name (key-name code)]
    (if name (get key-code-labels name (string name)) (string code))))

(defn sdl-keycode
  [name]
  (code-for sdl-keycodes "SDL keycode" name))

(defn sdl-key-name
  [code]
  (reverse-lookup sdl-keycodes code))

(defn sdl-key-label
  [code]
  (let [name (sdl-key-name code)]
    (if name (get sdl-keycode-labels name (string name)) (string code))))

(defn fake-system-code
  [name]
  (code-for fake-system-codes "fake/system code" name))

(defn fake-system-name
  [code]
  (reverse-lookup fake-system-codes code))

(defn fake-system-label
  [code]
  (let [name (fake-system-name code)]
    (if name (get fake-system-code-labels name) (string code))))
