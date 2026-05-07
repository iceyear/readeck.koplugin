describe("Readeck log levels", function()
    before_each(function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        package.loaded["readeck.core.log"] = nil
        package.loaded.logger = nil
    end)

    it("filters plugin log output by configured level", function()
        local calls = { info = 0, warn = 0, err = 0 }
        package.preload.logger = function()
            return {
                info = function()
                    calls.info = calls.info + 1
                end,
                warn = function()
                    calls.warn = calls.warn + 1
                end,
                err = function()
                    calls.err = calls.err + 1
                end,
            }
        end

        local Log = require("readeck.core.log")
        assert.are.equal("warn", Log:setLevel("warn"))

        Log:debug("debug")
        Log:info("info")
        Log:warn("warn")
        Log:error("error")

        assert.are.equal(0, calls.info)
        assert.are.equal(1, calls.warn)
        assert.are.equal(1, calls.err)
    end)
end)
