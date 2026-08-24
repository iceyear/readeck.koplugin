# Plan — Readeck browsing tab for KOReader

Grounded in three real sources, all read for this plan:

- `ko/` = `~/Toolbox/git/koreader-readeck/koreader-source` (KOReader frontend)
- `poc/` = `~/Toolbox/git/koreader-readeck/readeck.koplugin` (the proof of concept)
- Readeck server source, `codeberg.org/readeck/readeck` @ `d7659745` (2026-08-17) — the
  public docs at readeck.org/en/docs/api return 403 to automated fetches and the
  maintainer declined to publish the OpenAPI spec (Codeberg issue #166), so the contract
  below is pinned to `docs/api/*.yaml` fragments cross-checked against the Go code.

Unqualified paths are relative to `readeck.koplugin/`.

---

## 1. Context & goal

Today the plugin is a **sync engine**: `Readeck:synchronize()` pulls the first
`articles_per_sync` (default 30) unarchived articles and downloads every one of them.
There is no way to look at what is on the server and pick one, and no way to search what
is already on the device beyond KOReader's generic file browser.

Two goals, from the request:

1. **Browse the server without downloading everything.** See the library, pick one
   article, download just that one.
2. **Browse downloaded and archived articles offline**, from local metadata.

Both must support faceted search: seven buckets (all, unread, archived, favorite,
collections, by labels, by sources), labels that **re-rank and narrow after every
selection** (count-descending), and a source picker.

### The decision this plan turns on

The two goals look like two features. They are not — they are one feature over one
dataset, provided the device keeps a **metadata-only catalog** of the whole library.

The alternative (UI talks to the API online, and to sidecars offline) was considered and
rejected: it duplicates every filter in two places, and it cannot satisfy the
requirements at all offline, because **the facets the user asked for are not on disk
today** (§2.3). A catalog is not an optimisation here; it is the thing that makes the
offline half of the request possible.

Bookmark metadata is small — Readeck's list endpoint already returns `labels`, `site`,
`site_name`, `is_archived`, `is_marked` and `read_progress` (§2.1), so one pass over the
API yields everything all seven buckets need. ~300 bytes/article ⇒ **~1.5 MB for 5000
articles**, no epubs involved.

So: **sync a catalog, browse the catalog.** Online and offline run the *same* filter and
facet code over the *same* table. "Online" then means only three things: refreshing the
catalog, full-text search, and fetching an epub.

---

## 2. What the research established

### 2.1 The Readeck API is richer than the plugin uses

`GET /api/bookmarks` accepts `search, title, author, site, lang, type, labels, is_loaded,
has_errors, has_labels, has_notes, is_marked, is_archived, range_start, range_end,
read_status, id, collection, sort, seed, limit, offset`
(`docs/api/bookmarks/routes-bookmarks.yaml:45-140`, Go form at
`internal/bookmarks/routes/forms_filters.go:19-44`).

Load-bearing details, each verified against the Go implementation:

| Fact | Source |
| --- | --- |
| **The list response carries `labels`, `site`, `site_name`, `authors`, `read_progress`, `reading_time`** — list and detail serialise from the same `dataset.Bookmark` struct, and the list SELECT names those columns explicitly | `internal/bookmarks/routes/api_bookmarks.go:620-632`, `internal/bookmarks/dataset/bookmarks.go:147-183` |
| Pagination headers are `Total-Count`, `Total-Pages`, `Current-Page` + RFC-5988 `Link` | `internal/server/pagination.go:142-178` |
| `limit` is validated `gte:0 lte:100`. Over 100 does **not** clamp — it 404s | `internal/server/pagination.go:19-38` |
| `labels` is **one string, space-separated, AND-combined**, not a repeatable param | `forms_filters.go:96-125`, `internal/bookmarks/filters.go:146-168` |
| Labels with spaces **must be double-quoted** or they split into multiple ANDed terms; `-x` and `x*` are operators inside a label value | `internal/db/exp/exp.go:125-155`, server does this itself at `dataset/labels.go:43-52` |
| `sort`, `type`, `read_status`, `id` **are** repeatable array params | `forms_bookmarks.go:614-645`, `pkg/forms/values.go:448-475` |
| `GET /api/bookmarks/labels` returns `{name, count, href, href_bookmarks}` — **counts included** | `internal/bookmarks/dataset/labels.go:21-27` |
| Collections live at `/api/bookmarks/collections`, **not** `/api/collections`; a collection *is* a saved filter set (`search, title, author, site, type[], labels, read_status[], is_marked, is_archived, range_start, range_end`) | `internal/bookmarks/routes/http.go:49,145-158`, `docs/api/bookmarks/types.yaml` |
| `?collection=<uid>` **overwrites every other filter** (`*filters = f.FilterForm`) | `api_bookmarks.go:562-597` |
| **There is no sites-with-counts endpoint.** The only enumeration is the undocumented `GET /api/bookmarks/@complete?type=site&q=*`, which returns a flat string list, no counts | `api_bookmarks.go:273-289` |
| No `updated_since`. Delta sync is `GET /api/bookmarks/sync?since=<RFC3339>` → `[{id, time, type:"update"\|"delete"}]`, and is the only way to learn about deletions | `docs/api/bookmarks/routes-sync.yaml:16-30` |
| `site` matches display name **and** domain (FTS column is `site_name || ' ' || site || ' ' || domain`) | `internal/db/migrations/sqlite3/schema.sql:143` |
| Bad filter values return **422** with a form-error body, not 400 | `api_bookmarks.go:640-676` |

### 2.2 The plugin's network layer cannot express any of that yet

- `Api.bookmarks_query` whitelists exactly six keys — `{"limit","offset","is_archived","type","labels","sort"}` — and **silently drops everything else** (`readeck/net/api.lua:39`). A search box wired to it would appear to work and do nothing.
- `build_query` emits each key at most once (`net/api.lua:9-18`), so it *structurally* cannot produce the repeated params `sort`/`type`/`read_status`/`id` need. It needs replacing, not extending.
- **`callAPI` discards response headers.** `resp_headers` is read at `net/client.lua:78-89` only for a nil-check and debug logging. `Total-Count` is unreachable today.
- `callAPI` is **synchronous LuaSocket** (`net/client.lua:78`) and blocks the UI for up to `total_timeout` = 120 s. Any browser page-load through it freezes the device.
- `Api.paths` knows only `/api/info`, `/api/bookmarks`, `/api/bookmarks/{id}`, `.../article.epub` and the annotations routes (`net/api.lua:19-33`). No labels, collections or sync.
- Two footguns to respect: `filepath` **must be `""`, not `nil`** (`client.lua:52` calls `io.open` on it), and passing `headers = {}` rather than `nil` **suppresses the Authorization header** (`client.lua:38-42`).

### 2.3 Offline, almost nothing is recoverable today

This is the finding that shapes the plan. Per downloaded article the plugin writes only:
the epub; file mtime; and `custom_props.keywords` in the KOReader sidecar containing the
labels plus one `"Reading time: N min"` entry (`readeck/storage/metadata.lua`).

Everything else from the API row — `site`, `site_name`, `url`, `description`, `authors`,
`is_archived`, `is_marked`, `word_count`, `read_progress`, collections — is read into
memory during sync and **discarded**. There is no bookmark cache and no local database.

| Facet the request asks for | Recoverable offline today? |
| --- | --- |
| labels | ✅ from sidecar `custom_props.keywords` |
| unread / read progress | ⚠️ only if `sync_reading_progress` is on (**default false**, `core/defaults.lua:70`) and remote > local |
| **sources** | ❌ `site` is never written anywhere |
| **favorite** | ❌ `is_marked` never written |
| **archived** | ❌❌ worse than not-stored: sync queries `is_archived=0` (`sync/articles.lua:48,153`), so **archived articles are never downloaded and no local file can represent one** |
| collections | ❌ never fetched |

So "browse archived articles offline" is unreachable by any amount of local scanning. It
needs a catalog. Two further constraints on the fallback path:

- `doc_props` is written as `{}` (`storage/metadata.lua:106-107`), which also blocks
  KOReader from extracting title/author from the epub — so filenames are the only local
  title source, and they are lossy (truncated to 230 bytes, sanitised, frozen at first
  download).
- `INVESTIGATION-android-sidecar-permissions.md` records that until 2026-08-23 **no
  sidecar was written at all** on the user's Supernote (denied `lfs.mkdir`). Missing
  keyword data must be treated as expected, never as "this article has no labels".

### 2.4 The `|` separator does not exist

The request assumed labels are joined with `|` instead of `,`. Neither is true here.

- **This plugin joins with `"\n"`** and splits on `[^\n]+` (`storage/metadata.lua:14,65`). Introduced already using `"\n"` in commit `ffec743`; never changed. Zero pipe literals in the tree.
- **The PoC** joins with `", "` (`poc/readeck-sync.lua:497`) and parses back with `'([^, ]+)'` (`poc/readeck-cache.lua:437`) — which splits on spaces too, so `machine learning` becomes two labels. That bug is why the PoC's label and source drill-downs silently fail on multi-word values.

`"\n"` is the correct choice and should be kept: it is what KOReader itself expects
(`ko/frontend/apps/filemanager/filemanagerbookinfo.lua:585` sets `allow_newline` for
`keywords`), and it is the one character that cannot occur inside a Readeck label.
**No parser in this plan should be built around `|` or `,`.**

### 2.5 KOReader gives us the browser for free

- Multi-level navigation: keep your own `self.paths` stack and define `onReturn`. `Menu:init` already creates `self.paths` (`ko/frontend/ui/widget/menu.lua:704`); the back arrow appears only when `onReturn ~= nil` and is enabled only when `#self.paths > 0` (`menu.lua:1034,1040`). `OPDSBrowser` is the in-tree reference (`ko/plugins/opds.koplugin/opdsbrowser.lua:713-743, 1168-1180`).
- In-place refresh: `Menu:switchItemTable(title, item_table, itemnumber, itemmatch, subtitle)` (`menu.lua:1175-1217`). **`itemnumber = -1` keeps the current page** — what "load more" needs; `nil` resets to page 1 (the PoC never sets it, which is why its back button always loses your scroll position).
- `BookList` extends `Menu` with `covers_fullscreen`, `title_bar_fm_style` and a class-level `book_info_cache`; `BookList.getBookInfo(file)` returns `{been_opened, status, percent_finished, ...}` with one `dofile` per book and no document open (`ko/frontend/ui/widget/booklist.lua:257-318`).
- Reading custom keywords off disk without opening the document: `BookInfo.getCustomProp("keywords", filepath)` = `findCustomMetadataFile` + `openSettingsFile` + `readSetting("custom_props")` (`ko/frontend/apps/filemanager/filemanagerbookinfo.lua:280-284`). **Use this, not a hardcoded `<book>.sdr/custom_metadata.lua`** — sidecar location depends on the global `document_metadata_folder` (doc/dir/hash). Note it indexes the result of `readSetting("custom_props")` without a default, so it **throws** on a sidecar that exists but has no `custom_props` — which KOReader itself can produce, since `setCustomProp` clears the file when `custom_props` becomes empty (`filemanagerbookinfo.lua:533-546`). Wrap the call in `pcall`.
- Not blocking the UI: `Trapper:wrap(func)` + `Trapper:info(text)` (`ko/frontend/ui/trapper.lua:23-61, 94-232`). `Trapper:info` returns `false` when the user taps to dismiss. OPDS uses exactly this for downloads (`opdsbrowser.lua:1526-1528`).
- Multi-select convention: set `item.mandatory` to `"\u{2713}"` and toggle it in place (`ko/frontend/apps/filemanager/filemanagercollection.lua:27-28, 885-891`).

### 2.6 What the PoC gets right and wrong

Worth copying: the `MenuPath` idea (a stack of screen objects each able to build its own
item table), and the label selector that **does** implement progressive refinement —
after each toggle it recomputes the set of labels that still co-occur with the current
AND-selection (`poc/readeck-browser.lua:357-387`).

Worth not copying:

- Counts shown next to labels are **global and never recomputed** during refinement (`poc/readeck-browser.lua:313`) — precisely the behaviour the request asks to fix.
- `getItemTable` memoises forever with no invalidation hook (`:56-67`), so every visited screen is stale after a sync until the widget is destroyed.
- `Browser:init` calls the network **before** `Menu.init` runs (`:613`) — the menu tap appears dead on a slow or offline device.
- The download indicator is dead code: `api.bookmarkDownloaded(b)` uses a dot, so the bookmark is passed as `self` (`:165`).
- Label/author/site browsing only ever sees files already on disk; `/bookmarks/labels` is implemented but unreferenced (`poc/readeck-api.lua:387`).
- Reusable as-is: `parseLinkHeader` and `extractLimitAndOffset` (`poc/readeck-util.lua:92-109`) — though with `Total-Count` available we prefer offset arithmetic.

---

## 3. Gaps to close before any UI

| # | Gap | Where | Change |
| --- | --- | --- | --- |
| G1 | Query encoder can't express the needed params | `readeck/net/api.lua:9-44` | Replace `build_query` with an encoder that accepts an arbitrary filter table, emits **repeated** params for array values, and quotes label terms. Keep `Api.bookmarks_query` as a thin wrapper so existing callers are untouched. |
| G2 | Response headers unreachable | `readeck/net/client.lua:78-89` | Add an 8th `opts` arg to `callAPI`; when `opts.return_headers` is set, return `result, nil, code, resp_headers`. Additive — existing 7-arg callers unaffected. Must be forwarded through the 401-retry recursion at `client.lua:109`. |
| G3 | No paths for labels/collections/sync | `readeck/net/api.lua:19-33` | Add `Api.paths.labels`, `.collections`, `.sync`. |
| G4 | Nothing persists article metadata | new | `readeck/browse/catalog.lua` + its own settings file. |
| G5 | Archived articles never fetched | `readeck/sync/articles.lua:48,153` | **Leave sync alone.** The catalog refresh is a separate call that omits `is_archived`, so it sees everything. Download policy is unchanged. |

G1's label encoding is the subtle one. `labels` must become a single space-joined string
of quoted terms:

```lua
-- {"machine learning", "ai"} -> labels="machine learning" "ai"
local function encode_labels(labels)
    local terms = {}
    for _, name in ipairs(labels) do
        terms[#terms + 1] = '"' .. tostring(name):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
    end
    return table.concat(terms, " ")
end
```

Always quote, even single words — it neutralises the `-` and `*` operators, and it is
what the server does when it builds `href_bookmarks` (`dataset/labels.go:48`).

---

## 4. Architecture

```
                    ui/browser.lua          <- Menu subclass, paths stack, back = deselect
                    ui/browser/items.lua    <- item_table builders, formatting, icons
                            |
                            v
                    browse/facets.lua       <- PURE: filter + tally + sort   (the whole
                            ^                  seven-bucket + drill-down logic lives here)
                            |
                    browse/catalog.lua      <- PURE: load/save/upsert/remove/all
                            ^
              +-------------+-------------+
              |                           |
   browse/refresh.lua              browse/local_scan.lua
   (full + delta from API)         (dir scan -> downloaded set;
   uses callAPI + Trapper           sidecar keywords as pre-catalog fallback)
              |
        net/api.lua  (G1,G3)  ->  net/client.lua  (G2)
```

Six new files. The three that carry the logic (`catalog`, `facets`, plus the query
encoder in `net/api.lua`) are **pure Lua with no KOReader requires**, so they are
directly unit-testable under busted the way `storage/metadata.lua` already is.

| Path | Responsibility | ~LoC |
| --- | --- | --- |
| `readeck/browse/catalog.lua` | Own the on-disk catalog. `Catalog.load()`, `:all()`, `:get(id)`, `:upsert(entry)`, `:remove(id)`, `:save()`, `:stats()`. Plain module (not `install`) — no plugin state. | 130 |
| `readeck/browse/facets.lua` | `Facets.filter(entries, filter)`, `.tally(entries, field)`, `.candidate_labels(entries, selected)`, `.sort_by_count(tally)`, `.search(entries, text)`. Pure. | 180 |
| `readeck/browse/refresh.lua` | `install(Readeck, deps)`. `Readeck:refreshCatalogFull(opts)`, `:refreshCatalogDelta(opts)`, `:refreshCollections()`. Trapper-wrapped, cancellable. | 220 |
| `readeck/browse/local_scan.lua` | `install(...)`. `Readeck:scanDownloadedIDs()` → `{[id]=path}` from one `lfs.dir` pass; `Readeck:buildFallbackCatalog()` for the pre-catalog case. | 120 |
| `readeck/ui/browser.lua` | `install(...)`. `Readeck:showBrowser()`, the `BookList` subclass, `paths` stack, `onReturn`, `onMenuSelect`, `onMenuHold`, `close_callback`. | 320 |
| `readeck/ui/browser/items.lua` | Item-table builders per screen; mandatory-column formatting; download/cloud glyphs. | 260 |

**Wiring.** In `main.lua`, after `Menu.install(Readeck, deps)` and before
`State.install`:

```lua
local Browser = require("readeck.ui.browser")
local CatalogRefresh = require("readeck.browse.refresh")
local LocalScan = require("readeck.browse.local_scan")
...
LocalScan.install(Readeck, deps)
CatalogRefresh.install(Readeck, deps)
Browser.install(Readeck, deps)
```

Order is mostly irrelevant (methods resolve at call time), but `Browser.install` must
follow `Menu.install` because it appends to the menu builder.

**Menu entry.** New first item in `readeck/ui/menu.lua`'s `sub_item_table_func`:

```lua
{
    text = L("Browse articles"),
    callback = function() self:showBrowser() end,
},
```

Note the existing convention: submenu builders are invoked as `Readeck.buildX(self)`
(dot + explicit self) because `spec/koreader_smoke_spec.lua` drives menus with a plain
table stub that has no metatable. Anything run during menu *construction* must follow
that. A plain `callback` is fine.

**Two things every new module must respect** (from the codebase conventions):

- All modules attach methods onto the same flat `Readeck` table — there are no
  namespaces, so new method names must not collide. Prefix browser methods
  `Readeck:browse*` / `Readeck:catalog*`.
- Every user-facing string goes through `L(...)`, is added to `readeck/i18n/zh_cn.lua`,
  and is asserted in `spec/i18n_spec.lua`. `make check` runs luacheck + `stylua --check`
  (120 cols, 4 spaces, double quotes) + busted.

---

## 5. Data model

### Catalog entry

Kept deliberately narrow — only what the seven buckets and the item rows need.

```lua
{
    id           = "AbCdEf12345",
    title        = "Why e-ink is slow",
    site         = "example.com",          -- domain
    site_name    = "Example News",         -- display name; may be ""
    labels       = { "e-ink", "machine learning" },
    authors      = { "Jane Doe" },
    is_archived  = false,
    is_marked    = false,
    read_progress = 42,                    -- integer 0..100
    reading_time = 7,                      -- minutes
    type         = "article",              -- article | photo | video
    created      = "2026-08-01T10:00:00Z",
    published    = "2026-07-30T00:00:00Z", -- may be nil
    word_count   = 1800,
    description  = "Short server-provided summary.",
}
```

Serialised through `LuaSettings` into
`DataStorage:getSettingsDir() .. "/readeck_catalog.lua"` — **a separate file from
`readeck.lua` on purpose.** `Readeck:saveSettings()` (`storage/settings.lua`) rewrites
its whole table on every settings change; putting 5000 entries in there would make every
checkbox toggle an O(catalog) write.

File shape:

```lua
{ version = 1, synced_at = "2026-08-23T09:12:44Z", entries = { [id] = entry, ... },
  collections = { {id=, name=, filters={...}}, ... } }
```

`downloaded` is **not** stored — it is derived at browser-open time by
`Readeck:scanDownloadedIDs()`, one `lfs.dir` pass over `self.directory` reusing the
existing `Readeck:getArticleID(path)` (`core/helpers.lua:29`). Storing it would go stale
whenever the user deletes a file outside the plugin.

### Filter object

One shape, understood by both `Facets.filter` (local) and the remote query encoder.

```lua
{
    bucket   = "unread",              -- all|unread|archived|favorite|collection|label|source
    labels   = { "e-ink" },           -- AND-combined
    site     = nil,
    collection_id = nil,
    search   = nil,
    sort     = "-created",
}
```

### Facet result

```lua
{ { name = "e-ink", count = 42 }, { name = "lua", count = 17 }, ... }  -- count desc
```

---

## 6. The seven buckets

Every bucket resolves to the same local predicate; the remote column is used only for
catalog refresh and for full-text search.

| Bucket | Local predicate over catalog | Remote equivalent |
| --- | --- | --- |
| **all** | `not e.is_archived` | *(no filter)* |
| **unread** | `not e.is_archived and (e.read_progress or 0) == 0` | `read_status=unread` |
| **archived** | `e.is_archived` | `is_archived=true` |
| **favorite** | `e.is_marked` | `is_marked=true` |
| **collections** | list from `catalog.collections`; selecting one re-evaluates its stored filters (`labels`, `site`, `is_marked`, `is_archived`, `read_status`, `type`) against the catalog | `?collection=<uid>` |
| **by labels** | §7 | `labels="a" "b"` |
| **by sources** | `e.site_name == v or e.site == v` | `site=<v>` |

Two honest caveats:

- A collection's `search` field is server-side full-text over article *content*, which
  the device does not have. Offline, a collection carrying `search` is evaluated on the
  other filters and its row is marked with a `~` prefix and a subtitle noting the text
  match was skipped. Online it uses `?collection=<uid>` and is exact.
- `?collection=<uid>` overwrites all other filters server-side, so the UI must not let a
  collection be combined with label/source refinement in online mode. Locally it can be,
  which would be an inconsistency — so the UI forbids it in both.

### 6.1 How a stored collection filter is actually shaped

The table above understates the decoding work. What the server sends is not what this
plan assumed, and the first build got two of the fields wrong; see
`PLAN-collections-empty.md` for the full diagnosis.

- The filter keys sit **flat on the collection object**, not under a `filters` key. The
  catalog nests them itself.
- `labels` is **one search expression string**, not an array — `mgmt secops`, with
  multi-word names quoted. It is read back with `Api.decode_label_terms`, the inverse of
  the encoder the request builder already uses, so a name containing a space survives the
  round trip. Negated, wildcard and field-scoped terms are dropped rather than kept as
  literal text: the browser compares label names exactly, so keeping them would ask for a
  label nobody has and empty the collection, whereas dropping one only widens it.
- `is_archived` and `is_marked` are **tri-state**: true, false, or absent. Readeck types
  them as pointers with no `omitempty`, so "absent" arrives as JSON `null` — and KOReader's
  decoder represents `null` as a sentinel *function*, not as `nil`. They go through a
  `tri_boolean` coercion that yields `true`/`false`/`nil`, and `Facets.matches` tests them
  with `type(...) == "boolean"` rather than `~= nil`.
- `type` and `read_status` are arrays when set and `null` when not, so they need the same
  care; `string_list` happens to absorb the sentinel already.

The rule this establishes for every filter field: **a value the plugin cannot interpret
must widen the collection, never empty it.** Losing a restriction shows too much, which the
user can see and reason about; guessing wrong shows nothing, which is indistinguishable
from a broken feature.

---

## 7. Label drill-down

**Selection is the navigation stack.** Each chosen label pushes a path; KOReader's back
arrow pops it. That gets deselection, breadcrumbs and scroll restoration for free, and
directly fixes the PoC's stale-count bug because the item table is rebuilt on every push
*and* every pop.

```
function Facets.candidate_labels(entries, base_filter, selected)
    matching = {}
    for e in entries:
        if not Facets.matches(e, base_filter) then goto next end
        for s in selected:                       -- AND semantics
            if not has_label(e, s) then goto next end
        matching[#matching+1] = e
    ::next:: end

    counts, selected_set = {}, set(selected)
    for e in matching:
        for l in (e.labels or {}):
            if not selected_set[l] then counts[l] = (counts[l] or 0) + 1 end

    out = [{name=l, count=c} for l,c in counts]
    sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return ffiUtil.strcoll(a.name, b.name)             -- locale-aware tiebreak
    end)
    return out, #matching
end
```

Notes that matter:

- **Counts are recomputed over `matching`, not over the whole catalog** — that is the
  requirement, and the specific thing `poc/readeck-browser.lua:313` gets wrong.
- Count-descending is the default; secondary sort is `ffiUtil.strcoll` for stable,
  locale-correct ordering of ties.
- A label already selected is excluded from the candidate list. A candidate whose count
  equals `#matching` is still shown (it would not narrow anything, but hiding it is
  surprising); it is dimmed via `item.mandatory_dim = true`.
- The screen's first row is always `Show N articles` so the user can stop refining at any
  depth.
- Identical code runs in both modes because both read the catalog. The only difference is
  whether the catalog was refreshed first.

**The label vocabulary is the catalog's, not the sidecar's.** This matters: sidecar
keywords are polluted. `Metadata.merge_keywords` is add-only for labels
(`storage/metadata.lua:33-66` treats only reading-time-prefixed entries as managed), so
labels deleted server-side linger locally forever; and the reading-time pseudo-label is
only distinguishable by prefix-matching the *localised* string (`阅读時间:` in zh_CN).
Deriving facets from the catalog sidesteps both. The sidecar path is used only by the
pre-catalog fallback (§10), which must therefore filter out `L("Reading time") .. ":"`.

---

## 8. Sources

Same tally machinery, over `site_name` falling back to `site`:

```lua
Facets.tally(entries_matching_bucket, function(e)
    local n = e.site_name
    if n == nil or n == "" then n = e.site end
    return n
end)
```

sorted count-descending with the same `strcoll` tiebreak.

Deriving this from the catalog rather than the server is not a compromise — it is the
only option that yields counts at all, since **Readeck has no sites-with-counts
endpoint** (§2.1). The undocumented `@complete?type=site` route is deliberately unused:
it is absent from the OpenAPI spec so it carries no stability guarantee, it requires a
non-empty `q`, it returns no counts, and it UNIONs domains with site names so the same
source can appear twice.

Selecting a source sets `filter.site` and re-enters the article list. Labels can be
refined *within* a source and vice-versa — both are just fields on the one filter object.

---

## 9. Downloading a single article

The entry point already exists and needs no change: **`Readeck:download(article)`**
(`readeck/sync/downloads.lua:433`) resolves the target path via `getDownloadTarget`,
skips if present, calls `callAPI("GET", item_url, nil, "", local_path)`, then applies
metadata and reading progress, returning `downloaded` / `skipped` / `failed`.

The catalog entry is a superset of what it reads (`id`, `title`, `read_progress`), so it
can be passed straight in.

On tapping an article row:

```lua
NetworkMgr:runWhenConnected(function()
    Trapper:wrap(function()
        Trapper:info(T(L("Downloading %1…"), entry.title))
        local result = self:download(entry)
        if result == deps.failed then
            UIManager:show(InfoMessage:new({ text = L("Download failed.") }))
            return
        end
        self.browse_downloaded_ids[entry.id] = self:findLocalArticlePathByID(entry.id)
        -- refresh just this row, keep the page (ko/.../filemanagercollection.lua:925-928)
        self.item_table[item.idx].mandatory = Items.mandatory_for(entry, self)
        self:updateItems(1, true)
    end)
end)
```

If the article is already downloaded, skip straight to
`filemanagerutil.openFile(self.ui, path, self.close_callback)`
(`ko/frontend/apps/filemanager/filemanagerutil.lua:426-457`).

Long-press opens a `ButtonDialog` (the OPDS pattern, `opdsbrowser.lua:1109-1165`) with:
Open / Download / Delete local file / Toggle favorite / Archive. The last two are
`PATCH /api/bookmarks/{id}` — note the API asymmetry the PoC documents: you **read**
`is_marked` but **write** `is_favorite` (`poc/readeck-sync.lua:797-799`).

**Row rendering** (`mandatory` column, built eagerly as a plain string — not a
`mandatory_func` closure, since 5000 closures is real memory):

- downloaded: `"42%  7min"` using local `percent_finished` from `BookList.getBookInfo`
- not downloaded: `"\u{f0c2} 12%  7min"` (FontAwesome cloud; `nerdfonts/symbols.ttf` is fallback #6 in `ko/frontend/ui/font.lua:108-117`)

---

## 9.1 Tapping a row, as built

A tap means **read this**, whether or not the article is already on the device.
`openOrDownload` opens it when `ctx.downloaded` has a path, and otherwise downloads and
then opens the file it just fetched, deferred one `UIManager:nextTick` — the Trapper info
message is still tearing down, and `openLocal` closes the browser on its way to the reader,
so handing the document over from inside that repaint congests the EPDC. OPDS defers its
own post-download dialog for the same reason (`opds.koplugin/main.lua:124-127`).

The first cut stopped at the list once the download finished, which made reading an article
cost **two taps** — the download on the first, the open on the second. The long-press
**Download** action keeps that behaviour on purpose (`openOrDownload(item, true)`): picking
several articles out of the list without leaving it is the other half of what browsing is
for. `downloadEntry` returns the local path rather than a boolean so the caller can open it,
and skips its row redraw on the tap path, where the browser is closing anyway.

---

## 10. Online / offline

There is no mode switch to toggle. The browser always reads the catalog; connectivity
only gates three actions.

| Situation | Behaviour |
| --- | --- |
| Catalog present, offline | Full browsing, all seven buckets, all facets. Download rows are dimmed; tapping one offers "Sync later". |
| Catalog present, online | Same, plus: download works, and a "Refresh catalog" action in the title-bar menu. |
| Catalog stale (> `browse_catalog_max_age_hours`, default 24) and online | Non-blocking hint in the subtitle: `Catalog updated 3 days ago`. Never auto-refreshes on open — that is the PoC's blocking-init mistake (`poc/readeck-browser.lua:613`). |
| **No catalog yet, online** | First open offers "Fetch article list now" and runs a full refresh under Trapper with a cancellable progress message. |
| **No catalog yet, offline** | Degraded fallback: `Readeck:buildFallbackCatalog()` scans `self.directory` and reads each sidecar's `custom_props.keywords` via `BookInfo.getCustomProp`. Yields **labels and lossy filename titles only**. The buckets that need unavailable data (archived, favorite, sources) show an explanatory empty state rather than lying with an empty list. |

Connectivity is checked with `NetworkMgr:isConnected()` for gating, and every network
action is wrapped in `NetworkMgr:runWhenConnected(...)` — the OPDS convention
(`opdsbrowser.lua:1092-1103`).

**Catalog refresh.**

- *Full* — `GET /api/bookmarks?limit=100&offset=N`, **no `is_archived` filter** so archived rows are included. Read `Total-Count` (needs G2) to drive an accurate progress message. `limit=100` is the hard maximum; 101 returns 404, not a clamp. A baseline census request precedes it, but is an **optimisation, not a prerequisite**: it supplies the progress total and the only evidence that permits pruning, so a server that cannot answer it degrades to a slightly less accurate refresh rather than no refresh at all. Its cursor must be a real RFC3339 timestamp (`1970-01-01T00:00:00Z`) — `since=0` does not bind to a time, so the server falls back to Go's year-1 zero value, rejects it, and answers `422 {"since": {"is_bound": false, "errors": ["invalid value"]}}`.
- *Delta* — `GET /api/bookmarks/sync?since=<synced_at>` → `[{id, time, type}]`. `delete` ⇒ `catalog:remove(id)`. `update` ⇒ re-fetch in batches of 100 using repeated `id=` params (the `id` param preserves the order supplied). Advance `synced_at` to the newest `time` seen.
- Both run inside `Trapper:wrap` and check `Trapper:info(...)`'s return value each page so a tap aborts cleanly.
- Collections are refreshed alongside, via `GET /api/bookmarks/collections`.

Refresh is also called at the end of `Readeck:synchronize()` so normal sync keeps the
catalog warm — cheap, since it is a delta.

### 10.1 Catalog lifecycle — every write, as built

The catalog has exactly four ways to change, and nothing else may touch it.

| # | Trigger | Entry point | Effect |
| --- | --- | --- | --- |
| 1 | User asks for it in the browser menu | `refreshCatalogFull` / `refreshCatalogDelta` | Rebuild or delta, under Trapper, cancellable |
| 2 | End of a normal sync | `refreshCatalogAfterSync` → `refreshCatalogDelta` | Silent best-effort delta |
| 3 | The plugin itself mutates an article on the server | `catalogPatch` / `catalogRemove` / `catalogUpsertBookmark` / `catalogAddLabels` | Write-through, in memory |
| 4 | The catalog stops being about this account | `clearCatalog` | Dropped from memory **and** disk |

**Write-through (3) is gated on `self.catalog ~= nil`.** A background or periodic sync
must never force a multi-megabyte `dofile` on behalf of a user who has not opened the
browser. Those devices pick the same change up from the next delta refresh, because a
mutation the plugin made is a mutation the server records in its sync log. Every helper
that changes something sets `self.catalog_dirty`, and the browser's `close_callback`
saves only when that flag is set.

Concretely, the write-through sites:

- `sync/local_actions.lua` `removeArticle` — archive branch → `catalogApplyArchive(id, body)`, which translates the accepted PATCH body field by field (`is_archived`, and whichever of `read_progress` / `is_marked` / `add_labels` the body carried); delete branch → `catalogRemove(id)`.
- `sync/local_actions.lua` `syncReadingProgress` → `catalogPatch(id, {read_progress = …})`.
- `sync/local_actions.lua` `addTags` → `catalogAddLabels(id, tags)`. Labels are **add-only** on the server (`add_labels`), so this unions rather than replaces, or the browser would drop every label it did not send.
- `sync/downloads.lua` `applyDownloadedArticleMetadata` → `catalogUpsertBookmark(article)`. All six download paths — blocking, async, subprocess, retry, and the two already-on-disk shortcuts — funnel through this one function, so it is the single place that knows an article's bytes and metadata are current.

And the deliberate non-sites:

- **`processRemoteDeletes` removes nothing from the catalog.** Its `remote_article_ids` comes from the *filtered* sync list (one label, unread only, capped at `articles_per_sync`), so "missing from that list" means "not in this sync's scope", not "deleted on the server". Driving `catalogRemove` from it would erase exactly the archived and already-read articles the browser exists to show offline.
- Local-only paths (deleting a downloaded file, local completion bookkeeping) leave the catalog alone: the article still exists on the server, and downloaded-ness is recomputed by `scanDownloadedIDs`, not stored.

Invalidation (4) fires on **reset to defaults** and on a **server URL change that actually
changed the URL** — Readeck ids are per-server, so a catalog built against the old one is
meaningless and misleading. It deliberately does *not* fire on token refresh or
`clearAllTokens`: same account, new credentials.

### 10.2 The sync settings, applied to the browser

The catalog mirrors the **whole** server. What the sync downloads is a much smaller set,
carved out by three rules that used to live in two different places: the server enforced
`type=article` and the include label, and `filterIgnoredTags` dropped the exclude labels
client-side. A browser that ignored all three would offer a list the sync will never act
on, so it applies them too — through one shared, pure module, `readeck/core/filters.lua`,
which is what stops the two from drifting apart.

- `parse_label_list(text)` — comma-separated, **trimmed**, de-duplicated. Both settings and
  both consumers go through it. The trim is a bug fix: `filterIgnoredTags` split on commas
  alone, so `work, later` ignored `work` and a label named ` later` that no server sends.
- `rules_from(settings)` reads only `filter_tag` and `ignore_tags`, so the specs pass a
  plain table where production passes the plugin.
- `admits` / `apply(entries, rules)` — `apply` returns the survivors **and** the hidden
  count, which the browser puts in its subtitle. An article missing from a list the user
  expected it on has to be explainable.

Applied at exactly one place: `ArticleBrowser:loadEntries()`, the sole path from
`Catalog.all` to `self.entries`, called by `init` and `reload`. Everything downstream —
bucket counts, label facets, source facets, collection counts, rows — reads `self.entries`,
so no screen can forget. Filtering is at **display** time, not refresh time: the catalog
stays a faithful mirror and a changed setting takes effect with no rebuild.

Three deliberate divergences from the sync:

- **Video is hidden; photo is not.** The sync's `type=article` drops both. A video bookmark
  is a link to something the device cannot play, with no text to paginate; a photo bookmark
  still has a page worth reading, and hiding it was not asked for.
- **`is_archived=0` is not applied.** The archived bucket exists precisely to show those.
- **The whole hide is reversible.** `Hide what sync skips` in the browser menu
  (`browse_apply_sync_filters`, default on) turns it off. Browsing exists to pick one
  article out of the pile the sync does not download, so "excluded from sync" must not come
  to mean "unreachable".

One change on the sync side follows from sharing the parser: `filter_tag` now goes out as
`Api.bookmarks_query({labels = Filters.parse_label_list(...)})` — a list, so
`encode_label_terms` quotes each term. Previously the raw string was sent, and the server
splits an unquoted `labels` value on spaces into AND-ed terms, so a tag named `long read`
quietly asked for two different tags. Quoting is also what lets the browser match the same
set with a plain string comparison.

---

## 11. Performance

Targets on a slow e-ink device (single core, LuaJIT), N = 5000 articles:

| Operation | Budget | How |
| --- | --- | --- |
| Catalog load (`dofile` of ~1.5 MB) | < 2 s, **once per session** | Lazy — only on first `showBrowser()`, then held in memory. Shown under a Trapper info message. |
| Bucket switch / label refinement | < 150 ms | One linear pass; ~15 k table lookups for N=5000 × 3 labels. |
| Directory scan for `downloaded` | < 300 ms | One `lfs.dir` pass, once per browser open. Replaces the existing O(N·M) pattern where `findLocalArticlePathByID` runs a **full scan per article** inside the download loop (`sync/downloads.lua:95`). |
| Full catalog refresh | 50 requests, 2–5 min on slow wifi | Explicit user action only, cancellable, with `Total-Count` progress. Delta afterwards is one request. |
| Memory | ~4 MB | Catalog ~1.5 MB + item tables. Item rows use **plain string** `mandatory`, no per-item closures. |

**Never call `callAPI` outside `Trapper:wrap`.** It is synchronous and can block for 120 s
(§2.2). This is the single most important rule for the UI layer.

`BookList.getBookInfo` is class-level memoised (`ko/frontend/ui/widget/booklist.lua:309-318`)
so local read-progress lookups cost one `dofile` per book per session. Call
`BookList.resetBookInfoCache(file)` after a download so the row's progress is not stale.

---

## 12. Implementation phases

Each phase is independently reviewable and leaves the plugin working.

**P1 — Query encoder (G1, G3).** Rewrite `build_query` in `readeck/net/api.lua` to take an
arbitrary filter table, emit repeated params for arrays, and quote label terms. Keep
`Api.bookmarks_query` as a compatibility wrapper. Add the three new paths.
*Verify:* new `spec/browse_query_spec.lua` — repeated `sort`, quoted multi-word labels,
`is_archived=false` is emitted (not skipped — note `build_query`'s skip test is
`value ~= nil and value ~= ""`, so `false` and `0` do serialise), `limit > 100` rejected
client-side. Existing `spec/api_spec.lua` must still pass unchanged.

**P2 — Response headers (G2).** Add `opts` to `callAPI`, return headers when asked,
forward `opts` through the 401-retry recursion at `client.lua:109`.
*Verify:* extend `spec/mock_readeck_server.py` to emit `Total-Count`; assert a
`return_headers` call reads it and that a 7-arg call still returns exactly what it does
today.

**P3 — Catalog store (G4).** `readeck/browse/catalog.lua`. Pure, no KOReader requires.
*Verify:* `spec/catalog_spec.lua` — upsert/remove/get, save→load round-trip preserves
`labels` as an array, version field present, missing file yields an empty catalog.

**P4 — Facets.** `readeck/browse/facets.lua`. Pure.
*Verify:* `spec/facets_spec.lua` — the seven bucket predicates; `candidate_labels`
narrows and re-counts correctly across two successive selections; counts are over
`matching` not the whole set; sorted count-desc with `strcoll` tiebreak; **multi-word
labels survive** (the explicit PoC regression); selected labels excluded from candidates;
empty catalog returns `{}` not nil.

**P5 — Catalog refresh.** `readeck/browse/refresh.lua`: full + delta + collections, under
Trapper, cancellable, `Total-Count` progress.
*Verify:* mock server grows `/api/bookmarks/sync` and `/api/bookmarks/collections`; assert
full refresh pages to completion, delta applies `update` and `delete`, `synced_at`
advances, and a mid-run abort leaves the previous catalog intact.

**P6 — Local scan.** `readeck/browse/local_scan.lua`: `scanDownloadedIDs` and the
pre-catalog `buildFallbackCatalog`.
*Verify:* `spec/local_scan_spec.lua` with a temp dir of fixture filenames — ids parsed via
the existing `getArticleID`, reading-time pseudo-label filtered out using the *localised*
prefix, missing sidecar treated as "no data" rather than "no labels".

**P7 — Browser UI, read-only.** `readeck/ui/browser.lua` + `ui/browser/items.lua`. Root
buckets, article lists, label drill-down, source picker, collections. Back arrow pops.
No downloading yet. Menu entry added.
*Verify:* `spec/koreader_smoke_spec.lua` gains a case that constructs the browser against
the plain-table stub and walks root → labels → pick → back, asserting the item tables and
that `#paths` returns to 0.

**P8 — Actions.** Tap = open-or-download via `Readeck:download`; long-press
`ButtonDialog` with favorite/archive/delete. Single-row refresh with `updateItems(1, true)`.
*Verify:* mock-server assertions that download hits `/article.epub` once and that
favorite PATCHes `is_favorite` (not `is_marked`).

**P9 — Polish & i18n.** Empty states, stale-catalog subtitle, `zh_cn.lua` entries,
`spec/i18n_spec.lua` assertions, `make check` clean. Wire the delta refresh into the tail
of `Readeck:synchronize()`.

P1–P2 are prerequisites for P5. P3–P4 are independent of everything and can land first.
P7 depends on P3, P4, P6. P8 depends on P7.

**Status: P1–P9 implemented.** P8 grew a data half beyond what this section anticipated —
catalog write-through at the server-mutation sites, specified in §10.1 — because without
it every action taken from the browser left the list it was taken from out of date until
the next refresh.

---

## 13. Testing

New busted specs — `spec/browse_query_spec.lua`, `catalog_spec.lua`, `facets_spec.lua`,
`local_scan_spec.lua` — following the existing convention:
`package.path = "./readeck.koplugin/?.lua;" .. package.path` and KOReader stubbed via
`package.preload` in `install_koreader_stubs()`. `catalog`, `facets` and the query encoder
need no stubs at all.

`spec/mock_readeck_server.py` grows:

- `Total-Count` / `Total-Pages` / `Current-Page` on `GET /api/bookmarks`
- the filter params the browser sends: `labels`, `site`, `is_marked`, `is_archived`, `read_status`, `collection`, repeated `sort`
- `GET /api/bookmarks/labels` → `[{name, count, href, href_bookmarks}]`
- `GET /api/bookmarks/collections`
- `GET /api/bookmarks/sync?since=` → `[{id, time, type}]`
- a 422 form-error response for a bad filter value, and a 404 for `limit=101`, so the
  client's error handling is exercised against real server behaviour

Manual check on device: sync, open Browse, confirm archived and favorite buckets are
populated (they cannot be, pre-catalog — this is the end-to-end proof the catalog works),
turn wifi off, confirm all seven buckets and both drill-downs still work.

---

## 14. Risks & open questions

1. **First full refresh is slow** on a large library — 50 requests for 5000 articles. Mitigated by making it explicit, cancellable and progress-reported, and by delta afterwards. Not mitigated for a user on very slow wifi; they will wait.
2. **Server version skew.** `read_status`, `has_labels` and `/api/bookmarks/sync` may be absent on older Readeck. A bad param returns **422 with a form-error body** (not 400, not 404) — `refresh.lua` should detect 422, log the offending field, and retry once without the optional params. `core/features.lua` already probes server capabilities and is the right place to record the outcome.
3. **Catalog/disk divergence.** Files deleted outside the plugin. Handled by deriving `downloaded` from a live directory scan rather than storing it.
4. **`readeck_catalog.lua` size.** 5000 entries ≈ 1.5 MB is fine; 50 000 would not be. If that ever appears, the fix is `CacheSQLite` (the PoC's `poc/readeck-cache.lua:37-42` shows the shape) — deliberately not done now, since it would trade testable pure Lua for a binary dependency to solve a problem nobody has.
5. **Open question — should the catalog respect `filter_tag` / `ignore_tags`?** Sync uses them to decide what to *download*. My assumption: the catalog ignores them and stores everything, because the point of browsing is to see what sync skipped; the filters stay a download-policy concern. Worth confirming, and cheap to flip — it is one argument to `refreshCatalogFull`.
6. **Open question — collections offline with `search`.** Currently degraded to a `~` marker (§6). The alternative is hiding such collections offline. Degrading seems better but is a UX call.
