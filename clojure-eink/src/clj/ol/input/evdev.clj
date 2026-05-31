(ns ol.input.evdev)

(def EV_SYN 0)
(def EV_KEY 1)
(def EV_ABS 3)
(def EV_MSC 4)

(def SYN_REPORT 0)
(def SYN_MT_REPORT 2)
(def SYN_DROPPED 3)

(def ABS_X 0)
(def ABS_Y 1)
(def ABS_PRESSURE 24)
(def ABS_MT_SLOT 47)
(def ABS_MT_TOUCH_MAJOR 48)
(def ABS_MT_TOUCH_MINOR 49)
(def ABS_MT_ORIENTATION 52)
(def ABS_MT_POSITION_X 53)
(def ABS_MT_POSITION_Y 54)
(def ABS_MT_TOOL_TYPE 55)
(def ABS_MT_TRACKING_ID 57)
(def ABS_MT_PRESSURE 58)
(def ABS_MT_DISTANCE 59)

(def BTN_TOOL_FINGER 325)
(def BTN_TOUCH 330)

(def KEY_H 35)
(def KEY_F1 59)
(def KEY_KATAKANA 90)
(def KEY_HOME 102)
(def KEY_POWER 116)
(def KEY_F23 193)
(def KEY_F24 194)
(def BTN_STYLUS 331)
(def BTN_STYLUS2 332)

(def key-actions
  {0 :release
   1 :press
   2 :repeat})

(def event-type-names
  {EV_SYN :ev/syn
   EV_KEY :ev/key
   EV_ABS :ev/abs
   EV_MSC :ev/msc})

(def syn-code-names
  {SYN_REPORT    :syn/report
   SYN_MT_REPORT :syn/mt-report
   SYN_DROPPED   :syn/dropped})

(def abs-code-names
  {ABS_X              :abs/x
   ABS_Y              :abs/y
   ABS_PRESSURE       :abs/pressure
   ABS_MT_SLOT        :abs-mt/slot
   ABS_MT_TOUCH_MAJOR :abs-mt/touch-major
   ABS_MT_TOUCH_MINOR :abs-mt/touch-minor
   ABS_MT_ORIENTATION :abs-mt/orientation
   ABS_MT_POSITION_X  :abs-mt/position-x
   ABS_MT_POSITION_Y  :abs-mt/position-y
   ABS_MT_TOOL_TYPE   :abs-mt/tool-type
   ABS_MT_TRACKING_ID :abs-mt/tracking-id
   ABS_MT_PRESSURE    :abs-mt/pressure
   ABS_MT_DISTANCE    :abs-mt/distance})

(def key-code-names
  {BTN_TOOL_FINGER :btn/tool-finger
   BTN_TOUCH       :btn/touch
   KEY_H           :key/h
   KEY_F1          :key/f1
   KEY_KATAKANA    :key/katakana
   KEY_HOME        :key/home
   KEY_POWER       :key/power
   KEY_F23         :key/f23
   KEY_F24         :key/f24
   BTN_STYLUS      :btn/stylus
   BTN_STYLUS2     :btn/stylus2})

(defn event-type-name
  [type]
  (get event-type-names type :ev/unknown))

(defn event-code-name
  [type code]
  (condp = type
    EV_SYN (get syn-code-names code :syn/unknown)
    EV_ABS (get abs-code-names code :abs/unknown)
    EV_KEY (get key-code-names code :key/unknown)
    nil))

(defn annotate-event
  [event]
  (let [{:keys [type code]} event]
    (assoc event
           :type-name (event-type-name type)
           :code-name (event-code-name type code))))

(defn key-action
  [value]
  (get key-actions value))
