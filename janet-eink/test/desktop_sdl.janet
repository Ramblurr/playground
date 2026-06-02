(use ../deps/testament)
(import ../lib/desktop :as desktop)

(deftest desktop-sdl-renders-kobo-sized-hello-skia-buffer
  (def stats (desktop/render-hello-self-test))
  (def observed
    @{:width (get stats :width)
      :height (get stats :height)
      :text (get stats :text)
      :has-ink (> (get stats :black-pixels) 1000)})
  (is (deep= @{:width 1680
               :height 1264
               :text "HELLO SKIA"
               :has-ink true}
             observed)
      "desktop SDL backend renders the Kobo-sized Hello Skia buffer"))

(deftest desktop-sdl-centers-a-fixed-kobo-canvas-in-any-render-output
  (def large (desktop/fixed-viewport 2000 1400))
  (def small (desktop/fixed-viewport 1000 800))
  (is (deep= @{:x 160
               :y 68
               :width 1680
               :height 1264}
             large)
      "larger compositor windows center the fixed Kobo canvas without scaling")
  (is (deep= @{:x -340
               :y -232
               :width 1680
               :height 1264}
             small)
      "smaller compositor windows clip a fixed Kobo canvas instead of scaling it"))

(run-tests!)
