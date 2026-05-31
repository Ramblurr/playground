(ns ol.membrane.skia-eink-backend-test
  (:require
   [clojure.java.io :as io]
   [clojure.test :refer [deftest is testing]]
   [ol.membrane.skia-eink-backend :as backend])
  (:import
   [java.lang.foreign Arena MemorySegment ValueLayout]
   [java.lang.invoke MethodHandle]))

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

(defn- size-t
  [n]
  (if (= "32" (System/getProperty "sun.arch.data.model"))
    (int n)
    (long n)))

(defn- load-test-native
  []
  (some-> (skia-native-lib) backend/load-native))

(defmacro with-test-native
  [[native-binding] & body]
  `(if-let [~native-binding (load-test-native)]
     (do ~@body)
     (is true "skipped: EINK_SKIA_NATIVE_LIB is absent")))

(defn- create-ctx
  [native width height]
  (backend/invoke-native (:create native)
                         (int width)
                         (int height)
                         MemorySegment/NULL
                         MemorySegment/NULL))

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
        (is (= "" (backend/native-last-error native)))))
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
  (with-test-native [native]
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

(deftest native-context-clear-copy-test
  (with-test-native [native]
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
  (with-test-native [native]
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
