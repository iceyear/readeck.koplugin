package.path = "./readeck.koplugin/?.lua;" .. package.path

local Scheduler = require("readeck.scheduler")

describe("readeck.scheduler", function()
    it("limits asynchronous work to the configured concurrency", function()
        local scheduled = {}
        local running = 0
        local peak_running = 0
        local results = {}

        local function schedule(callback)
            table.insert(scheduled, callback)
        end

        Scheduler.run({ "a", "b", "c" }, {
            max_concurrent = 2,
            schedule = schedule,
            worker = function(item, done)
                running = running + 1
                peak_running = math.max(peak_running, running)
                table.insert(scheduled, function()
                    running = running - 1
                    done(item .. "-done")
                end)
                return Scheduler.ASYNC
            end,
            on_result = function(item, result)
                table.insert(results, item .. ":" .. result)
            end,
        })

        while #scheduled > 0 do
            local callback = table.remove(scheduled, 1)
            callback()
        end

        assert.are.equal(2, peak_running)
        assert.are.same({ "a:a-done", "b:b-done", "c:c-done" }, results)
    end)

    it("reports synchronous worker errors as failed results", function()
        local results = {}

        Scheduler.run({ "a" }, {
            worker = function()
                error("boom")
            end,
            on_result = function(_, result)
                table.insert(results, result.error:match("boom"))
            end,
        })

        assert.are.same({ "boom" }, results)
    end)
end)
