(ns examples.pong
  (:require
   [clojure.string :as string]
   [raylib-clj.core :as rl]))

(def WIDTH 800)
(def HEIGHT 450)
(def PADDLE_HEIGHT 50)
(def PADDLE_WIDTH 10)
(def BALL_RADIUS 10)
(def TOP [0 10 WIDTH 1])
(def BOTTOM [0 (- HEIGHT 10) WIDTH 1])
(def LEFT [0 0 1 HEIGHT])
(def RIGHT [WIDTH 0 1 HEIGHT])
(def PADDLE1_X 50)
(def PADDLE2_X 750)
(def MAX_POINTS 11)

(defn rand-direction []
  (* (quot 6 2) (rand-nth [1 -1])))

(defn initial-state []
  {:dt 0
   :time (System/nanoTime)
   :time-acc [1]
   :right 0
   :left 0
   :screen :title
   :paddle1 (- (quot 450 2) (quot PADDLE_HEIGHT 2))
   :paddle2 (- (quot 450 2) (quot PADDLE_HEIGHT 2))
   :ball [400 225 (rand-direction) (rand-direction)]})

(def game-atom (atom (initial-state)))

(defn init []
  (rl/init-window WIDTH HEIGHT "Raylib Clojure Pong")
  (rl/set-target-fps 60))

(defn update-fps [game]
  (let [last-time (:time game)
        acc (:time-acc game)
        newtime (System/nanoTime)
        diff (- newtime last-time)
        newacc (vec (take-last 100 (conj acc diff)))
        average-diff (/ (reduce + newacc) (count newacc))
        average-fps (long (/ 1000000000 average-diff))]
    (-> game
        (assoc :dt (rl/get-frame-time))
        (assoc :time newtime)
        (assoc :time-acc acc)
        (assoc :avg-fps average-fps))))

(defn move-paddle [game up-key down-key paddle-key]
  (cond
    (rl/key-down? up-key) (update game paddle-key #(max (second TOP)  (+ % (- 6))))
    (rl/key-down? down-key) (update game paddle-key #(min (- (second BOTTOM) PADDLE_HEIGHT) (+ % 6)))
    :else game))

(defn move-paddle1 [game]
  (move-paddle game rl/KEY_W rl/KEY_S :paddle1))

(defn move-paddle2 [game]
  (move-paddle game rl/KEY_K rl/KEY_J :paddle2))

(defn move-ball [{:keys [ball paddle1 paddle2] :as game}]
  (let [[x y dx dy] ball
        top? (rl/check-collision-circle-rec [x y] BALL_RADIUS TOP)
        bottom? (rl/check-collision-circle-rec [x y] BALL_RADIUS BOTTOM)
        ;; left? (rl/check-collision-circle-rec [x y] BALL_RADIUS LEFT)
        ;; right? (rl/check-collision-circle-rec [x y] BALL_RADIUS RIGHT)
        paddle1? (and (rl/check-collision-circle-rec [x y] BALL_RADIUS [PADDLE1_X paddle1 PADDLE_WIDTH PADDLE_HEIGHT])
                      (< x (+ PADDLE1_X PADDLE_WIDTH)))
        paddle2? (and (rl/check-collision-circle-rec [x y] BALL_RADIUS [PADDLE2_X paddle2 PADDLE_WIDTH PADDLE_HEIGHT])
                      (> x (- PADDLE2_X PADDLE_WIDTH)))
        scored (if (and (not (or paddle1? paddle2?))
                        (not (or top? bottom?)))
                 (cond (< x 0) :right
                       (> x WIDTH) :left)
                 nil)
        [xx yy] (cond
                  (or paddle1? paddle2?) [(- dx) dy]
                  (or top? bottom?) [dx (- dy)]
                  :else [dx dy])]

    (assoc game :ball [(+ x xx) (+ y yy) xx yy]
           :scored scored)))



(defn handle-score [{:keys [scored] :as game}]
  (if (nil? scored)
    game
    (-> game
        (update scored inc)
        (assoc :ball [400 225 (rand-direction) (rand-direction)]))))

(defn handle-endgame [{:keys [left right] :as game}]
  (let [ended? (or (>= left MAX_POINTS) (>= right MAX_POINTS))]
    (if ended?
      (assoc game :screen :ending
             :winner (if (>= left MAX_POINTS) :left :right))
      game)))

(defn handle-start [game]
  (if (rl/key-pressed? rl/KEY_ENTER)
    (assoc game :screen :game)
    game))

(defn handle-restart [game]
  (if (rl/key-pressed? rl/KEY_ENTER)
    (initial-state)
    game))

(defn tick [{:keys [screen] :as game}]
  (condp = screen
    :title (-> game handle-start)
    :game (-> game
              move-ball
              move-paddle1
              move-paddle2
              handle-score
              handle-endgame)

    :ending (-> game handle-restart)))

(defn draw-title [_]
  (rl/begin-drawing)
  (rl/clear-background rl/BLACK)
  (let [text "press ENTER to start"
        size 20
        width (rl/measure-text text size)]
    (rl/draw-text text  (- (quot WIDTH 2) (/ width 2)) (/ HEIGHT 2) size rl/WHITE))
  (rl/end-drawing))

(defn draw-game [{:keys [avg-fps paddle1 paddle2 ball left right]}]
  (rl/begin-drawing)
  (rl/clear-background rl/BLACK)
  (rl/draw-rectangle PADDLE1_X paddle1 PADDLE_WIDTH PADDLE_HEIGHT rl/BLUE)
  (rl/draw-rectangle PADDLE2_X  paddle2 PADDLE_WIDTH PADDLE_HEIGHT   rl/RED)
  (apply rl/draw-rectangle (conj TOP rl/WHITE))
  (apply rl/draw-rectangle (conj BOTTOM rl/WHITE))
  (rl/draw-text (str " fps: " avg-fps) 720 20 20 rl/PURPLE)
  (rl/draw-text (str left) (-  (quot WIDTH 2) 100) 20 20 rl/WHITE)
  (rl/draw-text (str right) (+ (quot WIDTH 2) 100) 20 20 rl/WHITE)
  (rl/draw-circle (first ball) (second ball) BALL_RADIUS rl/WHITE)
  (rl/end-drawing))

(defn draw-ending [{:keys [left right winner]}]
  (rl/begin-drawing)
  (rl/clear-background rl/BLACK)
  (rl/draw-text (str left) (-  (quot WIDTH 2) 100) 20 20 rl/WHITE)
  (rl/draw-text (str right) (+ (quot WIDTH 2) 100) 20 20 rl/WHITE)
  (let [winner-name (string/upper-case (name winner))
        text (str "Congratulations " winner-name "!")
        winner-color (if (= winner :left) rl/BLUE rl/RED)
        size 20
        width (rl/measure-text text size)]
    (rl/draw-text text  (- (quot WIDTH 2) (/ width 2)) (/ HEIGHT 2) size winner-color))
  (let [text "press ENTER to restart"
        size 20
        width (rl/measure-text text size)]
    (rl/draw-text text  (- (quot WIDTH 2) (/ width 2)) (- HEIGHT 100) size rl/WHITE))
  (rl/end-drawing))

(defn draw [{:keys [screen] :as game}]
  (condp = screen
    :title (draw-title game)
    :game   (draw-game game)
    :ending (draw-ending game)))

(defn start []
  (init)
  (loop []
    (let [game (tick (update-fps @game-atom))]
      (when-not (rl/window-should-close?)
        (reset! game-atom game)
        (draw game)
        (recur))))

  (rl/close-window))

(comment

  (future (start))                                 ;; rcf

  ;;
  )
