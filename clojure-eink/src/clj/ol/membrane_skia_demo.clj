(ns ol.membrane-skia-demo
  (:require
   [membrane.ui :as ui]
   [ol.membrane.backend.skia :as backend]
   [ol.project :as project]))

(def paragraph-text
  "This screen is rendered by Skia + SkParagraph into a native gray8 buffer, then presented through FBInk. If you see this text, you are on the SKIA path, not Java2D.")

(def unicode-smoke-text
  "Skia Unicode smoke: Café — Ω")

(defn- bounded
  [lo hi value]
  (max lo (min hi value)))

(defn- scaled-font-size
  [width divisor lo hi]
  (int (bounded lo hi (/ (double width) divisor))))

(defn- approximate-text-bounds
  [font text]
  (let [size (double (or (:size font) (:size ui/default-font)))]
    [(* 0.58 size (count (str text)))
     (* 1.35 size)]))

(defn- measured-text-bounds
  [context font text]
  (if context
    (backend/text-bounds context font text)
    (approximate-text-bounds font text)))

(defn- centered-label
  [context text font width height]
  (let [[label-width label-height] (measured-text-bounds context font text)]
    (ui/translate (/ (- width label-width) 2.0)
                  (/ (- height label-height) 2.0)
                  (ui/label text font))))

(defn demo-ui
  [{:keys [width height context]
    :or   {width 800 height 600}}]
  (let [margin          (bounded 12 56 (/ (double width) 14.0))
        title-font      (ui/font "Noto Sans" (scaled-font-size width 17 18 44))
        body-font       (ui/font "Noto Serif" (scaled-font-size width 31 13 26))
        small-font      (ui/font "Noto Sans" (scaled-font-size width 36 12 22))
        button-font     (ui/font "Noto Sans" (scaled-font-size width 35 12 24))
        paragraph-width (max 80.0 (- (double width) (* 2.0 margin)))
        title-y         margin
        paragraph-y     (+ title-y (:size title-font) (/ margin 1.4))
        smoke-y         (max (+ paragraph-y (* 3.2 (:size body-font)))
                             (- height margin 68))
        button-width    (bounded 120 (- width (* 2 margin)) (* 0.52 width))
        button-height   (bounded 34 72 (/ (double height) 7.0))
        button-y        (- height margin button-height)]
    (ui/fixed-bounds
     [width height]
     [(ui/with-color [1 1 1]
        (ui/rectangle width height))
      (ui/with-color [0 0 0]
        (ui/translate margin title-y
                      (ui/label "SKIA renderer on FBInk" title-font))
        (ui/translate margin paragraph-y
                      (backend/paragraph paragraph-text body-font paragraph-width))
        (ui/translate margin smoke-y
                      (ui/label unicode-smoke-text small-font)))
      (ui/translate margin button-y
                    [(ui/with-color [0.92 0.92 0.92]
                       (ui/rounded-rectangle button-width button-height 8))
                     (ui/with-color [0 0 0]
                       (ui/with-stroke-width
                         2
                         (ui/with-style :membrane.ui/style-stroke
                           (ui/rounded-rectangle button-width button-height 8)))
                       (centered-label context
                                       "Rendered by Skia"
                                       button-font
                                       button-width
                                       button-height))])])))

(defn demo-view
  [{:keys [container-size context]}]
  (let [[width height] container-size]
    (demo-ui {:width   width
              :height  height
              :context context})))

(defn- run-once!
  [opts]
  (let [context (backend/open-context! opts)]
    (try
      (project/log-time! (str "starting Skia Membrane render " (:width context) "x" (:height context)))
      (let [result (backend/render-view! context
                                         demo-view
                                         (assoc opts :include-container-info true))]
        (project/log-time! "finished Skia Membrane render")
        (if (:presented? result)
          (println "presented Skia Membrane demo" (:width context) "x" (:height context)
                   "via" (:native-lib context))
          (println "rendered Skia Membrane demo" (:width context) "x" (:height context)
                   "without native present"))
        result)
      (finally
        (backend/close-context! context)))))

(defn -main
  [& args]
  (project/log-time! "entered ol.membrane-skia-demo/-main")
  (let [opts (project/parse-args args)]
    (project/log-time! "parsed args")
    (if (:help? opts)
      (do
        (println (project/usage))
        (println "Skia Membrane demo options: set EINK_SKIA_NATIVE_LIB and EINK_FONT_DIR; use --present/--no-present --width N --height N --no-wait --no-flash"))
      (run-once! opts))))
