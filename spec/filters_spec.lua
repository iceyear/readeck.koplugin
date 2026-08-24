package.path = "./readeck.koplugin/?.lua;" .. package.path

local Filters = require("readeck.core.filters")

local function entry(t)
    t = t or {}
    return {
        id = t.id or "a",
        type = t.type or "article",
        labels = t.labels or {},
    }
end

describe("core filters", function()
    describe("parse_label_list", function()
        it("returns an empty list for nothing at all", function()
            assert.are.same({}, Filters.parse_label_list(nil))
            assert.are.same({}, Filters.parse_label_list(""))
            assert.are.same({}, Filters.parse_label_list(" , ,, "))
        end)

        it("splits on commas and trims each name", function()
            assert.are.same({ "work", "later", "long read" }, Filters.parse_label_list("work, later ,  long read "))
        end)

        it("drops duplicates so the lookup cannot double count", function()
            assert.are.same({ "work" }, Filters.parse_label_list("work, work , work"))
        end)

        it("keeps a single tag intact, which is the ordinary case", function()
            assert.are.same({ "news" }, Filters.parse_label_list("news"))
        end)
    end)

    describe("admits", function()
        it("admits everything when there are no rules", function()
            assert.is_true(Filters.admits(entry({ type = "video", labels = { "spam" } }), nil))
        end)

        it("hides video bookmarks", function()
            local rules = Filters.rules_from({})
            assert.is_false(Filters.admits(entry({ type = "video" }), rules))
            assert.is_true(Filters.admits(entry({ type = "article" }), rules))
        end)

        it("keeps photo bookmarks, which were not asked about", function()
            assert.is_true(Filters.admits(entry({ type = "photo" }), Filters.rules_from({})))
        end)

        it("requires every include label, AND-combined like the server", function()
            local rules = Filters.rules_from({ filter_tag = "work, urgent" })
            assert.is_true(Filters.admits(entry({ labels = { "work", "urgent", "x" } }), rules))
            assert.is_false(Filters.admits(entry({ labels = { "work" } }), rules))
            assert.is_false(Filters.admits(entry({ labels = {} }), rules))
        end)

        it("rejects an entry carrying any excluded label", function()
            local rules = Filters.rules_from({ ignore_tags = "spam, ads" })
            assert.is_false(Filters.admits(entry({ labels = { "news", "ads" } }), rules))
            assert.is_true(Filters.admits(entry({ labels = { "news" } }), rules))
        end)

        it("matches an excluded label the user typed with a leading space", function()
            local rules = Filters.rules_from({ ignore_tags = "spam, ads" })
            assert.are.equal("ads", Filters.excluded_label(entry({ labels = { "ads" } }), rules))
        end)

        it("rejects a non-table entry rather than raising", function()
            assert.is_false(Filters.admits(nil, Filters.rules_from({})))
        end)
    end)

    describe("apply", function()
        it("returns the survivors and how many were hidden", function()
            local entries = {
                entry({ id = "1", labels = { "news" } }),
                entry({ id = "2", type = "video" }),
                entry({ id = "3", labels = { "spam" } }),
                entry({ id = "4", labels = { "news", "spam" } }),
            }
            local kept, hidden = Filters.apply(entries, Filters.rules_from({ ignore_tags = "spam" }))
            assert.are.equal(1, #kept)
            assert.are.equal("1", kept[1].id)
            assert.are.equal(3, hidden)
        end)

        it("passes the list straight through with no rules", function()
            local entries = { entry({ type = "video" }) }
            local kept, hidden = Filters.apply(entries, nil)
            assert.are.equal(entries, kept)
            assert.are.equal(0, hidden)
        end)
    end)
end)
