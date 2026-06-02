# Bundle script for the modern Janet bundle.

(defn install
  [manifest]
  (bundle/add-directory manifest "otter")
  (bundle/add-directory manifest "otter/lib")
  (bundle/add manifest "init.janet" "otter/init.janet")
  (bundle/add manifest "lib/desktop.janet" "otter/lib/desktop.janet")
  (bundle/add manifest "lib/kobo.janet" "otter/lib/kobo.janet")
  (bundle/add manifest "lib/launcher.janet" "otter/lib/launcher.janet")
  (bundle/add manifest "lib/platform.janet" "otter/lib/platform.janet")
  (bundle/add-bin manifest "bin/otter"))
