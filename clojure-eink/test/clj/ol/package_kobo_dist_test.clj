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
   "run-membrane-skia-demo.sh"
   "run-membrane-skia-demo-source.sh"
   "run-reading-benchmark.sh"])

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

(deftest package-script-accepts-native-result-overrides-test
  (testing "bb build can pass native Nix result paths without root result symlinks"
    (let [script (slurp "scripts/package-kobo-dist.sh")]
      (is (= {:declares-fbink-override?     true
              :declares-skia-override?      true
              :uses-fbink-override-copy?    true
              :uses-fbink-override-closure? true
              :uses-skia-override-copy?     true
              :uses-skia-override-closure?  true}
             {:declares-fbink-override?     (str/includes? script "KOBO_NATIVE_RESULT=${KOBO_NATIVE_RESULT:-$ROOT/result-kobo-native}")
              :declares-skia-override?      (str/includes? script "KOBO_SKIA_NATIVE_RESULT=${KOBO_SKIA_NATIVE_RESULT:-$ROOT/result-kobo-skia-native}")
              :uses-fbink-override-copy?    (str/includes? script "cp -P \"$KOBO_NATIVE_RESULT\"/lib/libclojure_eink.so")
              :uses-fbink-override-closure? (str/includes? script "copy_nix_runtime_libs \"$KOBO_NATIVE_RESULT\"")
              :uses-skia-override-copy?     (str/includes? script "cp -P \"$KOBO_SKIA_NATIVE_RESULT\"/lib/libclojure_eink_skia.so")
              :uses-skia-override-closure?  (str/includes? script "copy_nix_runtime_libs \"$KOBO_SKIA_NATIVE_RESULT\"")})))))

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

(deftest package-script-builds-and-ships-aot-runtime-test
  (testing "package script builds and copies the production AOT jar"
    (let [script (slurp "scripts/package-kobo-dist.sh")]
      (is (= {:declares-aot-jar?          true
              :builds-aot-jar?            true
              :copies-aot-jar?            true
              :uses-uncompressed-aot-jar? true}
             {:declares-aot-jar?          (str/includes? script "AOT_JAR_NAME=\"clojure-eink-demo-aot.jar\"")
              :builds-aot-jar?            (str/includes? script "clojure -T:build aot-jar")
              :copies-aot-jar?            (str/includes? script "cp \"$ROOT/target/$AOT_JAR_NAME\" \"$DIST/$AOT_JAR_NAME\"")
              :uses-uncompressed-aot-jar? (str/includes? (slurp "build.clj") "jar c0f")})))))

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
             {:copies-skia-bridge?            (and (str/includes? script "KOBO_SKIA_NATIVE_RESULT")
                                                   (str/includes? script "libclojure_eink_skia.so"))
              :copies-skia-runtime-libs?      (str/includes? script "libsk*.so*")
              :copies-fbink-runtime-libs?     (str/includes? script "libfbink.so*")
              :dereferences-fbink-symlinks?   (str/includes? script "cp -L \"$KOBO_NATIVE_RESULT\"/lib/libfbink.so*")
              :copies-nix-runtime-closure?    (and (str/includes? script "copy_nix_runtime_libs")
                                                   (str/includes? script "nix-store -qR")
                                                   (str/includes? script "copy_nix_runtime_libs \"$KOBO_SKIA_NATIVE_RESULT\""))
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

(deftest production-skia-script-uses-aot-classpath-test
  (testing "production Skia runtime uses the AOT jar without src/clj"
    (let [skia-demo-script (template-text "run-membrane-skia-demo.sh")]
      (is (= {:uses-aot-jar?        true
              :omits-source-path?   true
              :runs-skia-demo-main? true}
             {:uses-aot-jar?        (str/includes? skia-demo-script
                                                   "-cp \"$APP_DIR/clojure-eink-demo-aot.jar:$APP_DIR/lib/java/*:$CLOJURE_JAR\"")
              :omits-source-path?   (not (str/includes? skia-demo-script "$APP_DIR/src/clj"))
              :runs-skia-demo-main? (str/includes? skia-demo-script
                                                   "clojure.main -m ol.membrane-skia-demo --present \"$@\"")})))))

(deftest source-skia-script-preserves-source-classpath-test
  (testing "source Skia runtime remains available for source-based workflows"
    (let [skia-source-script (template-text "run-membrane-skia-demo-source.sh")]
      (is (= {:script-present?      true
              :uses-source-path?    true
              :uses-source-app-jar? true
              :runs-skia-demo-main? true}
             {:script-present?      (boolean (seq skia-source-script))
              :uses-source-path?    (str/includes? skia-source-script "$APP_DIR/src/clj")
              :uses-source-app-jar? (str/includes? skia-source-script "$APP_DIR/clojure-eink-demo.jar")
              :runs-skia-demo-main? (str/includes? skia-source-script
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
