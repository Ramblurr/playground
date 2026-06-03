(use ../deps/testament)

(defn require-module
  [path]
  (def result (protect (require path :fresh true)))
  (if (get result 0)
    (get result 1)
    (do
      (is false (string "expected module " path " to load: " (get result 1)))
      nil)))

(defn module-value
  [module name]
  (def binding (get module name))
  (if binding
    (get binding :value)
    (do
      (is false (string "expected module to export " name))
      nil)))

(defn provider-summary
  [provider]
  @{:name (get provider :name)
    :native-fn? (= :function (type (get provider :native-fn)))
    :screen-size? (= :function (type (get provider :screen-size)))
    :present? (= :function (type (get provider :present)))
    :run-static? (= :function (type (get provider :run-static)))})

(defn with-pixel-format-env
  [value thunk]
  (let [original (os/getenv "OTTER_PIXEL_FORMAT" "")
        _ (os/setenv "OTTER_PIXEL_FORMAT" value)
        result (protect (thunk))]
    (os/setenv "OTTER_PIXEL_FORMAT" original)
    (if (get result 0)
      (get result 1)
      (error (get result 1)))))

(deftest desktop-provider-returns-provider-table
  (def desktop (require-module "../lib/platform/desktop"))
  (when desktop
    (def provider-fn (module-value desktop 'provider))
    (when provider-fn
      (def observed (provider-summary (provider-fn)))
      (is (deep= @{:name :desktop-sdl
                   :native-fn? true
                   :screen-size? true
                   :present? true
                   :run-static? true}
                 observed)
          "desktop provider exposes native loading, screen size, presentation, and run-static"))))

(deftest desktop-provider-defaults-to-rgba32-and-honors-pixel-format-env
  (let [desktop (require-module "../lib/platform/desktop")]
    (when desktop
      (let [screen-size (module-value desktop 'screen-size)]
        (when screen-size
          (let [observed @{:default (with-pixel-format-env ""
                                      (fn [] (get (screen-size) :pixel-format)))
                           :rgba32 (with-pixel-format-env "rgba32"
                                     (fn [] (get (screen-size) :pixel-format)))
                           :gray8 (with-pixel-format-env "gray8"
                                    (fn [] (get (screen-size) :pixel-format)))
                           :colon-gray8 (with-pixel-format-env ":gray8"
                                          (fn [] (get (screen-size) :pixel-format)))
                           :invalid-rejected? (not (get (protect (with-pixel-format-env "rgb565"
                                                                   (fn [] (screen-size))))
                                                        0))}]
            (is (deep= @{:default :rgba32
                         :rgba32 :rgba32
                         :gray8 :gray8
                         :colon-gray8 :gray8
                         :invalid-rejected? true}
                       observed)
                "desktop provider defaults to :rgba32 and supports OTTER_PIXEL_FORMAT overrides")))))))

(deftest kobo-provider-returns-provider-table
  (def kobo (require-module "../lib/platform/kobo"))
  (when kobo
    (def provider-fn (module-value kobo 'provider))
    (when provider-fn
      (def observed (provider-summary (provider-fn)))
      (is (deep= @{:name :kobo-fbink
                   :native-fn? true
                   :screen-size? true
                   :present? true
                   :run-static? true}
                 observed)
          "Kobo provider exposes native loading, screen size, presentation, and run-static"))))

(run-tests!)
