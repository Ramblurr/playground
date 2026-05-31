(ns ol.membrane.skia-eink-backend-test
  (:require
   [clojure.java.io :as io]
   [clojure.test :refer [deftest is testing]]
   [ol.membrane.skia-eink-backend :as backend])
  (:import
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
