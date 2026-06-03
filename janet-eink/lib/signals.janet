# Signals are explicit: callers read with `get`, write source cells with `set`,
# derive values with `computed`, and tie redraw/effect work to signals with
# `effect`/`dispose`.

(def- core-get get)
(def- core-put put)

(defn signal?
  "Returns true when `x` is a signal value managed by this module."
  [x]
  (and (table? x) (core-get x :signal?)))

(defn- new-signal
  [kind]
  @{:signal? true
    :kind kind
    :subs @[]
    :disposed? false})

(defn- ensure-live!
  [signal]
  (when (core-get signal :disposed?)
    (error "cannot use disposed signal"))
  signal)

(defn- array-contains?
  [xs x]
  (var found? false)
  (each item xs
    (when (= item x)
      (set found? true)))
  found?)

(defn- array-push-unique!
  [xs x]
  (unless (array-contains? xs x)
    (array/push xs x))
  xs)

(defn- record-dependency!
  [signal]
  (when-let [deps (dyn :ui/deps)]
    (array-push-unique! deps signal))
  nil)

(defn- subscribe!
  [signal callback]
  (ensure-live! signal)
  (def token @{:signal signal
               :callback callback
               :active? true})
  (array/push (core-get signal :subs) token)
  token)

(defn- unsubscribe!
  [token]
  (core-put token :active? false)
  nil)

(defn- notify!
  [signal]
  # Iterate over a snapshot so callbacks may subscribe/unsubscribe safely.
  (def subscribers (array/slice (core-get signal :subs)))
  (each token subscribers
    (when (core-get token :active?)
      ((core-get token :callback) signal)))
  nil)

(defn- mark-dirty!
  [signal]
  (unless (core-get signal :disposed?)
    (unless (core-get signal :dirty?)
      (core-put signal :dirty? true)
      (notify! signal)))
  nil)

(defn- clear-dep-tokens!
  [signal]
  (each token (core-get signal :dep-tokens @[])
    (unsubscribe! token))
  (core-put signal :dep-tokens @[])
  nil)

(defn- connect-deps!
  [signal deps]
  (def tokens @[])
  (each dep deps
    (when (signal? dep)
      (array/push tokens
                  (subscribe! dep (fn [_] (mark-dirty! signal))))))
  (core-put signal :dep-tokens tokens)
  nil)

(defn- recompute!
  [signal]
  (ensure-live! signal)
  (def deps @[])
  (def value
    (with-dyns [:ui/deps deps]
      ((core-get signal :thunk))))
  (clear-dep-tokens! signal)
  (connect-deps! signal deps)
  (core-put signal :value value)
  (core-put signal :dirty? false)
  value)

(defn- read-signal
  [signal]
  (unless (signal? signal)
    (error "expected signal"))
  (ensure-live! signal)
  (record-dependency! signal)
  (case (core-get signal :kind)
    :cell
    (core-get signal :value)

    :computed
    (if (core-get signal :dirty?)
      (recompute! signal)
      (core-get signal :value))

    :lens
    (if (core-get signal :dirty?)
      (recompute! signal)
      (core-get signal :value))

    (error "expected readable signal")))

(defn- path-get
  [root path]
  (var current root)
  (each key path
    (set current (core-get current key)))
  current)

(defn- path-set!
  [root path value]
  (def n (length path))
  (if (zero? n)
    value
    (do
      (var current root)
      (loop [i :range [0 (- n 1)]]
        (def key (core-get path i))
        (set current (core-get current key))
        (when (nil? current)
          (error (string "cannot set missing lens path at " key))))
      (core-put current (core-get path (- n 1)) value)
      root)))

(defn- write-cell!
  [signal value]
  (core-put signal :value value)
  (notify! signal)
  value)

(defn- write-lens!
  [signal value]
  (def parent (core-get signal :parent))
  (def path (core-get signal :path))
  (if (zero? (length path))
    (do
      (write-cell! parent value)
      value)
    (do
      (def root (read-signal parent))
      (path-set! root path value)
      # Writing the parent notifies this lens through its normal dependency
      # subscription when the lens has been read before.
      (write-cell! parent root)
      value)))

(defn- write-signal
  [signal value]
  (unless (signal? signal)
    (error "expected signal"))
  (ensure-live! signal)
  (case (core-get signal :kind)
    :cell (write-cell! signal value)
    :lens (write-lens! signal value)
    (error "computed signals are read-only")))

(defn cell
  "Creates a writable source signal initialized to `value`."
  [value]
  (def signal (new-signal :cell))
  (core-put signal :value value)
  signal)

(defn computed
  "Creates a lazy derived signal. Dependencies are tracked during `get`."
  [thunk]
  (def signal (new-signal :computed))
  (core-put signal :thunk thunk)
  (core-put signal :dirty? true)
  (core-put signal :dep-tokens @[])
  signal)

(defn lens
  "Creates a writable cursor into `signal` at `path`. Mutates nested state and
  notifies through the parent signal. Intended for mutable table/array app state."
  [signal path]
  (def lens-signal (new-signal :lens))
  (core-put lens-signal :parent signal)
  (core-put lens-signal :path path)
  (core-put lens-signal :dirty? true)
  (core-put lens-signal :dep-tokens @[])
  (core-put lens-signal :thunk
            (fn []
              (path-get (read-signal signal) path)))
  lens-signal)

(defn effect
  "Runs `thunk` immediately, then again whenever one of `signals` changes.
  Returns an effect handle that can be passed to `dispose`."
  [signals thunk]
  (def handle @{:kind :effect
                :tokens @[]
                :disposed? false
                :thunk thunk})
  (defn run-effect [_]
    (unless (core-get handle :disposed?)
      (thunk)))
  (each signal signals
    (when (signal? signal)
      (array/push (core-get handle :tokens)
                  (subscribe! signal run-effect))))
  (thunk)
  handle)

(defn get
  "Reads a signal value and records it in the dynamic `:ui/deps` collector when present."
  [signal]
  (read-signal signal))

(defn set
  "Writes a cell or lens signal and returns the new value."
  [signal value]
  (write-signal signal value))

(defn swap
  "Updates a cell or lens by applying `f` to the current value and extra `args`."
  [signal f & args]
  (write-signal signal (f (read-signal signal) ;args)))

(defn dispose
  "Stops an effect. Also detaches computed/lens dependencies when passed a signal."
  [thing]
  (when (table? thing)
    (case (core-get thing :kind)
      :effect
      (do
        (core-put thing :disposed? true)
        (each token (core-get thing :tokens @[])
          (unsubscribe! token))
        (core-put thing :tokens @[]))

      :computed
      (do
        (core-put thing :disposed? true)
        (clear-dep-tokens! thing))

      :lens
      (do
        (core-put thing :disposed? true)
        (clear-dep-tokens! thing))

      :cell
      (core-put thing :disposed? true)))
  nil)
