% Secret Fire
% Sam Ferrell
% June 5, 2026

# Secret Fire

_How DataScript provides rare leverage for building browser applications_

There is a secret fire in every project and for my real-time collaborative canvas application the name of that fire is DataScript. It is an in-memory triple store whose 'rare leverage' includes its queryability, relational design, and transaction language. There is nothing more singularly important to the success of my application than it.

---

**DataScript databases are wildly queryable**. There are Datalog queries, pull queries, direct index traversal, and lazy entity maps. Each have their own qualities and use cases - we'll take a look at pull queries since they are well suited for user interfaces comprising components.

Pull queries are vectors of attribute names whose values and relations are populated in the result. **They project a graph of relations as a tree** which maps well to component hierarchies. The shape of the result is predictable since they match the shape of the query. In this way they are similar to GraphQL queries.

_Example of a pull query and its result_

```clojure
[:person/name
 :culture/race
 :culture/kindred
 {:family/mother [:person/name]}
 {:family/children [:person/name]}]

;; =>
{:person/name "Fëanor"
 :culture/race "Elves"
 :culture/kindred "Noldor"
 :family/mother {:person/name "Míriel"}
 :family/children
 [{:person/name "Maedhros"}
  {:person/name "Maglor"}
  {:person/name "Celegorm"}]}
```

One of the most interesting features of pull queries are **reverse attribute lookups** which select all entities that contain the attribute and whose value is a reference to the entity being queried. They're a great way to determine if an entity is currently a member of some one-to-many relation. For example, whether or not a canvas object (leaf) is currently selected by the user (entity further up in state).

_Reverse attribute lookups are denoted with a leading underscore_

```clojure
[:place/name {:person/_home [:person/name]}] ;; =>
{:place/name "Valinor" :person/_home [{:person/name "Fëanor"}]}
```

Pull queries are uniquely positioned to enable a **fine-grained caching strategy**. Since queries declare exactly which attributes are relevant to the component, you can avoid requerying and rerendering until a transaction causes any of those entity-attributes to change. There are a few caveats that I've [written about in another post][1].

---

**DataScript is relational** but there are no tables to join, only one universal relation with itself. You might think of it as a key-value table where the values can reference other records on the same table recursively. A schema is only necessary to declare certain attributes as unique keys or reference types; everything else is assumed to be any arbitrary value, primitive or otherwise.

One thing that shakes out of this design is that **DataScript databases are referentially consistent**. Deleting an entity will also remove any relationships other entities had to it without any configuration or book keeping necessary.

Something that became noticeable during development was just how easy it was to rename attributes, refactor relations, and completely rearrange the whole graph structure. All that was necessary was to make sure my attribute names were globally unique and sanely namespaced.

---

**The language for creating change is composable** since, like most things in the ecosystem, it comprises the usual data structures like vectors and maps. With SQL you're stuck with bashing strings together or outsourcing string bashing to a library. Other databases might offer an interface of function calls within a transaction callback. DataScript's interface for creating change is called transaction data and it looks something like this.

```clojure
;; Create a new entity (negative integers are temporary IDs)
[[:db/add -1 :person/name "Strider"]
 [:db/add -1 :person/title "Ranger of the North"]]

;; Change an existing entity
[[:db/add 1 :person/name "Aragorn"]
 [:db/add 1 :person/title "Heir of Isildur"]]

;; Create a new entity and use it as a reference
[[:db/add -1 :person/name "Arwen"]
 [:db/add 1 :person/name "Elessar"]
 [:db/add 1 :person/title "King of the Reunited Kingdom"]
 [:db/add 1 :family/spouse -1]]

;; Remove an entity or retract an attribute
[[:db/retract 2 :person/name]
 [:db/retractEntity 1]]

;; Call a function with provided parameters
[[:db.fn/call change-name 2 "Evenstar"]]

;; Compare and swap
[[:db.fn/cas 1 :person/residence "Rivendell" "Minas Tirith"]]

;; Reference entities by unique attributes
[[:db/add [:artifact/name "Narya"] :artifact/owner [:person/name "Gandalf"]]]
```

Adept Clojure programmers already know how to create and change this data with core functions like `for`, `into`, and `cond->`. The ergonomics of this can't be overstated. Moreover, issues with transactions can be investigated just by looking at the transaction data that was applied instead of trying to compare before and after snapshots of the whole database.

Applying this transaction data returns a transaction report which includes a list of facts, or datoms, that have changed. These datoms not only represent a minimal changeset but **they can also be used as transaction data themselves**! They can be serialized, broadcast to peers, and applied as transaction data locally to reach parity.

One of the problems collaborative applications sometimes run into is thrashing caused by peers broadcasting more state than necessary. A recommendation often made is to send very fine-grained changesets to reduce the chance of overwriting work being done by another user. DataScript transaction reports contain exactly this minimal changeset by design.

My own collaborative application was not originally designed to support multiple users but after seeing the feature request so much I started thinking how it could be done. It would require some changes to the graph. Many transactions needed to be refactored as 'upserts'. Also, obviously, a server to parley messages and hold WebSocket connections. It took about a week to ship something stable and I haven't had to look too hard at it again since.

---

Most frontend state management libraries tend to represent state as object trees even if they are based on observables, signals, or reducers. Object trees are not relational and have a difficult time expressing graphs without running into issues with duplication and missing references. Changes to these trees cannot be expressed naturally as data so some ad-hoc language of change needs to be made for them. There is no leverage provided for querying object trees.

Comparable tooling includes Apollo and Relay where state management is essentially deferred to the server which itself is probably using a relational SQL database.

DataScript is my project's secret fire and it will avail you, as well.

[1]: /post/pull-query-dependencies.html "Finding Dependencies of Pull Queries"
