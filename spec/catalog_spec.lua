package.path = "./readeck.koplugin/?.lua;" .. package.path

local Catalog = require("readeck.browse.catalog")

local function fake_store(initial)
    return {
        data = { catalog = initial },
        flushed = 0,
        readSetting = function(self, key)
            return self.data[key]
        end,
        saveSetting = function(self, key, value)
            self.data[key] = value
        end,
        flush = function(self)
            self.flushed = self.flushed + 1
        end,
    }
end

local function bookmark(overrides)
    local base = {
        id = "abc123",
        title = "Why e-ink is slow",
        site = "example.com",
        site_name = "Example News",
        labels = { "e-ink", "machine learning" },
        authors = { "Jane Doe" },
        is_archived = false,
        is_marked = true,
        read_progress = 42,
        reading_time = 7,
        word_count = 1800,
        type = "article",
        created = "2026-08-01T10:00:00Z",
        published = "2026-07-30T00:00:00Z",
        description = "A summary.",
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

describe("readeck.browse.catalog", function()
    it("starts empty", function()
        local catalog = Catalog.empty()
        assert.are.equal(Catalog.VERSION, catalog.version)
        assert.are.same({}, catalog.entries)
        assert.are.same({}, catalog.collections)
        assert.are.equal(0, Catalog.count(catalog))
    end)

    it("maps a bookmark onto a narrow entry", function()
        local entry = Catalog.entry_from_bookmark(bookmark())
        assert.are.same({
            id = "abc123",
            title = "Why e-ink is slow",
            site = "example.com",
            site_name = "Example News",
            labels = { "e-ink", "machine learning" },
            authors = { "Jane Doe" },
            is_archived = false,
            is_marked = true,
            read_progress = 42,
            reading_time = 7,
            word_count = 1800,
            type = "article",
            created = "2026-08-01T10:00:00Z",
            published = "2026-07-30T00:00:00Z",
            description = "A summary.",
        }, entry)
    end)

    it("does not carry article content into the entry", function()
        local entry = Catalog.entry_from_bookmark(bookmark({
            resources = { article = { src = "http://x/article" } },
            href = "http://x/api/bookmarks/abc123",
        }))
        assert.is_nil(entry.resources)
        assert.is_nil(entry.href)
    end)

    it("fills in defaults for a sparse bookmark", function()
        local entry = Catalog.entry_from_bookmark({ id = "xyz" })
        assert.are.equal("xyz", entry.title)
        assert.are.same({}, entry.labels)
        assert.are.same({}, entry.authors)
        assert.is_false(entry.is_archived)
        assert.is_false(entry.is_marked)
        assert.are.equal(0, entry.read_progress)
        assert.are.equal("article", entry.type)
    end)

    it("accepts the 0/1 boolean form as well as real booleans", function()
        assert.is_true(Catalog.entry_from_bookmark({ id = "a", is_archived = 1 }).is_archived)
        assert.is_false(Catalog.entry_from_bookmark({ id = "a", is_archived = 0 }).is_archived)
        assert.is_true(Catalog.entry_from_bookmark({ id = "a", is_marked = "true" }).is_marked)
    end)

    it("rejects a bookmark with no id", function()
        assert.is_nil(Catalog.entry_from_bookmark({ title = "orphan" }))
        assert.is_nil(Catalog.entry_from_bookmark(nil))
        assert.is_nil(Catalog.entry_from_bookmark("nope"))
    end)

    it("upserts, gets, patches and removes entries", function()
        local catalog = Catalog.empty()
        Catalog.upsert(catalog, Catalog.entry_from_bookmark(bookmark()))
        assert.are.equal(1, Catalog.count(catalog))
        assert.are.equal("Why e-ink is slow", Catalog.get(catalog, "abc123").title)

        Catalog.upsert(catalog, Catalog.entry_from_bookmark(bookmark({ title = "Renamed" })))
        assert.are.equal(1, Catalog.count(catalog))
        assert.are.equal("Renamed", Catalog.get(catalog, "abc123").title)

        assert.are.equal(true, Catalog.patch(catalog, "abc123", { is_archived = true }).is_archived)
        assert.is_nil(Catalog.patch(catalog, "missing", { is_archived = true }))

        assert.is_true(Catalog.remove(catalog, "abc123"))
        assert.is_false(Catalog.remove(catalog, "abc123"))
        assert.are.equal(0, Catalog.count(catalog))
    end)

    it("returns entries in a deterministic order", function()
        local catalog = Catalog.empty()
        for _, id in ipairs({ "ccc", "aaa", "bbb" }) do
            Catalog.upsert(catalog, Catalog.entry_from_bookmark({ id = id }))
        end
        local ids = {}
        for _, entry in ipairs(Catalog.all(catalog)) do
            table.insert(ids, entry.id)
        end
        assert.are.same({ "aaa", "bbb", "ccc" }, ids)
    end)

    it("stores collections with the filters needed to re-evaluate them offline", function()
        local catalog = Catalog.empty()
        Catalog.set_collections(catalog, {
            { id = "col1", name = "Rust", labels = { "rust" }, is_archived = false },
            { name = "no id -- dropped" },
        })
        assert.are.equal(1, #catalog.collections)
        assert.are.equal("Rust", catalog.collections[1].name)
        assert.are.same({ "rust" }, catalog.collections[1].filters.labels)
        assert.are.equal(false, catalog.collections[1].filters.is_archived)
    end)

    -- What a real server actually sends. The nullable filter flags are pointers with no
    -- omitempty, so an unrestricted collection sends `null` for each -- and KOReader's JSON
    -- decoder represents null as a sentinel function rather than nil. The unset strings come
    -- through as "" rather than being omitted.
    it("coerces the shape Readeck really sends for an unrestricted collection", function()
        local null = function() end
        local collection = Catalog.collection_from_json({
            id = "SGq7sJBA9n7rd7z5aahjVu",
            name = "OffSecGreatAgain",
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
        -- nil, not false: the flag does not apply, so it must not narrow anything.
        assert.is_nil(collection.filters.is_archived)
        assert.is_nil(collection.filters.is_marked)
        assert.are.same({}, collection.filters.labels)
        assert.are.same({}, collection.filters.type)
        assert.are.same({}, collection.filters.read_status)
        assert.is_nil(collection.filters.site)
        assert.is_nil(collection.filters.search)
    end)

    it("reads a collection's label filter out of Readeck's search syntax", function()
        local plain = Catalog.collection_from_json({ id = "c1", labels = "mgmt secops" })
        assert.are.same({ "mgmt", "secops" }, plain.filters.labels)

        local quoted = Catalog.collection_from_json({ id = "c2", labels = '"multi word" k8s' })
        assert.are.same({ "multi word", "k8s" }, quoted.filters.labels)

        -- An array still works: the plugin's own callers build one, and a future server
        -- could switch to it.
        local array = Catalog.collection_from_json({ id = "c3", labels = { "rust" } })
        assert.are.same({ "rust" }, array.filters.labels)
    end)

    it("keeps a filter flag the server did set", function()
        assert.is_true(Catalog.collection_from_json({ id = "c1", is_marked = true }).filters.is_marked)
        assert.is_false(Catalog.collection_from_json({ id = "c2", is_archived = false }).filters.is_archived)
    end)

    -- A catalog written before the coercion existed holds the decoder's null sentinel on
    -- disk. Repairing it on load, rather than waiting for the next refresh, is why normalize
    -- rebuilds collections instead of trusting them -- and why the version is not bumped,
    -- which would throw every entry away to fix a list any refresh replaces anyway.
    it("repairs collections stored by an older build without discarding the catalog", function()
        local store = fake_store()
        store.data.catalog = {
            version = Catalog.VERSION,
            entries = { a = { id = "a", title = "Alpha" } },
            collections = {
                {
                    id = "c1",
                    name = "Everything",
                    filters = { labels = "mgmt secops", is_archived = function() end },
                },
            },
        }
        local catalog = Catalog.load(store)
        assert.are.equal(1, Catalog.count(catalog))
        assert.are.equal(Catalog.VERSION, catalog.version)
        assert.are.equal(1, #catalog.collections)
        assert.are.equal("Everything", catalog.collections[1].name)
        assert.is_nil(catalog.collections[1].filters.is_archived)
        assert.are.same({ "mgmt", "secops" }, catalog.collections[1].filters.labels)
    end)

    it("round-trips through a store", function()
        local store = fake_store()
        local catalog = Catalog.empty()
        Catalog.upsert(catalog, Catalog.entry_from_bookmark(bookmark()))
        assert.is_true(Catalog.save(store, catalog, "2026-08-23T09:12:44Z"))
        assert.are.equal(1, store.flushed)

        local reloaded = Catalog.load(store)
        assert.are.equal("2026-08-23T09:12:44Z", reloaded.synced_at)
        assert.are.equal("Why e-ink is slow", Catalog.get(reloaded, "abc123").title)
    end)

    it("returns an empty catalog when the store has nothing or throws", function()
        assert.are.equal(0, Catalog.count(Catalog.load(fake_store())))
        assert.are.equal(0, Catalog.count(Catalog.load(nil)))
        local broken = {
            readSetting = function()
                error("no settings file")
            end,
        }
        assert.are.equal(0, Catalog.count(Catalog.load(broken)))
    end)

    it("discards a catalog written by another version", function()
        assert.are.equal(0, Catalog.count(Catalog.normalize({ version = 99, entries = { a = { id = "a" } } })))
    end)

    it("discards a catalog belonging to a different server", function()
        local data = { version = Catalog.VERSION, server_url = "https://old", entries = { a = { id = "a" } } }
        assert.are.equal(0, Catalog.count(Catalog.normalize(data, "https://new")))
        assert.are.equal(1, Catalog.count(Catalog.normalize(data, "https://old")))
        -- No known server yet: keep what is on disk rather than throwing it away.
        assert.are.equal(1, Catalog.count(Catalog.normalize(data, nil)))
    end)

    it("repairs entries missing their list fields", function()
        local catalog = Catalog.normalize({
            version = Catalog.VERSION,
            entries = { a = { id = "a", labels = "not a list", read_progress = "37" } },
        })
        assert.are.same({}, Catalog.get(catalog, "a").labels)
        assert.are.same({}, Catalog.get(catalog, "a").authors)
        assert.are.equal(37, Catalog.get(catalog, "a").read_progress)
        assert.is_false(Catalog.get(catalog, "a").is_archived)
    end)

    it("summarises the catalog for the browser header", function()
        local catalog = Catalog.empty()
        Catalog.upsert(catalog, Catalog.entry_from_bookmark(bookmark({ id = "a", read_progress = 0 })))
        Catalog.upsert(
            catalog,
            Catalog.entry_from_bookmark(bookmark({ id = "b", read_progress = 50, is_marked = false }))
        )
        Catalog.upsert(
            catalog,
            Catalog.entry_from_bookmark(bookmark({
                id = "c",
                is_archived = true,
                is_marked = false,
                site_name = "Other",
                labels = { "lua" },
            }))
        )
        catalog.synced_at = "2026-08-23T09:12:44Z"

        local stats = Catalog.stats(catalog)
        assert.are.equal(3, stats.total)
        assert.are.equal(1, stats.unread)
        assert.are.equal(1, stats.archived)
        assert.are.equal(1, stats.favorite)
        assert.are.equal(3, stats.labels)
        assert.are.equal(2, stats.sources)
        assert.are.equal("2026-08-23T09:12:44Z", stats.synced_at)
    end)
end)

describe("readeck.browse.catalog invalidation", function()
    local function stored(overrides)
        local data = { version = Catalog.VERSION, entries = { a = { id = "a" } } }
        for key, value in pairs(overrides or {}) do
            data[key] = value
        end
        return data
    end

    it("discards a catalog belonging to a different account", function()
        local data = stored({ server_url = "https://rd", owner = "user-1" })
        assert.are.equal(0, Catalog.count(Catalog.normalize(data, "https://rd", "user-2")))
        assert.are.equal(1, Catalog.count(Catalog.normalize(data, "https://rd", "user-1")))
    end)

    it("treats an unknown owner as unknown, not as different", function()
        -- The plugin cannot identify the account yet, so a missing owner on either side
        -- must not throw away a 50-request rebuild.
        assert.are.equal(1, Catalog.count(Catalog.normalize(stored({ owner = "user-1" }), nil, nil)))
        assert.are.equal(1, Catalog.count(Catalog.normalize(stored(), nil, "user-1")))
    end)

    it("stamps the server and owner it was loaded for", function()
        local catalog = Catalog.normalize(stored(), "https://rd", "user-1")
        assert.are.equal("https://rd", catalog.server_url)
        assert.are.equal("user-1", catalog.owner)
    end)

    it("keeps the sync cursor and etag across a round trip", function()
        local store = fake_store()
        local catalog = Catalog.empty()
        catalog.cursor = "2026-08-23T09:11:44Z"
        catalog.etag = 'W/"abc"'
        Catalog.save(store, catalog)
        local reloaded = Catalog.load(store)
        assert.are.equal("2026-08-23T09:11:44Z", reloaded.cursor)
        assert.are.equal('W/"abc"', reloaded.etag)
    end)

    it("clears without leaving a resurrectable backup", function()
        local store = fake_store()
        Catalog.save(store, Catalog.normalize(stored()))
        assert.are.equal(1, Catalog.count(Catalog.load(store)))

        local removed = {}
        assert.is_true(Catalog.clear(store, "/settings/readeck_catalog.lua", function(path)
            table.insert(removed, path)
        end))
        assert.are.equal(0, Catalog.count(Catalog.load(store)))
        -- LuaSettings:open() falls back to "<file>.old" on any read failure, so the
        -- backup has to go too or the previous account's catalog comes back.
        assert.are.same({ "/settings/readeck_catalog.lua.old" }, removed)
    end)

    it("survives a clear with no store or no path", function()
        assert.is_false(Catalog.clear(nil))
        assert.is_true(Catalog.clear(fake_store()))
    end)
end)
