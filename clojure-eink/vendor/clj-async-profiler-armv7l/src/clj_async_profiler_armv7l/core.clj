(ns clj-async-profiler-armv7l.core
  (:require
   [clj-async-profiler.core :as profiler]
   [clojure.java.io :as io])
  (:import
   (java.io ByteArrayOutputStream File)
   (java.security MessageDigest)))

(def ^:private resource-path
  "clj_async_profiler_armv7l/libasyncProfiler.so")

(def ^:private cache-dir-name
  "clj-async-profiler-armv7l")

(defn- resource-bytes []
  (if-let [resource (io/resource resource-path)]
    (with-open [in  (io/input-stream resource)
                out (ByteArrayOutputStream.)]
      (io/copy in out)
      (.toByteArray out))
    (throw (ex-info (str "Could not find " resource-path " in resources.")
                    {:resource resource-path}))))

(defn- sha-256 [^bytes bytes]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256") bytes)]
    (apply str (map #(format "%02x" (bit-and 0xff (int %))) digest))))

(defn- cache-root []
  (io/file (or (not-empty (System/getenv "XDG_CACHE_HOME"))
               (when-let [home (not-empty (System/getProperty "user.home"))]
                 (str home File/separator ".cache"))
               (System/getProperty "java.io.tmpdir"))
           cache-dir-name))

(defn- set-permissions! [^File file]
  (.setReadable file true false)
  (.setExecutable file true false)
  (.setWritable file true true)
  file)

(defn- extract-agent! []
  (let [^bytes bytes (resource-bytes)
        file         (io/file (cache-root) (sha-256 bytes) "libasyncProfiler.so")]
    (when-not (and (.exists file)
                   (= (long (alength bytes)) (.length file)))
      (io/make-parents file)
      (with-open [out (io/output-stream file)]
        (.write out bytes)))
    (set-permissions! file)
    (.getAbsolutePath file)))

(defn install! []
  (let [path (extract-agent!)]
    (reset! profiler/async-profiler-agent-path path)
    path))

(def agent-path (install!))
