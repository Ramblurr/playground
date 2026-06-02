# Bundle script for the modern Janet bundle.

(defn- ensure-directory
  [path]
  (unless (= :directory (os/stat path :mode))
    (os/mkdir path)))


(defn install
  [manifest]
  (bundle/add-directory manifest "otter")
  (bundle/add-directory manifest "otter/lib")
  (bundle/add-directory manifest "otter/lib/platform")
  (bundle/add-directory manifest "otter/lib/demo")
  (bundle/add manifest "init.janet" "otter/init.janet")
  (bundle/add manifest "lib/launcher.janet" "otter/lib/launcher.janet")
  (bundle/add manifest "lib/platform.janet" "otter/lib/platform.janet")
  (bundle/add manifest "lib/platform/desktop.janet" "otter/lib/platform/desktop.janet")
  (bundle/add manifest "lib/platform/kobo.janet" "otter/lib/platform/kobo.janet")
  (bundle/add manifest "lib/skia.janet" "otter/lib/skia.janet")
  (bundle/add manifest "lib/demo/shapes.janet" "otter/lib/demo/shapes.janet")
  (bundle/add manifest "lib/signals.janet" "otter/lib/signals.janet")
  (ensure-directory (string (dyn :syspath) "/share"))
  (bundle/add-directory manifest "share/janet-eink")
  (bundle/add manifest "res/scripts/demo-skia.janet" "share/janet-eink/demo-skia.janet")
  (bundle/add-bin manifest "bin/otter"))
