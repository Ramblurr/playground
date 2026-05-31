(ns ol.membrane.skia-eink-backend-test
  (:require
   [clojure.java.io :as io]
   [clojure.test :refer [deftest is testing]])
  (:import
   [java.lang.foreign Arena SymbolLookup]
   [java.nio.file Path]))

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

(defn- skia-native-lib
  []
  (not-empty (System/getenv "EINK_SKIA_NATIVE_LIB")))

(defn- library-lookup
  [library-path]
  (let [file (io/file library-path)]
    (SymbolLookup/libraryLookup (Path/of (.getAbsolutePath file) (into-array String []))
                                (Arena/global))))

(defn- missing-symbols
  [lookup symbols]
  (->> symbols
       (remove #(.isPresent (.find lookup %)))
       vec))

(deftest skia-native-library-loads-last-error-symbol-test
  (if-let [library-path (skia-native-lib)]
    (testing "EINK_SKIA_NATIVE_LIB points at a loadable Skia bridge with the first ABI symbol"
      (is (.isFile (io/file library-path))
          (str "EINK_SKIA_NATIVE_LIB should point at a file: " library-path))
      (let [lookup (library-lookup library-path)]
        (is (= [] (missing-symbols lookup ["eink_skia_last_error"])))))
    (is true "skipped: EINK_SKIA_NATIVE_LIB is absent")))

(deftest required-skia-abi-surface-test
  (testing "the full v0 Skia bridge ABI is exported by the native library"
    (if-let [library-path (skia-native-lib)]
      (let [lookup (library-lookup library-path)]
        (is (= [] (missing-symbols lookup required-abi-symbols))))
      (is false "set EINK_SKIA_NATIVE_LIB to verify the required Skia ABI surface"))))
