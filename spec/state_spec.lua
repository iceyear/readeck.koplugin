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

    it("includes a random sort option", function()
        local by_key = {}
        for _, option in ipairs(Readeck:buildSortOptions()) do
            by_key[option[1]] = option[2]
        end

        assert.are.equal("Random", by_key["random"])
    end)
end)
