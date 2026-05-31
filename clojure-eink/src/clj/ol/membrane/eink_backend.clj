(ns ol.membrane.eink-backend
  (:require
   [clojure.string :as str]
   [membrane.toolkit :as tk]
   [membrane.ui :as ui]
   [ol.input.evdev :as evdev]
   [ol.input.kobo :as input.kobo]
   [ol.input.runtime :as input.runtime]
   [ol.project :as project])
  (:import
   [java.awt BasicStroke Color Font Graphics2D RenderingHints]
   [java.awt.geom Path2D$Double Rectangle2D$Double RoundRectangle2D$Double]
   [java.awt.image BufferedImage]))

(def ^:dynamic *g* nil)
(def ^:dynamic *paint-style* :membrane.ui/style-fill)
(def ^:dynamic *font-cache* nil)

(defprotocol IDraw
  :extend-via-metadata true
  (draw [this]))

(ui/add-default-draw-impls! IDraw #'draw)

(defn- color
  [[r g b a]]
  (Color. (float r) (float g) (float b) (float (or a 1.0))))

(defn get-java-font
  [font]
  (let [cache-key font]
    (if-let [cache *font-cache*]
      (if-let [entry (find @cache cache-key)]
        (val entry)
        (let [java-font (Font. (or (:name font) Font/SANS_SERIF)
                               (bit-or (if (= :bold (:weight font)) Font/BOLD 0)
                                       (if (= :italic (:slant font)) Font/ITALIC 0))
                               (int (or (:size font) (:size ui/default-font))))]
          (swap! cache assoc cache-key java-font)
          java-font))
      (Font. (or (:name font) Font/SANS_SERIF)
             (bit-or (if (= :bold (:weight font)) Font/BOLD 0)
                     (if (= :italic (:slant font)) Font/ITALIC 0))
             (int (or (:size font) (:size ui/default-font)))))))

(defn get-font-render-context
  []
  (if *g*
    (.getFontRenderContext ^Graphics2D *g*)
    (java.awt.font.FontRenderContext. (java.awt.geom.AffineTransform.)
                                      RenderingHints/VALUE_TEXT_ANTIALIAS_ON
                                      RenderingHints/VALUE_FRACTIONALMETRICS_ON)))

(defn text-bounds
  [font text]
  (let [^Font jfont (get-java-font font)
        frc         (get-font-render-context)
        lines       (str/split (str text) #"\n" -1)
        metrics     (.getLineMetrics jfont (str text) frc)
        line-height (.getHeight metrics)
        widths      (map (fn [^String line]
                           (.getWidth (.getStringBounds jfont line frc)))
                         lines)]
    [(double (reduce max 0 widths))
     (double (* line-height (count lines)))]))

(defn font-metrics
  [font]
  (let [frc     (get-font-render-context)
        jfont   (get-java-font font)
        metrics (.getLineMetrics ^Font jfont "" frc)]
    {:ascent  (.getAscent metrics)
     :descent (.getDescent metrics)
     :leading (.getLeading metrics)}))

(defn font-line-height
  [font]
  (let [frc     (get-font-render-context)
        jfont   (get-java-font font)
        metrics (.getLineMetrics ^Font jfont "" frc)]
    (.getHeight metrics)))

(defn font-advance-x
  [font s]
  (let [^Font jfont (get-java-font font)
        frc         (get-font-render-context)]
    (.getWidth (.getStringBounds jfont ^String (str s) frc))))

(defmacro ^:private push-stroke
  [& body]
  `(let [stroke# (.getStroke ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setStroke ^Graphics2D *g* stroke#)))))

(defmacro ^:private push-transform
  [& body]
  `(let [transform# (.getTransform ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setTransform ^Graphics2D *g* transform#)))))

(defmacro ^:private push-color
  [& body]
  `(let [color# (.getColor ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setColor ^Graphics2D *g* color#)))))

(defmacro ^:private push-font
  [& body]
  `(let [font# (.getFont ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setFont ^Graphics2D *g* font#)))))

(defmacro ^:private push-clip
  [& body]
  `(let [clip# (.getClip ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setClip ^Graphics2D *g* clip#)))))

(defn- merge-stroke
  [^BasicStroke stroke {:keys [width cap join miter-limit dash dash-phase]}]
  (BasicStroke. (float (or width (.getLineWidth stroke)))
                (int (or cap (.getEndCap stroke)))
                (int (or join (.getLineJoin stroke)))
                (float (or miter-limit (.getMiterLimit stroke)))
                ^floats (or dash (.getDashArray stroke))
                (float (or dash-phase (.getDashPhase stroke)))))

(defn- stroke-or-fill!
  [shape]
  (case *paint-style*
    :membrane.ui/style-fill (.fill ^Graphics2D *g* shape)
    :membrane.ui/style-stroke (.draw ^Graphics2D *g* shape)
    :membrane.ui/style-stroke-and-fill (do
                                         (.draw ^Graphics2D *g* shape)
                                         (.fill ^Graphics2D *g* shape))
    (.fill ^Graphics2D *g* shape)))

(extend-type membrane.ui.Label
  ui/IBounds
  (-bounds [this]
    (text-bounds (:font this) (:text this)))

  IDraw
  (draw [this]
    (let [lines       (str/split (:text this) #"\n" -1)
          font        (get-java-font (:font this))
          frc         (get-font-render-context)
          metrics     (.getLineMetrics ^Font font (:text this) frc)
          ascent      (.getAscent metrics)
          line-height (.getHeight metrics)]
      (push-font
       (.setFont ^Graphics2D *g* font)
       (doseq [[idx line] (map-indexed vector lines)]
         (.drawString ^Graphics2D *g* ^String line (float 0.0) (float (+ ascent (* idx line-height)))))))))

(extend-type membrane.ui.Translate
  IDraw
  (draw [this]
    (push-transform
     (.translate ^Graphics2D *g* (double (:x this)) (double (:y this)))
     (draw (:drawable this)))))

(extend-type membrane.ui.WithColor
  IDraw
  (draw [this]
    (push-color
     (.setColor ^Graphics2D *g* (color (:color this)))
     (doseq [drawable (:drawables this)]
       (draw drawable)))))

(extend-type membrane.ui.WithStyle
  IDraw
  (draw [this]
    (binding [*paint-style* (:style this)]
      (doseq [drawable (:drawables this)]
        (draw drawable)))))

(extend-type membrane.ui.WithStrokeWidth
  IDraw
  (draw [this]
    (push-stroke
     (.setStroke ^Graphics2D *g* (merge-stroke (.getStroke ^Graphics2D *g*)
                                               {:width (:stroke-width this)}))
     (doseq [drawable (:drawables this)]
       (draw drawable)))))

(extend-type membrane.ui.Path
  IDraw
  (draw [this]
    (when-let [[[x y] & more] (seq (:points this))]
      (let [path (Path2D$Double.)]
        (.moveTo path (double x) (double y))
        (doseq [[x y] more]
          (.lineTo path (double x) (double y)))
        (stroke-or-fill! path)))))

(extend-type membrane.ui.Rectangle
  IDraw
  (draw [this]
    (stroke-or-fill! (Rectangle2D$Double. 0 0 (double (:width this)) (double (:height this))))))

(extend-type membrane.ui.RoundedRectangle
  IDraw
  (draw [this]
    (let [arc-size (* 2 (:border-radius this))]
      (stroke-or-fill! (RoundRectangle2D$Double. 0 0
                                                 (double (:width this))
                                                 (double (:height this))
                                                 (double arc-size)
                                                 (double arc-size))))))

(extend-type membrane.ui.Scale
  IDraw
  (draw [this]
    (let [[sx sy] (:scalars this)]
      (push-transform
       (.scale ^Graphics2D *g* (double sx) (double sy))
       (doseq [drawable (:drawables this)]
         (draw drawable))))))

(extend-type membrane.ui.ScissorView
  IDraw
  (draw [this]
    (push-clip
     (let [[ox oy] (:offset this)
           [w h]   (:bounds this)]
       (.clip ^Graphics2D *g* (Rectangle2D$Double. (double ox) (double oy) (double w) (double h)))
       (draw (:drawable this))))))

(extend-type membrane.ui.ScrollView
  IDraw
  (draw [this]
    (draw (ui/scissor-view [0 0]
                           (:bounds this)
                           (let [[x y] (:offset this)]
                             (ui/translate x y (:drawable this)))))))

(defn- compatible-image?
  [^BufferedImage image width height]
  (and image
       (= BufferedImage/TYPE_BYTE_GRAY (.getType image))
       (= width (.getWidth image))
       (= height (.getHeight image))))

(defn- acquire-image
  [width height image-cache]
  (if image-cache
    (if (compatible-image? @image-cache width height)
      @image-cache
      (let [image (BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)]
        (reset! image-cache image)
        image))
    (BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)))

(defn render-to-image!
  [elem {:keys [width height image-cache font-cache]
         :or   {width 800 height 600}}]
  (let [image (acquire-image width height image-cache)
        g     (.createGraphics ^BufferedImage image)]
    (try
      (binding [*g*          g
                *font-cache* (or font-cache (atom {}))]
        (.setRenderingHint ^Graphics2D *g*
                           RenderingHints/KEY_ANTIALIASING
                           RenderingHints/VALUE_ANTIALIAS_ON)
        (.setRenderingHint ^Graphics2D *g*
                           RenderingHints/KEY_TEXT_ANTIALIASING
                           RenderingHints/VALUE_TEXT_ANTIALIAS_ON)
        (.setColor ^Graphics2D *g* Color/WHITE)
        (.fillRect ^Graphics2D *g* 0 0 (int width) (int height))
        (.setColor ^Graphics2D *g* Color/BLACK)
        (draw elem))
      image
      (finally
        (.dispose ^Graphics2D g)))))

(defn- positive-int-ceil
  [n]
  (max 1 (int (Math/ceil (double n)))))

(defn- element-size
  [elem]
  (let [[width height] (ui/bounds elem)]
    [(positive-int-ceil width) (positive-int-ceil height)]))

(defn- toolkit-save-image!
  [dest elem size]
  (let [[width height] (or size (element-size elem))
        image          (render-to-image! elem {:width  width
                                               :height height})]
    (project/write-png! image dest)))

(defn snapshot-gray8
  "Return a compact, independent copy of a gray8 buffer."
  [{:keys [width height stride data]}]
  (let [snapshot (byte-array (* width height))]
    (dotimes [row height]
      (System/arraycopy ^bytes data
                        (* row stride)
                        snapshot
                        (* row width)
                        width))
    {:width width :height height :stride width :data snapshot}))

(defn diff-gray8
  "Return the bounding changed rectangle between previous and current gray8 buffers.

  Returns nil when buffers are equal. A nil or incompatible previous buffer returns
  the full current rectangle."
  [previous {:keys [width height stride data]}]
  (if (or (nil? previous)
          (not= width (:width previous))
          (not= height (:height previous)))
    {:x 0 :y 0 :width width :height height}
    (let [prev-data   ^bytes (:data previous)
          prev-stride (long (:stride previous))
          cur-data    ^bytes data
          cur-stride  (long stride)
          min-x       (volatile! width)
          min-y       (volatile! height)
          max-x       (volatile! -1)
          max-y       (volatile! -1)]
      (dotimes [y height]
        (let [prev-row (* y prev-stride)
              cur-row  (* y cur-stride)]
          (dotimes [x width]
            (when (not= (aget prev-data (+ prev-row x))
                        (aget cur-data (+ cur-row x)))
              (when (< x @min-x) (vreset! min-x x))
              (when (< y @min-y) (vreset! min-y y))
              (when (> x @max-x) (vreset! max-x x))
              (when (> y @max-y) (vreset! max-y y))))))
      (when (not= -1 @max-x)
        {:x      @min-x
         :y      @min-y
         :width  (inc (- @max-x @min-x))
         :height (inc (- @max-y @min-y))}))))

(defn crop-gray8
  "Copy rect from gray8 into a compact gray8 buffer."
  [{:keys [stride data]} {:keys [x y width height]}]
  (let [crop (byte-array (* width height))]
    (dotimes [row height]
      (System/arraycopy ^bytes data
                        (+ x (* (+ y row) stride))
                        crop
                        (* row width)
                        width))
    {:width width :height height :stride width :data crop}))

(defn open-context!
  "Create a long-lived Membrane e-ink backend context.

  When `:native?` is true, loads and initializes the native FBInk bridge.
  Tests may pass `:native` directly to avoid native loading."
  [{:keys [native native? native-lib width height image-cache font-cache previous-gray]}]
  (let [native-lib' (or native-lib (project/default-native-lib))
        loaded?     (and native? (nil? native))
        native'     (or native
                        (when native?
                          (when-not native-lib'
                            (throw (ex-info "native library path not provided and no default native library was found" {})))
                          (project/load-native native-lib')))]
    (when loaded?
      (project/init-native! native'))
    (let [width'  (or width
                      (when native' (project/native-screen-width native'))
                      800)
          height' (or height
                      (when native' (project/native-screen-height native'))
                      600)]
      {:native         native'
       :native-lib     native-lib'
       :loaded-native? loaded?
       :width          width'
       :height         height'
       :image-cache    (or image-cache (atom nil))
       :font-cache     (or font-cache (atom {}))
       :previous-gray  (or previous-gray (atom nil))
       :render-count   (atom 0)
       :partial-count  (atom 0)})))

(defn close-context!
  [context]
  (when (and (:native context) (:loaded-native? context))
    (project/close-native! (:native context)))
  nil)

(defn render-frame!
  "Render `elem` through Java2D and convert it to the final gray8 bytes."
  [context elem opts]
  (let [render-opts       (merge opts
                                 {:width       (:width context)
                                  :height      (:height context)
                                  :image-cache (:image-cache context)
                                  :font-cache  (:font-cache context)})
        [image render-ms] (project/timed #(render-to-image! elem render-opts))
        [gray gray-ms]    (project/timed #(project/image->gray8 image))]
    (swap! (:render-count context) inc)
    {:image   image
     :gray    gray
     :timings {:render-to-image render-ms
               :image->gray8    gray-ms}}))

(defn- rect-area
  [{:keys [width height]}]
  (* (long width) (long height)))

(defn- full-rect
  [{:keys [width height]}]
  {:x 0 :y 0 :width width :height height})

(defn- full-present?
  [gray dirty-rect {:keys [damage? force-full? damage-full-threshold]
                    :or   {damage? true damage-full-threshold 0.35}}]
  (or (not damage?)
      force-full?
      (= dirty-rect (full-rect gray))
      (>= (/ (double (rect-area dirty-rect))
             (double (rect-area gray)))
          (double damage-full-threshold))))

(defn present-gray8-with-damage!
  "Present a gray8 buffer using one bounding dirty rectangle.

  `context` must contain `:native` and `:previous-gray` atom. The previous
  gray8 buffer is stored as an independent copied snapshot, never as the
  current image backing array."
  [context gray opts]
  (let [previous   @(:previous-gray context)
        damage?    (get opts :damage? true)
        dirty-rect (if damage?
                     (diff-gray8 previous gray)
                     (full-rect gray))]
    (if-not dirty-rect
      {:presented?   false
       :present-kind :skip
       :dirty-rect   nil}
      (let [present-kind (if (full-present? gray dirty-rect opts) :full :partial)
            gray-out     (if (= :full present-kind)
                           gray
                           (crop-gray8 gray dirty-rect))
            present-opts (if (= :full present-kind)
                           (assoc opts :x 0 :y 0)
                           (assoc opts :x (:x dirty-rect) :y (:y dirty-rect)))]
        (project/present-gray8! (:native context) gray-out present-opts)
        (reset! (:previous-gray context) (snapshot-gray8 gray))
        {:presented?   true
         :present-kind present-kind
         :dirty-rect   dirty-rect}))))

(defn present-frame!
  "Render and damage-present one Membrane frame.

  If the context has no native handle, this only renders/converts and returns
  `:present-kind :no-native`."
  [context elem opts]
  (let [{:keys [gray] :as frame} (render-frame! context elem opts)]
    (if (:native context)
      (let [[present-result present-ms] (project/timed #(present-gray8-with-damage! context gray opts))]
        (when (= :partial (:present-kind present-result))
          (swap! (:partial-count context) inc))
        (-> frame
            (merge present-result)
            (assoc-in [:timings :native-present] present-ms)))
      (merge frame
             {:presented?   false
              :present-kind :no-native
              :dirty-rect   nil}))))

(defn- view-container-info
  [context opts]
  {:container-size [(:width context) (:height context)]
   :context        context
   :opts           opts})

(defn view-element
  [context view-fn opts]
  (if (:include-container-info opts)
    (view-fn (view-container-info context opts))
    (view-fn)))

(defn render-view!
  "Render a view function once, presenting only when `:present?` is true."
  [context view-fn opts]
  (let [[elem view-ms] (project/timed #(view-element context view-fn opts))
        frame          (if (:present? opts)
                         (present-frame! context elem opts)
                         (render-frame! context elem opts))]
    (assoc-in frame [:timings :view] view-ms)))

(def page-repeat-keys
  #{:page-back :page-forward})

(defn- force-intents
  [intents]
  (doall (or intents [])))

(defn dispatch-normalized-event!
  [elem event]
  (try
    (case (:kind event)
      :touch-down
      (force-intents (ui/mouse-event elem (:pos event) 0 true 0))

      :touch-move
      (do
        (force-intents (ui/mouse-move elem (:pos event)))
        (force-intents (ui/mouse-move-global elem (:pos event))))

      :touch-up
      (force-intents (ui/mouse-event elem (:pos event) 0 false 0))

      :key
      (case (:action event)
        :press
        (force-intents (ui/key-press elem (:key event)))

        :repeat
        (when (contains? page-repeat-keys (:key event))
          (force-intents (ui/key-press elem (:key event))))

        :release
        []

        [])

      [])
    (catch Throwable t
      (binding [*out* *err*]
        (println "input dispatch failed:" (.getMessage t))
        (.printStackTrace t))
      [])))

(defn dispatch-normalized-events!
  [elem events]
  (mapv #(dispatch-normalized-event! elem %) events))

(defn input-event-rerender?
  [event opts]
  (case (:kind event)
    :touch-down true
    :touch-up true
    :touch-move (boolean (:input-render-moves? opts))
    :key (or (= :press (:action event))
             (and (= :repeat (:action event))
                  (contains? page-repeat-keys (:key event))))
    false))

(defn- print-normalized-events!
  [events]
  (doseq [event events]
    (println "input" (pr-str (dissoc event :raw))))
  (flush))

(defn- print-raw-events!
  [events]
  (doseq [event events]
    (println "raw-input" (pr-str (evdev/annotate-event event))))
  (flush))

(defn run-input-loop!
  "Run a long-lived native input loop for a Membrane view function."
  [view-fn base-opts]
  (let [context      (open-context! base-opts)
        opts         (assoc base-opts :include-container-info true)
        input-state  (atom (input.kobo/initial-state {:input-profile (or (:input-profile base-opts) :kobo-default)
                                                      :viewport      [(:width context) (:height context)]}))
        current-elem (atom nil)
        input-handle (atom nil)]
    (try
      (let [first-result (render-view! context view-fn opts)
            first-elem   (view-element context view-fn opts)]
        (reset! current-elem first-elem)
        (println "ready: Membrane native input loop")
        (reset! input-handle
                (input.runtime/start-input-thread! (:native context)
                                                   {:grab?      (:input-grab? base-opts)
                                                    :verbose?   (:verbose-input? base-opts)
                                                    :capacity   (:input-capacity base-opts 256)
                                                    :timeout-ms (:input-timeout-ms base-opts 250)}))
        (println "rendered initial frame" (:width context) "x" (:height context)
                 "mode" (name (or (:present-kind first-result) :render-only)))
        (flush)
        (loop []
          (let [batches (input.runtime/drain-queue! (:queue @input-handle))]
            (doseq [batch batches]
              (if (= :input-error (:kind batch))
                (throw (:error batch))
                (let [{next-state :state normalized :events}
                      (input.kobo/accept-raw-events @input-state batch)]
                  (reset! input-state next-state)
                  (when (:input-raw-dump? base-opts)
                    (print-raw-events! batch))
                  (when (or (:verbose-input? base-opts) (:input-dump? base-opts))
                    (print-normalized-events! normalized))
                  (dispatch-normalized-events! @current-elem normalized)
                  (when (some #(input-event-rerender? % base-opts) normalized)
                    (let [elem   (view-element context view-fn opts)
                          result (if (:present? base-opts)
                                   (present-frame! context elem base-opts)
                                   (render-frame! context elem base-opts))]
                      (reset! current-elem elem)
                      (println "rendered input frame" (:width context) "x" (:height context)
                               "mode" (name (or (:present-kind result) :render-only))
                               "dirty" (or (:dirty-rect result) "none"))
                      (flush))))))
            (Thread/sleep 25)
            (recur))))
      (finally
        (when-let [handle @input-handle]
          (input.runtime/stop-input-thread! handle))
        (close-context! context)))))

(defn parse-command-line
  [line]
  (let [tokens (-> line str/trim (str/split #"\s+"))]
    (if (or (empty? tokens)
            (= [""] tokens))
      {:command :blank :args []}
      {:command (keyword (str/lower-case (first tokens)))
       :args    (vec (rest tokens))})))

(defn- print-help!
  []
  (println "Commands:")
  (println "  render [options]   render/present without restarting the JVM")
  (println "  reload             call :reload! if supplied and clear render/damage caches")
  (println "  help               print this help")
  (println "  quit               close native backend and exit")
  (flush))

(defn- prompt!
  []
  (print "membrane-eink> ")
  (flush))

(defn clear-caches!
  [context]
  (reset! (:image-cache context) nil)
  (reset! (:font-cache context) {})
  (reset! (:previous-gray context) nil)
  (reset! (:partial-count context) 0)
  nil)

(defn run-loop!
  "Run a long-lived stdin command loop for a Membrane view function."
  [view-fn base-opts]
  (let [context (open-context! base-opts)]
    (println "ready: long-lived Membrane e-ink loop")
    (print-help!)
    (try
      (loop []
        (prompt!)
        (if-let [line (read-line)]
          (let [{:keys [command args]} (parse-command-line line)]
            (case command
              :blank (recur)
              :help (do (print-help!) (recur))
              :reload (do
                        (when-let [reload! (:reload! base-opts)]
                          (reload!))
                        (clear-caches! context)
                        (println "reloaded")
                        (flush)
                        (recur))
              :render (do
                        (let [opts   (-> (project/parse-args base-opts args)
                                         (assoc :width (:width context)
                                                :height (:height context)))
                              result (render-view! context view-fn opts)]
                          (println "rendered" (:width context) "x" (:height context)
                                   "mode" (name (or (:present-kind result) :render-only))
                                   "dirty" (or (:dirty-rect result) "none"))
                          (flush))
                        (recur))
              :quit :quit
              :exit :quit
              (do
                (println "unknown command:" (name command))
                (print-help!)
                (recur))))
          :eof))
      (finally
        (close-context! context)))))

(defn run
  ([view-fn]
   (run view-fn {}))
  ([view-fn opts]
   (run-loop! view-fn opts)))

(defn run-sync
  ([view-fn]
   (run-sync view-fn {}))
  ([view-fn opts]
   (run-loop! view-fn opts)))

(def toolkit
  (reify
    tk/IToolkit

    tk/IToolkitRun
    (run [_ view-fn]
      (run-loop! view-fn {}))
    (run [_ view-fn opts]
      (run-loop! view-fn opts))

    tk/IToolkitRunSync
    (run-sync [_ view-fn]
      (run-loop! view-fn {}))
    (run-sync [_ view-fn opts]
      (run-loop! view-fn opts))

    tk/IToolkitFontMetrics
    (font-metrics [_ font]
      (ol.membrane.eink-backend/font-metrics font))

    tk/IToolkitFontAdvanceX
    (font-advance-x [_ font s]
      (ol.membrane.eink-backend/font-advance-x font s))

    tk/IToolkitFontLineHeight
    (font-line-height [_ font]
      (ol.membrane.eink-backend/font-line-height font))

    tk/IToolkitSaveImage
    (save-image [_ dest elem]
      (toolkit-save-image! dest elem nil))
    (save-image [_ dest elem size]
      (toolkit-save-image! dest elem size))))

(defn present!
  [native elem opts]
  (let [image (render-to-image! elem opts)
        gray  (project/image->gray8 image)]
    (project/present-gray8! native gray opts)
    image))