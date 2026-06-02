(ns ol.bench.reading
  (:require
   [membrane.ui :as ui]
   [ol.membrane.paragraph :as paragraph]))

(def default-width 1264)
(def default-height 1680)

(def chapter-text
  [(str "The old reader woke before dawn and opened the book where the ribbon waited. "
        "Outside, the harbour was still black, with one pale lamp over the pier. "
        "He liked pages at this hour because the room made no argument with them. "
        "Each line arrived cleanly, rested a moment, and gave way to the next. "
        "The device in his hand had only one task: disappear behind the words. "
        "A good page turn should feel like a breath, not like machinery starting.")
   (str "Margins mattered, but only because they kept the eye from falling away. "
        "The font had to be quiet. The contrast had to be firm without shouting. "
        "When a sentence crossed the screen, it needed shape, rhythm, and patience. "
        "He tapped once. The next page came up, carrying the same silence forward.")
   (str "Some books ask for speed. Others ask for steadiness and a long battery. "
        "On paper, no one notices the renderer. On glass, that is the renderer's job. "
        "The chapter continued with a map, a letter, and a name he had forgotten. "
        "He read the name twice, then smiled because the story had remembered him.")
   (str "By sunrise the harbour had turned silver and the room had filled with gulls. "
        "Still the page held its place, black marks on a soft grey morning. "
        "The book did not hurry. The reader did not hurry. That was the whole point. "
        "Every refresh should protect that feeling, even on slow and stubborn hardware.")
   (str "At the end of the chapter he closed his eyes and listened to the quiet click "
        "inside the case. It was not paper, but it could still be respectful. A page "
        "could be drawn with care, without hurry, and without reminding the reader "
        "that a small computer was working underneath the glass.")
   (str "He turned back one page to check a sentence he had almost missed. The screen "
        "settled into black and white again. No menu opened, no spinner appeared, and "
        "nothing asked for attention. The words simply returned to their places, which "
        "was all he had wanted from the machine.")])

(defn- scaled-layout
  [width height]
  (let [scale (min (/ (double width) default-width)
                   (/ (double height) default-height))]
    {:scale      scale
     :margin-x   (* 86.0 scale)
     :top        (* 86.0 scale)
     :title-size (* 58.0 scale)
     :body-size  (* 28.0 scale)
     :foot-size  (* 24.0 scale)
     :line-gap   (* 39.0 scale)
     :para-gap   (* 20.0 scale)}))

(defn- paragraph-views
  [{:keys [paragraphs body-font content-width body-y footer-y para-gap align margin-x]}]
  (loop [texts paragraphs
         y     body-y
         out   []]
    (if-let [text (first texts)]
      (let [paragraph (paragraph/paragraph text body-font content-width {:align align})
            [_ h]     (ui/bounds paragraph)
            bottom    (+ y h)
            next-y    (+ bottom para-gap)]
        (if (> bottom footer-y)
          out
          (recur (next texts)
                 next-y
                 (conj out (ui/translate margin-x y paragraph)))))
      out)))

(defn reading-screen
  "Builds a production-like e-reader page using paragraph text blocks.

  The body text uses [[ol.membrane.paragraph/paragraph]] once per source paragraph. It does
  not split paragraphs into one `label` per word. The active backend supplies the
  paragraph measurement used to place blocks vertically."
  ([]
   (reading-screen {}))
  ([{:keys [container-size paragraphs align]
     :or   {paragraphs chapter-text
            align      :left}}]
   (let [[width height] (or container-size [default-width default-height])
         {:keys [margin-x top title-size body-size foot-size line-gap para-gap]}
         (scaled-layout width height)
         content-width  (max 80.0 (- (double width) (* 2.0 margin-x)))
         title-font     (ui/font "Noto Serif" title-size)
         body-font      (ui/font "Noto Serif" body-size)
         foot-font      (ui/font "Noto Sans" foot-size)
         body-y         (+ top title-size (* 1.45 line-gap))
         footer-y       (- height (* 1.45 margin-x))
         body           (paragraph-views {:paragraphs    paragraphs
                                          :body-font     body-font
                                          :content-width content-width
                                          :body-y        body-y
                                          :footer-y      footer-y
                                          :para-gap      para-gap
                                          :align         align
                                          :margin-x      margin-x})]
     (ui/fixed-bounds
      [width height]
      [(ui/with-color [1 1 1]
         (ui/rectangle width height))
       (apply ui/with-color
              [0 0 0]
              (concat
               [(ui/translate margin-x top (ui/label "Chapter 7" title-font))]
               body
               [(ui/translate margin-x footer-y (ui/label "247 · The quiet renderer" foot-font))]))]))))
