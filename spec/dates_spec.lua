package.path = "./readeck.koplugin/?.lua;" .. package.path

local Dates = require("readeck.core.dates")

describe("readeck.core.dates", function()
    it("parses UTC timestamps", function()
        assert.are.equal(1704067200, Dates.parse("2024-01-01T00:00:00Z"))
    end)

    it("parses timezone offsets", function()
        assert.are.equal(1704067200, Dates.parse("2024-01-01T02:00:00+0200"))
        assert.are.equal(1704067200, Dates.parse("2023-12-31T19:00:00-05:00"))
    end)

    it("uses created before published or updated for article timestamps", function()
        local article = {
            created = "2024-01-02T00:00:00Z",
            published = "2024-01-01T00:00:00Z",
            updated = "2024-01-03T00:00:00Z",
        }
        assert.are.equal(1704153600, Dates.article_timestamp(article))
    end)
end)
