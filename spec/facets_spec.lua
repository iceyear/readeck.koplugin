package.path = "./readeck.koplugin/?.lua;" .. package.path

local Catalog = require("readeck.browse.catalog")
local Facets = require("readeck.browse.facets")

local function entries(list)
    local result = {}
    for _, raw in ipairs(list) do
        table.insert(result, Catalog.entry_from_bookmark(raw))
    end
    return result
end

local function names(facets)
    local result = {}
    for _, facet in ipairs(facets) do
        table.insert(result, facet.name .. "=" .. facet.count)
    end
    return result
end

local function ids(list)
    local result = {}
    for _, entry in ipairs(list) do
        table.insert(result, entry.id)
    end
    return result
end

-- a: unread, e-ink+lua, Example
-- b: reading, e-ink, Example
-- c: read + favorite, lua, Other
-- d: archived, e-ink+lua+rust, Other
-- e: unread + favorite, no labels, no site
local LIBRARY = entries({
    {
        id = "a",
        title = "Alpha",
        labels = { "e-ink", "lua" },
        site = "example.com",
        site_name = "Example",
        read_progress = 0,
        created = "2026-08-01T00:00:00Z",
        reading_time = 5,
    },
    {
        id = "b",
        title = "Beta",
        labels = { "e-ink" },
        site = "example.com",
        site_name = "Example",
        read_progress = 40,
        created = "2026-08-02T00:00:00Z",
        reading_time = 12,
    },
    {
        id = "c",
        title = "Gamma",
        labels = { "lua" },
        site = "other.org",
        site_name = "Other",
        read_progress = 100,
        is_marked = true,
        created = "2026-08-03T00:00:00Z",
        reading_time = 3,
    },
    {
        id = "d",
        title = "Delta",
        labels = { "e-ink", "lua", "rust" },
        site = "other.org",
        site_name = "Other",
        is_archived = true,
        read_progress = 0,
        created = "2026-08-04T00:00:00Z",
        reading_time = 9,
    },
    { id = "e", title = "Epsilon", read_progress = 0, is_marked = true, created = "2026-08-05T00:00:00Z" },
})

describe("readeck.browse.facets buckets", function()
    it("all excludes archived articles", function()
        assert.are.same({ "a", "b", "c", "e" }, ids(Facets.filter(LIBRARY, { bucket = "all", sort = "created" })))
    end)

    it("unread means not archived and never opened", function()
        assert.are.same({ "a", "e" }, ids(Facets.filter(LIBRARY, { bucket = "unread", sort = "created" })))
    end)

    it("archived shows only archived articles", function()
        assert.are.same({ "d" }, ids(Facets.filter(LIBRARY, { bucket = "archived" })))
    end)

    it("favorite ignores the archived/read state", function()
        assert.are.same({ "c", "e" }, ids(Facets.filter(LIBRARY, { bucket = "favorite", sort = "created" })))
    end)

    it("facet buckets do not constrain the set on their own", function()
        assert.are.equal(5, #Facets.filter(LIBRARY, { bucket = "labels" }))
        assert.are.equal(5, #Facets.filter(LIBRARY, { bucket = "sources" }))
    end)
end)

describe("readeck.browse.facets filtering", function()
    it("AND-combines selected labels", function()
        assert.are.same({ "a", "d" }, ids(Facets.filter(LIBRARY, { labels = { "e-ink", "lua" }, sort = "created" })))
        assert.are.same({ "d" }, ids(Facets.filter(LIBRARY, { labels = { "e-ink", "lua", "rust" } })))
        assert.are.same({}, ids(Facets.filter(LIBRARY, { labels = { "e-ink", "nope" } })))
    end)

    it("combines a label with a bucket", function()
        assert.are.same({ "a" }, ids(Facets.filter(LIBRARY, { bucket = "unread", labels = { "e-ink" } })))
    end)

    it("filters by source using the display name", function()
        assert.are.same({ "a", "b" }, ids(Facets.filter(LIBRARY, { site = "Example", sort = "created" })))
        assert.are.same({ "c", "d" }, ids(Facets.filter(LIBRARY, { site = "Other", sort = "created" })))
    end)

    it("combines a source with a label and a bucket", function()
        assert.are.same({ "a" }, ids(Facets.filter(LIBRARY, { bucket = "all", site = "Example", labels = { "lua" } })))
    end)

    it("falls back to the domain when there is no site name", function()
        local no_name = entries({ { id = "x", site = "domain.tld" } })
        assert.are.equal("domain.tld", Facets.source_of(no_name[1]))
        assert.is_nil(Facets.source_of(entries({ { id = "y" } })[1]))
    end)

    it("derives a read status from local progress", function()
        assert.are.equal("unread", Facets.read_status_of({ read_progress = 0 }))
        assert.are.equal("reading", Facets.read_status_of({ read_progress = 40 }))
        assert.are.equal("read", Facets.read_status_of({ read_progress = 100 }))
        assert.are.equal("unread", Facets.read_status_of({}))
    end)

    it("filters by read status", function()
        assert.are.same({ "b" }, ids(Facets.filter(LIBRARY, { read_status = { "reading" } })))
        assert.are.same(
            { "a", "d", "e" },
            ids(Facets.filter(LIBRARY, { read_status = { "unread" }, sort = "created" }))
        )
    end)

    it("searches metadata case-insensitively", function()
        assert.are.same({ "b" }, ids(Facets.filter(LIBRARY, { search = "bet" })))
        assert.are.same({ "b" }, ids(Facets.filter(LIBRARY, { search = "BETA" })))
        assert.are.same({ "c", "d" }, ids(Facets.filter(LIBRARY, { search = "other", sort = "created" })))
        assert.are.same({ "d" }, ids(Facets.filter(LIBRARY, { search = "rust" })))
    end)

    it("treats an empty search as no search", function()
        assert.are.equal(5, #Facets.filter(LIBRARY, { search = "" }))
    end)
end)

describe("readeck.browse.facets sorting", function()
    it("defaults to newest first", function()
        assert.are.same({ "e", "d", "c", "b", "a" }, ids(Facets.filter(LIBRARY, {})))
    end)

    it("honours ascending and descending keys", function()
        assert.are.same({ "a", "b", "c", "d", "e" }, ids(Facets.filter(LIBRARY, { sort = "created" })))
        assert.are.same({ "a", "b", "d", "e", "c" }, ids(Facets.filter(LIBRARY, { sort = "title" })))
        assert.are.same({ "c", "e", "d", "b", "a" }, ids(Facets.filter(LIBRARY, { sort = "-title" })))
        assert.are.same({ "e", "c", "a", "d", "b" }, ids(Facets.filter(LIBRARY, { sort = "duration" })))
        assert.are.same({ "b", "d", "a", "c", "e" }, ids(Facets.filter(LIBRARY, { sort = "-duration" })))
    end)

    it("breaks ties by id so the order never reshuffles", function()
        local tied = entries({
            { id = "z", title = "Same", created = "2026-01-01T00:00:00Z" },
            { id = "a", title = "Same", created = "2026-01-01T00:00:00Z" },
            { id = "m", title = "Same", created = "2026-01-01T00:00:00Z" },
        })
        assert.are.same({ "a", "m", "z" }, ids(Facets.filter(tied, { sort = "title" })))
        assert.are.same({ "a", "m", "z" }, ids(Facets.filter(tied, { sort = "-title" })))
    end)

    it("falls back to created for an unknown sort key", function()
        assert.are.same(
            ids(Facets.filter(LIBRARY, { sort = "-created" })),
            ids(Facets.filter(LIBRARY, { sort = "-bogus" }))
        )
    end)
end)

describe("readeck.browse.facets tallies", function()
    it("orders labels by count descending", function()
        assert.are.same({ "e-ink=3", "lua=3", "rust=1" }, names(Facets.labels(LIBRARY, {})))
    end)

    it("orders sources by count descending", function()
        assert.are.same({ "Example=2", "Other=2" }, names(Facets.sources(LIBRARY, {})))
    end)

    it("tallies only within the current bucket", function()
        assert.are.same({ "e-ink=2", "lua=1" }, names(Facets.labels(LIBRARY, { bucket = "all", site = "Example" })))
        assert.are.same({ "Example=1" }, names(Facets.sources(LIBRARY, { bucket = "unread" })))
    end)

    it("breaks count ties by name", function()
        assert.are.same({ "e-ink=3", "lua=3", "rust=1" }, names(Facets.labels(LIBRARY, {})))
    end)
end)

describe("readeck.browse.facets label drill-down", function()
    it("recomputes counts over the matching set, not the whole catalog", function()
        local candidates, matching = Facets.candidate_labels(LIBRARY, {}, { "e-ink" })
        assert.are.equal(3, matching)
        -- Without the recomputation "lua" would still read 3 -- the PoC's bug.
        assert.are.same({ "lua=2", "rust=1" }, names(candidates))
    end)

    it("excludes labels already selected", function()
        local candidates = Facets.candidate_labels(LIBRARY, {}, { "e-ink", "lua" })
        assert.are.same({ "rust=1" }, names(candidates))
    end)

    it("narrows to nothing once every candidate is selected", function()
        local candidates, matching = Facets.candidate_labels(LIBRARY, {}, { "e-ink", "lua", "rust" })
        assert.are.same({}, names(candidates))
        assert.are.equal(1, matching)
    end)

    it("keeps a candidate that would not narrow anything", function()
        -- Every "rust" article also has "lua", so lua's count equals the matching count.
        local candidates, matching = Facets.candidate_labels(LIBRARY, {}, { "rust" })
        assert.are.equal(1, matching)
        assert.are.same({ "e-ink=1", "lua=1" }, names(candidates))
    end)

    it("applies the base filter before counting", function()
        local candidates, matching = Facets.candidate_labels(LIBRARY, { bucket = "archived" }, {})
        assert.are.equal(1, matching)
        assert.are.same({ "e-ink=1", "lua=1", "rust=1" }, names(candidates))
    end)

    it("returns the full vocabulary when nothing is selected", function()
        local candidates, matching = Facets.candidate_labels(LIBRARY, {}, {})
        assert.are.equal(5, matching)
        assert.are.same({ "e-ink=3", "lua=3", "rust=1" }, names(candidates))
    end)

    it("uses the injected collator for name tiebreaks", function()
        Facets.set_collator(function(a, b)
            return a > b
        end)
        assert.are.same({ "lua=3", "e-ink=3", "rust=1" }, names(Facets.labels(LIBRARY, {})))
        Facets.set_collator(function(a, b)
            return a < b
        end)
        assert.are.same({ "e-ink=3", "lua=3", "rust=1" }, names(Facets.labels(LIBRARY, {})))
    end)
end)

describe("readeck.browse.facets collections", function()
    it("re-evaluates a collection's stored filters locally", function()
        local collection = Catalog.collection_from_json({
            id = "col1",
            name = "Unread e-ink",
            labels = { "e-ink" },
            is_archived = false,
        })
        local filter, approximate = Facets.collection_filter(collection)
        assert.is_false(approximate)
        assert.are.same({ "a", "b" }, ids(Facets.filter(LIBRARY, filter, "created")))
    end)

    it("flags a collection whose text search cannot be evaluated offline", function()
        local collection = Catalog.collection_from_json({ id = "c2", name = "Rust notes", search = "borrow checker" })
        local filter, approximate = Facets.collection_filter(collection)
        assert.is_true(approximate)
        assert.is_nil(filter.search)
    end)

    it("handles a collection with no filters at all", function()
        local filter, approximate = Facets.collection_filter(nil)
        assert.is_false(approximate)
        assert.are.equal(5, #Facets.filter(LIBRARY, filter))
    end)

    -- The regression that emptied every collection. Readeck types the nullable filter flags
    -- as pointers with no omitempty, so an unrestricted collection sends `is_archived: null`
    -- -- and KOReader's JSON decoder represents null as a sentinel *function*, not nil. The
    -- old `filter.is_archived ~= nil` guard let it through, and a function never equals the
    -- boolean on an entry, so every article was rejected.
    it("treats an unset filter flag as unconstrained, not as a value to match", function()
        local null = function() end
        local collection = Catalog.collection_from_json({
            id = "col1",
            name = "Everything",
            labels = "",
            site = "",
            search = "",
            title = "",
            author = "",
            type = null,
            read_status = null,
            is_archived = null,
            is_marked = null,
        })
        local filter, approximate = Facets.collection_filter(collection)
        assert.is_false(approximate)
        -- Both call sites the browser uses: the row count and the drill-down.
        assert.are.equal(#LIBRARY, Facets.count(LIBRARY, filter))
        assert.are.equal(#LIBRARY, #Facets.filter(LIBRARY, filter))
    end)

    it("still honours a flag the server did set", function()
        local archived = Facets.collection_filter(Catalog.collection_from_json({
            id = "c1",
            is_archived = true,
        }))
        assert.are.same({ "d" }, ids(Facets.filter(LIBRARY, archived, "created")))

        local favorite = Facets.collection_filter(Catalog.collection_from_json({
            id = "c2",
            is_marked = true,
        }))
        assert.are.same({ "c", "e" }, ids(Facets.filter(LIBRARY, favorite, "created")))
    end)

    -- Readeck stores the label filter as one search expression, not an array, and quotes
    -- any name containing a space. Splitting on whitespace would ask for two labels nobody
    -- has and empty the collection.
    it("reads the label filter back out of the stored search expression", function()
        local collection = Catalog.collection_from_json({ id = "c1", labels = "e-ink lua" })
        assert.are.same({ "e-ink", "lua" }, collection.filters.labels)
        assert.are.same({ "a", "d" }, ids(Facets.filter(LIBRARY, Facets.collection_filter(collection), "created")))
    end)
end)

describe("readeck.browse.facets local reading state", function()
    -- The catalog is server truth, the sidecar is device truth, and they diverge: with
    -- sync_reading_progress off (the default) nothing local ever reaches the server.
    local LOCAL = {
        -- Read cover to cover on the device; the server still says 0.
        local_progress = function(id)
            return id == "a" and 100 or nil
        end,
        -- Marked finished at 87% -- a state no percentage captures.
        local_status = function(id)
            return id == "e" and "complete" or nil
        end,
    }

    it("keeps the unread bucket honest about device reading", function()
        assert.are.same({ "a", "e" }, ids(Facets.filter(LIBRARY, { bucket = "unread", sort = "created" })))
        assert.are.same({}, ids(Facets.filter(LIBRARY, { bucket = "unread" }, nil, LOCAL)))
    end)

    it("takes the higher of server and device progress", function()
        local a = LIBRARY[1]
        assert.are.equal(0, Facets.effective_progress(a))
        assert.are.equal(100, Facets.effective_progress(a, LOCAL))
        -- Never lets a stale local value hide server progress.
        assert.are.equal(40, Facets.effective_progress(LIBRARY[2], LOCAL))
    end)

    it("treats a locally completed or abandoned article as read", function()
        assert.are.equal("read", Facets.read_status_of(LIBRARY[5], LOCAL))
        assert.are.equal("unread", Facets.read_status_of(LIBRARY[5]))
        assert.is_true(Facets.locally_finished(LIBRARY[5], LOCAL))
        assert.is_false(Facets.locally_finished(LIBRARY[5]))
        assert.is_false(Facets.locally_finished(LIBRARY[1], LOCAL))
    end)

    it("feeds the merged state into read_status filtering", function()
        assert.are.same({ "d" }, ids(Facets.filter(LIBRARY, { read_status = { "unread" } }, nil, LOCAL)))
        assert.are.same(
            { "a", "c", "e" },
            ids(Facets.filter(LIBRARY, { read_status = { "read" }, sort = "created" }, nil, LOCAL))
        )
    end)

    it("applies the merged state to facet counts too", function()
        assert.are.same({ "Example=1" }, names(Facets.sources(LIBRARY, { bucket = "unread" })))
        assert.are.same({}, names(Facets.sources(LIBRARY, { bucket = "unread" }, LOCAL)))
        assert.are.same({}, names(Facets.labels(LIBRARY, { bucket = "unread" }, LOCAL)))
    end)

    it("applies the merged state to the label drill-down", function()
        local _, matching = Facets.candidate_labels(LIBRARY, { bucket = "unread" }, {}, LOCAL)
        assert.are.equal(0, matching)
    end)

    it("works with no accessors at all", function()
        assert.are.equal(0, Facets.effective_progress(LIBRARY[1], {}))
        assert.are.equal(2, Facets.count(LIBRARY, { bucket = "unread" }, {}))
    end)
end)
