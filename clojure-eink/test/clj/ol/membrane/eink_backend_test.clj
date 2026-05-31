(ns ol.membrane.eink-backend-test
  (:require
   [clojure.java.io :as io]
   [clojure.test :refer [deftest is testing]]
   [membrane.toolkit :as tk]
   [membrane.ui :as ui]
   [ol.membrane.eink-backend :as backend]
   [ol.project :as project])
  (:import
   [javax.imageio ImageIO]))


(deftest draw-basic-ui-to-gray-image-test
  (testing "renders Membrane shapes and text to a byte-backed grayscale image"
    (let [elem  [(ui/with-color [0 0 0]
                   (ui/rectangle 80 40))
                 (ui/translate 12 28
                               (ui/label "Hi" (ui/font nil 24)))]
          image (backend/render-to-image! elem {:width 160 :height 96})
          gray  (project/image->gray8 image)]
      (is (= 160 (:width gray)))
      (is (= 96 (:height gray)))
      (is (some #(< (bit-and 0xFF %) 250) (:data gray))))))

(deftest gray8-snapshot-copies-backing-data-test
  (testing "snapshot-gray8 copies bytes instead of keeping mutable image backing data"
    (let [data     (byte-array (map byte [1 2 3 4]))
          gray     {:width 2 :height 2 :stride 2 :data data}
          snapshot (backend/snapshot-gray8 gray)]
      (aset-byte data 0 (byte 99))
      (is (= {:width 2 :height 2 :stride 2} (dissoc snapshot :data)))
      (is (= [1 2 3 4] (mapv #(bit-and 0xFF %) (:data snapshot)))))))

(deftest diff-gray8-test
  (testing "nil previous means full damage"
    (is (= {:x 0 :y 0 :width 3 :height 2}
           (backend/diff-gray8 nil {:width 3 :height 2 :stride 3 :data (byte-array 6)}))))
  (testing "equal gray buffers have no damage"
    (let [gray {:width 3 :height 2 :stride 3 :data (byte-array (map byte [0 1 2 3 4 5]))}]
      (is (nil? (backend/diff-gray8 (backend/snapshot-gray8 gray) gray)))))
  (testing "damage is one bounding rect around changed pixels"
    (let [previous {:width 4 :height 3 :stride 4
                    :data  (byte-array (repeat 12 (byte 0)))}
          current  {:width 4 :height 3 :stride 4
                    :data  (byte-array (map byte [0 0 0 0
                                                   0 7 0 8
                                                   0 0 9 0]))}]
      (is (= {:x 1 :y 1 :width 3 :height 2}
             (backend/diff-gray8 previous current))))))

(deftest crop-gray8-test
  (testing "crop-gray8 copies rows into a compact buffer"
    (let [gray {:width 4 :height 3 :stride 4
                :data  (byte-array (map byte [0 1 2 3
                                               4 5 6 7
                                               8 9 10 11]))}
          crop (backend/crop-gray8 gray {:x 1 :y 1 :width 2 :height 2})]
      (is (= {:width 2 :height 2 :stride 2} (dissoc crop :data)))
      (is (= [5 6 9 10] (mapv #(bit-and 0xFF %) (:data crop)))))))

(deftest present-gray8-with-damage-test
  (testing "first present sends full buffer and stores a copied previous snapshot"
    (let [calls   (atom [])
          context {:native ::native :previous-gray (atom nil)}
          data    (byte-array (map byte [1 2 3 4]))
          gray    {:width 2 :height 2 :stride 2 :data data}]
      (with-redefs [project/present-gray8! (fn [native gray opts]
                                             (swap! calls conj {:native native :gray gray :opts opts}))]
        (is (= {:presented? true
                :present-kind :full
                :dirty-rect {:x 0 :y 0 :width 2 :height 2}}
               (select-keys (backend/present-gray8-with-damage! context gray {:waveform :du})
                            [:presented? :present-kind :dirty-rect])))
        (is (= 1 (count @calls)))
        (is (= ::native (:native (first @calls))))
        (is (= [1 2 3 4] (mapv #(bit-and 0xFF %) (-> @calls first :gray :data))))
        (aset-byte data 0 (byte 99))
        (is (= [1 2 3 4] (mapv #(bit-and 0xFF %) (:data @(:previous-gray context))))))))
  (testing "unchanged buffers skip native present"
    (let [calls   (atom [])
          gray    {:width 2 :height 2 :stride 2 :data (byte-array (map byte [1 2 3 4]))}
          context {:native ::native :previous-gray (atom (backend/snapshot-gray8 gray))}]
      (with-redefs [project/present-gray8! (fn [& args] (swap! calls conj args))]
        (is (= {:presented? false :present-kind :skip :dirty-rect nil}
               (select-keys (backend/present-gray8-with-damage! context gray {})
                            [:presented? :present-kind :dirty-rect])))
        (is (empty? @calls)))))
  (testing "small damage crops and presents at dirty x/y"
    (let [calls   (atom [])
          context {:native ::native
                   :previous-gray (atom {:width 4 :height 3 :stride 4
                                          :data (byte-array (repeat 12 (byte 0)))})}
          current {:width 4 :height 3 :stride 4
                   :data  (byte-array (map byte [0 0 0 0
                                                  0 7 0 8
                                                  0 0 9 0]))}]
      (with-redefs [project/present-gray8! (fn [native gray opts]
                                             (swap! calls conj {:native native :gray gray :opts opts}))]
        (is (= {:presented? true
                :present-kind :partial
                :dirty-rect {:x 1 :y 1 :width 3 :height 2}}
               (select-keys (backend/present-gray8-with-damage! context current {:damage-full-threshold 1.0})
                            [:presented? :present-kind :dirty-rect])))
        (is (= 1 (count @calls)))
        (is (= {:x 1 :y 1} (select-keys (:opts (first @calls)) [:x :y])))
        (is (= {:width 3 :height 2 :stride 3} (dissoc (:gray (first @calls)) :data)))
        (is (= [7 0 8 0 9 0] (mapv #(bit-and 0xFF %) (-> @calls first :gray :data))))))))

(deftest render-and-present-frame-test
  (testing "context render path reuses caches and skips unchanged second present"
    (let [calls   (atom [])
          context (backend/open-context! {:native ::native :width 160 :height 96})
          elem    [(ui/with-color [0 0 0]
                    (ui/rectangle 80 40))
                   (ui/translate 12 28
                                 (ui/label "Hi" (ui/font nil 24)))]]
      (try
        (with-redefs [project/present-gray8! (fn [native gray opts]
                                               (swap! calls conj {:native native :gray gray :opts opts}))]
          (let [first-result  (backend/present-frame! context elem {})
                first-image   (:image first-result)
                second-result (backend/present-frame! context elem {})]
            (is (= :full (:present-kind first-result)))
            (is (= :skip (:present-kind second-result)))
            (is (= 1 (count @calls)))
            (is (identical? first-image (:image second-result)))
            (is (some? @(:previous-gray context)))))
        (finally
          (backend/close-context! context))))))

(deftest render-view-test
  (testing "render-view! calls a view function with container info and presents when requested"
    (let [calls      (atom [])
          containers (atom [])
          context    (backend/open-context! {:native ::native :width 160 :height 96})
          view-fn    (fn [{:keys [container-size]}]
                       (swap! containers conj container-size)
                       (ui/rectangle 10 10))]
      (try
        (with-redefs [project/present-gray8! (fn [native gray opts]
                                               (swap! calls conj {:native native :gray gray :opts opts}))]
          (let [result (backend/render-view! context view-fn {:include-container-info true
                                                              :present? true})]
            (is (= [[160 96]] @containers))
            (is (= :full (:present-kind result)))
            (is (= 1 (count @calls)))))
        (finally
          (backend/close-context! context))))))

(defn- current-toolkit
  []
  (some-> (ns-resolve 'ol.membrane.eink-backend 'toolkit) deref))

(deftest toolkit-conformance-test
  (testing "e-ink backend exposes a Membrane toolkit object"
    (let [toolkit (current-toolkit)
          font    (ui/font nil 24)]
      (is (some? toolkit) "ol.membrane.eink-backend/toolkit should exist")
      (when toolkit
        (is (= {:toolkit?      true
                :run?          true
                :run-sync?     true
                :font-metrics? true
                :advance-x?    true
                :line-height?  true
                :save-image?   true}
               {:toolkit?      (tk/toolkit? toolkit)
                :run?          (satisfies? tk/IToolkitRun toolkit)
                :run-sync?     (satisfies? tk/IToolkitRunSync toolkit)
                :font-metrics? (satisfies? tk/IToolkitFontMetrics toolkit)
                :advance-x?    (satisfies? tk/IToolkitFontAdvanceX toolkit)
                :line-height?  (satisfies? tk/IToolkitFontLineHeight toolkit)
                :save-image?   (satisfies? tk/IToolkitSaveImage toolkit)}))
        (is (= (backend/font-metrics font)
               (tk/font-metrics toolkit font)))
        (is (= (backend/font-line-height font)
               (tk/font-line-height toolkit font)))
        (is (= (backend/font-advance-x font "Hello")
               (tk/font-advance-x toolkit font "Hello")))))))

(deftest toolkit-save-image-test
  (testing "toolkit save-image renders a PNG at the requested size"
    (let [toolkit (current-toolkit)
          dest    (str (java.nio.file.Files/createTempFile "membrane-toolkit" ".png"
                                                              (make-array java.nio.file.attribute.FileAttribute 0)))]
      (is (some? toolkit) "ol.membrane.eink-backend/toolkit should exist")
      (try
        (when toolkit
          (let [saved-path (tk/save-image toolkit
                                          dest
                                          (ui/with-color [0 0 0]
                                            (ui/rectangle 12 8))
                                          [64 32])
                image      (ImageIO/read (io/file saved-path))]
            (is (= (.getAbsolutePath (io/file dest)) saved-path))
            (is (= [64 32] [(.getWidth image) (.getHeight image)]))))
        (finally
          (io/delete-file dest true))))))
