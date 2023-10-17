(ns user
  (:require [portal.api :as inspect]))

(defn dev
  "Load and switch to the 'dev' namespace."
  []
  (require 'dev)
  (in-ns 'dev)
  :loaded)

(add-tap portal.api/submit)

(comment

(inspect/open {:theme :portal.colors/gruvbox})
  ;; Clear all values in the portal inspector window
  (inspect/clear)

  ;; Close the inspector
  (inspect/close)) ;; End of rich comment block

(comment
  (dev)

  (remove-tap inspect/submit)
  ;;
  )
