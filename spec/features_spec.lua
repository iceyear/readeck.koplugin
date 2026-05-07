package.path = "./readeck.koplugin/?.lua;" .. package.path

local Features = require("readeck.core.features")

describe("readeck.core.features", function()
    it("detects advertised OAuth support", function()
        assert.is_true(Features.supports_oauth({ features = { "email", "oauth" } }))
        assert.is_false(Features.supports_oauth({ features = { "email" } }))
        assert.is_nil(Features.supports_oauth({}))
    end)

    it("returns the canonical server version", function()
        assert.are.equal("0.22.2", Features.version({ version = { canonical = "0.22.2", release = "0.22" } }))
    end)

    it("compares semantic server versions", function()
        assert.is_true(Features.version_at_least({ version = { canonical = "0.22.2" } }, "0.22.2"))
        assert.is_true(Features.version_at_least({ version = { canonical = "0.23.0" } }, "0.22.2"))
        assert.is_false(Features.version_at_least({ version = { canonical = "0.22.1" } }, "0.22.2"))
    end)

    it("builds a highlight payload profile from server capabilities", function()
        assert.are.same(
            { notes = true, none_color = true },
            Features.highlight_payload_profile({ version = { canonical = "0.22.2" } })
        )
        assert.are.same(
            { notes = false, none_color = false },
            Features.highlight_payload_profile({ version = { canonical = "0.22.1" } })
        )
    end)
end)
