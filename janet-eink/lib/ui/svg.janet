# Terminal SVG node.
# TODO: Support external SVG resources such as linked images and fonts by
# configuring Skia resource providers/font managers. Current support targets
# self-contained SVG documents.

(import ../skia :as skia)
(import ./element :as elem)
(import ./nodes :as nodes)


(def fallback-svg-bytes
  (string
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"0 0 100 100\" fill=\"none\">"
    "<g clip-path=\"url(#fallback-clip)\">"
    "<rect width=\"100\" height=\"100\" fill=\"#F2F2F2\"/>"
    "<path d=\"M11 11L89 89M89 11L11 89\" stroke=\"#222222\" stroke-width=\"5\" stroke-linecap=\"round\"/>"
    "<rect x=\"2\" y=\"2\" width=\"96\" height=\"96\" stroke=\"#222222\" stroke-width=\"4\"/>"
    "</g>"
    "<defs><clipPath id=\"fallback-clip\"><rect width=\"100\" height=\"100\" fill=\"white\"/></clipPath></defs>"
    "</svg>"))


(defn- svg-handle?
  [value]
  (get (protect (skia/svg-info value)) 0))

(defn- source
  [props]
  (if (has-key? props :src)
    (get props :src)
    (error "svg: props must include :src")))

(defn- loaded-svg
  [svg owned? load-error]
  @{:svg svg
    :owned? owned?
    :load-error load-error})

(defn- protected-error-message
  [protected-result]
  (string (get protected-result 1)))

(defn- load-owned-source
  [load-fn]
  (let [loaded (protect (load-fn))]
    (if (get loaded 0)
      (loaded-svg (get loaded 1) true nil)
      (let [fallback (protect (skia/load-svg-bytes fallback-svg-bytes))]
        (if (get fallback 0)
          (loaded-svg (get fallback 1) true (protected-error-message loaded))
          (error (string "svg: failed to load fallback SVG after source load failed: "
                         (protected-error-message fallback))))))))

(defn- load-source
  [src]
  (cond
    (svg-handle? src)
    (loaded-svg src false nil)

    (= :buffer (type src))
    (load-owned-source (fn [] (skia/load-svg-bytes src)))

    (string? src)
    (load-owned-source (fn [] (skia/load-svg src)))

    :else
    (error (string "svg: :src expected a Skia SVG handle, SVG byte buffer, or path string, got " (type src)))))

(defn- close-owned-svg!
  [self]
  (when (and (get self :svg-owned? false) (get self :svg nil))
    (skia/close-svg (get self :svg)))
  (put self :svg nil)
  (put self :svg-info nil)
  (put self :svg-owned? false)
  (put self :svg-load-error nil)
  (put self :loaded-src nil)
  self)

(defn- ensure-svg!
  [self]
  (let [src (source (get self :props @{}))]
    (when (or (nil? (get self :svg nil))
              (not (deep= src (get self :loaded-src nil))))
      (let [loaded (load-source src)
            svg (get loaded :svg)
            info (skia/svg-info svg)]
        (close-owned-svg! self)
        (put self :svg svg)
        (put self :svg-info info)
        (put self :svg-owned? (get loaded :owned? false))
        (put self :svg-load-error (get loaded :load-error nil))
        (put self :loaded-src src)))
    (get self :svg)))

(defn- scale-value
  [props]
  (let [value (get props :scale :fit)]
    (case value
      :fit value
      :fill value
      (error (string "svg: :scale expected :fit or :fill, got " value)))))

(defn- preserve-aspect-ratio?
  [props]
  (let [value (get props :preserve-aspect-ratio true)]
    (cond
      (= value true) true
      (= value false) false
      :else (error (string "svg: :preserve-aspect-ratio expected true or false, got " value)))))

(defn- x-anchor
  [value]
  (case value
    nil :center
    :left :left
    :center :center
    :right :right
    0 :left
    0.5 :center
    1 :right
    (error (string "svg: :x expected :left, :center, :right, 0, 0.5, or 1, got " value))))

(defn- y-anchor
  [value]
  (case value
    nil :center
    :top :top
    :center :center
    :bottom :bottom
    0 :top
    0.5 :center
    1 :bottom
    (error (string "svg: :y expected :top, :center, :bottom, 0, 0.5, or 1, got " value))))

(defn- validate-options!
  [props]
  (source props)
  (preserve-aspect-ratio? props)
  (scale-value props)
  (x-anchor (get props :x nil))
  (y-anchor (get props :y nil))
  props)

(defn- svg-measure
  [_self _ctx cs]
  (nodes/make-size (get cs :w) (get cs :h)))

(defn- svg-draw
  [self ctx bounds]
  (nodes/store-bounds! self bounds)
  (let [canvas (get ctx :canvas nil)]
    (unless canvas
      (error "svg: draw requires ctx :canvas"))
    (skia/draw-svg canvas
                   (ensure-svg! self)
                   (get bounds :x)
                   (get bounds :y)
                   (get bounds :w)
                   (get bounds :h)
                   (get self :props @{})))
  self)

(defn- svg-unmount
  [self]
  (close-owned-svg! self)
  ((get nodes/TerminalNode :unmount) self))

(defn- svg-should-reconcile?
  [self _ctx new-element]
  (deep= (get (get self :props @{}) :src nil)
         (get (elem/element-props new-element) :src nil)))

(def SvgNode
  (table/setproto @{:measure svg-measure
                    :draw svg-draw
                    :unmount svg-unmount
                    :should-reconcile? svg-should-reconcile?}
                  nodes/TerminalNode))

(defn svg
  "Creates a terminal SVG node.

  Forms:
      [svg {:src svg-source}]
      [svg {:src svg-source :scale :fit :x :center :y :center}]

  Options:
      :src Skia SVG handle | SVG byte buffer | path string
      :preserve-aspect-ratio true | false, default true
      :scale :fit | :fill, default :fit
      :x :left | :center | :right | 0 | 0.5 | 1, default :center
      :y :top | :center | :bottom | 0 | 0.5 | 1, default :center

  If loading the source fails, the node renders a built-in fallback SVG.
  The node measures to the incoming constraints and renders into its assigned bounds."
  [& args]
  (let [props (elem/require-props! "svg" args)
        [_parsed-props children] (elem/parse-args args "svg")]
    (validate-options! props)
    (elem/expect-no-children! "svg" children)
    (nodes/make-node SvgNode :svg props @{:ui/builtin? true
                                          :constructor svg
                                          :retain-fields [:svg :svg-info :svg-owned? :svg-load-error :loaded-src]
                                          :svg nil
                                          :svg-info nil
                                          :svg-owned? false
                                          :svg-load-error nil
                                          :loaded-src nil})))
