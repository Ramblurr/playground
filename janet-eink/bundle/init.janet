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
  (bundle/add-directory manifest "otter/lib/ui")
  (bundle/add-directory manifest "otter/lib/demo")
  (bundle/add manifest "init.janet" "otter/init.janet")
  (bundle/add manifest "lib/launcher.janet" "otter/lib/launcher.janet")
  (bundle/add manifest "lib/platform.janet" "otter/lib/platform.janet")
  (bundle/add manifest "lib/platform/desktop.janet" "otter/lib/platform/desktop.janet")
  (bundle/add manifest "lib/platform/kobo.janet" "otter/lib/platform/kobo.janet")
  (bundle/add manifest "lib/paint.janet" "otter/lib/paint.janet")
  (bundle/add manifest "lib/skia.janet" "otter/lib/skia.janet")
  (bundle/add manifest "lib/ui.janet" "otter/lib/ui.janet")
  (bundle/add manifest "lib/ui/core.janet" "otter/lib/ui/core.janet")
  (bundle/add manifest "lib/ui/element.janet" "otter/lib/ui/element.janet")
  (bundle/add manifest "lib/ui/align.janet" "otter/lib/ui/align.janet")
  (bundle/add manifest "lib/ui/gap.janet" "otter/lib/ui/gap.janet")
  (bundle/add manifest "lib/ui/grow.janet" "otter/lib/ui/grow.janet")
  (bundle/add manifest "lib/ui/label.janet" "otter/lib/ui/label.janet")
  (bundle/add manifest "lib/ui/padding.janet" "otter/lib/ui/padding.janet")
  (bundle/add manifest "lib/ui/rect.janet" "otter/lib/ui/rect.janet")
  (bundle/add manifest "lib/ui/row-column.janet" "otter/lib/ui/row-column.janet")
  (bundle/add manifest "lib/ui/stack.janet" "otter/lib/ui/stack.janet")
  (bundle/add manifest "lib/ui/nodes.janet" "otter/lib/ui/nodes.janet")
  (bundle/add manifest "lib/ui/reconcile.janet" "otter/lib/ui/reconcile.janet")
  (bundle/add manifest "lib/ui/util.janet" "otter/lib/ui/util.janet")
  (bundle/add manifest "lib/demo/shapes.janet" "otter/lib/demo/shapes.janet")
  (bundle/add manifest "lib/demo/ui-hello-world.janet" "otter/lib/demo/ui-hello-world.janet")
  (bundle/add manifest "lib/signals.janet" "otter/lib/signals.janet")
  (ensure-directory (string (dyn :syspath) "/share"))
  (bundle/add-directory manifest "share/janet-eink")
  (bundle/add manifest "res/scripts/demo-skia.janet" "share/janet-eink/demo-skia.janet")
  (bundle/add-bin manifest "bin/otter"))
