# Shared prototype-based UI node hierarchy.
#
# Concrete widgets extend these prototypes and keep their rendering/layout logic in
# their own modules. This file owns only common node identity, defaults, component
# boundary nodes, and parent/child bookkeeping.

(defn props?
  "Returns true when `x` can be used as a node props/fields map."
  [x]
  (or (table? x) (struct? x)))

(defn node?
  "Returns true when `x` is a UI node table."
  [x]
  (and (table? x) (= true (get x :ui/node?))))

(defn- type-name
  [x]
  (string (type x)))

(defn- own-get
  "Looks up `key` without following a table prototype chain."
  [dict key default]
  (var value default)
  (when (props? dict)
    (eachp [k v] dict
      (when (= k key)
        (set value v))))
  value)

(defn normalize-props
  "Normalizes optional constructor props to a table/struct.

  `nil` becomes an empty mutable table. Other values must already be tables or
  structs so constructor errors happen early and name the offending node."
  [props &opt who]
  (cond
    (nil? props)
    @{}

    (props? props)
    props

    :else
    (error (string (or who "node") ": expected props table or struct, got " (type-name props)))))

(defn ensure-node!
  "Raises a clear error unless `x` is a UI node; returns `x` otherwise."
  [x &opt who]
  (unless (node? x)
    (error (string (or who "node") ": expected UI node, got " (type-name x))))
  x)

(defn number-value?
  "Returns true for Janet numbers."
  [x]
  (= :number (type x)))

(defn clamp-nonnegative
  "Clamps negative layout dimensions to zero."
  [n]
  (if (< n 0) 0 n))

(defn make-size
  "Builds a size/constraint struct with non-negative `:w` and `:h`."
  [w h]
  {:w (clamp-nonnegative w)
   :h (clamp-nonnegative h)})

(defn zero-size
  "The default no-op measurement result."
  []
  (make-size 0 0))

(defn size?
  "Returns true when `x` looks like a UI size/constraint map."
  [x]
  (and (props? x)
       (number-value? (get x :w))
       (number-value? (get x :h))))

(defn bounds?
  "Returns true when `x` looks like a UI draw-bounds map."
  [x]
  (and (size? x)
       (number-value? (get x :x))
       (number-value? (get x :y))))

(defn make-bounds
  "Builds an exact draw-bounds struct."
  [x y w h]
  {:x x
   :y y
   :w (clamp-nonnegative w)
   :h (clamp-nonnegative h)})

(defn mark-dirty!
  "Marks `node` dirty without touching ancestors."
  [node]
  (when (node? node)
    (put node :dirty? true))
  node)

(defn clear-dirty!
  "Marks `node` clean."
  [node]
  (when (node? node)
    (put node :dirty? false))
  node)

(defn invalidate-size!
  "Clears a node's size cache, marks it dirty, and bubbles to ancestors."
  [node]
  (when (node? node)
    (put node :size-cache nil)
    (put node :dirty? true)
    (when-let [parent (get node :parent)]
      (invalidate-size! parent)))
  node)

(defn cache-size!
  "Stores a simple constraint/size cache on `node` and returns `size`."
  [node cs size]
  (when (node? node)
    (put node :size-cache @{:cs cs :size size}))
  size)

(defn cached-size
  "Returns a cached size for matching constraints, or nil.

  This helper is intentionally conservative: mutable maps compare by value via
  `deep=`, so callers may use structs or tables for constraints."
  [node cs]
  (when (node? node)
    (when-let [cache (get node :size-cache)]
      (when (deep= cs (get cache :cs))
        (get cache :size)))))

(defn store-bounds!
  "Records the exact draw allocation on `node` and marks it clean."
  [node bounds]
  (ensure-node! node "store-bounds!")
  (put node :bounds bounds)
  (put node :dirty? false)
  node)

(defn measure
  "Measures `node` under maximum-size constraints `cs`.

  Nil/false nodes measure to zero so reconciliation can omit children cheaply."
  [node ctx cs]
  (if node
    (do
      (ensure-node! node "measure")
      (let [method (get node :measure)]
        (unless (function? method)
          (error (string "measure: node " (get node :kind :unknown) " has no :measure method")))
        (or (method node ctx cs) (zero-size))))
    (zero-size)))

(defn draw
  "Draws `node` into exact `bounds` using `ctx`.

  Nil/false nodes draw nothing. Node methods are responsible for mutating only
  `(:canvas ctx)` and storing their draw bounds."
  [node ctx bounds]
  (when node
    (ensure-node! node "draw")
    (let [method (get node :draw)]
      (unless (function? method)
        (error (string "draw: node " (get node :kind :unknown) " has no :draw method")))
      (method node ctx bounds))))

(defn unmount
  "Runs an idempotent cleanup hook for `node` and its descendants."
  [node]
  (when node
    (ensure-node! node "unmount")
    (let [method (get node :unmount)]
      (unless (function? method)
        (error (string "unmount: node " (get node :kind :unknown) " has no :unmount method")))
      (method node))))

(defn children
  "Returns a node's immediate child nodes as a mutable array.

  Wrapper/Fn nodes expose their `:child`; container nodes expose `:children`.
  Terminal nodes return their empty `:children` array."
  [node]
  (if node
    (do
      (ensure-node! node "children")
      (if-let [child (own-get node :child nil)]
        @[child]
        (or (own-get node :children nil) @[])))
    @[]))

(defn each-child
  "Calls `f` for each immediate child of `node`. Returns nil."
  [node f]
  (each child (children node)
    (f child))
  nil)

(defn- base-measure
  [_self _ctx _cs]
  (zero-size))

(defn- base-draw
  [self _ctx bounds]
  (store-bounds! self bounds))

(defn- base-unmount
  [self]
  (when (node? self)
    (put self :parent nil)
    (put self :bounds nil)
    (put self :size-cache nil)
    (put self :dirty? false))
  self)

(defn- wrapper-measure
  [self ctx cs]
  (if-let [child (get self :child)]
    (measure child ctx cs)
    (zero-size)))

(defn- wrapper-draw
  [self ctx bounds]
  (store-bounds! self bounds)
  (when-let [child (get self :child)]
    (draw child ctx bounds))
  self)

(defn- clear-parent-if!
  [child parent]
  (when (and (node? child) (= parent (get child :parent)))
    (put child :parent nil))
  child)

(defn- wrapper-unmount
  [self]
  (when-let [child (get self :child)]
    (unmount child)
    (clear-parent-if! child self))
  (put self :child nil)
  (base-unmount self))

(defn- container-unmount
  [self]
  (each child (get self :children @[])
    (when child
      (unmount child)
      (clear-parent-if! child self)))
  (put self :children @[])
  (base-unmount self))

(defn- fn-measure
  [self ctx cs]
  (wrapper-measure self ctx cs))

(defn- fn-draw
  [self ctx bounds]
  (wrapper-draw self ctx bounds))

(defn- fn-unmount
  [self]
  (wrapper-unmount self)
  (when-let [after-unmount (get self :after-unmount)]
    (when (function? after-unmount)
      (after-unmount self)))
  self)

(def Node
  @{:measure base-measure
    :draw base-draw
    :unmount base-unmount})

(def TerminalNode
  (table/setproto @{} Node))

(def WrapperNode
  (table/setproto @{:measure wrapper-measure
                    :draw wrapper-draw
                    :unmount wrapper-unmount}
                  Node))

(def ContainerNode
  (table/setproto @{:unmount container-unmount}
                  Node))

(def FnNode
  (table/setproto @{:measure fn-measure
                    :draw fn-draw
                    :unmount fn-unmount}
                  WrapperNode))

(defn extends?
  "Returns true when table `x` is `proto` or inherits from it."
  [x proto]
  (var current (if (table? x) x nil))
  (var found? false)
  (while (and current (not found?))
    (if (= current proto)
      (set found? true)
      (set current (table/getproto current))))
  found?)

(defn terminal-node?
  "Returns true for TerminalNode instances."
  [x]
  (and (node? x) (extends? x TerminalNode)))

(defn wrapper-node?
  "Returns true for WrapperNode instances, including FnNode instances."
  [x]
  (and (node? x) (extends? x WrapperNode)))

(defn container-node?
  "Returns true for ContainerNode instances."
  [x]
  (and (node? x) (extends? x ContainerNode)))

(defn fn-node?
  "Returns true for FnNode component-boundary instances."
  [x]
  (and (node? x) (extends? x FnNode)))

(defn kind
  "Returns a node's diagnostic kind keyword."
  [node]
  (when node
    (ensure-node! node "kind")
    (get node :kind)))

(defn- put-fields!
  [node fields]
  (when fields
    (unless (props? fields)
      (error (string "make-node: expected fields table or struct, got " (type-name fields))))
    (eachp [k v] fields
      (put node k v)))
  node)

(defn make-node
  "Creates a mutable node table with the shared retained-node fields.

  `proto` is usually one of the shared prototypes or a concrete prototype that
  extends them. `fields` may override defaults or add concrete-widget state."
  [proto kind &opt props fields]
  (unless (table? proto)
    (error (string "make-node: expected prototype table, got " (type-name proto))))
  (let [node @{:ui/node? true
               :kind kind
               :element nil
               :props (normalize-props props (string kind))
               :parent nil
               :child nil
               :children @[]
               :bounds nil
               :size-cache nil
               :dirty? true}]
    (put-fields! node fields)
    (table/setproto node proto)))

(defn set-parent!
  "Sets `child`'s parent pointer to `parent`. Nil/false children are ignored."
  [child parent]
  (when child
    (ensure-node! child "set-parent!")
    (when parent
      (ensure-node! parent "set-parent!"))
    (put child :parent parent))
  child)

(defn set-child!
  "Replaces a wrapper/Fn node's child and maintains parent pointers."
  [node child]
  (ensure-node! node "set-child!")
  (when-let [old-child (get node :child)]
    (clear-parent-if! old-child node))
  (let [next-child (if child child nil)]
    (when next-child
      (ensure-node! next-child "set-child!")
      (set-parent! next-child node))
    (put node :child next-child)
    (invalidate-size! node)
    next-child))

(defn clear-child!
  "Removes and returns a wrapper/Fn node's current child."
  [node]
  (ensure-node! node "clear-child!")
  (let [old-child (get node :child)]
    (when old-child
      (clear-parent-if! old-child node))
    (put node :child nil)
    (invalidate-size! node)
    old-child))

(defn set-children!
  "Replaces a container node's children, omitting nil/false entries."
  [node new-children]
  (ensure-node! node "set-children!")
  (each old-child (get node :children @[])
    (clear-parent-if! old-child node))
  (let [next-children @[]]
    (each child (or new-children @[])
      (when child
        (ensure-node! child "set-children!")
        (set-parent! child node)
        (array/push next-children child)))
    (put node :children next-children)
    (invalidate-size! node)
    next-children))

(defn clear-children!
  "Removes all container children and returns the old children array."
  [node]
  (ensure-node! node "clear-children!")
  (let [old-children (get node :children @[])]
    (each child old-children
      (clear-parent-if! child node))
    (put node :children @[])
    (invalidate-size! node)
    old-children))

(defn append-child!
  "Appends one child to a container node and sets its parent pointer."
  [node child]
  (ensure-node! node "append-child!")
  (when child
    (ensure-node! child "append-child!")
    (set-parent! child node)
    (array/push (get node :children) child)
    (invalidate-size! node))
  child)

(defn make-terminal
  "Creates a terminal node instance."
  [kind &opt props fields]
  (make-node TerminalNode kind props fields))

(defn make-wrapper
  "Creates a one-child wrapper node instance."
  [kind props child &opt fields]
  (let [node (make-node WrapperNode kind props fields)]
    (set-child! node child)
    node))

(defn make-container
  "Creates a multi-child container node instance."
  [kind props children &opt fields]
  (let [node (make-node ContainerNode kind props fields)]
    (set-children! node (or children @[]))
    node))

(defn make-fn-node
  "Creates a user component boundary node.

  Reconciliation owns calling `:render` and replacing `:child`; this node only
  preserves the boundary fields and delegates measure/draw to that child."
  [render args child &opt element]
  (let [node (make-node FnNode :fn @{} @{:render render
                                         :args (or args [])
                                         :element element})]
    (set-child! node child)
    node))
