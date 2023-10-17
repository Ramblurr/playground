(ns examples.asteroids
  (:require
   [clojure.string :as string]
   [raylib-clj.core :as rl]))

;; CREDITS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; All the math and helper functions for this asteroids impl are from
;; @cellularmitosis (Jason Pepas)
;; https://github.com/tantona/janetroids/blob/master/main.janet

(defmacro with-drawing
  [& body]
  `(do
     (try
       (rl/begin-drawing)
       ~@body
       (finally
         (rl/end-drawing)))))

;; CONSTS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(def WIDTH 800)
(def HEIGHT 800)
(def MAX_ASTEROID_SIZE 3)
(def BASE_ASTEROID_SPEED 1)
(def MAX_BULLET_AGE 120)
(def INITIAL_ASTEROIDS 3)
(def BULLET_RADIUS 2)

;; MATH ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defn vector-add [v1 v2]
  [(+ (v1 0) (v2 0))
   (+ (v1 1) (v2 1))])

(defn vector-sub [v1 v2]
  [(- (v1 0) (v2 0))
   (- (v1 1) (v2 1))])

(defn vector-mul [v1 v2]
  [(* (v1 0) (v2 0))
   (* (v1 1) (v2 1))])

(defn vector-wrap [v modulus]
  [(if (< (v 0) 0)
     (+ WIDTH (v 0))
     (mod (Math/abs (v 0)) modulus))
   (if (< (v 1) 0)
     (+ HEIGHT (v 1))
     (mod (Math/abs (v 1)) modulus))])

;; STATE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defn asteroid-speed [size]
  (let [base-speed BASE_ASTEROID_SPEED]
    (reduce (fn [speed _]
              (* 1.5 speed)) base-speed (range (- MAX_ASTEROID_SIZE size)))))

(defn random-asteroid-velocity
  "veolcity based on fixed speed in a random direction"
  [size]
  (let [speed (asteroid-speed size)
        angle (* (rand) Math/PI)]
    [(* speed (Math/cos angle))
     (* speed (Math/sin angle))]))

(defn make-asteroid-at
  [x y size]
  {:size size
   :position [x y]
   :velocity (random-asteroid-velocity size)})

(defn make-asteroid
  []
  (make-asteroid-at (* (* WIDTH 0.7) (- (rand) 0.5))
                    (* (* HEIGHT 0.7) (- (rand) 0.5))
                    MAX_ASTEROID_SIZE))

(defn make-bullet [pos velocity]
  {:position pos
   :velocity velocity
   :age 0})

(defn make-ship [width height]
  {:size 30
   :aspect 0.8
   :position [(/ width 2) (/ height 2)]
   :orientation 0.0
   :velocity [0.0 0.0]})

(defn initial-state []
  {:dt 0
   :time (System/nanoTime)
   :time-acc [1]
   :frame-counter -1
   :screen :title
   :ship (make-ship WIDTH HEIGHT)
   :asteroids (map (fn [_] (make-asteroid)) (range INITIAL_ASTEROIDS))
   :bullets []
   :alive true})

(defn asteroid-radius [asteroid]
  (* (asteroid :size) 10))

(defn find-ship-center [ship]
  (let [[ship-x ship-y] (:position ship)
        ship-size (:size ship)
        ship-aspect (:aspect ship)]
    [(+ ship-x (/ ship-size 3))
     (+ ship-y (* (/ ship-size 2) ship-aspect))]))

(defn rotate-ship-point [ship [x1 y1]]
  (let [[x0 y0] (find-ship-center ship)
        theta (:orientation ship)]
    [(- (* (- x1 x0) (Math/cos theta)) (* (- y1 y0) (Math/sin theta)))
     (+ (* (- y1 y0) (Math/cos theta)) (* (- x1 x0) (Math/sin theta)))]))

(defn ship-points [ship]
  (let [[ship-x ship-y] (ship :position)
        ship-size (ship :size)
        ship-aspect (ship :aspect)
        ship-center (find-ship-center ship)
        ship-length ship-size
        ship-width (* ship-size ship-aspect)
        p1 [ship-x ship-y]
        p2 [ship-x (+ ship-y ship-width)]
        p3 [(+ ship-x ship-length) (+ ship-y (/ ship-width 2))]
        rotated-points (map (fn [p] (rotate-ship-point ship p)) [p1 p2 p3])
        translated-rotated-points (mapv (fn [p] (vector-add ship-center p)) rotated-points)]
    translated-rotated-points))

(defn ship-thrust-vector [ship]
  (let [angle (:orientation ship)
        magnitude 0.05]
    [(* (Math/cos angle) magnitude)
     (* (Math/sin angle) magnitude)]))

(defn move-ship [game]
  (update game :ship (fn [{:keys [position velocity] :as  ship}]
                       (assoc ship :position
                              (vector-wrap (vector-add position velocity) WIDTH)))))

(defn move-bullets [game]
  (update game :bullets (fn [bullets]
                          (mapv (fn [bullet]
                                  (let [new-position (vector-add (bullet :position) (bullet :velocity))]
                                    (assoc bullet
                                           :position (vector-wrap new-position WIDTH)
                                           :age (inc (bullet :age)))))
                                bullets))))

(defn cull-bullets [game]
  (update game :bullets (fn [bullets]
                          (remove
                           (fn [bullet]
                             (>= (bullet :age) MAX_BULLET_AGE))
                           bullets))))

(defn move-asteroids [game]
  (update game :asteroids (fn [asteroids]
                            (mapv
                             #(assoc %
                                     :position (vector-wrap (vector-add (:position %) (:velocity %)) WIDTH))
                             asteroids))))

(defn spawn-asteroid [size [x y]]
  (make-asteroid-at x y size))

(defn ship-collides-asteroid? [sps {:keys [position size] :as asteroid}]
  (not (every? false?
               (map (fn [point]
                      (rl/check-collision-point-circle point position (asteroid-radius asteroid)))
                    sps))))

(defn collide-ship [game]
  (let [sps (ship-points (:ship game))]
    (if (not (every? false? (map (partial ship-collides-asteroid? sps) (:asteroids game))))
      (assoc game :alive false)
      game)))

(defn bullet-collides-asteroid? [bullet asteroid]
  (rl/check-collision-circles (:position bullet) BULLET_RADIUS (:position asteroid) (asteroid-radius asteroid)))

(defn calc-collisions [bullets asteroids]
  (let [collisions (for [bullet bullets
                         asteroid asteroids
                         :when (bullet-collides-asteroid? bullet asteroid)]
                     [bullet asteroid])]
    collisions))

(defn explode-asteroid [asteroid]
  (if (> (asteroid :size) 1)
    [(spawn-asteroid (- (asteroid :size) 1) (asteroid :position))
     (spawn-asteroid (- (asteroid :size) 1) (asteroid :position))]
    []))

(defn collide-bullets [game]
  (let [asteroids (:asteroids game)
        bullets (:bullets game)
        collisions (calc-collisions bullets asteroids)
        collided-asteroids (mapv second collisions)
        collided-bullets (mapv first collisions)
        asteroids-remaining  (mapcat (fn [asteroid]
                                    (if (some #(= asteroid %) collided-asteroids)
                                      (explode-asteroid asteroid)
                                      [asteroid])) asteroids)
        bullets-remaining (remove (fn [bullet] (some #(= bullet %) collided-bullets)) bullets)]
    (assoc game :bullets bullets-remaining
           :asteroids asteroids-remaining)))


(defn bullet-firing-vector [ship]
  (let [angle (:orientation ship)
        magnitude 5]
    [(* (Math/cos angle) magnitude)
     (* (Math/sin angle) magnitude)]))

(defn spawn-bullet [ship]
  (let [bullet-velocity (vector-add (ship :velocity) (bullet-firing-vector ship))]
    (make-bullet (find-ship-center ship)  bullet-velocity)))

(defn handle-input [game]
  (let [game (cond-> game
               (rl/key-down? rl/KEY_LEFT) (update :ship (fn [ship] (assoc ship :orientation (- (:orientation ship) 0.05))))
               (rl/key-down? rl/KEY_RIGHT) (update :ship (fn [ship] (assoc ship :orientation (+ (:orientation ship) 0.05))))
               (rl/key-down? rl/KEY_UP) (update :ship (fn [ship]
                                                        (assoc ship :velocity (vector-add (:velocity ship) (ship-thrust-vector ship)))))
               (rl/key-down? rl/KEY_DOWN) (update :ship (fn [ship]
                                                          (assoc ship :velocity (vector-sub (:velocity ship) (ship-thrust-vector ship))))))]
    (if (rl/key-pressed? rl/KEY_SPACE)
      (if (:alive game)
        (update game :bullets (fn [bullets]
                                (conj bullets (spawn-bullet (:ship game)))))
        (initial-state))
      game)))

(defn handle-game [game]
  (-> game
      handle-input
      move-ship
      move-bullets
      move-asteroids
      collide-ship
      cull-bullets
      collide-bullets))

(defn handle-start [game]
  (if (rl/key-pressed? rl/KEY_ENTER)
    (assoc game :screen :game)
    game))

(defn tick [{:keys [screen] :as game}]
  (try
    (condp = screen
      :title (handle-start game)
      :game (handle-game game)
      :ending game)
    (catch Exception e
      (println "Exception in tick: " e)
      (Thread/sleep 1000))))

(def game-atom (atom (initial-state)))

;; DRAW ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defn draw-asteroid [{:keys [position] :as asteroid}]
  (let [x (Math/floor (first position))
        y (Math/floor (second position))
        radius (asteroid-radius asteroid)]
    (rl/draw-circle
     x y radius rl/WHITE)))

(defn draw-asteroids [{:keys [asteroids]}]
  (doseq [asteroid asteroids]
    (draw-asteroid asteroid)))

(defn thrust-points [{:keys [ship]}]
  (let [[ship-center-x ship-center-y] (find-ship-center ship)
        p1 [(- ship-center-x 12) (+ ship-center-y 3)]
        p2 [(- ship-center-x 24) ship-center-y]
        p3 [(- ship-center-x 12) (- ship-center-y 3)]
        rotated-points (map (fn [p] (rotate-ship-point ship p)) [p1 p3 p2])
        translated-rotated-points (mapv #(vector-add [ship-center-x ship-center-y] %) rotated-points)]
    translated-rotated-points))

(defn retro-thrust-points1 [ship]
  (let [ship-center (find-ship-center ship)
        [ship-center-x ship-center-y] ship-center
        p1 [ship-center-x (- ship-center-y 7)]
        p2 [(+ ship-center-x 10) (- ship-center-y 9)]
        p3 [ship-center-x (- ship-center-y 11)]
        rotated-points (map (fn [p] (rotate-ship-point ship  p)) [p1 p2 p3])
        translated-rotated-points (mapv (fn [p] (vector-add ship-center p)) rotated-points)]
    translated-rotated-points))

(defn retro-thrust-points2 [ship]
  (let [ship-center (find-ship-center ship)
        [ship-center-x ship-center-y] ship-center
        p1 [ship-center-x (+ ship-center-y 7)]
        p2 [(+ ship-center-x 10) (+ ship-center-y 9)]
        p3 [ship-center-x (+ ship-center-y 11)]
        rotated-points (map (fn [p] (rotate-ship-point ship p)) [p1 p3 p2])
        translated-rotated-points (mapv (fn [p] (vector-add ship-center p)) rotated-points)]
    translated-rotated-points))

(defn draw-triangle [[v1 v2 v3] color]
  (rl/draw-triangle v1 v2 v3 color))

(defn draw-thrust [game]
  (draw-triangle (thrust-points game) rl/ORANGE))

(defn draw-retro-thrust [game]
  (draw-triangle (retro-thrust-points1 (:ship game)) rl/ORANGE)
  (draw-triangle (retro-thrust-points2 (:ship game)) rl/ORANGE))

(defn draw-ship [{:keys [frame-counter ship] :as game}]
  (let [is-alternate-frame (< (mod frame-counter 5) 3)]
    (when (and (rl/key-down? rl/KEY_UP) is-alternate-frame)
      (draw-thrust game))
    (when (and (rl/key-down? rl/KEY_DOWN) is-alternate-frame)
      (draw-retro-thrust game))
    (draw-triangle (ship-points ship) rl/WHITE)))

(defn draw-bullet [bullet]
  (let [[x y] (:position bullet)]
    (rl/draw-circle (Math/floor x) (Math/floor y) BULLET_RADIUS rl/WHITE)))

(defn draw-bullets [{:keys [bullets]}]
  (doseq [bullet bullets]
    (draw-bullet bullet)))

(defn draw-dead []
  (let [text "dead"
        size 48
        width (rl/measure-text text size)]
    (rl/draw-text text  (- (quot WIDTH 2) (/ width 2)) (- HEIGHT 100) size rl/RED))
  (let [text "press SPACE to restart"
        size 16
        width (rl/measure-text text size)]
    (rl/draw-text text  (- (quot WIDTH 2) (/ width 2)) (- HEIGHT 50) size rl/WHITE)))

(defn draw-game [game]
  (with-drawing
    (rl/clear-background rl/BLACK)
    (draw-asteroids game)
    (if (:alive game)
      (draw-ship game)
      (draw-dead))
    (draw-bullets game)))

(defn draw-ending [game]
  (let [text "You DIED. Press ENTER to restart"
        size 20
        width (rl/measure-text text size)]
    (rl/draw-text text  (- (quot WIDTH 2) (/ width 2)) (/ HEIGHT 2) size rl/WHITE)))
(defn draw-title [_]
  (with-drawing
    (rl/clear-background rl/BLACK)
    (let [text "press ENTER to start"
          size 20
          width (rl/measure-text text size)]
      (rl/draw-text text  (- (quot WIDTH 2) (/ width 2)) (/ HEIGHT 2) size rl/WHITE))))

(defn draw [{:keys [screen] :as game}]
  (try
    (condp = screen
      :title (draw-title game)
      :game   (draw-game game)
      :ending (draw-ending game))
    (catch Exception e
      (println "Exception in draw: " e)
      (Thread/sleep 1000))))

(defn update-fps [game]
  (let [last-time (:time game)
        acc (:time-acc game)
        newtime (System/nanoTime)
        diff (- newtime last-time)
        newacc (vec (take-last 100 (conj acc diff)))
        average-diff (/ (reduce + newacc) (count newacc))
        average-fps (long (/ 1000000000 average-diff))]
    (assoc game :dt (rl/get-frame-time)
           :time newtime
           :time-acc acc
           :avg-fps average-fps
           :frame-counter (inc (:frame-counter game)))))

(defn init []
  (rl/init-window WIDTH HEIGHT "Raylib Clojure Asteroids")
  (rl/set-target-fps 60))

(defn start []
  (init)
  (loop []
    (let [game (tick (update-fps @game-atom))]
      (when-not (rl/window-should-close?)
        (reset! game-atom game)
        (draw game)
        ;; (Thread/sleep 1000)
        (recur))))

  (rl/close-window))

(comment

  (future (start))                                 ;; rcf

  ;;
  )
