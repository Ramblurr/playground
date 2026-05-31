(ns ol.membrane.skia-eink-backend
  (:require
   [clojure.java.io :as io]
   [clojure.string :as str])
  (:import
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
