(ns ol.membrane.eink-backend
  (:require
   [clojure.string :as str]
   [membrane.ui :as ui]
   [ol.project :as project])
  (:import
   [java.awt BasicStroke Color Font Graphics2D RenderingHints]
   [java.awt.geom Path2D$Double Rectangle2D$Double RoundRectangle2D$Double]
   [java.awt.image BufferedImage]))

(def ^:dynamic *g* nil)
(def ^:dynamic *paint-style* :membrane.ui/style-fill)
(def ^:dynamic *font-cache* nil)

(defprotocol IDraw
  :extend-via-metadata true
  (draw [this]))

(ui/add-default-draw-impls! IDraw #'draw)

(defn- color
  [[r g b a]]
  (Color. (float r) (float g) (float b) (float (or a 1.0))))

(defn get-java-font
  [font]
  (let [cache-key font]
    (if-let [cache *font-cache*]
      (if-let [entry (find @cache cache-key)]
        (val entry)
        (let [java-font (Font. (or (:name font) Font/SANS_SERIF)
                               (bit-or (if (= :bold (:weight font)) Font/BOLD 0)
                                       (if (= :italic (:slant font)) Font/ITALIC 0))
                               (int (or (:size font) (:size ui/default-font))))]
          (swap! cache assoc cache-key java-font)
          java-font))
      (Font. (or (:name font) Font/SANS_SERIF)
             (bit-or (if (= :bold (:weight font)) Font/BOLD 0)
                     (if (= :italic (:slant font)) Font/ITALIC 0))
             (int (or (:size font) (:size ui/default-font)))))))

(defn get-font-render-context
  []
  (if *g*
    (.getFontRenderContext ^Graphics2D *g*)
    (java.awt.font.FontRenderContext. (java.awt.geom.AffineTransform.)
                                      RenderingHints/VALUE_TEXT_ANTIALIAS_ON
                                      RenderingHints/VALUE_FRACTIONALMETRICS_ON)))

(defn text-bounds
  [font text]
  (let [^Font jfont (get-java-font font)
        frc         (get-font-render-context)
        lines       (str/split (str text) #"\n" -1)
        metrics     (.getLineMetrics jfont (str text) frc)
        line-height (.getHeight metrics)
        widths      (map (fn [^String line]
                           (.getWidth (.getStringBounds jfont line frc)))
                         lines)]
    [(double (reduce max 0 widths))
     (double (* line-height (count lines)))]))

(defn font-metrics
  [font]
  (let [frc     (get-font-render-context)
        jfont   (get-java-font font)
        metrics (.getLineMetrics ^Font jfont "" frc)]
    {:ascent  (.getAscent metrics)
     :descent (.getDescent metrics)
     :leading (.getLeading metrics)}))

(defn font-line-height
  [font]
  (let [frc     (get-font-render-context)
        jfont   (get-java-font font)
        metrics (.getLineMetrics ^Font jfont "" frc)]
    (.getHeight metrics)))

(defn font-advance-x
  [font s]
  (let [^Font jfont (get-java-font font)
        frc         (get-font-render-context)]
    (.getWidth (.getStringBounds jfont ^String (str s) frc))))

(defmacro ^:private push-stroke
  [& body]
  `(let [stroke# (.getStroke ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setStroke ^Graphics2D *g* stroke#)))))

(defmacro ^:private push-transform
  [& body]
  `(let [transform# (.getTransform ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setTransform ^Graphics2D *g* transform#)))))

(defmacro ^:private push-color
  [& body]
  `(let [color# (.getColor ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setColor ^Graphics2D *g* color#)))))

(defmacro ^:private push-font
  [& body]
  `(let [font# (.getFont ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setFont ^Graphics2D *g* font#)))))

(defmacro ^:private push-clip
  [& body]
  `(let [clip# (.getClip ^Graphics2D *g*)]
     (try
       ~@body
       (finally
         (.setClip ^Graphics2D *g* clip#)))))

(defn- merge-stroke
  [^BasicStroke stroke {:keys [width cap join miter-limit dash dash-phase]}]
  (BasicStroke. (float (or width (.getLineWidth stroke)))
                (int (or cap (.getEndCap stroke)))
                (int (or join (.getLineJoin stroke)))
                (float (or miter-limit (.getMiterLimit stroke)))
                ^floats (or dash (.getDashArray stroke))
                (float (or dash-phase (.getDashPhase stroke)))))

(defn- stroke-or-fill!
  [shape]
  (case *paint-style*
    :membrane.ui/style-fill (.fill ^Graphics2D *g* shape)
    :membrane.ui/style-stroke (.draw ^Graphics2D *g* shape)
    :membrane.ui/style-stroke-and-fill (do
                                         (.draw ^Graphics2D *g* shape)
                                         (.fill ^Graphics2D *g* shape))
    (.fill ^Graphics2D *g* shape)))

(extend-type membrane.ui.Label
  ui/IBounds
  (-bounds [this]
    (text-bounds (:font this) (:text this)))

  IDraw
  (draw [this]
    (let [lines       (str/split (:text this) #"\n" -1)
          font        (get-java-font (:font this))
          frc         (get-font-render-context)
          metrics     (.getLineMetrics ^Font font (:text this) frc)
          ascent      (.getAscent metrics)
          line-height (.getHeight metrics)]
      (push-font
        (.setFont ^Graphics2D *g* font)
        (doseq [[idx line] (map-indexed vector lines)]
          (.drawString ^Graphics2D *g* ^String line (float 0.0) (float (+ ascent (* idx line-height)))))))))

(extend-type membrane.ui.Translate
  IDraw
  (draw [this]
    (push-transform
      (.translate ^Graphics2D *g* (double (:x this)) (double (:y this)))
      (draw (:drawable this)))))

(extend-type membrane.ui.WithColor
  IDraw
  (draw [this]
    (push-color
      (.setColor ^Graphics2D *g* (color (:color this)))
      (doseq [drawable (:drawables this)]
        (draw drawable)))))

(extend-type membrane.ui.WithStyle
  IDraw
  (draw [this]
    (binding [*paint-style* (:style this)]
      (doseq [drawable (:drawables this)]
        (draw drawable)))))

(extend-type membrane.ui.WithStrokeWidth
  IDraw
  (draw [this]
    (push-stroke
      (.setStroke ^Graphics2D *g* (merge-stroke (.getStroke ^Graphics2D *g*)
                                                {:width (:stroke-width this)}))
      (doseq [drawable (:drawables this)]
        (draw drawable)))))

(extend-type membrane.ui.Path
  IDraw
  (draw [this]
    (when-let [[[x y] & more] (seq (:points this))]
      (let [path (Path2D$Double.)]
        (.moveTo path (double x) (double y))
        (doseq [[x y] more]
          (.lineTo path (double x) (double y)))
        (stroke-or-fill! path)))))

(extend-type membrane.ui.Rectangle
  IDraw
  (draw [this]
    (stroke-or-fill! (Rectangle2D$Double. 0 0 (double (:width this)) (double (:height this))))))

(extend-type membrane.ui.RoundedRectangle
  IDraw
  (draw [this]
    (let [arc-size (* 2 (:border-radius this))]
      (stroke-or-fill! (RoundRectangle2D$Double. 0 0
                                                 (double (:width this))
                                                 (double (:height this))
                                                 (double arc-size)
                                                 (double arc-size))))))

(extend-type membrane.ui.Scale
  IDraw
  (draw [this]
    (let [[sx sy] (:scalars this)]
      (push-transform
        (.scale ^Graphics2D *g* (double sx) (double sy))
        (doseq [drawable (:drawables this)]
          (draw drawable))))))

(extend-type membrane.ui.ScissorView
  IDraw
  (draw [this]
    (push-clip
      (let [[ox oy] (:offset this)
            [w h]   (:bounds this)]
        (.clip ^Graphics2D *g* (Rectangle2D$Double. (double ox) (double oy) (double w) (double h)))
        (draw (:drawable this))))))

(extend-type membrane.ui.ScrollView
  IDraw
  (draw [this]
    (draw (ui/scissor-view [0 0]
                           (:bounds this)
                           (let [[x y] (:offset this)]
                             (ui/translate x y (:drawable this)))))))

(defn- compatible-image?
  [^BufferedImage image width height]
  (and image
       (= BufferedImage/TYPE_BYTE_GRAY (.getType image))
       (= width (.getWidth image))
       (= height (.getHeight image))))

(defn- acquire-image
  [width height image-cache]
  (if image-cache
    (if (compatible-image? @image-cache width height)
      @image-cache
      (let [image (BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)]
        (reset! image-cache image)
        image))
    (BufferedImage. width height BufferedImage/TYPE_BYTE_GRAY)))

(defn render-to-image!
  [elem {:keys [width height image-cache font-cache]
         :or   {width 800 height 600}}]
  (let [image (acquire-image width height image-cache)
        g     (.createGraphics ^BufferedImage image)]
    (try
      (binding [*g*          g
                *font-cache* (or font-cache (atom {}))]
        (.setRenderingHint ^Graphics2D *g*
                           RenderingHints/KEY_ANTIALIASING
                           RenderingHints/VALUE_ANTIALIAS_ON)
        (.setRenderingHint ^Graphics2D *g*
                           RenderingHints/KEY_TEXT_ANTIALIASING
                           RenderingHints/VALUE_TEXT_ANTIALIAS_ON)
        (.setColor ^Graphics2D *g* Color/WHITE)
        (.fillRect ^Graphics2D *g* 0 0 (int width) (int height))
        (.setColor ^Graphics2D *g* Color/BLACK)
        (draw elem))
      image
      (finally
        (.dispose ^Graphics2D g)))))

(defn present!
  [native elem opts]
  (let [image (render-to-image! elem opts)
        gray  (project/image->gray8 image)]
    (project/present-gray8! native gray opts)
    image))

