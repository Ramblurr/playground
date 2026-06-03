# Shared UI utility predicates and diagnostics.

(defn props?
  "Returns true when `x` is a table or struct suitable for props/options."
  [x]
  (or (table? x) (struct? x)))

(defn type-name
  "Returns Janet's type keyword rendered as a string for diagnostics."
  [x]
  (string (type x)))
