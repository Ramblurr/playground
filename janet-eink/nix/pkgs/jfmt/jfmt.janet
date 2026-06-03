#!/usr/bin/env janet

(def- packaged-syspath "@jfmtSyspath@")
(when (not= packaged-syspath (string "@" "jfmtSyspath" "@"))
  (put root-env :syspath packaged-syspath))

(import spork/fmt)

(defn main
  [& args]
  (var quiet false)
  (var check false)
  (var parsing-options true)
  (def files @[])

  (each arg (tuple/slice args 1)
    (cond
      (and parsing-options (= "--" arg))
      (set parsing-options false)

      (and parsing-options (or (= "-q" arg) (= "--quiet" arg)))
      (set quiet true)

      (and parsing-options (= "--check" arg))
      (set check true)

      true
      (array/push files arg)))

  (if (= 0 (length files))
    (unless check
      (prin (fmt/format (file/read stdin :all))))
    (each f files
      (def source (string (slurp f)))
      (def formatted (string (fmt/format source)))
      (when (not= source formatted)
        (unless check
          (spit f formatted))
        (unless quiet
          (print f))))))
