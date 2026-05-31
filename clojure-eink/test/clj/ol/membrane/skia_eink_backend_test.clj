(ns ol.membrane.skia-eink-backend-test
  (:require
   [clojure.java.io :as io]
   [clojure.test :refer [deftest is testing]]
   [ol.membrane.skia-eink-backend :as backend])
  (:import
   [java.lang.foreign Arena MemorySegment ValueLayout]
   [java.lang.invoke MethodHandle]
   [java.nio.charset StandardCharsets]))

(def required-abi-symbols
  ["eink_skia_last_error"
   "eink_skia_create"
   "eink_skia_destroy"
   "eink_skia_width"
   "eink_skia_height"
   "eink_skia_stride"
   "eink_skia_clear"
   "eink_skia_save"
   "eink_skia_restore"
   "eink_skia_translate"
   "eink_skia_scale"
   "eink_skia_clip_rect"
   "eink_skia_set_color"
   "eink_skia_set_style"
   "eink_skia_set_stroke_width"
   "eink_skia_draw_rect"
   "eink_skia_draw_round_rect"
   "eink_skia_draw_path"
   "eink_skia_text_bounds"
   "eink_skia_draw_text_box"
   "eink_skia_copy_gray8"
   "eink_skia_present"])

(def required-handle-keys
  [:last-error
   :create
   :destroy
   :width
   :height
   :stride
   :clear
   :save
   :restore
   :translate
   :scale
   :clip-rect
   :set-color
   :set-style
   :set-stroke-width
   :draw-rect
   :draw-round-rect
   :draw-path
   :text-bounds
   :draw-text-box
   :copy-gray8
   :present])

(defn- skia-native-lib
  []
  (not-empty (System/getenv "EINK_SKIA_NATIVE_LIB")))

(defn- font-dir
  []
  (not-empty (System/getenv "EINK_FONT_DIR")))

(defn- size-t
  [n]
  (if (= "32" (System/getProperty "sun.arch.data.model"))
    (int n)
    (long n)))

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

(defn- load-test-native
  []
  (some-> (skia-native-lib) backend/load-native))

(defmacro with-test-native
  [[native-binding] & body]
  `(if-let [~native-binding (load-test-native)]
     (do ~@body)
     (is true "skipped: EINK_SKIA_NATIVE_LIB is absent")))

(defmacro with-test-native-and-fonts
  [[native-binding font-dir-binding] & body]
  `(with-test-native [~native-binding]
     (if-let [~font-dir-binding (font-dir)]
       (do ~@body)
       (is true "skipped: EINK_FONT_DIR is absent"))))

(defn- create-ctx
  ([native width height]
   (create-ctx native width height (font-dir) nil))
  ([native width height font-dir family]
   (with-open [arena (Arena/ofConfined)]
     (backend/invoke-native (:create native)
                            (int width)
                            (int height)
                            (c-string arena font-dir)
                            (c-string arena family)))))

(defn- destroy-ctx
  [native ctx]
  (backend/invoke-native (:destroy native) ctx))

(defn- copy-ctx-bytes
  [native ctx dst-len]
  (with-open [arena (Arena/ofConfined)]
    (let [segment (.allocate arena (long dst-len) 1)
          rv      (backend/invoke-native (:copy-gray8 native) ctx segment (size-t dst-len))
          dst     (byte-array dst-len)]
      (when (zero? rv)
        (MemorySegment/copy segment ValueLayout/JAVA_BYTE 0 dst 0 dst-len))
      {:rv    rv
       :bytes (mapv #(bit-and 0xFF %) dst)})))

(defn- byte-at
  [bytes width x y]
  (nth bytes (+ x (* y width))))

(defn- dark?
  [b]
  (< b 250))

(defn- draw-path
  [native ctx points closed?]
  (with-open [arena (Arena/ofConfined)]
    (let [values  (mapcat identity points)
          segment (.allocate arena (long (* 4 (count values))) 4)]
      (doseq [[idx value] (map-indexed vector values)]
        (.set segment ValueLayout/JAVA_FLOAT (long (* idx 4)) (float value)))
      (backend/invoke-native (:draw-path native)
                             ctx
                             segment
                             (int (count points))
                             (int (if closed? 1 0))))))

(defn- text-bounds
  [native ctx text family size weight slant max-width]
  (with-open [arena (Arena/ofConfined)]
    (let [text-bytes  (.getBytes text StandardCharsets/UTF_8)
          text-seg    (c-string arena text)
          family-seg  (c-string arena family)
          width-seg   (.allocate arena (long 4) 4)
          height-seg  (.allocate arena (long 4) 4)
          ascent-seg  (.allocate arena (long 4) 4)
          descent-seg (.allocate arena (long 4) 4)
          leading-seg (.allocate arena (long 4) 4)
          rv          (backend/invoke-native (:text-bounds native)
                                             ctx
                                             text-seg
                                             (int (alength text-bytes))
                                             family-seg
                                             (float size)
                                             (int weight)
                                             (int slant)
                                             (float max-width)
                                             width-seg
                                             height-seg
                                             ascent-seg
                                             descent-seg
                                             leading-seg)]
      {:rv      rv
       :width   (.get width-seg ValueLayout/JAVA_FLOAT 0)
       :height  (.get height-seg ValueLayout/JAVA_FLOAT 0)
       :ascent  (.get ascent-seg ValueLayout/JAVA_FLOAT 0)
       :descent (.get descent-seg ValueLayout/JAVA_FLOAT 0)
       :leading (.get leading-seg ValueLayout/JAVA_FLOAT 0)})))

(defn- draw-text-box
  [native ctx text family size weight slant x y max-width]
  (with-open [arena (Arena/ofConfined)]
    (let [text-bytes (.getBytes text StandardCharsets/UTF_8)]
      (backend/invoke-native (:draw-text-box native)
                             ctx
                             (c-string arena text)
                             (int (alength text-bytes))
                             (c-string arena family)
                             (float size)
                             (int weight)
                             (int slant)
                             (float x)
                             (float y)
                             (float max-width)))))

(deftest default-native-lib-keeps-skia-env-separate-test
  (testing "Skia native discovery uses EINK_SKIA_NATIVE_LIB and never EINK_NATIVE_LIB"
    (is (= {:skia-env-wins   "skia.so"
            :old-env-ignored nil}
           {:skia-env-wins   (backend/default-native-lib {"EINK_SKIA_NATIVE_LIB" "skia.so"
                                                          "EINK_NATIVE_LIB"      "old-java2d.so"}
                                                         [])
            :old-env-ignored (backend/default-native-lib {"EINK_NATIVE_LIB" "old-java2d.so"}
                                                         [])}))))

(deftest load-native-rejects-missing-library-test
  (testing "nil library path fails before symbol lookup"
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"Skia native library path not provided"
                          (backend/load-native nil))))
  (testing "nonexistent library path fails clearly"
    (let [missing (str (java.nio.file.Files/createTempDirectory
                        "missing-skia-native"
                        (make-array java.nio.file.attribute.FileAttribute 0))
                       "/libclojure_eink_skia.so")]
      (try
        (is (thrown-with-msg? clojure.lang.ExceptionInfo
                              #"Skia native library does not exist"
                              (backend/load-native missing)))
        (finally
          (io/delete-file (.getParentFile (io/file missing)) true))))))

(deftest skia-native-library-loads-last-error-symbol-test
  (if-let [library-path (skia-native-lib)]
    (testing "EINK_SKIA_NATIVE_LIB points at a loadable Skia bridge with the first ABI symbol"
      (let [native (backend/load-native library-path)]
        (is (= []
               (remove #(instance? MethodHandle %)
                       [(:last-error native)])))
        (is (string? (backend/native-last-error native)))))
    (is true "skipped: EINK_SKIA_NATIVE_LIB is absent")))

(deftest required-skia-abi-surface-test
  (testing "the full v0 Skia bridge ABI is exported by the native library"
    (if-let [library-path (skia-native-lib)]
      (let [native (backend/load-native library-path)]
        (is (= required-abi-symbols backend/required-abi-symbols))
        (is (= {:missing-handles     []
                :all-method-handles? true}
               {:missing-handles     (vec (remove #(contains? native %) required-handle-keys))
                :all-method-handles? (every? #(instance? MethodHandle %)
                                             (map native required-handle-keys))})))
      (is true "skipped: EINK_SKIA_NATIVE_LIB is absent"))))

(deftest native-context-create-destroy-test
  (with-test-native-and-fonts [native _font-dir]
    (testing "creating a native gray8 context exposes stable geometry"
      (let [ctx (create-ctx native 13 7)]
        (try
          (is (not= MemorySegment/NULL ctx))
          (is (= {:width  13
                  :height 7
                  :stride 13}
                 {:width  (backend/invoke-native (:width native) ctx)
                  :height (backend/invoke-native (:height native) ctx)
                  :stride (backend/invoke-native (:stride native) ctx)}))
          (finally
            (is (= 0 (destroy-ctx native ctx)))))))))

(deftest native-context-invalid-dimensions-test
  (with-test-native [native]
    (testing "invalid dimensions fail clearly"
      (let [ctx (create-ctx native 0 7)]
        (is (= MemorySegment/NULL ctx))
        (is (re-find #"invalid dimensions" (backend/native-last-error native)))))))

(deftest native-font-directory-validation-test
  (with-test-native [native]
    (testing "missing font directories fail clearly"
      (let [ctx (create-ctx native 12 8 "/definitely/missing/eink-fonts" nil)]
        (is (= MemorySegment/NULL ctx))
        (is (re-find #"font directory" (backend/native-last-error native)))))
    (testing "empty font directories fail clearly"
      (let [dir (java.nio.file.Files/createTempDirectory
                 "empty-eink-fonts"
                 (make-array java.nio.file.attribute.FileAttribute 0))]
        (try
          (let [ctx (create-ctx native 12 8 (str dir) nil)]
            (is (= MemorySegment/NULL ctx))
            (is (re-find #"font directory is empty" (backend/native-last-error native))))
          (finally
            (io/delete-file (.toFile dir) true)))))))

(deftest native-context-clear-copy-test
  (with-test-native-and-fonts [native _font-dir]
    (testing "clear to white fills every gray8 byte and copy reports undersized buffers"
      (let [ctx (create-ctx native 4 3)]
        (try
          (is (= 0 (backend/invoke-native (:clear native) ctx (unchecked-byte 255))))
          (is (= {:rv    0
                  :bytes (vec (repeat 12 255))}
                 (copy-ctx-bytes native ctx 12)))
          (is (= {:rv    -22
                  :bytes (vec (repeat 11 0))}
                 (copy-ctx-bytes native ctx 11)))
          (is (re-find #"undersized" (backend/native-last-error native)))
          (finally
            (is (= 0 (destroy-ctx native ctx)))))))))

(deftest native-context-repeated-create-destroy-test
  (with-test-native-and-fonts [native _font-dir]
    (testing "contexts can be repeatedly created and destroyed"
      (is (= {:iterations 25
              :failures   0}
             (reduce (fn [acc _]
                       (let [ctx (create-ctx native 2 2)
                             rv  (destroy-ctx native ctx)]
                         (-> acc
                             (update :iterations inc)
                             (update :failures + (if (and (not= MemorySegment/NULL ctx)
                                                          (zero? rv))
                                                   0
                                                   1)))))
                     {:iterations 0 :failures 0}
                     (range 25)))))))

(deftest native-draw-rect-makes-gray8-nonwhite-test
  (with-test-native-and-fonts [native _font-dir]
    (testing "drawing a black filled rectangle changes gray8 pixels from white"
      (let [ctx (create-ctx native 32 16)]
        (try
          (is (= 0 (backend/invoke-native (:clear native) ctx (unchecked-byte 255))))
          (is (= 0 (backend/invoke-native (:set-color native) ctx (float 0.0) (float 0.0) (float 0.0) (float 1.0))))
          (is (= 0 (backend/invoke-native (:set-style native) ctx (int 0))))
          (is (= 0 (backend/invoke-native (:draw-rect native) ctx (float 4) (float 3) (float 10) (float 5))))
          (let [{:keys [bytes]} (copy-ctx-bytes native ctx (* 32 16))]
            (is (dark? (byte-at bytes 32 5 4)))
            (is (some dark? bytes)))
          (finally
            (is (= 0 (destroy-ctx native ctx)))))))))

(deftest native-transform-clip-and-restore-test
  (with-test-native-and-fonts [native _font-dir]
    (testing "save/clip/restore and translate/scale affect primitive drawing"
      (let [ctx (create-ctx native 20 8)]
        (try
          (is (= 0 (backend/invoke-native (:clear native) ctx (unchecked-byte 255))))
          (is (= 0 (backend/invoke-native (:set-color native) ctx (float 0.0) (float 0.0) (float 0.0) (float 1.0))))
          (is (= 0 (backend/invoke-native (:save native) ctx)))
          (is (= 0 (backend/invoke-native (:clip-rect native) ctx (float 0) (float 0) (float 6) (float 6))))
          (is (= 0 (backend/invoke-native (:draw-rect native) ctx (float 0) (float 0) (float 12) (float 6))))
          (is (= 0 (backend/invoke-native (:restore native) ctx)))
          (is (= 0 (backend/invoke-native (:save native) ctx)))
          (is (= 0 (backend/invoke-native (:translate native) ctx (float 8) (float 0))))
          (is (= 0 (backend/invoke-native (:scale native) ctx (float 2) (float 1))))
          (is (= 0 (backend/invoke-native (:draw-rect native) ctx (float 0) (float 0) (float 2) (float 4))))
          (is (= 0 (backend/invoke-native (:restore native) ctx)))
          (let [{:keys [bytes]} (copy-ctx-bytes native ctx (* 20 8))]
            (is (= {:clipped-in  true
                    :clipped-out false
                    :translated  true}
                   {:clipped-in  (dark? (byte-at bytes 20 2 2))
                    :clipped-out (dark? (byte-at bytes 20 7 2))
                    :translated  (dark? (byte-at bytes 20 9 2))})))
          (finally
            (is (= 0 (destroy-ctx native ctx)))))))))

(deftest native-draw-round-rect-and-path-test
  (with-test-native-and-fonts [native _font-dir]
    (testing "rounded rectangles and stroked paths draw visible gray8 pixels"
      (let [ctx (create-ctx native 32 24)]
        (try
          (is (= 0 (backend/invoke-native (:clear native) ctx (unchecked-byte 255))))
          (is (= 0 (backend/invoke-native (:set-color native) ctx (float 0.0) (float 0.0) (float 0.0) (float 1.0))))
          (is (= 0 (backend/invoke-native (:set-style native) ctx (int 0))))
          (is (= 0 (backend/invoke-native (:draw-round-rect native) ctx (float 2) (float 2) (float 12) (float 8) (float 3))))
          (is (= 0 (backend/invoke-native (:set-style native) ctx (int 1))))
          (is (= 0 (backend/invoke-native (:set-stroke-width native) ctx (float 2))))
          (is (= 0 (draw-path native ctx [[18 3] [28 12] [18 21]] false)))
          (let [{:keys [bytes]} (copy-ctx-bytes native ctx (* 32 24))]
            (is (dark? (byte-at bytes 32 6 6)))
            (is (some dark? (drop (+ 18 (* 3 32)) bytes))))
          (finally
            (is (= 0 (destroy-ctx native ctx)))))))))

(deftest native-text-bounds-and-draw-text-box-test
  (with-test-native-and-fonts [native font-dir]
    (testing "SkParagraph text bounds are positive and drawing text changes gray8 pixels"
      (let [ctx (create-ctx native 180 96 font-dir "Noto Sans")]
        (try
          (is (not= MemorySegment/NULL ctx))
          (when (not= MemorySegment/NULL ctx)
            (let [bounds (text-bounds native
                                      ctx
                                      "SkParagraph wraps text — Café 123"
                                      "Noto Sans"
                                      18
                                      400
                                      0
                                      120)]
              (is (= 0 (:rv bounds)))
              (is (pos? (:width bounds)))
              (is (pos? (:height bounds)))
              (is (pos? (:ascent bounds)))
              (is (not (neg? (:descent bounds)))))
            (is (= 0 (backend/invoke-native (:clear native) ctx (unchecked-byte 255))))
            (is (= 0 (backend/invoke-native (:set-color native) ctx (float 0.0) (float 0.0) (float 0.0) (float 1.0))))
            (is (= 0 (draw-text-box native
                                    ctx
                                    "Visible SkParagraph text"
                                    "Noto Serif"
                                    20
                                    400
                                    0
                                    4
                                    4
                                    150)))
            (let [{:keys [bytes]} (copy-ctx-bytes native ctx (* 180 96))]
              (is (some dark? bytes))))
          (finally
            (when (not= MemorySegment/NULL ctx)
              (is (= 0 (destroy-ctx native ctx))))))))))
