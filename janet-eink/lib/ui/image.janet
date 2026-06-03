# Terminal image node.

(import ../skia :as skia)
(import ./core :as core)
(import ./element :as elem)
(import ./nodes :as nodes)
(import ./util :as util)


(def x-anchors
  {:left 0
   :center 0.5
   :right 1})

(def y-anchors
  {:top 0
   :center 0.5
   :bottom 1})


(defn- image-handle?
  [value]
  (get (protect (skia/image-info value)) 0))

(defn- load-source
  [src]
  (cond
    (image-handle? src)
    src

    (util/props? src)
    (skia/create-image src)

    (string? src)
    (skia/load-png src)

    :else
    (error (string "image: :src expected a Skia image, create-image options table, or path string, got " (type src)))))

(defn- source
  [props]
  (if (has-key? props :src)
    (get props :src)
    (error "image: props must include :src")))

(defn- ensure-image!
  [self]
  (let [src (source (get self :props @{}))]
    (when (or (nil? (get self :image nil))
              (not (deep= src (get self :loaded-src nil))))
      (let [image (load-source src)
            info (skia/image-info image)]
        (put self :image image)
        (put self :image-info info)
        (put self :loaded-src src)))
    (get self :image)))

(defn- image-info
  [self]
  (ensure-image! self)
  (get self :image-info))

(defn- positive-number!
  [who value]
  (unless (and (= :number (type value)) (> value 0))
    (error (string "image: " who " expected a positive number, got " value)))
  value)

(defn- scale-value
  [props]
  (let [value (get props :scale :fit)]
    (cond
      (or (= value :fit) (= value :fill) (= value :content))
      value

      (= :number (type value))
      (positive-number! ":scale" value)

      :else
      (error (string "image: :scale expected :fit, :fill, :content, or a positive number, got " value)))))

(defn- anchor-number!
  [who value]
  (unless (and (= :number (type value)) (>= value 0) (<= value 1))
    (error (string "image: " who " expected a number from 0 to 1, got " value)))
  value)

(defn- anchor-value
  [who options value default]
  (cond
    (nil? value)
    default

    (= :number (type value))
    (anchor-number! who value)

    :else
    (let [factor (get options value nil)]
      (if (nil? factor)
        (error (string "image: " who " expected a valid anchor keyword or number from 0 to 1, got " value))
        factor))))

(defn- image-width
  [self]
  (get (image-info self) :width))

(defn- image-height
  [self]
  (get (image-info self) :height))

(defn- scaled-content-size
  [ctx width height scale]
  (nodes/make-size (math/ceil (* width (core/scale ctx) scale))
                   (math/ceil (* height (core/scale ctx) scale))))

(defn- fit-size
  [width height cs]
  (let [aspect (/ width height)]
    (nodes/make-size (min (get cs :w) (* (get cs :h) aspect))
                     (min (/ (get cs :w) aspect) (get cs :h)))))

(defn- image-measure
  [self ctx cs]
  (let [props (get self :props @{})
        scale (scale-value props)
        width (image-width self)
        height (image-height self)]
    (case scale
      :content (scaled-content-size ctx width height 1)
      :fit (fit-size width height cs)
      :fill (nodes/make-size (get cs :w) (get cs :h))
      (scaled-content-size ctx width height scale))))

(defn- right
  [rect]
  (+ (get rect :x) (get rect :w)))

(defn- bottom
  [rect]
  (+ (get rect :y) (get rect :h)))

(defn- intersect-rect
  [a b]
  (let [x1 (max (get a :x) (get b :x))
        y1 (max (get a :y) (get b :y))
        x2 (min (right a) (right b))
        y2 (min (bottom a) (bottom b))]
    (when (and (> x2 x1) (> y2 y1))
      {:x x1 :y y1 :w (- x2 x1) :h (- y2 y1)})))

(defn- draw-scale
  [props ctx bounds width height]
  (let [scale (scale-value props)]
    (case scale
      :content (core/scale ctx)
      :fit (min (/ (get bounds :w) width)
                (/ (get bounds :h) height))
      :fill (max (/ (get bounds :w) width)
                 (/ (get bounds :h) height))
      (* (core/scale ctx) scale))))

(defn- image-draw-rects
  [self ctx bounds]
  (let [props (get self :props @{})
        width (image-width self)
        height (image-height self)
        xpos (anchor-value ":x" x-anchors (get props :x nil) 0.5)
        ypos (anchor-value ":y" y-anchors (get props :y nil) 0.5)
        scale (draw-scale props ctx bounds width height)
        img-width (* width scale)
        img-height (* height scale)
        img-left (- (+ (get bounds :x) (* (get bounds :w) xpos)) (* img-width xpos))
        img-top (- (+ (get bounds :y) (* (get bounds :h) ypos)) (* img-height ypos))
        img-rect {:x img-left :y img-top :w img-width :h img-height}
        dst (intersect-rect bounds img-rect)]
    (when dst
      {:dst dst
       :src {:x (/ (- (get dst :x) img-left) scale)
             :y (/ (- (get dst :y) img-top) scale)
             :w (/ (get dst :w) scale)
             :h (/ (get dst :h) scale)}})))

(defn- image-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (let [canvas (get ctx :canvas nil)]
    (unless canvas
      (error "image: draw requires ctx :canvas"))
    (let [image (ensure-image! self)]
      (when-let [rects (image-draw-rects self ctx bounds)]
        (let [dst (get rects :dst)
              src (get rects :src)]
          (skia/draw-image canvas image (get dst :x) (get dst :y)
                           {:src src :w (get dst :w) :h (get dst :h)})))))
  self)

(defn- image-unmount
  [self]
  (put self :image nil)
  (put self :image-info nil)
  (put self :loaded-src nil)
  ((get nodes/TerminalNode :unmount) self))

(def ImageNode
  (table/setproto @{:measure image-measure
                    :draw image-draw
                    :unmount image-unmount}
                  nodes/TerminalNode))

(defn image
  "Creates a terminal image node.

  Forms:
      [image {:src image-source}]
      [image {:src image-source :scale :fit :x :center :y :center}]

  Options:
      :src   Skia image | create-image options table | PNG path string
      :scale :fit | :fill | :content | positive number, default :fit
      :x     :left | :center | :right | number 0..1, default :center
      :y     :top | :center | :bottom | number 0..1, default :center

  Image drawing crops to the assigned bounds using source/destination rectangles."
  [& args]
  (let [props (elem/require-props! "image" args)
        [_parsed-props children] (elem/parse-args args "image")]
    (source props)
    (scale-value props)
    (anchor-value ":x" x-anchors (get props :x nil) 0.5)
    (anchor-value ":y" y-anchors (get props :y nil) 0.5)
    (elem/expect-no-children! "image" children)
    (nodes/make-node ImageNode :image props @{:ui/builtin? true
                                              :constructor image
                                              :retain-fields [:image :image-info :loaded-src]
                                              :image nil
                                              :image-info nil
                                              :loaded-src nil})))
