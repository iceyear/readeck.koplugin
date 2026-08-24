package.path = "./readeck.koplugin/?.lua;" .. package.path

local Items = require("readeck.ui.browser.items")

local function ctx(overrides)
    local base = {
        downloaded = {},
        local_progress = function() end,
        local_status = function() end,
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

local function entry(overrides)
    local base = { id = "a1", title = "An article", read_progress = 0 }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

describe("readeck.ui.browser.items", function()
    describe("mandatory_for", function()
        it("marks an article that is only on the server", function()
            local text = Items.mandatory_for(entry(), ctx())
            assert.is_truthy(text:find(Items.CLOUD, 1, true))
        end)

        it("drops the cloud marker once the article is on the device", function()
            local text = Items.mandatory_for(entry(), ctx({ downloaded = { a1 = "/books/a1.epub" } }))
            assert.is_nil(text:find(Items.CLOUD, 1, true))
        end)

        it("shows progress and reading time when both are known", function()
            local text = Items.mandatory_for(
                entry({ read_progress = 42, reading_time = 7 }),
                ctx({ downloaded = { a1 = "/books/a1.epub" } })
            )
            assert.is_truthy(text:find("42"))
            assert.is_truthy(text:find("7 min", 1, true))
        end)

        it("hides zero progress rather than showing 0%", function()
            local text = Items.mandatory_for(entry(), ctx({ downloaded = { a1 = "/books/a1.epub" } }))
            assert.are.equal("", text)
        end)

        it("prefers the device percentage when it is ahead of the server", function()
            local text = Items.mandatory_for(
                entry({ read_progress = 10 }),
                ctx({
                    downloaded = { a1 = "/books/a1.epub" },
                    local_progress = function()
                        return 65
                    end,
                })
            )
            assert.is_truthy(text:find("65"))
            assert.is_nil(text:find("10"))
        end)
    end)

    describe("article_row", function()
        it("dims an undownloaded article when downloading is impossible", function()
            local row = Items.article_row(entry(), ctx({ can_download = false }))
            assert.is_true(row.dim)
            assert.are.equal("article", row.kind)
        end)

        it("leaves a downloaded article usable offline", function()
            local row = Items.article_row(entry(), ctx({ can_download = false, downloaded = { a1 = "/a.epub" } }))
            assert.is_nil(row.dim)
        end)

        it("falls back to the id when an entry has no title", function()
            local row = Items.article_row({ id = "a9" }, ctx())
            assert.are.equal("a9", row.text)
        end)
    end)

    describe("buckets", function()
        it("lists the seven buckets in the documented order", function()
            local rows = Items.buckets({}, {}, ctx())
            local names = {}
            for _, row in ipairs(rows) do
                table.insert(names, row.bucket)
            end
            assert.are.same({ "all", "unread", "archived", "favorite", "collections", "labels", "sources" }, names)
        end)

        it("dims a bucket the current catalog cannot answer", function()
            local rows = Items.buckets({ all = 12 }, { archived = false }, ctx())
            assert.are.equal("12", rows[1].mandatory)
            assert.are.equal("–", rows[3].mandatory)
            assert.is_true(rows[3].dim)
            assert.is_true(rows[3].unavailable)
        end)
    end)

    describe("labels", function()
        it("offers to stop refining before listing any label", function()
            local rows = Items.labels({}, 8, ctx())
            assert.are.equal("show_matching", rows[1].kind)
            assert.is_truthy(rows[1].text:find("8"))
            assert.is_true(rows[1].bold)
        end)

        it("carries each label's count", function()
            local rows = Items.labels({ { name = "python", count = 3 } }, 8, ctx())
            assert.are.equal("label", rows[2].kind)
            assert.are.equal("python", rows[2].label)
            assert.are.equal("3", rows[2].mandatory)
            assert.is_nil(rows[2].mandatory_dim)
        end)

        it("dims a label that every remaining article already carries", function()
            local rows = Items.labels({ { name = "python", count = 8 } }, 8, ctx())
            assert.is_true(rows[2].mandatory_dim)
        end)
    end)

    describe("collections", function()
        it("marks a collection whose full-text search cannot be reproduced offline", function()
            local rows = Items.collections({
                { id = "c1", name = "Rust", filters = { labels = "rust" } },
                { id = "c2", name = "Notes", filters = { search = "kernel" } },
            }, function()
                return 4
            end)
            assert.are.equal("Rust", rows[1].text)
            assert.is_nil(rows[1].approximate)
            assert.are.equal("~ Notes", rows[2].text)
            assert.is_true(rows[2].approximate)
            assert.are.equal("4", rows[2].mandatory)
        end)
    end)

    describe("empty_state", function()
        it("leaves a populated list untouched", function()
            local rows = { { text = "a" } }
            assert.are.equal(rows, Items.empty_state(rows, "Nothing here."))
        end)

        it("explains an empty screen with one unselectable row", function()
            local rows = Items.empty_state({}, "Nothing here.")
            assert.are.equal(1, #rows)
            assert.are.equal("Nothing here.", rows[1].text)
            assert.is_true(rows[1].dim)
            assert.are.equal("empty", rows[1].kind)
        end)
    end)

    describe("breadcrumb", function()
        it("joins the parts it was given", function()
            assert.are.equal("Unread › research › python", Items.breadcrumb({ "Unread", "research", "python" }))
        end)

        it("skips empty segments so the separator never doubles up", function()
            assert.are.equal("Unread › python", Items.breadcrumb({ "Unread", "", "python" }))
        end)

        it("returns an empty string when there is nothing to show", function()
            assert.are.equal("", Items.breadcrumb(nil))
        end)
    end)
end)
