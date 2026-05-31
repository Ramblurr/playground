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
(defn -main
  [& args]
  (project/log-time! "entered ol.membrane-demo/-main")
  (let [opts (project/parse-args args)]
    (project/log-time! "parsed args")
    (if (:help? opts)
      (println (project/usage))
      (let [native-lib   (or (:native-lib opts) (project/default-native-lib))
            native       (when (:native? opts)
                           (when-not native-lib
                             (throw (ex-info "native library path not provided and no default native library was found" {})))
                           (let [loaded (project/load-native native-lib)]
                             (project/log-time! "loaded native library and linked symbols")
                             loaded))
            initialized? (volatile! false)]
        (try
          (when native
            (project/init-native! native)
            (vreset! initialized? true)
            (project/log-time! "initialized FBInk/native backend"))
          (let [width  (or (:width opts)
                           (when native
                             (let [w (project/native-screen-width native)]
                               (project/log-time! (str "queried screen width: " w))
                               w))
                           800)
                height (or (:height opts)
                           (when native
                             (let [h (project/native-screen-height native)]
                               (project/log-time! (str "queried screen height: " h))
                               h))
                           600)
                elem   (demo-ui {:width width :height height})
                image  (do
                         (project/log-time! (str "starting Membrane render " width "x" height))
                         (let [image (backend/render-to-image! elem {:width       width
                                                                       :height      height
                                                                       :image-cache (atom nil)
                                                                       :font-cache  (atom {})})]
                           (project/log-time! "finished Membrane render")
                           image))]
            (when-let [png (:png opts)]
              (project/log-time! "starting PNG write")
              (println "wrote" (project/write-png! image png))
              (project/log-time! "finished PNG write"))
            (if native
              (do
                (project/log-time! "starting native present")
                (project/present-gray8! native (project/image->gray8 image) opts)
                (project/log-time! "finished native present")
                (println "presented Membrane demo" width "x" height "via" native-lib))
              (println "rendered Membrane demo" width "x" height "without native present")))
          (finally
            (when (and native @initialized?)
              (project/log-time! "closing native backend")
              (project/close-native! native)
              (project/log-time! "closed native backend"))))))))
