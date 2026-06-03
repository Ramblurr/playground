(use ../deps/testament)
(import ../lib/paint :as paint)

(defn approx=
  [expected actual]
  (< (math/abs (- expected actual)) 0.000001))

(defn color-select
  [color]
  @{:r (get color :r)
    :g (get color :g)
    :b (get color :b)
    :a (get color :a)
    :model (get color :model)})

(defn paint-select
  [p]
  @{:otter/paint? (get p :otter/paint?)
    :style (get p :style)
    :r (get p :r)
    :g (get p :g)
    :b (get p :b)
    :a (get p :a)
    :width (get p :width nil)
    :cap (get p :cap nil)
    :join (get p :join nil)
    :miter (get p :miter nil)
    :anti-alias? (get p :anti-alias?)
    :skia-dither? (get p :skia-dither?)})

(deftest grayscale-string-shorthand-normalizes-to-srgb-floats
  (def observed
    @{:black-1 (color-select (paint/color "0"))
      :black-2 (color-select (paint/color "00"))
      :mid-1 (color-select (paint/color "8"))
      :mid-2 (color-select (paint/color "80"))
      :gray-alpha (color-select (paint/color "8080"))
      :white-1 (color-select (paint/color "F"))
      :white-2 (color-select (paint/color "FF"))})
  (is (deep= @{:black-1 @{:r 0 :g 0 :b 0 :a 1 :model :gray8}
               :black-2 @{:r 0 :g 0 :b 0 :a 1 :model :gray8}
               :mid-1 @{:r (/ 136 255) :g (/ 136 255) :b (/ 136 255) :a 1 :model :gray8}
               :mid-2 @{:r (/ 128 255) :g (/ 128 255) :b (/ 128 255) :a 1 :model :gray8}
               :gray-alpha @{:r (/ 128 255) :g (/ 128 255) :b (/ 128 255) :a (/ 128 255) :model :gray8}
               :white-1 @{:r 1 :g 1 :b 1 :a 1 :model :gray8}
               :white-2 @{:r 1 :g 1 :b 1 :a 1 :model :gray8}}
             observed)
      "one-, two-, and four-digit grayscale strings produce unpremultiplied color floats"))

(deftest rgb-string-shorthand-normalizes-to-srgb-floats
  (def observed
    @{:red-3 (color-select (paint/color "F00"))
      :red-6 (color-select (paint/color "FF0000"))
      :red-alpha (color-select (paint/color "FF000080"))
      :accent (color-select (paint/color "FFDD22"))})
  (is (deep= @{:red-3 @{:r 1 :g 0 :b 0 :a 1 :model :srgb}
               :red-6 @{:r 1 :g 0 :b 0 :a 1 :model :srgb}
               :red-alpha @{:r 1 :g 0 :b 0 :a (/ 128 255) :model :srgb}
               :accent @{:r 1 :g (/ 221 255) :b (/ 34 255) :a 1 :model :srgb}}
             observed)
      "three-, six-, and eight-digit RGB strings produce unpremultiplied color floats"))

(deftest srgb-and-oklch-vector-colors-normalize-with-explicit-models
  (def srgb (color-select (paint/color [1 0.87 0.13 0.5] {:model :srgb})))
  (def oklch-white (color-select (paint/color [1 0 0] {:model :oklch})))
  (def oklch-black (color-select (paint/color [0 0 0 0.25] {:model :oklch})))
  (def observed
    @{:srgb srgb
      :oklch-white-close? (and (approx= 1 (get oklch-white :r))
                               (approx= 1 (get oklch-white :g))
                               (approx= 1 (get oklch-white :b))
                               (approx= 1 (get oklch-white :a))
                               (= :oklch (get oklch-white :model)))
      :oklch-black-close? (and (approx= 0 (get oklch-black :r))
                               (approx= 0 (get oklch-black :g))
                               (approx= 0 (get oklch-black :b))
                               (approx= 0.25 (get oklch-black :a))
                               (= :oklch (get oklch-black :model)))})
  (is (deep= @{:srgb @{:r 1 :g 0.87 :b 0.13 :a 0.5 :model :srgb}
               :oklch-white-close? true
               :oklch-black-close? true}
             observed)
      "numeric vectors normalize only when an explicit color model is supplied"))

(deftest fill-and-stroke-gray-map-specs-normalize-byte-gray-and-alpha
  (def observed
    @{:fill (paint-select (paint/paint {:fill-gray 128 :alpha 192} @{}))
      :stroke (paint-select (paint/paint {:stroke-gray 128 :width 2} @{}))
      :scaled-stroke (paint-select (paint/paint {:stroke-gray 64 :width 2} {:scale 1.5}))})
  (is (deep= @{:fill @{:otter/paint? true
                       :style :fill
                       :r (/ 128 255)
                       :g (/ 128 255)
                       :b (/ 128 255)
                       :a (/ 192 255)
                       :width nil
                       :cap nil
                       :join nil
                       :miter nil
                       :anti-alias? true
                       :skia-dither? false}
               :stroke @{:otter/paint? true
                         :style :stroke
                         :r (/ 128 255)
                         :g (/ 128 255)
                         :b (/ 128 255)
                         :a 1
                         :width 2
                         :cap :butt
                         :join :miter
                         :miter 4
                         :anti-alias? true
                         :skia-dither? false}
               :scaled-stroke @{:otter/paint? true
                                :style :stroke
                                :r (/ 64 255)
                                :g (/ 64 255)
                                :b (/ 64 255)
                                :a 1
                                :width 3
                                :cap :butt
                                :join :miter
                                :miter 4
                                :anti-alias? true
                                :skia-dither? false}}
             observed)
      "gray map fields use byte gray/alpha and scale stroke width through context"))

(deftest fill-stroke-and-skia-field-paint-maps-normalize
  (def observed
    @{:fill (paint-select (paint/paint {:fill "FFDD22" :anti-alias? false :skia-dither? true} @{}))
      :stroke (paint-select (paint/paint {:stroke "0088FF"
                                          :width 6
                                          :cap :round
                                          :join :bevel
                                          :miter 5
                                          :anti-alias? true
                                          :skia-dither? true} @{}))
      :vector-fill (paint-select (paint/paint {:fill [1 0.87 0.13] :model :srgb} @{}))})
  (is (deep= @{:fill @{:otter/paint? true
                       :style :fill
                       :r 1
                       :g (/ 221 255)
                       :b (/ 34 255)
                       :a 1
                       :width nil
                       :cap nil
                       :join nil
                       :miter nil
                       :anti-alias? false
                       :skia-dither? true}
               :stroke @{:otter/paint? true
                         :style :stroke
                         :r 0
                         :g (/ 136 255)
                         :b 1
                         :a 1
                         :width 6
                         :cap :round
                         :join :bevel
                         :miter 5
                         :anti-alias? true
                         :skia-dither? true}
               :vector-fill @{:otter/paint? true
                              :style :fill
                              :r 1
                              :g 0.87
                              :b 0.13
                              :a 1
                              :width nil
                              :cap nil
                              :join nil
                              :miter nil
                              :anti-alias? true
                              :skia-dither? false}}
             observed)
      "fill/stroke paint maps preserve style, stroke fields, and Skia paint hints"))

(deftest paint-sequences-and-nil-normalize-through-paints
  (def observed
    @{:nil (paint/paints nil @{})
      :single (map paint-select (paint/paints "0" @{}))
      :sequence (map paint-select (paint/paints [{:fill "F"}
                                                 {:stroke "80" :width 1}] @{}))})
  (is (deep= @{:nil @[]
               :single @[@{:otter/paint? true
                           :style :fill
                           :r 0
                           :g 0
                           :b 0
                           :a 1
                           :width nil
                           :cap nil
                           :join nil
                           :miter nil
                           :anti-alias? true
                           :skia-dither? false}]
               :sequence @[@{:otter/paint? true
                             :style :fill
                             :r 1
                             :g 1
                             :b 1
                             :a 1
                             :width nil
                             :cap nil
                             :join nil
                             :miter nil
                             :anti-alias? true
                             :skia-dither? false}
                           @{:otter/paint? true
                             :style :stroke
                             :r (/ 128 255)
                             :g (/ 128 255)
                             :b (/ 128 255)
                             :a 1
                             :width 1
                             :cap :butt
                             :join :miter
                             :miter 4
                             :anti-alias? true
                             :skia-dither? false}]}
             observed)
      "paint/paints always returns an array and draws top-level paint sequences in order"))

(deftest malformed-specs-fail-clearly
  (def observed
    @{:bad-string (not (get (protect (paint/color "GG")) 0))
      :bad-length (not (get (protect (paint/color "FFFFF")) 0))
      :naked-integer-paint (not (get (protect (paint/paint 0 @{})) 0))
      :naked-integer-color (not (get (protect (paint/color 0)) 0))
      :ambiguous-gray-fill (not (get (protect (paint/paint {:fill "F" :fill-gray 255} @{})) 0))
      :ambiguous-fill-stroke (not (get (protect (paint/paint {:fill "F" :stroke "0"} @{})) 0))
      :bad-gray-byte (not (get (protect (paint/paint {:fill-gray 256} @{})) 0))
      :bad-alpha-byte (not (get (protect (paint/paint {:fill-gray 0 :alpha -1} @{})) 0))
      :negative-stroke-width (not (get (protect (paint/paint {:stroke "0" :width -1} @{})) 0))
      :bad-cap (not (get (protect (paint/paint {:stroke "0" :cap :triangle} @{})) 0))
      :bad-join (not (get (protect (paint/paint {:stroke "0" :join :triangle} @{})) 0))
      :top-level-vector-color (not (get (protect (paint/paints [1 0 0] @{})) 0))})
  (is (deep= @{:bad-string true
               :bad-length true
               :naked-integer-paint true
               :naked-integer-color true
               :ambiguous-gray-fill true
               :ambiguous-fill-stroke true
               :bad-gray-byte true
               :bad-alpha-byte true
               :negative-stroke-width true
               :bad-cap true
               :bad-join true
               :top-level-vector-color true}
             observed)
      "malformed colors, naked integer specs, ambiguous maps, and invalid stroke fields fail"))

(run-tests!)
