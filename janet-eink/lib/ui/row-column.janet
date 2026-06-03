# Shared row/column container nodes.

(import ./core :as core)
(import ./element :as elem)
(import ./gap :as gap)
(import ./nodes :as nodes)


(def row-axis
  {:kind :row
   :name "row"
   :main :w
   :cross :h
   :pos-main :x
   :pos-cross :y
   :gap-dimension :width
   :assigned-key :assigned-width
   :align-options {:top 0 :center 0.5 :bottom 1}
   :align-doc ":top, :center, :bottom, or a number"})

(def column-axis
  {:kind :column
   :name "column"
   :main :h
   :cross :w
   :pos-main :y
   :pos-cross :x
   :gap-dimension :height
   :assigned-key :assigned-height
   :align-options {:left 0 :center 0.5 :right 1}
   :align-doc ":left, :center, :right, or a number"})

(defn- axis-name
  [axis]
  (get axis :name))

(defn- value-on
  [shape key]
  (get shape key))

(defn- make-axis-size
  [axis main cross]
  (if (= :w (get axis :main))
    (nodes/make-size main cross)
    (nodes/make-size cross main)))

(defn- make-axis-bounds
  [axis main-pos cross-pos main-size cross-size]
  (if (= :w (get axis :main))
    (nodes/make-bounds main-pos cross-pos main-size cross-size)
    (nodes/make-bounds cross-pos main-pos cross-size main-size)))

(defn- align-factor
  [axis value]
  (cond
    (or (nil? value) (= false value)) nil

    (= :number (type value)) value

    :else
    (let [options (get axis :align-options)
          factor (get options value nil)]
      (if (nil? factor)
        (error (string (axis-name axis) ": :align must be " (get axis :align-doc) ", got " value))
        factor))))

(defn- validate-align!
  [axis props]
  (align-factor axis (get props :align nil))
  props)

(defn- gap-element
  [axis props]
  (when (has-key? props :gap)
    (let [value (get props :gap nil)]
      (cond
        (or (nil? value) (= false value)) nil
        (core/dimension? value) [gap/gap {(get axis :gap-dimension) value}]
        (tuple? value) value
        :else (error (string (axis-name axis) ": :gap must be a number/function dimension or markup tuple, got " (type value)))))))

(defn- interpose-gap
  [children gap-el]
  (if (or (nil? gap-el) (< (length children) 2))
    children
    (let [out @[]]
      (var i 0)
      (while (< i (length children))
        (when (> i 0)
          (array/push out gap-el))
        (array/push out (get children i))
        (++ i))
      out)))

(defn- axis-child-elements
  [axis _self _ctx element]
  (let [parsed (elem/parse-element element)
        props (get parsed 1)
        children (elem/normalize-children (get parsed 2))]
    (interpose-gap children (gap-element axis props))))

(defn- grow-factor
  [axis child]
  (when (= :grow (get child :kind nil))
    (let [factor (or (get child :factor nil)
                     (get child :grow-factor nil)
                     1)]
      (unless (and (= :number (type factor)) (> factor 0))
        (error (string (axis-name axis) ": grow child factor must be positive, got " (type factor))))
      factor)))

(defn- push-hug-entry!
  [axis entries child ctx cs]
  (let [size (nodes/measure child ctx cs)]
    (array/push entries @{:child child
                          :size size
                          :factor nil})
    size))

(defn- allocate-grow-main-sizes!
  [axis entries leftover total-factor]
  (var assigned-sum 0)
  (var remaining-grow 0)
  (each entry entries
    (when (get entry :factor nil)
      (++ remaining-grow)))
  (each entry entries
    (when-let [factor (get entry :factor nil)]
      (let [assigned (if (= remaining-grow 1)
                       (- leftover assigned-sum)
                       (math/round (* leftover (/ factor total-factor))))
            assigned (nodes/clamp-nonnegative assigned)]
        (put entry (get axis :assigned-key) assigned)
        (set assigned-sum (+ assigned-sum assigned))
        (-- remaining-grow)))))

(defn- axis-layout
  [axis self ctx cs]
  (let [entries @[]]
    (var hug-main 0)
    (var max-cross 0)
    (var total-factor 0)
    (each child (get self :children @[])
      (if-let [factor (grow-factor axis child)]
        (do
          (array/push entries @{:child child
                                :size nil
                                :factor factor})
          (set total-factor (+ total-factor factor)))
        (let [size (push-hug-entry! axis entries child ctx cs)]
          (set hug-main (+ hug-main (value-on size (get axis :main))))
          (set max-cross (max max-cross (value-on size (get axis :cross)))))))
    (let [leftover (if (> total-factor 0)
                     (nodes/clamp-nonnegative (- (value-on cs (get axis :main)) hug-main))
                     0)]
      (when (> total-factor 0)
        (allocate-grow-main-sizes! axis entries leftover total-factor)
        (each entry entries
          (when (get entry :factor nil)
            (let [assigned-main (get entry (get axis :assigned-key))
                  child-cs (make-axis-size axis assigned-main (value-on cs (get axis :cross)))
                  size (nodes/measure (get entry :child) ctx child-cs)]
              (put entry :size size)
              (set max-cross (max max-cross (value-on size (get axis :cross))))))))
      @{:entries entries
        :size (make-axis-size axis (+ hug-main leftover) max-cross)
        :hug-main hug-main
        :total-factor total-factor})))

(defn- axis-measure
  [axis self ctx cs]
  (get (axis-layout axis self ctx cs) :size))

(defn- aligned-cross-position
  [axis bounds child-cross align]
  (if (nil? align)
    (value-on bounds (get axis :pos-cross))
    (+ (value-on bounds (get axis :pos-cross))
       (math/round (* (- (value-on bounds (get axis :cross)) child-cross) align)))))

(defn- axis-draw
  [axis self ctx bounds]
  (nodes/store-bounds! self bounds)
  (let [layout (axis-layout axis self ctx (nodes/make-size (get bounds :w) (get bounds :h)))
        align (align-factor axis (get (get self :props @{}) :align nil))]
    (var main-pos (value-on bounds (get axis :pos-main)))
    (each entry (get layout :entries)
      (let [child (get entry :child)
            size (get entry :size)
            child-main (or (get entry (get axis :assigned-key) nil)
                           (value-on size (get axis :main)))
            child-cross (if (nil? align)
                          (value-on bounds (get axis :cross))
                          (value-on size (get axis :cross)))
            cross-pos (aligned-cross-position axis bounds child-cross align)]
        (nodes/draw child ctx (make-axis-bounds axis main-pos cross-pos child-main child-cross))
        (set main-pos (+ main-pos child-main)))))
  self)

(defn- make-container-proto
  [axis]
  (table/setproto @{:measure (fn [self ctx cs] (axis-measure axis self ctx cs))
                    :draw (fn [self ctx bounds] (axis-draw axis self ctx bounds))
                    :child-elements (fn [self ctx element] (axis-child-elements axis self ctx element))}
                  nodes/ContainerNode))

(def RowNode
  (make-container-proto row-axis))

(def ColumnNode
  (make-container-proto column-axis))

(defn- make-axis-node
  [axis proto constructor args]
  (let [[props children] (elem/parse-args args (axis-name axis))]
    (validate-align! axis props)
    (gap-element axis props)
    (elem/expect-any-children! (axis-name axis) children)
    (nodes/make-node proto (get axis :kind) props @{:ui/builtin? true
                                                    :constructor constructor})))

(defn row
  "Creates a horizontal container node.

  Forms:
      [row child ...]
      [row {:gap 8 :align :center} child ...]

  Options:
      :gap   number | function | markup tuple - inserted between children
      :align :top | :center | :bottom | number - vertical alignment

  Non-grow children hug their natural width. Future `ui/grow` children consume
  leftover width by positive grow factor. Row height is the max child height;
  children draw with the full row height unless `:align` positions them within it."
  [& args]
  (make-axis-node row-axis RowNode row args))

(defn column
  "Creates a vertical container node.

  Forms:
      [column child ...]
      [column {:gap 8 :align :center} child ...]

  Options:
      :gap   number | function | markup tuple - inserted between children
      :align :left | :center | :right | number - horizontal alignment

  Non-grow children hug their natural height. Future `ui/grow` children consume
  leftover height by positive grow factor. Column width is the max child width;
  children draw with the full column width unless `:align` positions them within it."
  [& args]
  (make-axis-node column-axis ColumnNode column args))
