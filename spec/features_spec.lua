package.path = "./readeck.koplugin/?.lua;" .. package.path

local Features = require("readeck.features")

describe("readeck.features", function()
    it("detects advertised OAuth support", function()
        assert.is_true(Features.supports_oauth({ features = { "email", "oauth" } }))
        assert.is_false(Features.supports_oauth({ features = { "email" } }))
        assert.is_nil(Features.supports_oauth({}))
    end)

    it("returns the canonical server version", function()
        assert.are.equal("0.22.2", Features.version({ version = { canonical = "0.22.2", release = "0.22" } }))
    end)
end)
