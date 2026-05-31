(ns ol.package-kobo-dist-test
  (:require
   [clojure.java.io :as io]
   [clojure.string :as str]
   [clojure.test :refer [deftest is testing]]))

(def dist-template-dir "resources/kobo-dist")

(def expected-dist-template-files
  ["README-KOBO.txt"
   "run-demo.sh"
   "run-loop.sh"
   "run-png-smoke.sh"
   "run-membrane-demo.sh"
   "run-membrane-loop.sh"
   "run-membrane-skia-demo.sh"])

(def expected-runtime-scripts
  (remove #{"README-KOBO.txt"} expected-dist-template-files))

(defn- dist-template-path
  [file-name]
  (str dist-template-dir "/" file-name))

(defn- template-text
  [file-name]
  (let [path (dist-template-path file-name)]
    (if (-> path io/file .isFile)
      (slurp path)
      "")))

(defn- existing-template-files
  [file-names]
  (->> file-names
       (filter #(-> % dist-template-path io/file .isFile))
       set))

(defn- executable-template-files
  [file-names]
  (->> file-names
       (filter #(-> % dist-template-path io/file .canExecute))
       set))

(deftest kobo-dist-template-files-test
  (testing "Kobo runtime files are tracked sources outside target/dist"
    (is (= (set expected-dist-template-files)
           (existing-template-files expected-dist-template-files))))
  (testing "runtime scripts are executable in the tracked template"
    (is (= (set expected-runtime-scripts)
           (executable-template-files expected-runtime-scripts)))))

(deftest package-script-rebuilds-dist-from-template-test
  (testing "package script rebuilds target/dist from resources/kobo-dist"
    (let [script (slurp "scripts/package-kobo-dist.sh")]
      (is (= {:declares-template-source? true
              :cleans-whole-dist?        true
              :copies-template?          true
              :generates-runtime-files?  false
              :allows-stale-native-lib?  false}
             {:declares-template-source? (str/includes? script "DIST_TEMPLATE=\"$ROOT/resources/kobo-dist\"")
              :cleans-whole-dist?        (str/includes? script "rm -rf \"$DIST\"")
              :copies-template?          (str/includes? script "cp -R \"$DIST_TEMPLATE\"/. \"$DIST/\"")
              :generates-runtime-files?  (or (str/includes? script "cat > \"$DIST/run-")
                                             (str/includes? script "cat > \"$DIST/README-KOBO.txt\""))
              :allows-stale-native-lib?  (or (str/includes? script "elif [[ ! -f \"$DIST/lib/libclojure_eink.so\" ]]")
                                             (str/includes? script "elif [[ ! -f \"$DIST/lib/libclojure_eink_skia.so\" ]]"))})))))

(deftest runtime-scripts-include-jvm-dependencies-test
  (testing "tracked Kobo scripts include copied Maven dependency jars on the runtime classpath"
    (is (= (zipmap expected-runtime-scripts (repeat true))
           (->> expected-runtime-scripts
                (map (fn [file-name]
                       [file-name
                        (str/includes? (template-text file-name) "$APP_DIR/lib/java/*")]))
                (into {}))))))

(deftest package-script-ships-jvm-dependencies-test
  (testing "package script copies Maven dependency jars for the Kobo runtime"
    (let [script (slurp "scripts/package-kobo-dist.sh")]
      (is (= {:copies-jars?                         true
              :runtime-classpath-moved-to-template? true}
             {:copies-jars?                         (and (str/includes? script "lib/java")
                                                         (str/includes? script "clojure -Spath"))
              :runtime-classpath-moved-to-template? (not (str/includes? script "$APP_DIR/lib/java/*"))})))))

(deftest package-script-ships-skia-demo-runtime-test
  (testing "generated Kobo dist includes the separate Skia demo runtime pieces"
    (let [script           (slurp "scripts/package-kobo-dist.sh")
          skia-demo-script (template-text "run-membrane-skia-demo.sh")]
      (is (= {:copies-skia-bridge?            true
              :copies-skia-runtime-libs?      true
              :copies-fbink-runtime-libs?     true
              :dereferences-fbink-symlinks?   true
              :copies-nix-runtime-closure?    true
              :dereferences-closure-symlinks? true
              :overwrites-duplicate-libs?     true
              :excludes-glibc-closure-libs?   true
              :cleans-stale-dist?             true
              :copies-fonts?                  true
              :ships-skia-script-template?    true
              :exports-skia-native-lib?       true
              :exports-font-dir?              true
              :sets-ld-library-path?          true
              :runs-skia-demo-main?           true}
             {:copies-skia-bridge?            (and (str/includes? script "result-kobo-skia-native/lib")
                                                   (str/includes? script "libclojure_eink_skia.so"))
              :copies-skia-runtime-libs?      (str/includes? script "libsk*.so*")
              :copies-fbink-runtime-libs?     (str/includes? script "libfbink.so*")
              :dereferences-fbink-symlinks?   (str/includes? script "cp -L \"$ROOT\"/result-kobo-native/lib/libfbink.so*")
              :copies-nix-runtime-closure?    (and (str/includes? script "copy_nix_runtime_libs")
                                                   (str/includes? script "nix-store -qR")
                                                   (str/includes? script "result-kobo-skia-native"))
              :dereferences-closure-symlinks? (str/includes? script "cp -L \"$lib_path\"")
              :overwrites-duplicate-libs?     (str/includes? script "rm -f \"$DIST/lib/$(basename -- \"$lib_path\")\"")
              :excludes-glibc-closure-libs?   (str/includes? script "*-glibc-*)")
              :cleans-stale-dist?             (str/includes? script "rm -rf \"$DIST\"")
              :copies-fonts?                  (and (str/includes? script "resources/fonts")
                                                   (str/includes? script "$DIST/fonts"))
              :ships-skia-script-template?    (not (str/blank? skia-demo-script))
              :exports-skia-native-lib?       (str/includes? skia-demo-script
                                                             "export EINK_SKIA_NATIVE_LIB=\"$APP_DIR/lib/libclojure_eink_skia.so\"")
              :exports-font-dir?              (str/includes? skia-demo-script
                                                             "export EINK_FONT_DIR=\"$APP_DIR/fonts\"")
              :sets-ld-library-path?          (str/includes? skia-demo-script
                                                             "export LD_LIBRARY_PATH=\"$APP_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\"")
              :runs-skia-demo-main?           (str/includes? skia-demo-script
                                                             "clojure.main -m ol.membrane-skia-demo --present \"$@\"")})))))

(deftest java2d-membrane-script-stays-on-old-native-env-test
  (testing "existing Java2D Membrane script does not depend on Skia env vars"
    (let [java2d-demo-script  (template-text "run-membrane-demo.sh")
          java2d-loop-script  (template-text "run-membrane-loop.sh")
          java2d-script-texts [java2d-demo-script java2d-loop-script]]
      (is (= {:scripts-present?       true
              :exports-old-native?    true
              :no-skia-native-env?    true
              :no-skia-font-env?      true
              :runs-java2d-demo-main? true}
             {:scripts-present?       (every? seq java2d-script-texts)
              :exports-old-native?    (every? #(str/includes? % "export EINK_NATIVE_LIB=\"$APP_DIR/lib/libclojure_eink.so\"")
                                              java2d-script-texts)
              :no-skia-native-env?    (not-any? #(str/includes? % "EINK_SKIA_NATIVE_LIB")
                                                java2d-script-texts)
              :no-skia-font-env?      (not-any? #(str/includes? % "EINK_FONT_DIR")
                                                java2d-script-texts)
              :runs-java2d-demo-main? (str/includes? java2d-demo-script
                                                     "clojure.main -m ol.membrane-demo --present \"$@\"")})))))
