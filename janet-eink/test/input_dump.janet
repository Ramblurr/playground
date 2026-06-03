(use ../deps/testament)
(import ../lib/input :as input)

(deftest input-dump-recognizes-terminal-window-close-events
  (let [observed @{:window-close (input/terminal-event? @{:event :window-close-request :source :sdl})
                   :window-resize (input/terminal-event? @{:event :window-resize :source :sdl})
                   :raw-key (input/terminal-event? @{:type 1 :code 97 :value 1})
                   :nil-value (input/terminal-event? nil)}]
    (is (deep= @{:window-close true
                 :window-resize false
                 :raw-key false
                 :nil-value false}
               observed)
        "input dump stops on SDL window close requests but not ordinary input records")))

(run-tests!)
