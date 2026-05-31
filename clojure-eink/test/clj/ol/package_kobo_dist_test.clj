(ns ol.package-kobo-dist-test
  (:require
   [clojure.string :as str]
   [clojure.test :refer [deftest is testing]])
  (:import
   [java.util.regex Pattern]))

(deftest package-script-ships-jvm-dependencies-test
  (testing "generated Kobo scripts include copied Maven dependency jars"
    (let [script (slurp "scripts/package-kobo-dist.sh")]
      (is (= {:copies-jars?       true
              :runtime-classpath? true}
             {:copies-jars?       (and (str/includes? script "lib/java")
                                       (str/includes? script "clojure -Spath"))
              :runtime-classpath? (str/includes? script "$APP_DIR/lib/java/*")})))))

(defn- generated-script
  [package-script name]
  (second (re-find (re-pattern (str "(?s)cat > \"\\$DIST/"
                                    (Pattern/quote name)
                                    "\" <<'EOF'\\n(.*?)\\nEOF"))
                   package-script)))

(deftest package-script-ships-skia-demo-runtime-test
  (testing "generated Kobo dist includes the separate Skia demo runtime pieces"
    (let [script           (slurp "scripts/package-kobo-dist.sh")
          skia-demo-script (generated-script script "run-membrane-skia-demo.sh")]
      (is (= {:copies-skia-bridge?       true
              :copies-skia-runtime-libs? true
              :copies-fonts?             true
              :writes-skia-script?       true
              :exports-skia-native-lib?  true
              :exports-font-dir?         true
              :sets-ld-library-path?     true
              :runs-skia-demo-main?      true
              :chmods-skia-script?       true}
             {:copies-skia-bridge?       (and (str/includes? script "result-kobo-skia-native/lib")
                                              (str/includes? script "libclojure_eink_skia.so"))
              :copies-skia-runtime-libs? (str/includes? script "libsk*.so*")
              :copies-fonts?             (and (str/includes? script "resources/fonts")
                                              (str/includes? script "$DIST/fonts"))
              :writes-skia-script?       (some? skia-demo-script)
              :exports-skia-native-lib?  (str/includes? (or skia-demo-script "")
                                                        "export EINK_SKIA_NATIVE_LIB=\"$APP_DIR/lib/libclojure_eink_skia.so\"")
              :exports-font-dir?         (str/includes? (or skia-demo-script "")
                                                        "export EINK_FONT_DIR=\"$APP_DIR/fonts\"")
              :sets-ld-library-path?     (str/includes? (or skia-demo-script "")
                                                        "export LD_LIBRARY_PATH=\"$APP_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\"")
              :runs-skia-demo-main?      (str/includes? (or skia-demo-script "")
                                                        "clojure.main -m ol.membrane-skia-demo --present \"$@\"")
              :chmods-skia-script?       (str/includes? script "run-membrane-skia-demo.sh")})))))

(deftest java2d-membrane-script-stays-on-old-native-env-test
  (testing "existing Java2D Membrane script does not depend on Skia env vars"
    (let [script              (slurp "scripts/package-kobo-dist.sh")
          java2d-demo-script  (generated-script script "run-membrane-demo.sh")
          java2d-loop-script  (generated-script script "run-membrane-loop.sh")
          java2d-script-texts [java2d-demo-script java2d-loop-script]]
      (is (= {:scripts-present?       true
              :exports-old-native?    true
              :no-skia-native-env?    true
              :no-skia-font-env?      true
              :runs-java2d-demo-main? true}
             {:scripts-present?       (every? some? java2d-script-texts)
              :exports-old-native?    (every? #(str/includes? % "export EINK_NATIVE_LIB=\"$APP_DIR/lib/libclojure_eink.so\"")
                                              java2d-script-texts)
              :no-skia-native-env?    (not-any? #(str/includes? % "EINK_SKIA_NATIVE_LIB")
                                                java2d-script-texts)
              :no-skia-font-env?      (not-any? #(str/includes? % "EINK_FONT_DIR")
                                                java2d-script-texts)
              :runs-java2d-demo-main? (str/includes? java2d-demo-script
                                                     "clojure.main -m ol.membrane-demo --present \"$@\"")})))))
