# Bundle script for the modern Janet bundle.

(defn install
  [manifest]
  (bundle/add-directory manifest "otter")
  (bundle/add-directory manifest "otter/lib")
  (bundle/add manifest "init.janet" "otter/init.janet")
  (bundle/add manifest "lib/launcher.janet" "otter/lib/launcher.janet")
  (bundle/add-bin manifest "bin/otter"))
