(ns ol.bb-tasks-test
  (:require
   [clojure.string :as str]
   [clojure.test :refer [deftest is testing]]))

(defn- bb-edn-text
  []
  (slurp "bb.edn"))

(deftest clean-task-removes-target-and-root-nix-result-symlinks-test
  (testing "bb clean removes target and only root Nix result symlinks"
    (let [tasks (bb-edn-text)]
      (is (= {:cleans-target?               true
              :uses-root-find?              true
              :limits-deletion-to-symlinks? true
              :groups-result-name-matches?  true
              :matches-result?              true
              :matches-result-star?         true
              :deletes-matches?             true}
             {:cleans-target?               (str/includes? tasks "clojure -T:build clean")
              :uses-root-find?              (str/includes? tasks "\"find\" \".\" \"-maxdepth\" \"1\"")
              :limits-deletion-to-symlinks? (str/includes? tasks "\"-type\" \"l\"")
              :groups-result-name-matches?  (and (str/includes? tasks "\"(\"")
                                                 (str/includes? tasks "\")\""))
              :matches-result?              (str/includes? tasks "\"-name\" \"result\"")
              :matches-result-star?         (str/includes? tasks "\"-name\" \"result-*\"")
              :deletes-matches?             (str/includes? tasks "\"-delete\"")})))))

(deftest build-task-builds-native-artifacts-and-packages-dist-test
  (testing "bb build creates ignored native result links under target and packages dist"
    (let [tasks (bb-edn-text)]
      (is (= {:builds-fbink-bridge?     true
              :builds-skia-bridge?      true
              :links-under-target?      true
              :uses-env-executable?     true
              :passes-fbink-result-env? true
              :passes-skia-result-env?  true
              :runs-package-script?     true}
             {:builds-fbink-bridge?     (str/includes? tasks ".#clojure-eink-fbink-bridge-kobo")
              :builds-skia-bridge?      (str/includes? tasks ".#clojure-eink-skia-bridge-kobo")
              :links-under-target?      (and (str/includes? tasks "target/nix-results/kobo-native")
                                             (str/includes? tasks "target/nix-results/kobo-skia-native"))
              :uses-env-executable?     (str/includes? tasks "(shell \"env\"")
              :passes-fbink-result-env? (str/includes? tasks "\"KOBO_NATIVE_RESULT=target/nix-results/kobo-native\"")
              :passes-skia-result-env?  (str/includes? tasks "\"KOBO_SKIA_NATIVE_RESULT=target/nix-results/kobo-skia-native\"")
              :runs-package-script?     (str/includes? tasks "\"scripts/package-kobo-dist.sh\"")})))))
