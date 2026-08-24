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

    describe("age_in_hours", function()
        it("measures the distance from a timestamp to the given now", function()
            local now = Dates.parse("2024-01-02T06:00:00Z")
            assert.are.equal(30, Dates.age_in_hours("2024-01-01T00:00:00Z", now))
        end)

        it("returns nil for anything it cannot parse", function()
            assert.is_nil(Dates.age_in_hours("never", os.time()))
            assert.is_nil(Dates.age_in_hours(nil, os.time()))
        end)
    end)

    describe("humanize_age", function()
        local function L(text)
            return text
        end
        local function T(format, value)
            return format:gsub("%%1", tostring(value))
        end

        it("stays coarse below an hour", function()
            assert.are.equal("just now", Dates.humanize_age(0, L, T))
            assert.are.equal("just now", Dates.humanize_age(0.9, L, T))
        end)

        it("counts whole hours up to two days", function()
            assert.are.equal("1 hours ago", Dates.humanize_age(1, L, T))
            assert.are.equal("47 hours ago", Dates.humanize_age(47.9, L, T))
        end)

        it("switches to days at 48 hours", function()
            assert.are.equal("2 days ago", Dates.humanize_age(48, L, T))
            assert.are.equal("3 days ago", Dates.humanize_age(80, L, T))
        end)

        it("treats a missing age as brand new rather than erroring", function()
            assert.are.equal("just now", Dates.humanize_age(nil, L, T))
        end)
    end)
end)
