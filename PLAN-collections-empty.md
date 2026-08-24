# Fix: every Readeck collection shows zero articles

The Collections screen lists the collections correctly, but each row counts `0` and
drilling into one shows nothing.

## 1. Root cause

Readeck declares the nullable collection filter flags as Go pointers, with no `omitempty`:

```go
// readeck/internal/bookmarks/filters.go
IsMarked   *bool  `json:"is_marked"`
IsArchived *bool  `json:"is_archived"`
```

so an unset flag is emitted as JSON `null`, not omitted. A collection with no
archived/favourite restriction — which is most of them — arrives as
`{"is_archived": null, "is_marked": null, ...}`.

KOReader's JSON decoder does **not** map `null` to `nil` by default. `common/json/util.lua`
defines the null marker as a *function*:

```lua
-- Function to insert nulls into the JSON stream
local function null()
    return null
end
```

and `common/json/decode/others.lua` uses `null = jsonutil.null` unless the caller passes
`mode == "simple"`. `readeck/net/client.lua:160` calls `pcall(JSON.decode, content)` with no
mode, so **`is_archived` reaches the plugin as a Lua function**.

`Catalog.collection_from_json` is the single place that stores a field raw. Every neighbour
is coerced; these two are not:

```lua
-- readeck/browse/catalog.lua:123-133
labels      = string_list(collection.labels),
site        = string_or_nil(collection.site),
...
is_archived = collection.is_archived,   -- raw
is_marked   = collection.is_marked,     -- raw
```

`Facets.collection_filter` copies both verbatim, and `Facets.matches` tests them with `~= nil`:

```lua
-- readeck/browse/facets.lua:183-188
if filter.is_archived ~= nil and entry.is_archived ~= filter.is_archived then
    return false
end
if filter.is_marked ~= nil and entry.is_marked ~= filter.is_marked then
    return false
end
```

`function ~= nil` is **true**, and `entry.is_archived` is always a real Lua boolean
(`boolean()` at `catalog.lua:98`, and again on load at `catalog.lua:176`), so
`boolean ~= function` is **true** as well — different types, `__eq` never consulted.
Every entry is rejected for every collection. The names survive because `name` goes through
`string_or_nil`.

Both symptoms come from this one filter table: the row count
(`items.lua:181` → `Facets.count`) and the drill-down (`browser.lua:258` → `Facets.filter`)
consume the same table against the same `self.entries`.

`is_marked` is independently sufficient — fixing only `is_archived` would leave the bug intact.

### Corroborating evidence

The previous PoC hit the same nulls and guarded against them explicitly:

```lua
-- koreader-readeck/readeck.koplugin/readeck-api.lua:81
if val ~= rapidjson.null then
```

A response captured from the author's own server (`koreader-readeck/aaa/cache.sqlite`,
key `collections`) holds three collections whose `type`, `read_status`, `is_archived`,
`is_marked`, `has_labels`, `has_errors` and `is_loaded` are all the null sentinel, while
`is_deleted` and `is_pinned` in the same object are real booleans — so the nulls are
deliberate tri-state, not a serialisation quirk.

## 2. Secondary bug, found on the way

`collection.labels` is **not a JSON array**. Readeck stores it as `Labels string` — a raw
search-query string such as `mgmt secops`. `string_list()` returns `{}` for any non-table,
so a collection's label restriction is silently dropped today.

This *widens* the filter, so it cannot cause the zero-count symptom — but it will surface as
over-matching the moment the null bug is fixed, so it belongs in the same change.

Splitting on whitespace is not enough. Readeck serialises a multi-word label with
`strconv.Quote`, and its scanner (`internal/searchstring/searchstring.go`) understands
quoting, `\` escapes, `-` negation, `*` wildcards and `field:` prefixes. A naive
`gmatch("[^%s]+")` — what the PoC did — shreds `"multi word"` into two labels that do not
exist, emptying the collection.

## 3. Also worth knowing

`frontend/dump.lua` serialises a function as the literal text `function: 0x...`, so every
`readeck_catalog.lua` written since collections landed is a **syntax-error file**;
`LuaSettings` then silently falls back to `readeck_catalog.lua.old`. Some users may already
be browsing a stale backup catalog. The fix removes the sentinel before it is ever persisted.

## 4. The fix

### Step 1 — coerce at the boundary *(this is the fix)*

`readeck/browse/catalog.lua`: add a `tri_boolean(value)` local next to the existing
`boolean()`, returning `true` / `false` / **`nil`**:

```lua
local function tri_boolean(value)
    if type(value) == "boolean" then return value end
    if value == "true" or value == 1 then return true end
    if value == "false" or value == 0 then return false end
    return nil
end
```

and use it for `is_archived` / `is_marked`.

`nil` is the correct default: `Facets.matches` skips a nil flag entirely, so anything the
plugin cannot interpret **widens** the collection instead of emptying it. That is the
degradation rule this whole bug argues for.

It must be a *new* helper. The existing `boolean()` maps every truthy value — a function
included — to `true`, which would narrow every collection to archived-only: the same bug
wearing a different hat.

The test is type-based, so it catches `json.util.null`, `json.util.undefined`, tables and
userdata without `catalog.lua` ever requiring `json` — the module stays dependency-free and
directly unit-testable.

### Step 2 — belt and braces in the matcher

`readeck/browse/facets.lua:183` and `:186`: `filter.is_archived ~= nil` →
`type(filter.is_archived) == "boolean"`.

Deliberately *not* the fix — a guard in the matcher cannot repair a value already written to
disk. Worth having anyway: `Facets.matches` accepts filter tables from three producers, and
`~= nil` is simply the wrong predicate for a tri-state flag.

### Step 3 — repair catalogs already on disk

`Catalog.normalize` coerces entries but re-inserts collections verbatim
(`catalog.lua:181-187`), so step 1 alone leaves a stale catalog broken until the next
successful `refreshCollections`.

Extract the filter table into a local `collection_filters(source)` and call it from both
`Catalog.collection_from_json` (flat raw JSON) and `Catalog.normalize`
(`collection.filters or {}`).

**Do not bump `Catalog.VERSION`.** A version mismatch returns `Catalog.empty()`, discarding
every entry and forcing a full library re-sync — to repair a list that any refresh replaces
wholesale anyway. One helper, two call sites, no migration.

### Step 4 — decode the label search string

`readeck/net/api.lua`: add `Api.decode_label_terms(value)` directly below the existing
`Api.encode_label_terms`, as its exact inverse — same file, same syntax, round-trippable.

Mirror Readeck's scanner: skip whitespace runs; on `"` or `'` read a quoted term to the
matching delimiter or EOF, where `\` + delim and `\\` yield the literal character, any other
`\x` keeps both characters, and an embedded whitespace run collapses to one space; otherwise
read an unquoted term terminating at whitespace, `:` or `*`.

Drop terms carrying a leading `-`, a trailing `*`, or a `field:` prefix. `Facets.has_label`
is exact string equality, so keeping the literal text would demand a label named `-foo` and
empty the collection. Dropping loses a restriction, which is the safe direction. (A
collection defined *solely* as `-draft` will therefore count the whole library — see
open questions.)

### Step 5 — use it

`readeck/browse/catalog.lua`: inside `collection_filters`, parse `labels` with
`Api.decode_label_terms` when it is a string and fall back to `string_list` otherwise, so
the array form the specs and the plugin's own callers use keeps working.

`net/api.lua` has zero requires and is already loaded alongside `catalog.lua` by
`service.lua`, so there is no cycle. If keeping `browse/` free of any sibling require matters
more, inline the same scanner as a local and cross-reference `api.lua` in a comment.

### Step 6 — tests: `spec/catalog_spec.lua`

The suite is green while the feature is completely broken, because `catalog_spec.lua:140`
and `facets_spec.lua:262` hand-feed `labels = {"rust"}, is_archived = false` — a JSON array
and a real boolean, neither of which Readeck ever sends.

Add, using `local null = function() end` as the sentinel:

- the real server shape → `filters.is_archived` and `is_marked` are `nil`, `labels`/`type`/
  `read_status` are `{}`
- `"mgmt secops"` → `{"mgmt", "secops"}`; `'"multi word" k8s'` → `{"multi word", "k8s"}`;
  the escape case, as the decode counterpart of `browse_query_spec.lua:57`
- real booleans still survive: `false` → `false`, `true` → `true`
- a `Catalog.normalize` case: a v1 catalog off disk whose `collections[1].filters.is_archived`
  is a function comes back `nil`, entries preserved, version still 1

### Step 7 — tests: `spec/facets_spec.lua` and the mock server

The direct regression, through the two call sites the browser actually uses: build a
collection via `Catalog.collection_from_json` with sentinel flags, take
`Facets.collection_filter`, and assert `Facets.count(LIBRARY, filter) == #LIBRARY` and
`#Facets.filter(LIBRARY, filter) == #LIBRARY` — not zero. Plus a `labels = '"e ink"'` case.

`spec/mock_readeck_server.py` has no collections endpoint at all. Adding one that returns
the null-bearing shape is the only layer that would have caught this, since it is the only
one that runs the real decoder.

## 5. Verification

1. Add the `facets_spec` case from step 7 **first**, with no production change — it must fail
   with `0`, confirming the diagnosis inside the suite.
2. Prove the sentinel against the real decoder on this KOReader build:
   `JSON.decode('{"is_archived":null}')` → `type(t.is_archived) == "function"`.
3. `make test`, with the pre-existing collection tests unchanged and still passing.
4. `make check` (luacheck + stylua).
5. On device: clear the catalog, full refresh, open Browse → Collections. Counts non-zero,
   drill-down lists articles.
6. Confirm `readeck_catalog.lua` now loads without a syntax error and contains no
   `function: 0x` text.
7. Migration check: keep a broken catalog, install the fix, open the browser **without**
   refreshing — step 3 must repair it on load with `Catalog.count` unchanged.
8. Degradation: a collection with `is_archived: true` must narrow to archived only; one with
   the flags absent must not narrow.

## 6. Open questions

- **Is the user's catalog file currently unloadable?** Worth checking before concluding the
  fix worked — a fallback to `.old` could mask or mimic the symptom.
- **Should `client.lua` decode with `mode = "simple"`** (null → nil) as a global fix? It would
  neutralise this whole class at the wire boundary, but a null inside a JSON array then
  becomes a hole that shortens `#` and truncates `ipairs`. Recommend **not** here — separate
  change, with its own audit of every decoded array.
- **Excluded (`-label`) and wildcard (`label*`) terms** are dropped rather than honoured.
  Supporting them means `filters.labels` stops being a plain string list, which ripples into
  `facets.lua`, `browser.lua:247` and `browser.lua:520`. Possible follow-up: a separate
  `filters.label_terms` consumed only by `Facets.matches`.
- **Escape fidelity**: `Api.encode_label_terms` escapes only `\` and `"`, while Readeck uses
  `strconv.Quote`, which also emits `\n`, `\t`, `\uXXXX`. Almost certainly irrelevant for
  label names.
