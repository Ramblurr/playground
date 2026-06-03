(import ./device :as device)
(import ./input/raw :as raw)
(import ./input/normalize :as normalize)

(defn- dict?
  [value]
  (or (= :table (type value)) (= :struct (type value))))

(defn- error-result?
  [value]
  (and (dict? value) (has-key? value :error)))

(defn open
  [dev path &opt options]
  (device/input-open dev path (or options {})))

(defn open-default
  [dev &opt options]
  (device/input-open-default dev (or options {})))

(defn poll
  [dev timeout-ms &opt max-events]
  (device/input-poll dev timeout-ms max-events))

(defn close
  [dev handle]
  (device/input-close dev handle))

(defn close-all
  [dev]
  (device/input-close-all dev))

(defn- opened-handles
  [result]
  (cond
    (and (dict? result) (has-key? result :handles)) (get result :handles)
    (error-result? result) @[]
    :else @[result]))

(defn- print-open-error
  [result]
  (eprint (string "input open failed: "
                  (get result :operation "open")
                  ": "
                  (get result :message (get result :error "unknown error")))))

(defn- print-poll-error
  [result]
  (eprint (string "input poll failed: "
                  (get result :operation "poll")
                  ": "
                  (get result :message (get result :error "unknown error")))))

(defn normalize-batch
  [state records]
  (let [events @[]]
    (each record records
      (cond
        (raw/raw-record? record)
        (when-let [event (normalize/record state record)]
          (array/push events event))

        (and (dict? record) (has-key? record :event))
        (array/push events record)))
    events))

(defn terminal-event?
  [event]
  (and (dict? event) (= :window-close-request (get event :event nil))))

(defn- print-event
  [event]
  (pp event))

(defn dump
  [dev &opt opts]
  (let [options (or opts {})
        open-options {:grab? (get options :grab? false)}
        open-result (if-let [path (get options :path nil)]
                      (open dev path open-options)
                      (open-default dev open-options))]
    (if (error-result? open-result)
      (do
        (print-open-error open-result)
        1)
      (let [handles (opened-handles open-result)]
        (if (= 0 (length handles))
          (do
            (eprint "input open produced no handles")
            (close-all dev)
            1)
          (let [state (normalize/new-state)
                limit (get options :limit 200)
                timeout-ms (get options :timeout-ms 1000)
                idle-limit (get options :idle-limit 10)
                normalized? (get options :normalized? false)]
            (var printed 0)
            (var idle-count 0)
            (var status 0)
            (var running true)
            (while (and running (< printed limit))
              (let [result (poll dev timeout-ms (max 1 (- limit printed)))]
                (cond
                  (error-result? result)
                  (do
                    (print-poll-error result)
                    (set status 1)
                    (set running false))

                  (get result :timeout? false)
                  (do
                    (++ idle-count)
                    (when (>= idle-count idle-limit)
                      (set running false)))

                  :else
                  (do
                    (set idle-count 0)
                    (let [records (get result :events @[])]
                      (if normalized?
                        (each event (normalize-batch state records)
                          (when (< printed limit)
                            (print-event event)
                            (++ printed)
                            (when (terminal-event? event)
                              (set running false))))
                        (each record records
                          (when (< printed limit)
                            (if (raw/raw-record? record)
                              (print (raw/format-record record))
                              (do
                                (print-event record)
                                (when (terminal-event? record)
                                  (set running false))))
                            (++ printed)))))))))
            (close-all dev)
            status))))))
