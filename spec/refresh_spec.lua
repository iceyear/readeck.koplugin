package.path = "./readeck.koplugin/?.lua;" .. package.path

local Catalog = require("readeck.browse.catalog")
local Dates = require("readeck.core.dates")
local Refresh = require("readeck.browse.refresh")

local function catalog_with(ids)
    local catalog = Catalog.empty()
    for _, id in ipairs(ids) do
        Catalog.upsert(catalog, Catalog.entry_from_bookmark({ id = id, updated = "2026-08-01T00:00:00Z" }))
    end
    return catalog
end

describe("readeck.core.dates rfc3339 output", function()
    it("formats an epoch as UTC with a trailing Z", function()
        assert.are.equal("2026-08-23T13:32:29Z", Dates.to_rfc3339(Dates.parse("2026-08-23T13:32:29Z")))
        assert.is_nil(Dates.to_rfc3339(nil))
        assert.is_nil(Dates.to_rfc3339("not a number"))
    end)

    it("round-trips a timestamp with variable-length fractional seconds", function()
        -- Go's RFC3339Nano trims trailing zeros, so the fraction is not fixed width.
        assert.are.equal("2026-08-23T13:32:29Z", Dates.to_rfc3339(Dates.parse("2026-08-23T13:32:29.13506Z")))
        assert.are.equal("2026-08-23T13:32:29Z", Dates.to_rfc3339(Dates.parse("2026-08-23T13:32:29.1Z")))
    end)
end)

describe("readeck.browse.refresh sync log parsing", function()
    it("keeps only well-formed rows", function()
        local items = Refresh.parse_sync_items({
            { id = "a", time = "2026-08-01T00:00:00Z", type = "update" },
            { id = "b", time = "2026-08-02T00:00:00Z", type = "delete" },
            { id = "c", time = "2026-08-03T00:00:00Z", type = "purge" },
            { id = "", time = "2026-08-04T00:00:00Z", type = "update" },
            { time = "2026-08-05T00:00:00Z", type = "update" },
            "garbage",
        })
        assert.are.equal(2, #items)
        assert.are.equal("a", items[1].id)
        assert.are.equal("b", items[2].id)
    end)

    it("computes the maximum time over every row, not the first", function()
        -- ORDER BY across the UNION is a text comparison of two different serialisation
        -- formats, so the first element is not reliably the newest.
        local _, max_time = Refresh.parse_sync_items({
            { id = "a", time = "2026-08-01T00:00:00Z", type = "update" },
            { id = "b", time = "2026-08-09T00:00:00Z", type = "delete" },
            { id = "c", time = "2026-08-05T00:00:00Z", type = "update" },
        })
        assert.are.equal(Dates.parse("2026-08-09T00:00:00Z"), max_time)
    end)

    it("handles an empty or non-table payload", function()
        local items, max_time = Refresh.parse_sync_items({})
        assert.are.same({}, items)
        assert.is_nil(max_time)
        assert.are.same({}, (Refresh.parse_sync_items(nil)))
        assert.are.same({}, (Refresh.parse_sync_items("nope")))
    end)
end)

describe("readeck.browse.refresh applying a delta", function()
    it("removes deleted articles and queues changed ones", function()
        local catalog = catalog_with({ "a", "b", "c" })
        local items = Refresh.parse_sync_items({
            { id = "a", time = "2026-08-10T00:00:00Z", type = "update" },
            { id = "b", time = "2026-08-11T00:00:00Z", type = "delete" },
            { id = "d", time = "2026-08-12T00:00:00Z", type = "update" },
        })
        local plan = Refresh.apply_sync(catalog, items)
        assert.are.same({ "b" }, plan.removed)
        assert.are.same({ "a", "d" }, plan.stale)
        assert.is_nil(Catalog.get(catalog, "b"))
        assert.is_not_nil(Catalog.get(catalog, "c"))
    end)

    it("skips articles whose mtime has not moved", function()
        -- The `since` bound is inclusive, so the boundary rows come back every time.
        local catalog = catalog_with({ "a" })
        local items = Refresh.parse_sync_items({ { id = "a", time = "2026-08-01T00:00:00Z", type = "update" } })
        assert.are.same({}, Refresh.apply_sync(catalog, items).stale)
    end)

    it("lets a delete win over an update for the same id", function()
        local catalog = catalog_with({ "a" })
        local items = Refresh.parse_sync_items({
            { id = "a", time = "2026-08-10T00:00:00Z", type = "update" },
            { id = "a", time = "2026-08-11T00:00:00Z", type = "delete" },
        })
        local plan = Refresh.apply_sync(catalog, items)
        assert.are.same({ "a" }, plan.removed)
        assert.are.same({}, plan.stale)
    end)

    it("does not queue the same id twice", function()
        local catalog = Catalog.empty()
        local items = Refresh.parse_sync_items({
            { id = "a", time = "2026-08-10T00:00:00Z", type = "update" },
            { id = "a", time = "2026-08-11T00:00:00Z", type = "update" },
        })
        assert.are.same({ "a" }, Refresh.apply_sync(catalog, items).stale)
    end)

    it("reports nothing removed for a delete of an article we never had", function()
        local plan = Refresh.apply_sync(
            Catalog.empty(),
            Refresh.parse_sync_items({
                { id = "ghost", time = "2026-08-10T00:00:00Z", type = "delete" },
            })
        )
        assert.are.same({}, plan.removed)
    end)
end)

describe("readeck.browse.refresh reconciliation", function()
    it("drops local leftovers against a complete census", function()
        local catalog = catalog_with({ "a", "b", "c" })
        local items = Refresh.parse_sync_items({
            { id = "a", time = "2026-08-01T00:00:00Z", type = "update" },
            { id = "c", time = "2026-08-01T00:00:00Z", type = "update" },
        })
        assert.are.same({ "b" }, Refresh.reconcile(catalog, items, true))
        assert.are.equal(2, Catalog.count(catalog))
    end)

    it("never treats a bounded delta's absences as deletions", function()
        -- A `since`-bounded sync only reports what changed; reconciling against it would
        -- wipe the entire library.
        local catalog = catalog_with({ "a", "b", "c" })
        assert.are.same({}, Refresh.reconcile(catalog, {}, false))
        assert.are.equal(3, Catalog.count(catalog))
    end)
end)

describe("readeck.browse.refresh cursor", function()
    it("rewinds by a safety margin to survive the commit race", function()
        local max_time = Dates.parse("2026-08-23T13:32:29Z")
        assert.are.equal("2026-08-23T13:31:29Z", Refresh.cursor_from(max_time))
        assert.are.equal("2026-08-23T13:32:19Z", Refresh.cursor_from(max_time, 10))
    end)

    it("emits UTC with a trailing Z and no offset", function()
        -- A "+HH:MM" offset in the query string decodes as a space server-side and 422s.
        local cursor = Refresh.cursor_from(Dates.parse("2026-08-23T13:32:29Z"))
        assert.is_not_nil(cursor:match("Z$"))
        assert.is_nil(cursor:find("+", 1, true))
    end)

    it("returns nothing when the log was empty", function()
        assert.is_nil(Refresh.cursor_from(nil))
    end)

    it("baselines with a timestamp the server can bind, not a sentinel", function()
        -- `since=0` does not bind to a time, so the server falls back to Go's year-1 zero
        -- value, rejects it, and answers 422 -- fatal on the one request a first-ever
        -- refresh cannot skip. The epoch binds and still means "everything".
        assert.are.equal("1970-01-01T00:00:00Z", Refresh.BASELINE_CURSOR)
        assert.is_truthy(Refresh.BASELINE_CURSOR:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"))
        assert.is_truthy(tonumber(Refresh.BASELINE_CURSOR:sub(1, 4)) > 1)
    end)
end)

describe("readeck.browse.refresh hydration", function()
    it("batches ids up to the server's limit cap", function()
        local ids = {}
        for index = 1, 250 do
            ids[index] = "id" .. index
        end
        local batches = Refresh.batches(ids)
        assert.are.equal(3, #batches)
        assert.are.equal(100, #batches[1])
        assert.are.equal(50, #batches[3])
        assert.are.equal(100, Refresh.ID_BATCH_SIZE)
        assert.are.same({}, Refresh.batches({}))
        assert.are.same({}, Refresh.batches(nil))
    end)

    it("matches hydrated bookmarks by id, not by position", function()
        -- The ?id= route's requested ordering is overwritten by the default sort.
        local catalog = Catalog.empty()
        local count = Refresh.hydrate(catalog, {
            { id = "c", title = "Gamma" },
            { id = "a", title = "Alpha" },
        })
        assert.are.equal(2, count)
        assert.are.equal("Alpha", Catalog.get(catalog, "a").title)
        assert.are.equal("Gamma", Catalog.get(catalog, "c").title)
    end)

    it("skips bookmarks with no id", function()
        local catalog = Catalog.empty()
        assert.are.equal(1, Refresh.hydrate(catalog, { { title = "orphan" }, { id = "a" } }))
    end)

    it("finds the ids that offset paging skipped", function()
        local catalog = catalog_with({ "a" })
        local items = Refresh.parse_sync_items({
            { id = "a", time = "2026-08-01T00:00:00Z", type = "update" },
            { id = "b", time = "2026-08-01T00:00:00Z", type = "update" },
            { id = "z", time = "2026-08-01T00:00:00Z", type = "delete" },
        })
        assert.are.same({ "b" }, Refresh.missing_ids(catalog, items))
    end)
end)

describe("readeck.browse.refresh response classification", function()
    it("treats 304 as nothing-changed so the cursor is left alone", function()
        assert.are.equal("unchanged", Refresh.classify_sync_response(nil, "http_error", 304))
    end)

    it("treats 422 as a corrupt cursor", function()
        assert.are.equal("bad_cursor", Refresh.classify_sync_response(nil, "http_error", 422))
    end)

    it("treats 404 as a server too old for sync", function()
        assert.are.equal("unsupported", Refresh.classify_sync_response(nil, "http_error", 404))
    end)

    it("distinguishes a real payload from an error", function()
        assert.are.equal("ok", Refresh.classify_sync_response({}, nil, 200))
        assert.are.equal("error", Refresh.classify_sync_response(nil, "network_error", nil))
        assert.are.equal("error", Refresh.classify_sync_response(true, nil, 200))
    end)
end)

describe("readeck.browse.refresh progress", function()
    it("reports a fraction only when the total is known", function()
        assert.are.equal(0.5, Refresh.progress_fraction(50, 100))
        assert.is_nil(Refresh.progress_fraction(50, nil))
        assert.is_nil(Refresh.progress_fraction(50, 0))
    end)

    it("clamps to the unit interval", function()
        assert.are.equal(1, Refresh.progress_fraction(150, 100))
        assert.are.equal(0, Refresh.progress_fraction(-1, 100))
    end)
end)
