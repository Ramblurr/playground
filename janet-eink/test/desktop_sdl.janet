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

(run-tests!)
