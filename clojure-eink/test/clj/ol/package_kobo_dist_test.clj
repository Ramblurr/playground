(ns ol.package-kobo-dist-test
  (:require
   [clojure.string :as str]
   [clojure.test :refer [deftest is testing]]))

(deftest package-script-ships-jvm-dependencies-test
  (testing "generated Kobo scripts include copied Maven dependency jars"
    (let [script (slurp "scripts/package-kobo-dist.sh")]
      (is (= {:copies-jars? true
              :runtime-classpath? true}
             {:copies-jars? (and (str/includes? script "lib/java")
                                 (str/includes? script "clojure -Spath"))
              :runtime-classpath? (str/includes? script "$APP_DIR/lib/java/*")})))))
