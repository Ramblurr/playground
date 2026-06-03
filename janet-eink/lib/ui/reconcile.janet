# Retained UI reconciliation.
#
# It creates fresh nodes when needed, reuses compatible nodes by
# element-head identity, reconciles child lists, unmounts dropped nodes, and wraps
# user component boundaries in FnNode.

(import ./element :as elem)
(import ./nodes :as nodes)
(import ./label :as label)
(import ./util :as util)

(var make nil)
(var make-impl nil)
(var reconcile nil)
(var reconcile-many nil)

(def- builtin-heads @{})

(defn register-builtin!
  "Registers a constructor function as a built-in element head.

  Concrete built-in modules should also set `:constructor` on returned nodes.
  The registry lets reconciliation distinguish `[ui/label ...]` from a user
  component that happens to return a label node directly."
  [head kind]
  (unless (function? head)
    (error (string "register-builtin!: expected function head, got " (type head))))
  (put builtin-heads head kind)
  head)

(register-builtin! label/label :label)

(defn builtin-head?
  "Returns true when `head` is known to be a built-in element constructor."
  [head]
  (not (nil? (get builtin-heads head))))

(defn- omitted?
  [x]
  (elem/omitted? x))

(defn autoconvert
  "Converts convenient source values to canonical element values.

  - nil/false stay omitted
  - nodes pass through
  - strings become `[label/label string]`
  - tuple markup passes through
  "
  [element]
  (cond
    (omitted? element)
    nil

    (nodes/node? element)
    element

    (string? element)
    [label/label element]

    :else
    element))


(defn- element-args
  [element]
  (elem/values->array element 1))

(defn- parsed-element
  [element]
  (let [converted (autoconvert element)]
    (cond
      (omitted? converted)
      nil

      (nodes/node? converted)
      converted

      :else
      (elem/parse-element converted))))

(defn- element-key-from-parsed
  [parsed]
  (when (and parsed (not (nodes/node? parsed)))
    (let [props (get parsed 1)]
      (get props :key nil))))

(defn element-key
  "Returns an element key from props `:key`, or nil when unkeyed."
  [element]
  (let [converted (autoconvert element)]
    (cond
      (omitted? converted)
      nil

      (nodes/node? converted)
      (get converted :key nil)

      :else
      (element-key-from-parsed (elem/parse-element converted)))))

(defn- sync-key!
  [node element]
  (when (nodes/node? node)
    (let [k (element-key element)]
      (if (nil? k)
        (put node :key nil)
        (put node :key k))))
  node)

(defn- invoke-head
  [head args element]
  (unless (function? head)
    (error (string "element head must be callable, got " (util/type-name head)
                   " in " element)))
  (head ;args))

(defn- invoke-element
  [element]
  (let [converted (autoconvert element)
        parsed (elem/parse-element converted)
        head (get parsed 0)
        args (element-args converted)]
    @{:element converted
      :parsed parsed
      :head head
      :args args
      :result (invoke-head head args converted)}))

(defn- builtin-call-result?
  [head node]
  (and (nodes/node? node)
       (or (builtin-head? head)
           (= head (get node :constructor nil)))))

(defn- child-elements-default
  [node _ctx element]
  (let [parsed (elem/parse-element element)
        children (get parsed 2)]
    (cond
      (nodes/terminal-node? node)
      @[]

      (nodes/wrapper-node? node)
      children

      (nodes/container-node? node)
      children

      :else
      children)))

(defn child-elements
  "Returns raw child element values for `node` and `element`.

  Concrete nodes may provide `:child-elements` with signature
  `(fn [node ctx element] ...)`. Without a hook, terminal nodes have no children
  and wrapper/container nodes use parsed post-props children."
  [node ctx element]
  (nodes/ensure-node! node "child-elements")
  (if-let [f (get node :child-elements)]
    (or (f node ctx element) @[])
    (child-elements-default node ctx element)))

(defn- normalize-child-elements
  [children]
  (elem/normalize-children children autoconvert))

(defn- own-key?
  [table key]
  (var found? false)
  (when (table? table)
    (eachp [k _v] table
      (when (= k key)
        (set found? true))))
  found?)

(defn- retained-field?
  [fresh key]
  (var found? false)
  (each retained (get fresh :retain-fields @[])
    (when (= retained key)
      (set found? true)))
  found?)

(defn- copy-node-fields!
  [old-node fresh element]
  (let [parent (get old-node :parent nil)
        bounds (get old-node :bounds nil)
        child (get old-node :child nil)
        children (get old-node :children @[])]
    # Remove stale own fields while preserving retained topology/cache fields.
    (eachp [k _v] old-node
      (unless (or (= k :parent)
                  (= k :bounds)
                  (= k :child)
                  (= k :children)
                  (retained-field? fresh k))
        (unless (own-key? fresh k)
          (put old-node k nil))))
    (table/setproto old-node (table/getproto fresh))
    (eachp [k v] fresh
      (unless (or (= k :parent)
                  (= k :bounds)
                  (= k :child)
                  (= k :children)
                  (retained-field? fresh k))
        (put old-node k v)))
    (put old-node :parent parent)
    (put old-node :bounds bounds)
    (put old-node :child child)
    (put old-node :children children)
    (put old-node :element element)
    (put old-node :size-cache nil)
    (put old-node :dirty? true)
    (sync-key! old-node element)
    old-node))

(defn- clear-terminal-children!
  [node]
  (when-let [child (get node :child)]
    (nodes/unmount child)
    (nodes/clear-child! node))
  (each child (get node :children @[])
    (nodes/unmount child))
  (nodes/clear-children! node)
  node)

(defn- reconcile-wrapper-children!
  [node ctx raw-child-elements]
  (let [normalized (normalize-child-elements raw-child-elements)]
    (when (> (length normalized) 1)
      (error (string "wrapper node " (get node :kind :unknown)
                     ": expected zero or one child element, got " (length normalized))))
    (let [old-child (get node :child nil)
          child-element (get normalized 0 nil)
          new-child (reconcile old-child ctx child-element)]
      (nodes/set-child! node new-child)))
  node)

(defn- reconcile-container-children!
  [node ctx raw-child-elements]
  (let [old-children (get node :children @[])
        new-children (reconcile-many ctx old-children raw-child-elements)]
    (nodes/set-children! node new-children))
  node)

(defn- reconcile-node-children!
  [node ctx element]
  (let [raw-children (child-elements node ctx element)]
    (cond
      (nodes/terminal-node? node)
      (clear-terminal-children! node)

      (nodes/wrapper-node? node)
      (reconcile-wrapper-children! node ctx raw-children)

      (nodes/container-node? node)
      (reconcile-container-children! node ctx raw-children)

      :else
      node)))

(defn- component-descriptor?
  [x]
  (and (util/props? x) (function? (get x :render))))

(defn- component-render-result
  [head args initial-result]
  (cond
    (function? initial-result)
    @{:render initial-result
      :child-result (initial-result ;args)
      :descriptor nil}

    (component-descriptor? initial-result)
    (let [render (get initial-result :render)]
      @{:render render
        :child-result (render ;args)
        :descriptor initial-result})

    :else
    @{:render head
      :child-result initial-result
      :descriptor nil}))

(defn- apply-component-descriptor!
  [node descriptor]
  (each key [:measure :draw :should-setup? :should-render?
             :before-render :after-render :before-draw :after-draw
             :after-mount :after-unmount]
    (if (and descriptor (not (nil? (get descriptor key))))
      (put node key (get descriptor key))
      (put node key nil)))
  node)

(defn- make-component-boundary!
  [start-node ctx element head args initial-result]
  (let [render-info (component-render-result head args initial-result)
        render (get render-info :render)
        child-result (get render-info :child-result)
        descriptor (get render-info :descriptor)
        node (if (nodes/fn-node? start-node)
               start-node
               (nodes/make-fn-node render args nil element))]
    (put node :render render)
    (put node :args args)
    (put node :factory head)
    (put node :element element)
    (put node :dirty? true)
    (put node :size-cache nil)
    (sync-key! node element)
    (apply-component-descriptor! node descriptor)
    (let [new-child (reconcile (get node :child nil) ctx child-result)]
      (nodes/set-child! node new-child))
    node))

(defn- make-from-invocation
  [start-node ctx invocation]
  (let [element (get invocation :element)
        head (get invocation :head)
        args (get invocation :args)
        result (get invocation :result)]
    (cond
      (and (nodes/node? result) (builtin-call-result? head result))
      (do
        (put result :element element)
        (put result :dirty? true)
        (put result :size-cache nil)
        (sync-key! result element)
        (reconcile-node-children! result ctx element)
        result)

      (nodes/node? result)
      (make-component-boundary! start-node ctx element head args result)

      (or (omitted? result) (tuple? result) (string? result) (function? result) (component-descriptor? result))
      (make-component-boundary! start-node ctx element head args result)

      :else
      (error (string "unexpected return from element head " head ": " result)))))

(defn- construct-built-in-fresh
  [element]
  (let [invocation (invoke-element element)
        head (get invocation :head)
        result (get invocation :result)]
    (unless (and (nodes/node? result) (builtin-call-result? head result))
      (error (string "expected built-in constructor to return a UI node for " element
                     ", got " (util/type-name result))))
    result))

(defn- reconcile-built-in-node!
  [node ctx element]
  (let [fresh (construct-built-in-fresh element)]
    (copy-node-fields! node fresh element)
    (reconcile-node-children! node ctx element)
    node))

(defn- fn-should-render?
  [node args]
  (if-let [pred (get node :should-render?)]
    (pred ;args)
    true))

(defn- reconcile-fn-node!
  [node ctx element]
  (let [converted (autoconvert element)
        parsed (elem/parse-element converted)
        head (get parsed 0)
        args (element-args converted)]
    (if (fn-should-render? node args)
      (let [result (invoke-head head args converted)]
        (make-component-boundary! node ctx converted head args result))
      (do
        (put node :factory head)
        (put node :args args)
        (put node :element converted)
        (put node :dirty? false)
        (sync-key! node converted)
        node))))

(defn should-reconcile?
  "Returns true when `old-node` can be retained for `new-element`."
  [ctx old-node new-element]
  (let [converted (autoconvert new-element)]
    (cond
      (or (nil? old-node) (omitted? converted))
      false

      (nodes/node? converted)
      (= old-node converted)

      (not (tuple? converted))
      false

      :else
      (let [old-element (get old-node :element nil)]
        (and (tuple? old-element)
             (= (get old-element 0) (get converted 0))
             (if-let [f (get old-node :should-reconcile?)]
               (f old-node ctx converted)
               true))))))

(set make-impl
  (fn [start-node element &opt ctx]
    (let [converted (autoconvert element)]
      (cond
        (omitted? converted)
        nil

        (nodes/node? converted)
        converted

        (not (tuple? converted))
        (error (string "make-impl: expected tuple element markup, node, string, nil, or false; got "
                       (util/type-name converted)))

        :else
        (make-from-invocation start-node ctx (invoke-element converted))))))

(set make
  (fn [element]
    (make-impl nil element nil)))

(set reconcile
  (fn [old-node ctx element]
    (let [converted (autoconvert element)]
      (cond
        (omitted? converted)
        (do
          (nodes/unmount old-node)
          nil)

        (nodes/node? converted)
        (do
          (when (and old-node (not (= old-node converted)))
            (nodes/unmount old-node))
          converted)

        (should-reconcile? ctx old-node converted)
        (if (nodes/fn-node? old-node)
          (reconcile-fn-node! old-node ctx converted)
          (reconcile-built-in-node! old-node ctx converted))

        :else
        (do
          (nodes/unmount old-node)
          (make-impl nil converted ctx))))))

(defn- next-index!
  [counts key]
  (let [idx (+ 1 (get counts key -1))]
    (put counts key idx)
    idx))

(defn- keyed-token!
  [counts key]
  [key (next-index! counts key)])

(defn- split-old-nodes
  [old-nodes]
  (let [unkeyed @[]
        keyed @{}
        counts @{}]
    (each node (or old-nodes @[])
      (when node
        (let [key (get node :key nil)]
          (if (nil? key)
            (array/push unkeyed node)
            (put keyed (keyed-token! counts key) node)))))
    @{:unkeyed unkeyed :keyed keyed}))

(defn- unmount-keyed-leftovers!
  [keyed]
  (eachp [_token node] keyed
    (when node
      (nodes/unmount node)))
  nil)

(defn- push-node!
  [out node]
  (when node
    (array/push out node))
  node)

(set reconcile-many
  (fn [ctx old-nodes elements]
    (let [new-elements (normalize-child-elements elements)
          split (split-old-nodes old-nodes)
          old-unkeyed (get split :unkeyed)
          old-keyed (get split :keyed)
          new-key-counts @{}
          out @[]]
      (var old-idx 0)
      (var new-idx 0)
      (while (< new-idx (length new-elements))
        (let [new-element (get new-elements new-idx)
              key (element-key new-element)]
          (if (not (nil? key))
            (let [token (keyed-token! new-key-counts key)
                  old-node (get old-keyed token nil)
                  new-node (reconcile old-node ctx new-element)]
              (when old-node
                (put old-keyed token nil))
              (push-node! out new-node)
              (++ new-idx))
            (let [old-node (get old-unkeyed old-idx nil)
                  old-next (get old-unkeyed (+ old-idx 1) nil)
                  new-next (get new-elements (+ new-idx 1) nil)]
              (cond
                (should-reconcile? ctx old-node new-element)
                (do
                  (push-node! out (reconcile old-node ctx new-element))
                  (++ old-idx)
                  (++ new-idx))

                (should-reconcile? ctx old-next new-element)
                (do
                  (nodes/unmount old-node)
                  (push-node! out (reconcile old-next ctx new-element))
                  (set old-idx (+ old-idx 2))
                  (++ new-idx))

                (and new-next
                     (nil? (element-key new-next))
                     (should-reconcile? ctx old-node new-next))
                (do
                  (push-node! out (make-impl nil new-element ctx))
                  (++ new-idx))

                :else
                (do
                  (when old-node
                    (nodes/unmount old-node)
                    (++ old-idx))
                  (push-node! out (make-impl nil new-element ctx))
                  (++ new-idx)))))))
      (while (< old-idx (length old-unkeyed))
        (nodes/unmount (get old-unkeyed old-idx))
        (++ old-idx))
      (unmount-keyed-leftovers! old-keyed)
      out)))
