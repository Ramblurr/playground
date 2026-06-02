# Bundle script for the modern Janet bundle.

(defn- ensure-directory
  [path]
  (unless (= :directory (os/stat path :mode))
    (os/mkdir path)))


(defn install
  [manifest]
  (bundle/add-directory manifest "otter")
  (bundle/add-directory manifest "otter/lib")
  (bundle/add manifest "init.janet" "otter/init.janet")
  (bundle/add manifest "lib/desktop.janet" "otter/lib/desktop.janet")
  (bundle/add manifest "lib/kobo.janet" "otter/lib/kobo.janet")
  (bundle/add manifest "lib/launcher.janet" "otter/lib/launcher.janet")
  (bundle/add manifest "lib/platform.janet" "otter/lib/platform.janet")
  (bundle/add manifest "lib/signals.janet" "otter/lib/signals.janet")
  (ensure-directory (string (dyn :syspath) "/share"))
  (bundle/add-directory manifest "share/janet-eink")
  (bundle/add manifest "res/scripts/demo-skia.janet" "share/janet-eink/demo-skia.janet")
  (bundle/add-bin manifest "bin/otter"))
