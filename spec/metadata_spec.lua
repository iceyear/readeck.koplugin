package.path = "./readeck.koplugin/?.lua;" .. package.path

local Metadata = require("readeck.storage.metadata")

describe("readeck.storage.metadata", function()
    it("formats reading time keywords", function()
        assert.are.equal("Reading time: 7 min", Metadata.reading_time_keyword(6.6))
    end)

    it("merges labels and replaces managed reading time", function()
        local keywords = Metadata.article_keywords({
            labels = { "research", "later" },
            reading_time = 12,
        }, "research\nReading time: 5 min\nexisting")

        assert.are.equal("research\nexisting\nlater\nReading time: 12 min", keywords)
    end)

    it("supports translated reading time labels", function()
        local keywords = Metadata.article_keywords({
            reading_time = 3,
        }, "阅读时间: 1 分钟\nkeep", { reading_time = "阅读时间", minute = "分钟" })

        assert.are.equal("keep\n阅读时间: 3 分钟", keywords)
    end)
end)
