package.path = "./readeck.koplugin/?.lua;" .. package.path

local Status = require("readeck.status")

describe("readeck.status", function()
    it("adds action counters", function()
        local counts = Status.new_counts({ remote_archived = 1 })
        Status.add(counts, { remote_archived = 2, local_removed = 3 })

        assert.are.equal(3, counts.remote_archived)
        assert.are.equal(3, counts.local_removed)
        assert.are.equal(0, counts.remote_deleted)
    end)

    it("merges processed article ID sets", function()
        local counts = Status.new_counts()
        Status.add(counts, { processed_article_ids = { abc = true } })
        Status.add(counts, { processed_article_ids = { def = true } })

        assert.is_true(counts.processed_article_ids.abc)
        assert.is_true(counts.processed_article_ids.def)
    end)
end)
