package.path = "./readeck.koplugin/?.lua;" .. package.path

local Api = require("readeck.net.api")
local Filters = require("readeck.core.filters")

local function query_of(url)
    return url:match("%?(.*)$") or ""
end

describe("readeck.net.api browse queries", function()
    it("keeps the legacy key order for the sync filters", function()
        assert.are.equal(
            "limit=30&offset=0&is_archived=0&type=article&sort=-created",
            query_of(Api.bookmarks_query({
                limit = 30,
                offset = 0,
                is_archived = 0,
                type = "article",
                sort = "-created",
            }))
        )
    end)

    it("repeats array parameters instead of joining them", function()
        assert.are.equal("sort=-created&sort=title", query_of(Api.bookmarks_query({ sort = { "-created", "title" } })))
        assert.are.equal("type=article&type=video", query_of(Api.bookmarks_query({ type = { "article", "video" } })))
        assert.are.equal(
            "read_status=unread&read_status=reading",
            query_of(Api.bookmarks_query({ read_status = { "unread", "reading" } }))
        )
        assert.are.equal("id=abc&id=def", query_of(Api.bookmarks_query({ id = { "abc", "def" } })))
    end)

    it("quotes label terms when labels are given as a list", function()
        assert.are.equal(
            "labels=%22machine%20learning%22%20%22ai%22",
            query_of(Api.bookmarks_query({ labels = { "machine learning", "ai" } }))
        )
    end)

    it("passes a plain string labels filter through unquoted", function()
        assert.are.equal("labels=research%20notes", query_of(Api.bookmarks_query({ labels = "research notes" })))
    end)

    it("sends the include setting as quoted terms, which the browser matches exactly", function()
        -- The sync used to pass the raw setting string, which the server splits on spaces
        -- into AND-ed terms -- so a tag named "long read" quietly asked for two tags. Both
        -- sides now go through the same parser, so what is downloaded is what is listed.
        assert.are.equal(
            "labels=%22long%20read%22",
            query_of(Api.bookmarks_query({ labels = Filters.parse_label_list("  long read ") }))
        )
        assert.are.equal("/api/bookmarks", Api.bookmarks_query({ labels = Filters.parse_label_list("") }))
    end)

    it("escapes quotes and backslashes inside label terms", function()
        assert.are.equal('"say \\"hi\\"" "a\\\\b"', Api.encode_label_terms({ 'say "hi"', "a\\b" }))
    end)

    it("drops an empty label list rather than sending labels=", function()
        assert.is_nil(Api.encode_label_terms({}))
        assert.are.equal("/api/bookmarks", Api.bookmarks_query({ labels = {} }))
    end)

    -- A collection stores its label filter as this same expression, so the plugin has to be
    -- able to read one back to re-evaluate the collection offline.
    it("decodes a label expression back into plain names", function()
        assert.are.same({ "mgmt", "secops" }, Api.decode_label_terms("mgmt secops"))
        assert.are.same({ "mgmt", "secops" }, Api.decode_label_terms("  mgmt   secops  "))
        assert.are.same({ "multi word", "k8s" }, Api.decode_label_terms('"multi word" k8s'))
        assert.are.same({ "multi word" }, Api.decode_label_terms("'multi word'"))
        assert.are.same({}, Api.decode_label_terms(""))
        assert.are.same({}, Api.decode_label_terms(nil))
        assert.are.same({}, Api.decode_label_terms({ "not a string" }))
    end)

    it("round-trips whatever the encoder produced", function()
        local names = { 'say "hi"', "a\\b", "e ink", "rust" }
        assert.are.same(names, Api.decode_label_terms(Api.encode_label_terms(names)))
    end)

    -- Operators are dropped, not kept as text. The browser compares label names exactly, so
    -- a literal "-draft" would ask for a label nobody has and empty the collection; losing
    -- the restriction shows too much rather than nothing.
    it("drops terms that are operators rather than label names", function()
        assert.are.same({ "k8s" }, Api.decode_label_terms("-draft k8s"))
        assert.are.same({ "mgmt" }, Api.decode_label_terms("k8s* mgmt"))
        assert.are.same({ "k8s" }, Api.decode_label_terms("author:ada k8s"))
        assert.are.same({}, Api.decode_label_terms('-"multi word"'))
    end)

    it("closes an unterminated quote at the end of the expression", function()
        assert.are.same({ "multi word" }, Api.decode_label_terms('"multi word'))
    end)

    it("does not mutate the caller's filter table", function()
        local params = { labels = { "one" }, limit = 500 }
        Api.bookmarks_query(params)
        assert.are.same({ "one" }, params.labels)
        assert.are.equal(500, params.limit)
    end)

    it("emits boolean filters instead of dropping false", function()
        assert.are.equal("is_marked=true", query_of(Api.bookmarks_query({ is_marked = true })))
        assert.are.equal("is_marked=false", query_of(Api.bookmarks_query({ is_marked = false })))
        assert.are.equal("is_archived=false", query_of(Api.bookmarks_query({ is_archived = false })))
    end)

    it("clamps limit to the server maximum", function()
        assert.are.equal(100, Api.MAX_LIMIT)
        assert.are.equal("limit=100", query_of(Api.bookmarks_query({ limit = 500 })))
        assert.are.equal("limit=100", query_of(Api.bookmarks_query({ limit = 100 })))
        assert.are.equal("limit=99", query_of(Api.bookmarks_query({ limit = 99 })))
    end)

    it("supports the browse filters the buckets need", function()
        assert.are.equal(
            "offset=20&site=example.com&is_marked=true&has_labels=true&collection=abc123",
            query_of(Api.bookmarks_query({
                offset = 20,
                site = "example.com",
                is_marked = true,
                has_labels = true,
                collection = "abc123",
            }))
        )
        assert.are.equal("search=rust%20async", query_of(Api.bookmarks_query({ search = "rust async" })))
    end)

    it("returns a bare path when no filters are set", function()
        assert.are.equal("/api/bookmarks", Api.bookmarks_query())
        assert.are.equal("/api/bookmarks", Api.bookmarks_query({}))
    end)

    it("exposes the browse endpoints", function()
        assert.are.equal("/api/bookmarks/labels", Api.paths.labels)
        assert.are.equal("/api/bookmarks/collections", Api.paths.collections)
        assert.are.equal("/api/bookmarks/sync", Api.paths.sync)
    end)

    it("builds sync URLs with an optional cursor", function()
        assert.are.equal("/api/bookmarks/sync", Api.sync_query())
        assert.are.equal("/api/bookmarks/sync", Api.sync_query(""))
        assert.are.equal("/api/bookmarks/sync?since=2026-08-23T10%3A00%3A00Z", Api.sync_query("2026-08-23T10:00:00Z"))
    end)
end)

describe("readeck.net.api pagination", function()
    it("reads the Readeck pagination headers", function()
        assert.are.same(
            { total_count = 137, total_pages = 5, current_page = 2 },
            Api.pagination({ ["total-count"] = "137", ["total-pages"] = "5", ["current-page"] = "2" })
        )
    end)

    it("tolerates canonical header casing and missing headers", function()
        assert.are.same({ total_count = 4 }, Api.pagination({ ["Total-Count"] = "4" }))
        assert.are.same({}, Api.pagination({}))
        assert.are.same({}, Api.pagination(nil))
    end)

    it("decides whether to fetch another page", function()
        assert.is_true(Api.has_next_page({ current_page = 1, total_pages = 3 }, 100))
        assert.is_false(Api.has_next_page({ current_page = 3, total_pages = 3 }, 300))
        assert.is_true(Api.has_next_page({ total_count = 137 }, 100))
        assert.is_false(Api.has_next_page({ total_count = 137 }, 137))
        assert.is_false(Api.has_next_page({}, 0))
        assert.is_false(Api.has_next_page(nil, 0))
    end)
end)
