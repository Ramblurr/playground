(ns examples.hello-world
  (:require [raylib-clj.core :as rl]))

(defn init []
  (rl/init-window 800 450 "raylib [core] example - basic window")
  (rl/set-target-fps 60))

(defn tick [game]
  (let [
        last-time (:time game)
        acc (:time-acc game )
        newtime (System/nanoTime)
        diff (- newtime last-time)
        newacc (vec (take-last 100 (conj acc diff)))
        average-diff (/ (reduce + newacc) (count newacc))
        average-fps (long (/ 1000000000 average-diff)) ]

    (if (rl/key-down? rl/KEY_Q)
      (assoc game :exit? true)
      (-> game
          (assoc :time newtime)
          (assoc :time-acc acc)
          (assoc :avg-fps average-fps)
          (assoc :label "Hello world")))))

(defn draw [game]
  (rl/begin-drawing)
  (rl/clear-background rl/WHITE)
  (rl/draw-text (:label game) 100 100 20 rl/PURPLE)
  (rl/draw-text "press q to exit" 100 150 20 rl/PURPLE)
  (rl/draw-text (str "dt: " (:dt game)) 100 200 20 rl/PURPLE)
  (rl/draw-text (str "fps: " (:avg-fps game)) 100 250 20 rl/PURPLE)
  (rl/end-drawing))

(def game-atom (atom
                {:exit? false
                 :label "Hello world"
                 :dt 0
                 :time (System/nanoTime)
                 :time-acc [1]
                 }))
(defn start []
  (init)
  (loop []
    (let [game (tick (assoc @game-atom
                            :dt (rl/get-frame-time)
                            ))]
      (when-not (or (:exit? @game-atom) (rl/window-should-close?))
        (reset! game-atom game)
        (draw game)
        (recur))))

  (rl/close-window))

(comment
  (init)
  (start)
  (future (start))                                 ;; rcf

  ;;
  )
