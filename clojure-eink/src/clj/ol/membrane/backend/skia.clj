(ns ol.membrane.backend.skia
  (:require
   [clojure.java.io :as io]
   [clojure.string :as str]
   [membrane.ui :as ui])
  (:import
   [java.io ByteArrayOutputStream]
   [java.lang.foreign Arena FunctionDescriptor Linker Linker$Option MemoryLayout MemorySegment SymbolLookup ValueLayout]
   [java.lang.invoke MethodHandle]
   [java.nio.charset StandardCharsets]
   [java.nio.file Path]))

(def default-native-lib-candidates
  ["result-skia-native/lib/libclojure_eink_skia.so"
   "result/lib/libclojure_eink_skia.so"
   "libclojure_eink_skia.so"])

(defn default-native-lib
  ([]
   (default-native-lib (System/getenv) default-native-lib-candidates))
  ([env candidates]
   (or (not-empty (get env "EINK_SKIA_NATIVE_LIB"))
       (some #(when (.exists (io/file %)) %)
             candidates))))

(def ^:private int-layout ValueLayout/JAVA_INT)
(def ^:private float-layout ValueLayout/JAVA_FLOAT)
(def ^:private byte-layout ValueLayout/JAVA_BYTE)
(def ^:private address-layout ValueLayout/ADDRESS)

(def ^:private size-t-layout
  (if (= "32" (System/getProperty "sun.arch.data.model"))
    ValueLayout/JAVA_INT
    ValueLayout/JAVA_LONG))

(def native-symbols
  [{:key :last-error :symbol "eink_skia_last_error" :return address-layout :args []}
   {:key :create :symbol "eink_skia_create" :return address-layout :args [int-layout int-layout address-layout address-layout]}
   {:key :destroy :symbol "eink_skia_destroy" :return int-layout :args [address-layout]}
   {:key :width :symbol "eink_skia_width" :return int-layout :args [address-layout]}
   {:key :height :symbol "eink_skia_height" :return int-layout :args [address-layout]}
   {:key :stride :symbol "eink_skia_stride" :return int-layout :args [address-layout]}
   {:key :clear :symbol "eink_skia_clear" :return int-layout :args [address-layout byte-layout]}
   {:key :save :symbol "eink_skia_save" :return int-layout :args [address-layout]}
   {:key :restore :symbol "eink_skia_restore" :return int-layout :args [address-layout]}
   {:key :translate :symbol "eink_skia_translate" :return int-layout :args [address-layout float-layout float-layout]}
   {:key :scale :symbol "eink_skia_scale" :return int-layout :args [address-layout float-layout float-layout]}
   {:key :clip-rect :symbol "eink_skia_clip_rect" :return int-layout :args [address-layout float-layout float-layout float-layout float-layout]}
   {:key :set-color :symbol "eink_skia_set_color" :return int-layout :args [address-layout float-layout float-layout float-layout float-layout]}
   {:key :set-style :symbol "eink_skia_set_style" :return int-layout :args [address-layout int-layout]}
   {:key :set-stroke-width :symbol "eink_skia_set_stroke_width" :return int-layout :args [address-layout float-layout]}
   {:key :draw-rect :symbol "eink_skia_draw_rect" :return int-layout :args [address-layout float-layout float-layout float-layout float-layout]}
   {:key :draw-round-rect :symbol "eink_skia_draw_round_rect" :return int-layout :args [address-layout float-layout float-layout float-layout float-layout float-layout]}
   {:key :draw-path :symbol "eink_skia_draw_path" :return int-layout :args [address-layout address-layout int-layout int-layout]}
   {:key :text-bounds :symbol "eink_skia_text_bounds" :return int-layout :args [address-layout address-layout int-layout address-layout float-layout int-layout int-layout float-layout address-layout address-layout address-layout address-layout address-layout]}
   {:key :draw-text-box :symbol "eink_skia_draw_text_box" :return int-layout :args [address-layout address-layout int-layout address-layout float-layout int-layout int-layout float-layout float-layout float-layout]}
   {:key :text-cache-stats :symbol "eink_skia_text_cache_stats" :return int-layout :args [address-layout address-layout address-layout address-layout address-layout]}
   {:key :clear-text-cache :symbol "eink_skia_clear_text_cache" :return int-layout :args [address-layout]}
   {:key :replay-commands :symbol "eink_skia_replay_commands" :return int-layout :args [address-layout address-layout size-t-layout int-layout]}
   {:key :copy-gray8 :symbol "eink_skia_copy_gray8" :return int-layout :args [address-layout address-layout size-t-layout]}
   {:key :present :symbol "eink_skia_present" :return int-layout :args [address-layout int-layout int-layout int-layout int-layout int-layout int-layout int-layout]}])

(def required-abi-symbols
  (mapv :symbol native-symbols))

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

(defn- symbol-address
  [^SymbolLookup lookup native-lib symbol]
  (let [found (.find lookup symbol)]
    (if (.isPresent found)
      (.get found)
      (throw (ex-info (str "missing Skia native symbol: " symbol)
                      {:native-lib native-lib
                       :symbol     symbol})))))

(defn- downcall
  [^SymbolLookup lookup ^Linker linker native-lib {:keys [symbol return args]}]
  (let [address (symbol-address lookup native-lib symbol)
        options (make-array Linker$Option 0)
        method  (linker-downcall-method)]
    (.invoke method
             linker
             (object-array [address (descriptor return args) options]))))

(defn- native-library-file
  [library-path]
  (when (or (nil? library-path)
            (str/blank? (str library-path)))
    (throw (ex-info "Skia native library path not provided"
                    {:env "EINK_SKIA_NATIVE_LIB"})))
  (let [file (.getAbsoluteFile (io/file library-path))]
    (when-not (.isFile file)
      (throw (ex-info (str "Skia native library does not exist: " (.getPath file))
                      {:native-lib (.getPath file)})))
    file))

(defn load-native
  ([]
   (load-native (default-native-lib)))
  ([library-path]
   (let [file       (native-library-file library-path)
         native-lib (.getPath file)
         path       (Path/of native-lib (into-array String []))
         lookup     (try
                      (SymbolLookup/libraryLookup path (Arena/global))
                      (catch Throwable t
                        (throw (ex-info (str "Skia native library could not be loaded: " native-lib)
                                        {:native-lib native-lib}
                                        t))))
         linker     (Linker/nativeLinker)
         first-spec (first native-symbols)
         handles    (reduce (fn [acc spec]
                              (assoc acc (:key spec) (downcall lookup linker native-lib spec)))
                            {(:key first-spec) (downcall lookup linker native-lib first-spec)}
                            (rest native-symbols))]
     (assoc handles
            :native-lib native-lib
            :lookup lookup
            :linker linker))))

(defn invoke-native
  [^MethodHandle handle & args]
  (.invokeWithArguments handle (object-array args)))

(defn native-last-error
  [native]
  (let [address (invoke-native (:last-error native))]
    (when-not (= MemorySegment/NULL address)
      (let [segment (.reinterpret ^MemorySegment address (long 4096))]
        (loop [i     0
               bytes []]
          (let [b (bit-and 0xFF (int (.get segment ValueLayout/JAVA_BYTE (long i))))]
            (if (zero? b)
              (String. (byte-array (map unchecked-byte bytes)) StandardCharsets/UTF_8)
              (recur (inc i) (conj bytes b)))))))))

(def default-font-dir-env "EINK_FONT_DIR")

(def default-width 800)
(def default-height 600)
(def label-max-width 1000000.0)

(def ^:dynamic *context* nil)
(def ^:dynamic *color* [0 0 0 1])
(def ^:dynamic *style* :membrane.ui/style-fill)
(def ^:dynamic *stroke-width* 1.0)
(def ^:dynamic *command-batch* nil)
(def ^:dynamic *batch-text?* false)

(def style->native
  {:membrane.ui/style-fill            0
   :membrane.ui/style-stroke          1
   :membrane.ui/style-stroke-and-fill 2})


(def waveforms
  {:auto 0
   :du   1
   :gc16 2
   :gl16 3
   :a2   4})

(defprotocol IDraw
  :extend-via-metadata true
  (draw [this]))

(ui/add-default-draw-impls! IDraw #'draw)

(declare paragraph-bounds)

(defrecord Paragraph [text font width]
  ui/IOrigin
  (-origin [_]
    [0 0])

  ui/IBounds
  (-bounds [this]
    (if *context*
      (paragraph-bounds *context* this)
      [width (double (* 1.35 (or (:size font) (:size ui/default-font))))])))

(defn paragraph
  [text font width]
  (Paragraph. (str text) font (double width)))

(defn default-font-dir
  ([]
   (default-font-dir (System/getenv)))
  ([env]
   (not-empty (get env default-font-dir-env))))

(defn- size-t
  [n]
  (if (= "32" (System/getProperty "sun.arch.data.model"))
    (int n)
    (long n)))

(defn- timed
  [f]
  (let [start  (System/nanoTime)
        result (f)
        end    (System/nanoTime)]
    [result (/ (double (- end start)) 1000000.0)]))

(defn- c-string
  [^Arena arena value]
  (if (some? value)
    (let [bytes   (.getBytes (str value) StandardCharsets/UTF_8)
          segment (.allocate arena (long (inc (alength bytes))) 1)]
      (doseq [idx (range (alength bytes))]
        (.set segment ValueLayout/JAVA_BYTE (long idx) (aget bytes idx)))
      (.set segment ValueLayout/JAVA_BYTE (long (alength bytes)) (byte 0))
      segment)
    MemorySegment/NULL))

(defn- check-native!
  [context rv action]
  (let [code (int rv)]
    (when (neg? code)
      (let [native (:native context)]
        (throw (ex-info (str action " failed: " (or (native-last-error native) code))
                        {:action action
                         :code   code}))))
    code))

(defn- native-call!
  [context key & args]
  (check-native! context
                 (apply invoke-native (get-in context [:native key]) (:skia-context context) args)
                 (name key)))

(def ^:private command-opcodes
  {:save             1
   :restore          2
   :translate        3
   :scale            4
   :clip-rect        5
   :set-color        6
   :set-style        7
   :set-stroke-width 8
   :draw-rect        9
   :draw-round-rect  10
   :draw-path        11
   :draw-text-box    12})

(defn- new-command-batch
  []
  {:out           (ByteArrayOutputStream. 4096)
   :pending-count (volatile! 0)
   :flushes       (volatile! 0)
   :commands      (volatile! 0)
   :bytes         (volatile! 0)
   :text-calls    (volatile! 0)})

(defn- write-u8!
  [^ByteArrayOutputStream out value]
  (.write out (unchecked-int (bit-and (long value) 0xFF))))

(defn- write-i32-le!
  [^ByteArrayOutputStream out value]
  (let [n (long value)]
    (dotimes [shift 4]
      (write-u8! out (bit-shift-right n (* shift 8))))))

(defn- write-f32-le!
  [^ByteArrayOutputStream out value]
  (write-i32-le! out (Float/floatToIntBits (float value))))

(defn- utf8-bytes
  [value]
  (.getBytes (str value) StandardCharsets/UTF_8))

(defn- bump-command-count!
  [batch]
  (vswap! (:pending-count batch) inc)
  (vswap! (:commands batch) inc))

(defn- append-simple-command!
  [batch op]
  (write-u8! (:out batch) (command-opcodes op))
  (bump-command-count! batch))

(defn- append-command!
  [batch op args]
  (case op
    (:save :restore)
    (append-simple-command! batch op)

    (:translate :scale)
    (let [[x y] args]
      (append-simple-command! batch op)
      (write-f32-le! (:out batch) x)
      (write-f32-le! (:out batch) y))

    (:clip-rect :draw-rect)
    (let [[x y width height] args]
      (append-simple-command! batch op)
      (write-f32-le! (:out batch) x)
      (write-f32-le! (:out batch) y)
      (write-f32-le! (:out batch) width)
      (write-f32-le! (:out batch) height))

    :set-color
    (let [[r g b a] args]
      (append-simple-command! batch op)
      (write-f32-le! (:out batch) r)
      (write-f32-le! (:out batch) g)
      (write-f32-le! (:out batch) b)
      (write-f32-le! (:out batch) a))

    :set-style
    (let [[style] args]
      (append-simple-command! batch op)
      (write-i32-le! (:out batch) style))

    :set-stroke-width
    (let [[width] args]
      (append-simple-command! batch op)
      (write-f32-le! (:out batch) width))

    :draw-round-rect
    (let [[x y width height radius] args]
      (append-simple-command! batch op)
      (write-f32-le! (:out batch) x)
      (write-f32-le! (:out batch) y)
      (write-f32-le! (:out batch) width)
      (write-f32-le! (:out batch) height)
      (write-f32-le! (:out batch) radius))))

(defn- append-path-command!
  [batch points closed?]
  (append-simple-command! batch :draw-path)
  (write-i32-le! (:out batch) (count points))
  (write-i32-le! (:out batch) (if closed? 1 0))
  (doseq [[x y] points]
    (write-f32-le! (:out batch) x)
    (write-f32-le! (:out batch) y)))

(declare font-family font-size font-weight font-slant)

(defn- append-text-command!
  [batch text font x y max-width]
  (let [text-bytes   (utf8-bytes text)
        family       (or (font-family font) "")
        family-bytes (utf8-bytes family)
        out          (:out batch)]
    (append-simple-command! batch :draw-text-box)
    (write-i32-le! out (alength text-bytes))
    (write-i32-le! out (alength family-bytes))
    (write-f32-le! out (font-size font))
    (write-i32-le! out (font-weight font))
    (write-i32-le! out (font-slant font))
    (write-f32-le! out x)
    (write-f32-le! out y)
    (write-f32-le! out max-width)
    (.write out text-bytes 0 (alength text-bytes))
    (.write out family-bytes 0 (alength family-bytes))))

(defn- command-batch-stats
  [batch]
  {:flushes    @(:flushes batch)
   :commands   @(:commands batch)
   :bytes      @(:bytes batch)
   :text-calls @(:text-calls batch)})

(defn- flush-batch!
  [context]
  (when-let [batch *command-batch*]
    (let [^ByteArrayOutputStream out (:out batch)
          command-count             @(:pending-count batch)
          byte-count                (.size out)]
      (when (pos? byte-count)
        (let [bytes (.toByteArray out)]
          (with-open [arena (Arena/ofConfined)]
            (let [segment (.allocate arena (long byte-count) 1)]
              (MemorySegment/copy bytes 0 segment ValueLayout/JAVA_BYTE 0 byte-count)
              (check-native! context
                             (invoke-native (:replay-commands (:native context))
                                            (:skia-context context)
                                            segment
                                            (size-t byte-count)
                                            (int command-count))
                             "replay-commands"))))
        (vswap! (:flushes batch) inc)
        (vswap! (:bytes batch) + byte-count)
        (.reset out)
        (vreset! (:pending-count batch) 0)))))

(defn- canvas-command!
  [context op & args]
  (if *command-batch*
    (do
      (append-command! *command-batch* op args)
      0)
    (apply native-call! context op args)))

(defn- require-context
  []
  (or *context*
      (throw (ex-info "Skia Membrane draw called without a bound context" {}))))

(defn- require-font-dir
  [font-dir]
  (when (or (nil? font-dir)
            (str/blank? (str font-dir)))
    (throw (ex-info "Skia font directory path not provided"
                    {:env default-font-dir-env})))
  font-dir)

(defn- font-family
  [font]
  (not-empty (:name font)))

(defn- font-size
  [font]
  (float (or (:size font) (:size ui/default-font))))

(defn- font-weight
  [font]
  (let [weight (:weight font)]
    (int (cond
           (number? weight) weight
           (= :bold weight) 700
           :else 0))))

(defn- font-slant
  [font]
  (int (case (:slant font)
         :italic 1
         :oblique 2
         0)))

(defn- approximate-text-bounds
  [font text]
  (let [size (double (or (:size font) (:size ui/default-font)))]
    [(* 0.58 size (count (str text)))
     (* 1.35 size)]))

(defn- normalized-color
  [[r g b a]]
  [(float (or r 0.0))
   (float (or g 0.0))
   (float (or b 0.0))
   (float (or a 1.0))])

(defn- set-color!
  [context color]
  (let [[r g b a] (normalized-color color)]
    (canvas-command! context :set-color r g b a)))

(defn- set-style!
  [context style]
  (canvas-command! context :set-style (int (get style->native style 0))))

(defn- set-stroke-width!
  [context width]
  (canvas-command! context :set-stroke-width (float width)))

(defn- with-saved-canvas*
  [context f]
  (canvas-command! context :save)
  (try
    (f)
    (finally
      (canvas-command! context :restore))))

(defn text-metrics
  [context font text max-width]
  (with-open [arena (Arena/ofConfined)]
    (let [text'       (str text)
          text-bytes  (.getBytes text' StandardCharsets/UTF_8)
          width-seg   (.allocate arena (long 4) 4)
          height-seg  (.allocate arena (long 4) 4)
          ascent-seg  (.allocate arena (long 4) 4)
          descent-seg (.allocate arena (long 4) 4)
          leading-seg (.allocate arena (long 4) 4)]
      (check-native! context
                     (invoke-native (:text-bounds (:native context))
                                    (:skia-context context)
                                    (c-string arena text')
                                    (int (alength text-bytes))
                                    (c-string arena (font-family font))
                                    (font-size font)
                                    (font-weight font)
                                    (font-slant font)
                                    (float max-width)
                                    width-seg
                                    height-seg
                                    ascent-seg
                                    descent-seg
                                    leading-seg)
                     "text-bounds")
      {:width   (.get width-seg ValueLayout/JAVA_FLOAT 0)
       :height  (.get height-seg ValueLayout/JAVA_FLOAT 0)
       :ascent  (.get ascent-seg ValueLayout/JAVA_FLOAT 0)
       :descent (.get descent-seg ValueLayout/JAVA_FLOAT 0)
       :leading (.get leading-seg ValueLayout/JAVA_FLOAT 0)})))

(defn text-bounds
  ([context font text]
   (text-bounds context font text label-max-width))
  ([context font text max-width]
   (let [{:keys [width height]} (text-metrics context font text max-width)]
     [(double width) (double height)])))

(defn text-cache-stats
  [context]
  (with-open [arena (Arena/ofConfined)]
    (let [entries-seg   (.allocate arena (long 4) 4)
          hits-seg      (.allocate arena (long 4) 4)
          misses-seg    (.allocate arena (long 4) 4)
          evictions-seg (.allocate arena (long 4) 4)]
      (check-native! context
                     (invoke-native (:text-cache-stats (:native context))
                                    (:skia-context context)
                                    entries-seg
                                    hits-seg
                                    misses-seg
                                    evictions-seg)
                     "text-cache-stats")
      {:entries   (.get entries-seg ValueLayout/JAVA_INT 0)
       :hits      (.get hits-seg ValueLayout/JAVA_INT 0)
       :misses    (.get misses-seg ValueLayout/JAVA_INT 0)
       :evictions (.get evictions-seg ValueLayout/JAVA_INT 0)})))

(defn clear-text-cache!
  [context]
  (native-call! context :clear-text-cache)
  nil)

(defn paragraph-bounds
  [context {:keys [text font width]}]
  (text-bounds context font text width))

(defn- draw-text-box!
  [context text font x y max-width]
  (if (and *command-batch* *batch-text?*)
    (do
      (append-text-command! *command-batch* text font (float x) (float y) (float max-width))
      (vswap! (:text-calls *command-batch*) inc)
      0)
    (do
      (flush-batch! context)
      (when *command-batch*
        (vswap! (:text-calls *command-batch*) inc))
      (with-open [arena (Arena/ofConfined)]
        (let [text'      (str text)
              text-bytes (utf8-bytes text')]
          (check-native! context
                         (invoke-native (:draw-text-box (:native context))
                                        (:skia-context context)
                                        (c-string arena text')
                                        (int (alength text-bytes))
                                        (c-string arena (font-family font))
                                        (font-size font)
                                        (font-weight font)
                                        (font-slant font)
                                        (float x)
                                        (float y)
                                        (float max-width))
                         "draw-text-box"))))))

(defn copy-gray8
  [context]
  (let [width  (:width context)
        height (:height context)
        stride (:stride context)
        len    (* stride height)]
    (with-open [arena (Arena/ofConfined)]
      (let [segment (.allocate arena (long len) 1)
            data    (byte-array len)]
        (native-call! context :copy-gray8 segment (size-t len))
        (MemorySegment/copy segment ValueLayout/JAVA_BYTE 0 data 0 len)
        {:width  width
         :height height
         :stride stride
         :data   data}))))

(defn open-context!
  [{:keys [native native-lib font-dir default-family width height render-count]
    :as   _opts}]
  (let [native'     (or native (load-native (or native-lib (default-native-lib))))
        width'      (int (or width default-width))
        height'     (int (or height default-height))
        font-dir'   (require-font-dir (or font-dir (default-font-dir)))
        native-lib' (or native-lib (:native-lib native'))]
    (with-open [arena (Arena/ofConfined)]
      (let [skia-context (invoke-native (:create native')
                                        width'
                                        height'
                                        (c-string arena font-dir')
                                        (c-string arena default-family))]
        (when (= MemorySegment/NULL skia-context)
          (throw (ex-info (str "Skia context creation failed: " (native-last-error native'))
                          {:native-lib native-lib'
                           :font-dir   font-dir'
                           :width      width'
                           :height     height'})))
        {:native         native'
         :skia-context   skia-context
         :native-lib     native-lib'
         :font-dir       font-dir'
         :default-family default-family
         :width          width'
         :height         height'
         :stride         (invoke-native (:stride native') skia-context)
         :render-count   (or render-count (atom 0))}))))

(defn close-context!
  [context]
  (when (and (:native context)
             (:skia-context context)
             (not= MemorySegment/NULL (:skia-context context)))
    (check-native! context
                   (invoke-native (:destroy (:native context)) (:skia-context context))
                   "destroy"))
  nil)

(extend-type membrane.ui.Label
  ui/IBounds
  (-bounds [this]
    (if *context*
      (text-bounds *context* (:font this) (:text this))
      (approximate-text-bounds (:font this) (:text this))))

  IDraw
  (draw [this]
    (let [context (require-context)]
      (draw-text-box! context (:text this) (:font this) 0.0 0.0 label-max-width))))

(extend-type Paragraph
  IDraw
  (draw [this]
    (let [context (require-context)]
      (draw-text-box! context (:text this) (:font this) 0.0 0.0 (:width this)))))

(extend-type membrane.ui.Translate
  IDraw
  (draw [this]
    (let [context (require-context)]
      (with-saved-canvas*
        context
        (fn []
          (canvas-command! context :translate (float (:x this)) (float (:y this)))
          (draw (:drawable this)))))))

(extend-type membrane.ui.WithColor
  IDraw
  (draw [this]
    (let [context  (require-context)
          previous *color*
          color    (:color this)]
      (set-color! context color)
      (try
        (binding [*color* color]
          (doseq [drawable (:drawables this)]
            (draw drawable)))
        (finally
          (set-color! context previous))))))

(extend-type membrane.ui.WithStyle
  IDraw
  (draw [this]
    (let [context  (require-context)
          previous *style*
          style    (:style this)]
      (set-style! context style)
      (try
        (binding [*style* style]
          (doseq [drawable (:drawables this)]
            (draw drawable)))
        (finally
          (set-style! context previous))))))

(extend-type membrane.ui.WithStrokeWidth
  IDraw
  (draw [this]
    (let [context  (require-context)
          previous *stroke-width*
          width    (:stroke-width this)]
      (set-stroke-width! context width)
      (try
        (binding [*stroke-width* width]
          (doseq [drawable (:drawables this)]
            (draw drawable)))
        (finally
          (set-stroke-width! context previous))))))

(extend-type membrane.ui.Path
  IDraw
  (draw [this]
    (when-let [points (seq (:points this))]
      (let [context (require-context)]
        (if *command-batch*
          (append-path-command! *command-batch* points false)
          (let [values (mapcat identity points)]
            (with-open [arena (Arena/ofConfined)]
              (let [segment (.allocate arena (long (* 4 (count values))) 4)]
                (doseq [[idx value] (map-indexed vector values)]
                  (.set segment ValueLayout/JAVA_FLOAT (long (* idx 4)) (float value)))
                (native-call! context :draw-path segment (int (count points)) (int 0))))))))))

(extend-type membrane.ui.Rectangle
  IDraw
  (draw [this]
    (let [context (require-context)]
      (canvas-command! context
                       :draw-rect
                       (float 0.0)
                       (float 0.0)
                       (float (:width this))
                       (float (:height this))))))

(extend-type membrane.ui.RoundedRectangle
  IDraw
  (draw [this]
    (let [context (require-context)]
      (canvas-command! context
                       :draw-round-rect
                       (float 0.0)
                       (float 0.0)
                       (float (:width this))
                       (float (:height this))
                       (float (:border-radius this))))))

(extend-type membrane.ui.Scale
  IDraw
  (draw [this]
    (let [context (require-context)
          [sx sy] (:scalars this)]
      (with-saved-canvas*
        context
        (fn []
          (canvas-command! context :scale (float sx) (float sy))
          (doseq [drawable (:drawables this)]
            (draw drawable)))))))

(extend-type membrane.ui.ScissorView
  IDraw
  (draw [this]
    (let [context (require-context)
          [ox oy] (:offset this)
          [w h]   (:bounds this)]
      (with-saved-canvas*
        context
        (fn []
          (canvas-command! context :clip-rect (float ox) (float oy) (float w) (float h))
          (draw (:drawable this)))))))

(extend-type membrane.ui.ScrollView
  IDraw
  (draw [this]
    (draw (ui/scissor-view [0 0]
                           (:bounds this)
                           (let [[x y] (:offset this)]
                             (ui/translate x y (:drawable this)))))))

(defn- render-frame-direct!
  [context elem opts]
  (let [clear-gray        (int (or (:clear-gray opts) 255))
        [_clear clear-ms] (timed #(native-call! context :clear (unchecked-byte clear-gray)))
        [_draw draw-ms]   (timed #(binding [*context*       context
                                            *color*         [0 0 0 1]
                                            *style*         :membrane.ui/style-fill
                                            *stroke-width*  1.0
                                            *command-batch* nil
                                            *batch-text?*   false]
                                    (set-color! context *color*)
                                    (set-style! context *style*)
                                    (set-stroke-width! context *stroke-width*)
                                    (draw elem)))
        [gray copy-ms]    (timed #(copy-gray8 context))]
    (swap! (:render-count context) inc)
    {:gray    gray
     :timings {:clear      clear-ms
               :draw       draw-ms
               :copy-gray8 copy-ms}}))

(defn render-frame-batched!
  [context elem opts]
  (let [batch             (new-command-batch)
        clear-gray        (int (or (:clear-gray opts) 255))
        [_clear clear-ms] (timed #(native-call! context :clear (unchecked-byte clear-gray)))
        [_draw draw-ms]   (timed #(binding [*context*       context
                                            *color*         [0 0 0 1]
                                            *style*         :membrane.ui/style-fill
                                            *stroke-width*  1.0
                                            *command-batch* batch
                                            *batch-text?*   (true? (:skia-batch-text? opts))]
                                    (set-color! context *color*)
                                    (set-style! context *style*)
                                    (set-stroke-width! context *stroke-width*)
                                    (draw elem)
                                    (flush-batch! context)))
        [gray copy-ms]    (timed #(copy-gray8 context))]
    (swap! (:render-count context) inc)
    {:gray       gray
     :skia-batch (command-batch-stats batch)
     :timings    {:clear      clear-ms
                  :draw       draw-ms
                  :copy-gray8 copy-ms}}))

(defn render-frame!
  [context elem opts]
  (if (:skia-batch? opts)
    (render-frame-batched! context elem opts)
    (render-frame-direct! context elem opts)))

(defn present-frame!
  [context elem opts]
  (let [{:keys [gray] :as frame} (render-frame! context elem opts)
        x                        (int (or (:x opts) 0))
        y                        (int (or (:y opts) 0))
        width                    (int (or (:width opts) (:width gray)))
        height                   (int (or (:height opts) (:height gray)))
        waveform                 (int (get waveforms (:waveform opts :gc16) (:gc16 waveforms)))
        flash                    (int (if (get opts :flash? true) 1 0))
        wait                     (int (if (get opts :wait? true) 1 0))
        [_ ms]                   (timed #(native-call! context :present x y width height waveform flash wait))]
    (assoc frame
           :presented? true
           :present-kind :full
           :dirty-rect {:x x :y y :width width :height height}
           :timings (assoc (:timings frame) :native-present ms))))

(defn- view-container-info
  [context opts]
  {:container-size [(:width context) (:height context)]
   :context        context
   :opts           opts})

(defn view-element
  [context view-fn opts]
  (binding [*context* context]
    (if (:include-container-info opts)
      (view-fn (view-container-info context opts))
      (view-fn))))

(defn render-view!
  [context view-fn opts]
  (let [[elem view-ms] (timed #(view-element context view-fn opts))
        frame          (if (:present? opts)
                         (present-frame! context elem opts)
                         (render-frame! context elem opts))]
    (assoc-in frame [:timings :view] view-ms)))

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
  (println "  render            render/present without restarting the JVM")
  (println "  help              print this help")
  (println "  quit              close native backend and exit")
  (flush))

(defn- prompt!
  []
  (print "membrane-skia-eink> ")
  (flush))

(defn run-loop!
  [view-fn base-opts]
  (let [context (open-context! base-opts)]
    (println "ready: long-lived Membrane Skia e-ink loop")
    (print-help!)
    (try
      (loop []
        (prompt!)
        (if-let [line (read-line)]
          (let [{:keys [command]} (parse-command-line line)]
            (case command
              :blank (recur)
              :help (do (print-help!) (recur))
              :render (do
                        (let [result (render-view! context view-fn (assoc base-opts :include-container-info true))]
                          (println "rendered" (:width context) "x" (:height context)
                                   "mode" (name (or (:present-kind result) :render-only)))
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