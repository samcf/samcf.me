# Finding Dependencies of Pull-style Queries in DataScript

Pull queries declaratively describe which entity data should be retrieved. Sometimes you might like to avoid rerunning a query if its result could not possibly have changed. One way to figure that out is to derive a set of entity ID / attribute pairs. When you receive a transaction report with datoms found in that set, the query should be run again and its dependencies recomputed.

_The query and its result are both needed_

```clojure
(let [q [:db/id, :a, :b, {:c [:db/id, :d, :e, :f]}]
      r {:db/id 1, :a "foo", :c {:db/id 2, :e "bar", :f "baz"}}]
  (query-deps q r))
;; => #{(1 :a) (1 :b) (1 :c) (2 :d) (2 :e) (2 :f)}
```

The query is necessary since it enumerates every attribute needed including those currently absent from the result. The result is needed for the relevant entity IDs and the values of references to other entities. Together they give you a clear picture of which changes to the database would cause the query result to be invalidated.

There are some restrictions with this approach. Most importantly, **reverse attribute lookups are not supported** since they violate the necessary forward-direction traversal of the pattern. Determining those dependencies would require additional queries which would probably defeat the purpose of doing this at all.

Another caveat is that every query must include the `:db/id` attribute in each pattern since the entity ID is needed to populate the dependencies set. This attribute should be included manually only if the application needs it, otherwise it should be injected automatically for the purposes of this optimization.

Some supported pattern options like wildcards and `:as` attribute renaming also need to be considered if you want to support the full breadth of the pull syntax.

This may be obvious but any changes to the entity ID argument in the call to `pull` should invalidate the query result. Less obviously, query dependencies need to be recomputed every time a result is invalidated. That is to say, you must pay attention to every transaction going forward, or if you stop paying attention, you will need to recompute query dependencies from scratch and then start paying attention again.

Implementation requires walking the query pattern tree in step with the corresponding result, extracting ID / attribute pairs along the way. When a map is found in the query, ensure that its values are only walked into if there is a matching value in the result.

```clojure
(defn query-deps [pattern result]
  ;; Use a loop to tail-recursively populate the set of query dependencies.
  (loop [acc {:queue #queue [[pattern result]] :deps (hash-set)}]
    (if (seq (:queue acc))
      (let [[pattern result] (peek (:queue acc))]
        (recur
         ;; Iterate through the pattern elements, each possibly contributing
         ;; to the query deps and/or the queue as well.
         (reduce
          (fn [acc spec] (walk-spec acc spec result))
          (update acc :queue pop) pattern)))
      (:deps acc))))

(defn walk-spec [acc spec result]
  (let [id (:db/id result)]
    (cond

      ;; Keywords are just attribute names and are added to the deps set.
      ;; Unless, of course, they are :db/id or reverse attribute lookups.
      (keyword? spec)
      (if (allowed? spec) (update acc :deps conj (list id spec)) acc)

      ;; Vectors are the same way, but the attribute name itself is the first
      ;; element - the rest can be ignored.
      (vector? spec)
      (let [attr (first spec)]
        (if (allowed? attr) (update acc :deps conj (list id attr)) acc))

      ;; Maps represent joins to other entities. Reduce over the entries and
      ;; add their pattern/result pairs to the queue. Don't forget to add the
      ;; map keys to the dependencies, as well (in this case, I just added the
      ;; keys and the parent result to the queue as one pair).
      (map? spec)
      (reduce-kv
       (fn [acc spec pattern]
         (let [attr (attr-name spec)]
           (if-let [result (result attr)]
             (if (vector? result)
               (update acc :queue into (map (fn [result] [pattern result])) result)
               (update acc :queue conj [pattern result]))
             acc)))
       (update acc :queue conj [(keys spec) result]) spec))))
```

Once you've determined the query dependencies you can avoid rerunning the query until a relevant transaction report is received. Transaction reports contain, among other things, a list of datoms that have changed. When you receive a report that contains datoms present in the query dependencies, invalidate and recompute the dependencies and the result itself by running the query again.

_Small example of invalidating a query result_

```clojure
(ds/listen! conn
  (fn [report]
    (when
     (some
      (fn [datom] (contains? deps (list (.-e datom) (.-a datom))))
      (:tx-data report))
      ;; Use this opportunity to invalidate the result by changing state
      ;; somewhere.
      )))
```

For my use case, I have a React app whose components declare their data needs as pull queries. By avoiding unnecessary requerying I can also prevent unnecessary rerender attempts. One side effect of caching query results this way is that my app now greatly benefits from many more fine grained components with smaller dependency surfaces rather than fewer, larger components.

As a final note, you may prefer representing query dependencies as a map of entity IDs whose values are sets of relevant attribute names. This way, you can test the map directly for the presence of entity IDs which is useful for supporting wildcards.
