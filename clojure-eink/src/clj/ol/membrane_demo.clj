(ns ol.membrane-demo
  (:require
   [membrane.ui :as ui]
   [ol.membrane.eink-backend :as backend]
   [ol.project :as project]))


(defn- centered-label
  [text font width height]
  (let [[label-width label-height] (backend/text-bounds font text)]
    (ui/translate (/ (- width label-width) 2.0)
                  (/ (- height label-height) 2.0)
                  (ui/label text font))))

(defn demo-ui
  [{:keys [width height]
    :or   {width 800 height 600}}]
  (let [title-font    (ui/font nil 42)
        body-font     (ui/font nil 30)
        button-font   (ui/font nil 28)
        button-width  360
        button-height 82
        button-radius 8
        content       [(ui/with-color [1 1 1]
                        (ui/rectangle width height))
                       (ui/with-color [0 0 0]
                         (ui/translate 48 72
                                       (ui/label "Membrane on FBInk" title-font))
                         (ui/translate 48 136
                                       (ui/label "Java2D grayscale -> FBInk" body-font)))
                       (ui/translate 48 210
                                     [(ui/with-color [0.94 0.94 0.94]
                                        (ui/rounded-rectangle button-width button-height button-radius))
                                      (ui/with-color [0 0 0]
                                        (ui/with-stroke-width
                                          3
                                          (ui/with-style :membrane.ui/style-stroke
                                            (ui/rounded-rectangle button-width button-height button-radius)))
                                        (centered-label "Click Me" button-font button-width button-height))])]]
    (ui/fixed-bounds [width height] content)))
(defn- demo-view
  [{:keys [container-size]}]
  (let [[width height] container-size]
    (demo-ui {:width width :height height})))

(defn- loop-request?
  [args]
  (some #{"--loop"} args))

(defn- without-loop-flag
  [args]
  (remove #(= "--loop" %) args))

(defn- reload-demo!
  []
  (doseq [path ["src/clj/ol/membrane/eink_backend.clj"
                "src/clj/ol/membrane_demo.clj"]]
    (load-file path)
    (println "reloaded" path))
  (flush))

(defn- run-once!
  [opts]
  (let [context (backend/open-context! opts)]
    (try
      (let [width  (:width context)
            height (:height context)
            elem   (demo-ui {:width width :height height})
            result (do
                     (project/log-time! (str "starting Membrane render " width "x" height))
                     (let [result (if (:present? opts)
                                    (backend/present-frame! context elem opts)
                                    (backend/render-frame! context elem opts))]
                       (project/log-time! "finished Membrane render")
                       result))
            image  (:image result)]
        (when-let [png (:png opts)]
          (project/log-time! "starting PNG write")
          (println "wrote" (project/write-png! image png))
          (project/log-time! "finished PNG write"))
        (if (:presented? result)
          (println "presented Membrane demo" width "x" height "via" (:native-lib context)
                   "mode" (name (:present-kind result)))
          (println "rendered Membrane demo" width "x" height "without native present"
                   "mode" (name (or (:present-kind result) :no-present))))
        result)
      (finally
        (backend/close-context! context)))))

(defn -main
  [& args]
  (project/log-time! "entered ol.membrane-demo/-main")
  (let [loop? (loop-request? args)
        opts  (project/parse-args (without-loop-flag args))]
    (project/log-time! "parsed args")
    (if (:help? opts)
      (do
        (println (project/usage))
        (println "Membrane demo options: --loop"))
      (if loop?
        (backend/run-loop! demo-view (assoc opts
                                            :include-container-info true
                                            :reload! reload-demo!))
        (run-once! opts)))))
