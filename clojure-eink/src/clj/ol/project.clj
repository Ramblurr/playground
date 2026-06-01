(ns ol.project
  (:require
   [clojure.java.io :as io]
   [clojure.string :as str])
  (:import
   [java.awt Color Font Graphics2D RenderingHints]
   [java.awt.font LineBreakMeasurer TextAttribute]
   [java.awt.image BufferedImage ComponentSampleModel DataBufferByte]
   [java.lang.foreign Arena FunctionDescriptor Linker Linker$Option MemoryLayout MemorySegment SymbolLookup ValueLayout]
   [java.lang.invoke MethodHandle]
   [java.nio.charset StandardCharsets]
   [java.nio.file Path]
   [javax.imageio ImageIO]))

(def default-text
  "Clojure rendered this paragraph with Java2D TextLayout, copied the grayscale pixels through Java FFM, and asked a tiny C library to present them with FBInk.")

(def waveforms
  {:auto 0
   :du   1
   :gc16 2
   :gl16 3
   :a2   4})

(def render-modes
  #{:layout :cached-layout :simple-text :rects})

(defonce process-start-ns (System/nanoTime))

(defn elapsed-ms
  []
  (/ (double (- (System/nanoTime) process-start-ns)) 1000000.0))

(defn log-time!
  [label]
  (printf "[%.1f ms] %s%n" (elapsed-ms) label)
  (flush))

(defn ns->ms
  [nanos]
  (/ (double nanos) 1000000.0))

(defn timed
  [f]
  (let [start  (System/nanoTime)
        result (f)
        end    (System/nanoTime)]
    [result (ns->ms (- end start))]))

(defn log-duration!
  [label ms]
  (printf "[%.1f ms] %s: %.1f ms%n" (elapsed-ms) label (double ms))
  (flush))

(def render-phase-order
  [[:image-allocation "image allocation"]
   [:graphics-setup "graphics setup"]
   [:font-setup "font setup"]
   [:background-fill "background fill"]
   [:text-layout "text layout"]
   [:glyph-draw "glyph draw"]
   [:total-render "Java2D render total"]
   [:image->gray8 "image->gray8"]
   [:native-present "native present"]])

(defn log-render-timings!
  [iteration total-renders timings]
  (doseq [[k label] render-phase-order
          :when     (contains? timings k)]
    (log-duration! (format "render %d/%d %s" iteration total-renders label) (get timings k))))

(defn- normalized-paragraph
  [text]
  (str/replace text #"\s+" " "))

(defn- simple-lines
  [text]
  (->> (str/split (normalized-paragraph text) #"\s+")
       (partition-all 8)
       (map #(str/join " " %))
       (take 10)
       vec))

(defn- layout-body-lines
  [^Graphics2D g paragraph ^Font body-font width height margin ^Font title-font]
  (let [attributed (java.text.AttributedString. ^String paragraph)
        _          (.addAttribute attributed TextAttribute/FONT body-font)
        iterator   (.getIterator attributed)
        frc        (.getFontRenderContext g)
        measurer   (LineBreakMeasurer. iterator frc)
        end        (.getEndIndex iterator)
        wrap-width (float (- width (* 2 margin)))
        start-y    (float (+ margin (.getSize title-font) margin))]
    (loop [y       start-y
           layouts []]
      (if (and (< (.getPosition measurer) end)
               (< y (- height margin)))
        (let [layout   (.nextLayout measurer wrap-width)
              baseline (+ y (.getAscent layout))]
          (recur (float (+ baseline (.getDescent layout) (.getLeading layout)))
                 (conj layouts [layout (float margin) (float baseline)])))
        layouts))))

(defn- cached-value
  [cache cache-key load-fn]
  (if cache
    (if-let [entry (find @cache cache-key)]
      (val entry)
      (let [value (load-fn)]
        (swap! cache assoc cache-key value)
        value))
    (load-fn)))

(defn- draw-layout-text!
  [^Graphics2D g ^Font title-font margin body-layouts]
  (.setColor g Color/BLACK)
  (.setFont g title-font)
  (.drawString g "Clojure e-ink PoC" margin margin)
  (doseq [[layout x baseline] body-layouts]
    (.draw layout g (float x) (float baseline))))

(defn- draw-simple-text!
  [^Graphics2D g ^Font title-font ^Font body-font margin text]
  (.setColor g Color/BLACK)
  (.setFont g title-font)
  (.drawString g "Clojure e-ink PoC" margin margin)
  (.setFont g body-font)
  (let [line-height (max 24 (long (* 1.25 (.getSize body-font))))
        start-y     (+ margin (.getSize title-font) margin)]
    (doseq [[idx line] (map-indexed vector (simple-lines text))]
      (.drawString g ^String line margin (+ start-y (* idx line-height))))))

(defn- draw-rects!
  [^Graphics2D g width height margin]
  (let [content-width  (- width (* 2 margin))
        content-height (- height (* 2 margin))
        rows           24
        row-height     (max 8 (quot content-height rows))]
    (dotimes [idx rows]
      (.setColor g (if (even? idx) Color/BLACK Color/LIGHT_GRAY))
      (.fillRect g
                 margin
                 (+ margin (* idx row-height))
                 content-width
                 (max 4 (quot row-height 2))))))

(defn- compatible-image?
  [^BufferedImage image width height]
  (and image
       (= BufferedImage/TYPE_BYTE_GRAY (.getType image))
       (= width (.getWidth image))
       (= height (.getHeight image))))

(defn- acquire-render-image
  [width height existing-image image-cache]
  (cond
    (compatible-image? existing-image width height)
    existing-image

    image-cache
    (if (compatible-image? @image-cache width height)
      @image-cache
      (let [image (BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)]
        (reset! image-cache image)
        image))

    :else
    (BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)))

(defn render-demo-frame
  [{:keys [width height text margin font-size render-mode layout-cache image-cache]
    :as   opts
    :or   {width       800
           height      600
           text        default-text
           margin      48
           render-mode :layout}}]
  (when-not (contains? render-modes render-mode)
    (throw (ex-info (str "unknown render mode: " render-mode) {:render-mode render-mode})))
  (let [[image image-allocation-ms] (timed #(acquire-render-image width height (:image opts) image-cache))
        ^Graphics2D g               (.createGraphics ^BufferedImage image)]
    (try
      (let [[fonts font-setup-ms]
            (timed
             #(let [font-size (or font-size (max 22 (quot width 28)))]
                {:body-font  (Font. "SansSerif" Font/PLAIN font-size)
                 :title-font (Font. "SansSerif" Font/BOLD (max 28 (quot width 22)))}))
            {:keys [body-font title-font]} fonts
            [_graphics graphics-setup-ms]
            (timed
             #(do
                (.setRenderingHint g RenderingHints/KEY_TEXT_ANTIALIASING RenderingHints/VALUE_TEXT_ANTIALIAS_ON)
                (.setRenderingHint g RenderingHints/KEY_ANTIALIASING RenderingHints/VALUE_ANTIALIAS_ON)))
            [_background background-fill-ms]
            (timed
             #(do
                (.setColor g Color/WHITE)
                (.fillRect g 0 0 width height)))
            [text-work text-layout-ms]
            (timed
             #(case render-mode
                :layout
                (layout-body-lines g (normalized-paragraph text) body-font width height margin title-font)

                :cached-layout
                (let [paragraph (normalized-paragraph text)
                      cache-key [paragraph width height margin (.getSize body-font) (.getSize title-font)]]
                  (cached-value layout-cache
                                cache-key
                                (fn []
                                  (layout-body-lines g paragraph body-font width height margin title-font))))

                :simple-text
                (simple-lines text)

                :rects
                nil))
            [_glyphs glyph-draw-ms]
            (timed
             #(case render-mode
                (:layout :cached-layout)
                (draw-layout-text! g title-font margin text-work)

                :simple-text
                (draw-simple-text! g title-font body-font margin text)

                :rects
                (draw-rects! g width height margin)))]
        {:image   image
         :timings {:image-allocation image-allocation-ms
                   :graphics-setup   graphics-setup-ms
                   :font-setup       font-setup-ms
                   :background-fill  background-fill-ms
                   :text-layout      text-layout-ms
                   :glyph-draw       glyph-draw-ms}})
      (finally
        (.dispose g)))))

(defn render-demo-image
  [opts]
  (:image (render-demo-frame opts)))

(defn image->gray8
  [^BufferedImage image]
  (let [raster       (.getRaster image)
        data-buffer  (.getDataBuffer raster)
        sample-model (.getSampleModel raster)
        width        (.getWidth image)
        height       (.getHeight image)]
    (when-not (instance? DataBufferByte data-buffer)
      (throw (ex-info "expected a byte-backed grayscale BufferedImage" {:image-type (.getType image)})))
    (let [raw    (.getData ^DataBufferByte data-buffer)
          offset (.getOffset ^DataBufferByte data-buffer)
          stride (if (instance? ComponentSampleModel sample-model)
                   (.getScanlineStride ^ComponentSampleModel sample-model)
                   width)]
      (if (and (zero? offset)
               (= stride width)
               (= (alength ^bytes raw) (* width height)))
        {:width width :height height :stride stride :data raw}
        (let [compact (byte-array (* width height))]
          (dotimes [row height]
            (System/arraycopy raw (+ offset (* row stride)) compact (* row width) width))
          {:width width :height height :stride width :data compact})))))

(defn write-png!
  [^BufferedImage image path]
  (let [file (io/file path)]
    (some-> file .getParentFile .mkdirs)
    (ImageIO/write image "png" file)
    (.getAbsolutePath file)))

(defn- descriptor
  [return-layout arg-layouts]
  (if return-layout
    (FunctionDescriptor/of return-layout (into-array MemoryLayout arg-layouts))
    (FunctionDescriptor/ofVoid (into-array MemoryLayout arg-layouts))))

(defn- linker-downcall-method
  []
  (.getMethod Linker
              "downcallHandle"
              (into-array Class [MemorySegment
                                 FunctionDescriptor
                                 (class (make-array Linker$Option 0))])))

(defn- downcall-handle
  [^Linker linker address return-layout arg-layouts]
  (let [options (make-array Linker$Option 0)
        method  (linker-downcall-method)]
    (.invoke method
             linker
             (object-array [address (descriptor return-layout arg-layouts) options]))))

(defn- downcall
  [^SymbolLookup lookup ^Linker linker symbol return-layout arg-layouts]
  (downcall-handle linker (.orElseThrow (.find lookup symbol)) return-layout arg-layouts))

(defn- optional-downcall
  [^SymbolLookup lookup ^Linker linker symbol return-layout arg-layouts]
  (when-let [address (.orElse (.find lookup symbol) nil)]
    (downcall-handle linker address return-layout arg-layouts)))

(def input-event-layout
  (MemoryLayout/structLayout
   (into-array MemoryLayout
               [ValueLayout/JAVA_LONG
                ValueLayout/JAVA_LONG
                ValueLayout/JAVA_INT
                ValueLayout/JAVA_INT
                ValueLayout/JAVA_INT
                ValueLayout/JAVA_INT
                ValueLayout/JAVA_INT
                ValueLayout/JAVA_INT])))

(defn input-event-layout-size
  []
  (long (.byteSize input-event-layout)))

(defn load-native
  [library-path]
  (let [path           (Path/of (.getAbsolutePath (io/file library-path)) (into-array String []))
        lookup         (SymbolLookup/libraryLookup path (Arena/global))
        linker         (Linker/nativeLinker)
        int-layout     ValueLayout/JAVA_INT
        address-layout ValueLayout/ADDRESS]
    {:init               (downcall lookup linker "eink_init" int-layout [int-layout int-layout])
     :close              (downcall lookup linker "eink_close" int-layout [])
     :width              (downcall lookup linker "eink_screen_width" int-layout [])
     :height             (downcall lookup linker "eink_screen_height" int-layout [])
     :present-gray8      (downcall lookup linker
                                   "eink_present_gray8"
                                   int-layout
                                   [address-layout int-layout int-layout int-layout int-layout int-layout int-layout int-layout int-layout])
     :last-error         (downcall lookup linker "eink_last_error" address-layout [])
     :input-event-size   (optional-downcall lookup linker "eink_input_event_size" int-layout [])
     :input-open-scan    (optional-downcall lookup linker "eink_input_open_scan" int-layout [int-layout int-layout])
     :input-device-count (optional-downcall lookup linker "eink_input_device_count" int-layout [])
     :input-device-path  (optional-downcall lookup linker "eink_input_device_path" address-layout [int-layout])
     :input-device-name  (optional-downcall lookup linker "eink_input_device_name" address-layout [int-layout])
     :input-device-type  (optional-downcall lookup linker "eink_input_device_type" int-layout [int-layout])
     :input-poll         (optional-downcall lookup linker "eink_input_poll" int-layout [address-layout int-layout int-layout])
     :input-close        (optional-downcall lookup linker "eink_input_close" int-layout [])}))

(defn- invoke-native
  [^MethodHandle handle & args]
  (.invokeWithArguments handle (object-array args)))

(defn- native-c-string
  ([address]
   (native-c-string address 4096))
  ([address max-bytes]
   (when-not (= MemorySegment/NULL address)
     (let [segment (.reinterpret ^MemorySegment address (long max-bytes))]
       (loop [i     0
              bytes []]
         (let [b (bit-and 0xFF (int (.get segment ValueLayout/JAVA_BYTE (long i))))]
           (if (or (zero? b)
                   (>= (inc i) max-bytes))
             (String. (byte-array (map unchecked-byte bytes)) StandardCharsets/UTF_8)
             (recur (inc i) (conj bytes b)))))))))

(defn native-last-error
  [native]
  (native-c-string (invoke-native (:last-error native))))

(defn- check-native!
  [native rv action]
  (let [code (int rv)]
    (when (neg? code)
      (throw (ex-info (str action " failed: " (or (native-last-error native) code))
                      {:action action :code code})))
    code))

(defn- require-native-handle
  [native k action]
  (or (get native k)
      (throw (ex-info (str action " is not available in the native library")
                      {:action action :symbol k}))))

(defn input-event-size
  [native]
  (check-native! native
                 (invoke-native (require-native-handle native :input-event-size "eink_input_event_size"))
                 "eink_input_event_size"))

(defn input-open-scan!
  [native {:keys [grab? verbose?] :or {grab? false verbose? false}}]
  (check-native! native
                 (invoke-native (require-native-handle native :input-open-scan "eink_input_open_scan")
                                (int (if grab? 1 0))
                                (int (if verbose? 1 0)))
                 "eink_input_open_scan"))

(defn input-device-count
  [native]
  (check-native! native
                 (invoke-native (require-native-handle native :input-device-count "eink_input_device_count"))
                 "eink_input_device_count"))

(defn input-device-info
  [native index]
  (let [index (int index)]
    {:index index
     :path  (native-c-string
             (invoke-native (require-native-handle native :input-device-path "eink_input_device_path")
                            index))
     :name  (native-c-string
             (invoke-native (require-native-handle native :input-device-name "eink_input_device_name")
                            index))
     :type  (int (invoke-native (require-native-handle native :input-device-type "eink_input_device_type")
                                index))}))

(defn- read-input-event
  [^MemorySegment segment offset]
  {:sec          (.get segment ValueLayout/JAVA_LONG (long offset))
   :usec         (.get segment ValueLayout/JAVA_LONG (long (+ offset 8)))
   :type         (int (.get segment ValueLayout/JAVA_INT (long (+ offset 16))))
   :code         (int (.get segment ValueLayout/JAVA_INT (long (+ offset 20))))
   :value        (int (.get segment ValueLayout/JAVA_INT (long (+ offset 24))))
   :device-index (int (.get segment ValueLayout/JAVA_INT (long (+ offset 28))))
   :device-type  (int (.get segment ValueLayout/JAVA_INT (long (+ offset 32))))})

(defn input-poll!
  [native {:keys [capacity timeout-ms] :or {capacity 256 timeout-ms 0}}]
  (let [event-size  (input-event-layout-size)
        native-size (input-event-size native)]
    (when-not (= event-size native-size)
      (throw (ex-info "native input event layout size mismatch"
                      {:clojure-size event-size :native-size native-size})))
    (with-open [arena (Arena/ofConfined)]
      (let [capacity (int capacity)
            segment  (.allocate arena (long (* capacity event-size)) 8)
            count    (check-native! native
                                    (invoke-native (require-native-handle native :input-poll "eink_input_poll")
                                                   segment
                                                   capacity
                                                   (int timeout-ms))
                                    "eink_input_poll")]
        (mapv (fn [idx]
                (read-input-event segment (* idx event-size)))
              (range count))))))

(defn input-close!
  [native]
  (when-let [handle (:input-close native)]
    (check-native! native (invoke-native handle) "eink_input_close")))

(defn present-gray8!
  [native {:keys [width height stride data]} {:keys [x y waveform flash? wait?]
                                              :or   {x 0 y 0 waveform :gc16 flash? true wait? true}}]
  (let [mode (get waveforms waveform (:gc16 waveforms))]
    (with-open [arena (Arena/ofConfined)]
      (let [segment (.allocate arena (long (alength ^bytes data)) 1)]
        (MemorySegment/copy data 0 segment ValueLayout/JAVA_BYTE 0 (alength ^bytes data))
        (check-native!
         native
         (invoke-native (:present-gray8 native)
                        segment
                        (int width)
                        (int height)
                        (int stride)
                        (int x)
                        (int y)
                        (int mode)
                        (int (if flash? 1 0))
                        (int (if wait? 1 0)))
         "eink_present_gray8")))))

(defn present-image!
  [native ^BufferedImage image opts]
  (present-gray8! native (image->gray8 image) opts))

(defn default-native-lib
  []
  (or (System/getenv "EINK_NATIVE_LIB")
      (some #(when (.exists (io/file %)) %)
            ["result-native/lib/libclojure_eink.so"
             "result/lib/libclojure_eink.so"
             "libclojure_eink.so"])))

(defn init-native!
  [native]
  (check-native! native (invoke-native (:init native) (int 1) (int 0)) "eink_init"))

(defn close-native!
  [native]
  (input-close! native)
  (invoke-native (:close native)))

(defn native-screen-width
  [native]
  (int (invoke-native (:width native))))

(defn native-screen-height
  [native]
  (int (invoke-native (:height native))))

(defn- option-value
  [option value]
  (when-not value
    (throw (ex-info (str "missing value for " option) {:option option})))
  value)

(defn- parse-positive-long-option
  [option value]
  (let [raw (option-value option value)
        n   (try
              (parse-long raw)
              (catch Exception _
                (throw (ex-info (str "invalid integer for " option ": " raw)
                                {:option option :value raw}))))]
    (when-not (pos? n)
      (throw (ex-info (str option " must be positive") {:option option :value raw})))
    n))

(defn- parse-render-mode-option
  [option value]
  (let [raw  (option-value option value)
        mode (keyword (str/lower-case raw))]
    (when-not (contains? render-modes mode)
      (throw (ex-info (str "unknown render mode: " raw)
                      {:option option :value raw :allowed render-modes})))
    mode))

(def default-options
  {:text         default-text
   :png          nil
   :present?     false
   :native?      false
   :present-mode :none
   :native-lib   nil
   :width        nil
   :height       nil
   :renders      1
   :render-mode  :layout
   :reuse-image? false
   :waveform     :gc16
   :flash?       true
   :wait?        true
   :skia-batch?  false})

(defn parse-args
  ([args]
   (parse-args default-options args))
  ([initial-opts args]
   (loop [opts (merge default-options initial-opts)
          xs   (seq args)]
     (if-not xs
       opts
       (let [[arg & more] xs]
         (case arg
           "--present" (recur (assoc opts :present? true :native? true :present-mode :each) more)
           "--no-present" (recur (assoc opts :present? false :present-mode :none) more)
           "--present-last" (recur (assoc opts :present? true :native? true :present-mode :last) more)
           "--present-each" (recur (assoc opts :present? true :native? true :present-mode :each) more)
           "--renders" (recur (assoc opts :renders (parse-positive-long-option arg (first more))) (next more))
           "--repeat" (recur (assoc opts :renders (parse-positive-long-option arg (first more))) (next more))
           "--render-mode" (recur (assoc opts :render-mode (parse-render-mode-option arg (first more))) (next more))
           "--mode" (recur (assoc opts :render-mode (parse-render-mode-option arg (first more))) (next more))
           "--reuse-image" (recur (assoc opts :reuse-image? true) more)
           "--no-reuse-image" (recur (assoc opts :reuse-image? false) more)
           "--png" (recur (assoc opts :png (option-value arg (first more))) (next more))
           "--native-lib" (recur (assoc opts :native-lib (option-value arg (first more))) (next more))
           "--width" (recur (assoc opts :width (parse-positive-long-option arg (first more))) (next more))
           "--height" (recur (assoc opts :height (parse-positive-long-option arg (first more))) (next more))
           "--text" (recur (assoc opts :text (option-value arg (first more))) (next more))
           "--waveform" (recur (assoc opts :waveform (keyword (str/lower-case (option-value arg (first more))))) (next more))
           "--no-flash" (recur (assoc opts :flash? false) more)
           "--no-wait" (recur (assoc opts :wait? false) more)
           "--skia-batch" (recur (assoc opts :skia-batch? true) more)
           "--no-skia-batch" (recur (assoc opts :skia-batch? false) more)
           "--help" (recur (assoc opts :help? true) more)
           (if (str/starts-with? arg "--")
             (throw (ex-info (str "unknown option: " arg) {:arg arg}))
             (assoc opts :text (str/join " " xs)))))))))

(defn usage
  []
  (str "Usage:\n"
       "  clojure -M -m ol.project --png target/eink-demo.png\n"
       "  EINK_NATIVE_LIB=result-kobo-native/lib/libclojure_eink.so \\\n"
       "    clojure -J--enable-native-access=ALL-UNNAMED -M -m ol.project --present\n\n"
       "Options: --text TEXT --width N --height N --renders N --repeat N "
       "--render-mode layout|cached-layout|simple-text|rects --reuse-image "
       "--present --no-present --present-last --present-each "
       "--waveform auto|du|gc16|gl16|a2 --no-flash --no-wait "
       "--skia-batch --no-skia-batch"))

(defn- should-present-iteration?
  [present-mode iteration total-renders]
  (case present-mode
    :each true
    :last (= iteration total-renders)
    :none false
    false))

(defn benchmark-renders!
  [opts]
  (let [native        (:native opts)
        native-lib    (:native-lib opts)
        width         (or (:width opts) 800)
        height        (or (:height opts) 600)
        total-renders (:renders opts)
        layout-cache  (when (= :cached-layout (:render-mode opts))
                        (or (:layout-cache opts) (atom {})))
        image-cache   (when (:reuse-image? opts)
                        (or (:image-cache opts) (atom nil)))
        render-opts   (cond-> (assoc opts :width width :height height)
                        layout-cache (assoc :layout-cache layout-cache)
                        image-cache (assoc :image-cache image-cache))
        last-image    (loop [iteration  1
                             last-image nil]
                        (if (> iteration total-renders)
                          last-image
                          (do
                            (log-time! (format "render %d/%d starting Java2D render %dx%d"
                                               iteration
                                               total-renders
                                               width
                                               height))
                            (let [[frame total-render-ms] (timed #(render-demo-frame render-opts))
                                  {:keys [image timings]} frame
                                  [gray gray8-ms]         (timed #(image->gray8 image))
                                  present?                (and native
                                                               (should-present-iteration? (:present-mode opts)
                                                                                          iteration
                                                                                          total-renders))
                                  present-ms              (when present?
                                                            (log-time! (format "render %d/%d starting native present"
                                                                               iteration
                                                                               total-renders))
                                                            (let [[_present rv-ms] (timed #(present-gray8! native gray opts))]
                                                              rv-ms))
                                  all-timings             (cond-> (assoc timings
                                                                         :total-render total-render-ms
                                                                         :image->gray8 gray8-ms)
                                                            present-ms (assoc :native-present present-ms))]
                              (log-render-timings! iteration total-renders all-timings)
                              (when present?
                                (log-time! (format "render %d/%d finished native present" iteration total-renders)))
                              (recur (inc iteration) image)))))]
    (when-let [png (:png opts)]
      (log-time! "starting PNG write")
      (println "wrote" (write-png! last-image png))
      (log-time! "finished PNG write"))
    (if native
      (println "benchmarked" total-renders "render(s)" width "x" height
               "via" native-lib "present-mode" (name (:present-mode opts)))
      (println "benchmarked" total-renders "render(s)" width "x" height
               "without native present"))
    last-image))

(defn -main
  [& args]
  (log-time! "entered ol.project/-main")
  (let [opts (parse-args args)]
    (log-time! "parsed args")
    (if (:help? opts)
      (println (usage))
      (let [native-lib   (or (:native-lib opts) (default-native-lib))
            native       (when (:native? opts)
                           (when-not native-lib
                             (throw (ex-info "native library path not provided and no default native library was found" {})))
                           (let [loaded (load-native native-lib)]
                             (log-time! "loaded native library and linked symbols")
                             loaded))
            initialized? (volatile! false)]
        (try
          (when native
            (init-native! native)
            (vreset! initialized? true)
            (log-time! "initialized FBInk/native backend"))
          (let [width  (or (:width opts)
                           (when native
                             (let [w (native-screen-width native)]
                               (log-time! (str "queried screen width: " w))
                               w))
                           800)
                height (or (:height opts)
                           (when native
                             (let [h (native-screen-height native)]
                               (log-time! (str "queried screen height: " h))
                               h))
                           600)]
            (benchmark-renders! (assoc opts
                                       :native native
                                       :native-lib native-lib
                                       :width width
                                       :height height)))
          (finally
            (when (and native @initialized?)
              (log-time! "closing native backend")
              (close-native! native)
              (log-time! "closed native backend"))))))))
