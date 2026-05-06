package.path = "./readeck.koplugin/?.lua;" .. package.path

local Api = require("readeck.api")

describe("readeck.api", function()
    it("builds bookmark list URLs", function()
        assert.are.equal(
            "/api/bookmarks?limit=30&offset=0&is_archived=0&type=article&labels=research%20notes&sort=-created",
            Api.bookmarks_query({
                limit = 30,
                offset = 0,
                is_archived = 0,
                type = "article",
                labels = "research notes",
                sort = "-created",
            })
        )
    end)

    it("can be tested with a mock Readeck transport", function()
        local requests = {}
        local client = Api.new(function(request)
            table.insert(requests, request)
            if request.path == Api.paths.info then
                return { version = { canonical = "0.22.2" }, features = { "oauth" } }
            end
            if request.path == Api.paths.annotations("abc") and request.method == "POST" then
                return { id = "annotation-id", note = request.body.note }
            end
            if request.path == Api.paths.bookmark_article("abc") then
                return "EPUB"
            end
            return true
        end)

        local info = client:get_info()
        local annotation = client:create_annotation("abc", { note = "reader note" })
        local epub = client:download_article("abc")

        assert.are.equal("0.22.2", info.version.canonical)
        assert.are.equal("reader note", annotation.note)
        assert.are.equal("EPUB", epub)
        assert.are.same({
            { method = "GET", path = "/api/info", headers = {} },
            {
                method = "POST",
                path = "/api/bookmarks/abc/annotations",
                body = { note = "reader note" },
                headers = {},
            },
            { method = "GET", path = "/api/bookmarks/abc/article.epub", headers = {} },
        }, requests)
    end)
end)
