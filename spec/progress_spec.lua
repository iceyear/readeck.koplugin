package.path = "./readeck.koplugin/?.lua;" .. package.path

local Progress = require("readeck.sync.progress")

describe("readeck.sync.progress", function()
    it("converts KOReader fractional progress to Readeck percent", function()
        assert.are.equal(37, Progress.percent_finished_to_readeck_progress(0.37))
        assert.are.equal(100, Progress.percent_finished_to_readeck_progress(1))
    end)

    it("clamps percent values", function()
        assert.are.equal(100, Progress.percent_finished_to_readeck_progress(120))
        assert.are.equal(0, Progress.percent_finished_to_readeck_progress(-1))
    end)

    it("converts Readeck progress to KOReader fractional progress", function()
        assert.are.equal(0.37, Progress.readeck_progress_to_percent_finished(37))
        assert.are.equal(1, Progress.readeck_progress_to_percent_finished(100))
        assert.are.equal(0, Progress.readeck_progress_to_percent_finished(-20))
    end)

    it("updates local progress only for newer incomplete remote progress", function()
        assert.is_true(Progress.should_update_local_percent(nil, 37))
        assert.is_true(Progress.should_update_local_percent(0.12, 37))
        assert.is_false(Progress.should_update_local_percent(0.42, 37))
        assert.is_false(Progress.should_update_local_percent(0.42, 100))
    end)

    it("updates remote progress only for newer incomplete local progress", function()
        assert.is_true(Progress.should_update_remote_percent(0.37, nil))
        assert.is_true(Progress.should_update_remote_percent(0.37, 12))
        assert.is_false(Progress.should_update_remote_percent(0.37, 42))
        assert.is_false(Progress.should_update_remote_percent(1, 42))
    end)
end)
