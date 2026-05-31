(ns ol.membrane-demo.kobo
  (:require
   [membrane.basic-components :as basic]
   [membrane.component :as component :refer [defui]]
   [membrane.ui :as ui]
   [ol.membrane.eink-backend :as backend]))

(def basic-components-loaded?
  (var? #'basic/button))

(defn font*
  [family size & {:keys [weight slant]}]
  (cond-> (ui/font family size)
    weight (assoc :weight weight)
    slant  (assoc :slant slant)))

(def default-more-state
  {:time "2:58 PM"
   :viewport [1000 1350]
   :menu [{:id :wishlist :icon :heart :label "My Wishlist"}
          {:id :articles :icon :articles :label "My Articles" :accent? true}
          {:id :activity :icon :activity :label "Activity"}
          {:id :beta :icon :flask :label "Beta Features"}
          {:id :settings :icon :settings :label "Settings"}
          {:id :help :icon :help :label "Help"}]
   :tabs [{:id :home :icon :home :label "Home"}
          {:id :books :icon :books :label "My Books"}
          {:id :discover :icon :discover :label "Discover"}
          {:id :more :icon :more :label "More" :active? true}]})

(def reference-viewport [1000 1350])

(def default-theme
  {:background [1 1 1]
   :ink [0 0 0]
   :divider [0.56 0.56 0.56]
   :accent [0.10 0.10 0.10]
   :reverse [1 1 1]
   :fonts {:status (font* "SansSerif" 20)
           :title (font* "Serif" 46)
           :menu (font* "Serif" 29 :slant :italic)
           :tab (font* "SansSerif" 24)
           :tab-active (font* "SansSerif" 24 :weight :bold)}})

(defn viewport-scale
  [[w h]]
  (let [[reference-w reference-h] reference-viewport]
    (min (/ (double w) (double reference-w))
         (/ (double h) (double reference-h)))))

(defn- scaled-size
  [scale size]
  (/ (Math/round (* scale (double size) 10.0)) 10.0))

(defn- scale-font
  [scale font]
  (update font :size #(scaled-size scale %)))

(defn theme-for
  [viewport]
  (let [scale (viewport-scale viewport)]
    (-> default-theme
        (assoc :scale scale)
        (update :fonts
                (fn [fonts]
                  (into {}
                        (map (fn [[font-id font]]
                               [font-id (scale-font scale font)])
                             fonts)))))))

(defn layout-for
  [[w h]]
  {:screen [w h]
   :margin-x (* w 0.05)
   :status-h (double (* h (/ 90 1350)))
   :header-h (double (* h (/ 100 1350)))
   :row-h (double (* h (/ 110 1350)))
   :bottom-h (double (* h (/ 105 1350)))
   :divider 1
   :icon-slot-w (* w 0.095)
   :tab-count 4})

(defn- hline
  [width color thickness]
  (ui/with-color color
    (ui/rectangle width thickness)))

(defn- label-size
  [text font]
  (backend/text-bounds font text))

(defn- center-in
  [elem [w h]]
  (let [[ew eh] (ui/bounds elem)]
    (ui/translate (/ (- w ew) 2.0)
                  (/ (- h eh) 2.0)
                  elem)))

(def layout-gap 1)

(defn- centered-cell
  [[w h] elem]
  (ui/fixed-bounds [w h]
                   (center-in elem [w h])))

(defn- label-left-cell
  [text font [w h] color]
  (let [[_ label-h] (label-size text font)]
    (ui/with-color color
      (ui/fixed-bounds [w h]
                       (ui/translate 0
                                     (/ (- h label-h) 2.0)
                                     (ui/label text font))))))

(defn- label-centered-cell
  [text font [w h] color]
  (ui/with-color color
    (ui/fixed-bounds [w h]
                     (center-in (ui/label text font) [w h]))))

(defn- label-centered
  [text font [w h]]
  (center-in (ui/label text font) [w h]))

(defn- divider-row
  [width margin color thickness]
  (ui/horizontal-layout
   (ui/spacer margin thickness)
   (hline (- width (* 2 margin)) color thickness)
   (ui/spacer margin thickness)))


(defn- stroke-icon
  [color width elem]
  (ui/with-color color
    (ui/with-stroke-width width
      (ui/with-style :membrane.ui/style-stroke elem))))

(defn- filled-icon
  [color elem]
  (ui/with-color color
    (ui/with-style :membrane.ui/style-fill elem)))

(defn- circle-path
  [r steps]
  (apply ui/path
         (for [i (range (inc steps))]
           (let [theta (* 2 Math/PI (/ i steps))]
             [(+ r (* r (Math/cos theta)))
              (+ r (* r (Math/sin theta)))]))))

(defn- icon-box
  [size elem]
  (ui/fixed-bounds [size size] elem))

(defn- points
  [size pairs]
  (mapv (fn [[x y]] [(* size x) (* size y)]) pairs))

(defn- path*
  [size pairs]
  (apply ui/path (points size pairs)))

(defn- line*
  [size a b]
  (path* size [a b]))

(defn- heart-icon
  [size color]
  (icon-box size
            (stroke-icon color 2
                         (path* size [[0.50 0.86] [0.15 0.52] [0.12 0.34]
                                      [0.28 0.20] [0.50 0.36] [0.72 0.20]
                                      [0.88 0.34] [0.85 0.52] [0.50 0.86]]))))

(defn- articles-icon
  [size color reverse]
  (icon-box size
            [(filled-icon color
                          (path* size [[0.20 0.12] [0.80 0.12] [0.80 0.62]
                                       [0.50 0.88] [0.20 0.62] [0.20 0.12]]))
             (stroke-icon reverse 3
                          (path* size [[0.34 0.46] [0.48 0.60] [0.68 0.34]]))]))

(defn- activity-icon
  [size color]
  (icon-box size
            (ui/with-color color
              [(ui/with-stroke-width 2
                 (ui/with-style :membrane.ui/style-stroke
                   [(line* size [0.18 0.12] [0.18 0.82])
                    (line* size [0.18 0.82] [0.88 0.82])]))
               (ui/translate (* size 0.30) (* size 0.52)
                             (ui/rectangle (* size 0.10) (* size 0.30)))
               (ui/translate (* size 0.48) (* size 0.34)
                             (ui/rectangle (* size 0.10) (* size 0.48)))
               (ui/translate (* size 0.66) (* size 0.20)
                             (ui/rectangle (* size 0.10) (* size 0.62)))])))

(defn- flask-icon
  [size color]
  (icon-box size
            [(stroke-icon color 2
                          (path* size [[0.42 0.12] [0.58 0.12] [0.58 0.38]
                                       [0.80 0.82] [0.20 0.82] [0.42 0.38]
                                       [0.42 0.12]]))
             (stroke-icon color 2 (line* size [0.32 0.66] [0.68 0.66]))
             (filled-icon color (ui/translate (* size 0.70) (* size 0.25)
                                              (circle-path (* size 0.05) 12)))]))

(defn- settings-icon
  [size color]
  (let [r (* size 0.38)
        c (* size 0.5)]
    (icon-box size
              [(stroke-icon color 2 (ui/translate (- c r) (- c r) (circle-path r 18)))
               (stroke-icon color 2 (ui/translate (* size 0.36) (* size 0.36)
                                                  (circle-path (* size 0.14) 14)))
               (stroke-icon color 2
                            [(line* size [0.50 0.04] [0.50 0.18])
                             (line* size [0.50 0.82] [0.50 0.96])
                             (line* size [0.04 0.50] [0.18 0.50])
                             (line* size [0.82 0.50] [0.96 0.50])])])))

(defn- help-icon
  [size color]
  (let [font (font* "SansSerif" (* size 0.70) :weight :bold)]
    (icon-box size
              [(stroke-icon color 2 (circle-path (/ size 2.0) 20))
               (ui/with-color color
                 (label-centered "?" font [size size]))])))

(defn- sun-icon
  [size color]
  (icon-box size
            [(stroke-icon color 2 (ui/translate (* size 0.32) (* size 0.32)
                                                (circle-path (* size 0.18) 14)))
             (stroke-icon color 2
                          [(line* size [0.50 0.02] [0.50 0.18])
                           (line* size [0.50 0.82] [0.50 0.98])
                           (line* size [0.02 0.50] [0.18 0.50])
                           (line* size [0.82 0.50] [0.98 0.50])
                           (line* size [0.16 0.16] [0.28 0.28])
                           (line* size [0.72 0.72] [0.84 0.84])
                           (line* size [0.84 0.16] [0.72 0.28])
                           (line* size [0.28 0.72] [0.16 0.84])])]))

(defn- wifi-icon
  [size color]
  (icon-box size
            (stroke-icon color 2
                         [(path* size [[0.16 0.38] [0.50 0.20] [0.84 0.38]])
                          (path* size [[0.28 0.56] [0.50 0.44] [0.72 0.56]])
                          (path* size [[0.40 0.72] [0.50 0.66] [0.60 0.72]])
                          (line* size [0.50 0.84] [0.50 0.86])])))

(defn- battery-icon
  [size color]
  (icon-box size
            [(stroke-icon color 2 (ui/translate (* size 0.08) (* size 0.30)
                                                (ui/rounded-rectangle (* size 0.72) (* size 0.40) 2)))
             (filled-icon color (ui/translate (* size 0.84) (* size 0.42)
                                              (ui/rectangle (* size 0.08) (* size 0.16))))
             (filled-icon color (ui/translate (* size 0.16) (* size 0.38)
                                              (ui/rectangle (* size 0.38) (* size 0.24))))]))

(defn- sync-icon
  [size color]
  (icon-box size
            (stroke-icon color 2
                         [(path* size [[0.75 0.28] [0.82 0.50] [0.70 0.72]
                                      [0.48 0.82] [0.26 0.72]])
                          (path* size [[0.25 0.72] [0.18 0.50] [0.30 0.28]
                                      [0.52 0.18] [0.74 0.28]])
                          (path* size [[0.70 0.16] [0.76 0.30] [0.60 0.30]])])))

(defn- search-icon
  [size color]
  (icon-box size
            (stroke-icon color 2
                         [(ui/translate (* size 0.12) (* size 0.12)
                                        (circle-path (* size 0.30) 18))
                          (line* size [0.62 0.62] [0.90 0.90])])))

(defn- home-icon
  [size color]
  (icon-box size
            (stroke-icon color 2
                         (path* size [[0.16 0.48] [0.50 0.18] [0.84 0.48]
                                      [0.76 0.48] [0.76 0.84] [0.28 0.84]
                                      [0.28 0.48] [0.16 0.48]]))))

(defn- books-icon
  [size color]
  (icon-box size
            (ui/with-color color
              [(ui/translate (* size 0.18) (* size 0.20)
                             (ui/rectangle (* size 0.12) (* size 0.62)))
               (ui/translate (* size 0.38) (* size 0.14)
                             (ui/rectangle (* size 0.12) (* size 0.68)))
               (ui/translate (* size 0.58) (* size 0.26)
                             (ui/rectangle (* size 0.12) (* size 0.56)))
               (stroke-icon color 2 (line* size [0.14 0.84] [0.76 0.84]))])))

(defn- discover-icon
  [size color]
  (icon-box size
            [(stroke-icon color 2 (circle-path (/ size 2.0) 20))
             (filled-icon color (path* size [[0.58 0.28] [0.46 0.54] [0.28 0.70]
                                            [0.42 0.42] [0.58 0.28]]))]))

(defn- more-tab-icon
  [size color]
  (icon-box size
            (stroke-icon color 3
                         [(line* size [0.20 0.32] [0.80 0.32])
                          (line* size [0.20 0.50] [0.80 0.50])
                          (line* size [0.20 0.68] [0.80 0.68])])))

(defn- menu-icon
  [id size theme]
  (let [ink (:ink theme)
        accent (:accent theme)
        reverse (:reverse theme)]
    (case id
      :heart (heart-icon size ink)
      :articles (articles-icon size accent reverse)
      :activity (activity-icon size ink)
      :flask (flask-icon size ink)
      :settings (settings-icon size ink)
      :help (help-icon size ink)
      (icon-box size (ui/spacer size size)))))

(defn- status-icon
  [id size theme]
  (let [ink (:ink theme)]
    (case id
      :sun (sun-icon size ink)
      :wifi (wifi-icon size ink)
      :battery (battery-icon size ink)
      :sync (sync-icon size ink)
      :search (search-icon size ink))))

(defn- tab-icon
  [id size color]
  (case id
    :home (home-icon size color)
    :books (books-icon size color)
    :discover (discover-icon size color)
    :more (more-tab-icon size color)
    (icon-box size (ui/spacer size size))))

(defui status-row [{:keys [time theme layout]}]
  (let [[w _] (:screen layout)
        h (:status-h layout)
        margin (:margin-x layout)
        icon-size (min 38 (* h 0.46))
        icon-gap (* w 0.028)
        icon-ids [:sun :wifi :battery :sync :search]
        icon-strip-w (+ (* (count icon-ids) icon-size)
                        (* (dec (count icon-ids)) icon-gap))
        time-w (max 0 (- w (* 2 margin) icon-strip-w))
        icon-cells (map (fn [icon-id]
                          (centered-cell [icon-size h]
                                         (status-icon icon-id icon-size theme)))
                        icon-ids)]
    (ui/fixed-bounds
     [w h]
     (apply ui/horizontal-layout
            (concat [(ui/spacer margin h)
                     (label-left-cell time (-> theme :fonts :status) [time-w h] (:ink theme))]
                    (interpose (ui/spacer icon-gap h) icon-cells)
                    [(ui/spacer margin h)])))))

(defui page-header [{:keys [title theme layout]}]
  (let [[w _] (:screen layout)
        h (:header-h layout)
        margin (:margin-x layout)
        divider-h (:divider layout)
        title-h (max 0 (- h divider-h layout-gap))
        content-w (- w (* 2 margin))]
    (ui/fixed-bounds
     [w h]
     (ui/vertical-layout
      (ui/horizontal-layout
       (ui/spacer margin title-h)
       (label-left-cell title (-> theme :fonts :title) [content-w title-h] (:ink theme))
       (ui/spacer margin title-h))
      (divider-row w margin (:divider theme) divider-h)))))

(defui menu-row [{:keys [item theme layout]}]
  (let [[w _] (:screen layout)
        h (:row-h layout)
        margin (:margin-x layout)
        divider-h (:divider layout)
        content-h (max 0 (- h divider-h layout-gap))
        icon-size (min 40 (* content-h 0.42))
        icon-slot (:icon-slot-w layout)
        label-w (max 0 (- w (* 2 margin) icon-slot))]
    (ui/fixed-bounds
     [w h]
     (ui/vertical-layout
      (ui/horizontal-layout
       (ui/spacer margin content-h)
       (centered-cell [icon-slot content-h]
                      (menu-icon (:icon item) icon-size theme))
       (label-left-cell (:label item) (-> theme :fonts :menu) [label-w content-h] (:ink theme))
       (ui/spacer margin content-h))
      (divider-row w margin (:divider theme) divider-h)))))

(defui menu-list [{:keys [items theme layout]}]
  (let [[w _] (:screen layout)
        h (* (:row-h layout) (count items))]
    (ui/fixed-bounds
     [w h]
     (apply ui/vertical-layout
            (map (fn [item]
                   (menu-row {:item item :theme theme :layout layout}))
                 items)))))

(defui tab-item [{:keys [tab theme layout]}]
  (let [[w _] (:screen layout)
        h (:bottom-h layout)
        tab-w (/ w (:tab-count layout))
        active? (:active? tab)
        color (if active? (:accent theme) (:ink theme))
        icon-size (min 38 (* h 0.38))
        icon-h (* h 0.52)
        label-h (max 0 (- h icon-h layout-gap))
        font (if active?
               (-> theme :fonts :tab-active)
               (-> theme :fonts :tab))]
    (ui/fixed-bounds
     [tab-w h]
     (ui/vertical-layout
      (centered-cell [tab-w icon-h]
                     (tab-icon (:icon tab) icon-size color))
      (label-centered-cell (:label tab) font [tab-w label-h] color)))))

(defui bottom-tab-bar [{:keys [tabs theme layout]}]
  (let [[w _] (:screen layout)
        h (:bottom-h layout)
        tab-w (/ w (:tab-count layout))
        indicator-h 3
        divider-h (:divider layout)
        tabs-h (max 0 (- h indicator-h divider-h (* 2 layout-gap)))
        tab-layout (assoc layout :bottom-h tabs-h)]
    (ui/fixed-bounds
     [w h]
     (ui/vertical-layout
      (apply ui/horizontal-layout
             (map (fn [tab]
                    (ui/fixed-bounds [tab-w indicator-h]
                                     (if (:active? tab)
                                       (hline tab-w (:accent theme) indicator-h)
                                       (ui/spacer tab-w indicator-h))))
                  tabs))
      (hline w (:divider theme) divider-h)
      (apply ui/horizontal-layout
             (map (fn [tab]
                    (tab-item {:tab tab :theme theme :layout tab-layout}))
                  tabs))))))

(defui more-screen [{:keys [time menu tabs theme viewport]}]
  (let [viewport (or viewport (:viewport default-more-state))
        theme (or theme (theme-for viewport))
        menu (or menu (:menu default-more-state))
        tabs (or tabs (:tabs default-more-state))
        time (or time (:time default-more-state))
        layout (layout-for viewport)
        [w h] (:screen layout)
        status-h (:status-h layout)
        header-h (:header-h layout)
        menu-h (* (:row-h layout) (count menu))
        bottom-h (:bottom-h layout)
        spacer-h (max 0 (- h status-h header-h menu-h bottom-h (* 4 layout-gap)))]
    (ui/fixed-bounds
     [w h]
     [(ui/with-color (:background theme)
        (ui/rectangle w h))
      (ui/vertical-layout
       (status-row {:time time :theme theme :layout layout})
       (page-header {:title "More" :theme theme :layout layout})
       (menu-list {:items menu :theme theme :layout layout})
       (ui/spacer w spacer-h)
       (bottom-tab-bar {:tabs tabs :theme theme :layout layout}))])))

(defn more-view
  ([]
   (component/make-app #'more-screen default-more-state))
  ([state]
   (component/make-app #'more-screen (merge default-more-state state))))