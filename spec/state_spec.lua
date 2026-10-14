package.path = "./readeck.koplugin/?.lua;" .. package.path

package.preload["dispatcher"] = function()
    return {
        registerAction = function() end,
    }
end

local State = require("readeck.core.state")

describe("readeck.core.state sort options", function()
    local Readeck = {}
    State.install(Readeck, {
        L = function(text)
            return text
        end,
        Log = {
            setLevel = function(_, level)
                return level
            end,
        },
    })

    local function by_key(options)
        local result = {}
        for _, option in ipairs(options) do
            result[option[1]] = option[2]
        end
        return result
    end

    it("includes a random sort option for Readeck 0.23.0+", function()
        Readeck.server_info = { version = { canonical = "0.23.1" } }
        assert.are.equal("Random", by_key(Readeck:buildSortOptions())["random"])
    end)

    it("omits the random sort option for older servers", function()
        Readeck.server_info = { version = { canonical = "0.22.2" } }
        assert.is_nil(by_key(Readeck:buildSortOptions())["random"])
    end)

    it("omits the random sort option when the server version is unknown", function()
        Readeck.server_info = nil
        assert.is_nil(by_key(Readeck:buildSortOptions())["random"])
    end)

    it("falls back to the default sort when random is unsupported", function()
        Readeck.server_info = { version = { canonical = "0.22.2" } }
        Readeck.sort_param = "random"
        assert.are.equal("-created", Readeck:getEffectiveSortParam())

        Readeck.server_info = { version = { canonical = "0.23.1" } }
        assert.are.equal("random", Readeck:getEffectiveSortParam())
    end)
end)
