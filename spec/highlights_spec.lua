package.path = "./readeck.koplugin/?.lua;" .. package.path

local Highlights = require("readeck.annotations.highlights")

describe("readeck.annotations.highlights", function()
    it("builds Readeck annotation payloads with notes", function()
        local payload = Highlights.build_payload({
            drawer = "lighten",
            color = "green",
            text = "highlighted text",
            note = "reader note",
            pos0 = "/body/DocFragment/body/main/section/p[2]/text().4",
            pos1 = "/body/DocFragment/body/main/section/p[2]/text().18",
        }, { notes = true, none_color = true })

        assert.are.same({
            text = "highlighted text",
            color = "green",
            note = "reader note",
            start_selector = "section/p[2]",
            start_offset = 4,
            end_selector = "section/p[2]",
            end_offset = 18,
        }, payload)
    end)

    it("orders reversed selections", function()
        local payload = Highlights.build_payload({
            drawer = "underscore",
            text = "highlighted text",
            pos0 = "section/p[3].10",
            pos1 = "section/p[2].1",
        })

        assert.are.equal("section/p[2]", payload.start_selector)
        assert.are.equal(1, payload.start_offset)
        assert.are.equal("section/p[3]", payload.end_selector)
        assert.are.equal(10, payload.end_offset)
    end)

    it("maps KOReader highlight colors to Readeck colors", function()
        local payload = Highlights.build_payload({
            drawer = "lighten",
            color = "purple",
            text = "highlighted text",
            pos0 = "section/p[2].4",
            pos1 = "section/p[2].18",
        })

        assert.are.equal("blue", payload.color)
    end)

    it("omits notes and downgrades transparent color for legacy servers", function()
        local payload = Highlights.build_payload({
            drawer = "lighten",
            color = "none",
            text = "highlighted text",
            note = "reader note",
            pos0 = "section/p[2].4",
            pos1 = "section/p[2].18",
        }, { notes = false, none_color = false })

        assert.are.equal("yellow", payload.color)
        assert.is_nil(payload.note)
    end)

    it("keeps transparent color for modern servers", function()
        local payload = Highlights.build_payload({
            drawer = "lighten",
            color = "none",
            text = "highlighted text",
            pos0 = "section/p[2].4",
            pos1 = "section/p[2].18",
        }, { notes = true, none_color = true })

        assert.are.equal("none", payload.color)
    end)

    it("repairs highlights that start at a line break before text", function()
        local payload = Highlights.build_payload({
            drawer = "lighten",
            text = "让我们",
            pos0 = "section/section/div[2]/div[8]/div[3]/br.0",
            pos1 = "section/section/div[2]/div[8]/div[3]/span.3",
        })

        assert.are.equal("section/section/div[2]/div[8]/div[3]/span", payload.start_selector)
        assert.are.equal(0, payload.start_offset)
        assert.are.equal("section/section/div[2]/div[8]/div[3]/span", payload.end_selector)
        assert.are.equal(3, payload.end_offset)
    end)

    it("converts KOReader text node selectors to Readeck element selectors", function()
        local payload = Highlights.build_payload({
            drawer = "lighten",
            text = "edits",
            pos0 = "section/section/p[9]/text()[2].10",
            pos1 = "section/section/p[9]/text()[2].15",
        })

        assert.are.equal("section/section/p[9]", payload.start_selector)
        assert.are.equal("section/section/p[9]", payload.end_selector)
        assert.are.equal(10, payload.start_offset)
        assert.are.equal(15, payload.end_offset)
    end)

    it("skips void element boundaries that cannot be repaired", function()
        local payload, reason = Highlights.build_payload({
            drawer = "lighten",
            text = "highlighted text",
            pos0 = "section/p[1]/br.0",
            pos1 = "section/p[2]/span.5",
        })

        assert.is_nil(payload)
        assert.are.equal("unsupported_selector", reason)
    end)

    it("detects overlapping highlights", function()
        local local_highlight = Highlights.build_payload({
            drawer = "lighten",
            text = "local",
            pos0 = "section/p[2].4",
            pos1 = "section/p[2].18",
        })
        local remote_highlight = {
            start_selector = "section/p[2]",
            start_offset = 10,
            end_selector = "section/p[2]",
            end_offset = 20,
        }

        assert.is_true(Highlights.overlap(local_highlight, remote_highlight))
    end)

    it("converts Readeck annotations to KOReader rolling highlights", function()
        local annotation = Highlights.remote_to_local_annotation({
            id = "remote-id",
            text = "remote text",
            note = "remote note",
            color = "blue",
            start_selector = "/body/DocFragment/body/main/section/p[2]/text()",
            start_offset = 4,
            end_selector = "/body/DocFragment/body/main/section/p[2]/text()",
            end_offset = 15,
            created = "2026-05-06T17:47:45Z",
        })

        assert.are.same({
            page = "section/p[2].4",
            pos0 = "section/p[2].4",
            pos1 = "section/p[2].15",
            text = "remote text",
            note = "remote note",
            datetime = "2026-05-06 17:47:45",
            drawer = "lighten",
            color = "blue",
            readeck_annotation_id = "remote-id",
        }, annotation)
    end)

    it("stores sync snapshots when importing Readeck annotations", function()
        local annotation = Highlights.remote_to_local_annotation({
            id = "remote-id",
            text = "remote text",
            note = "remote note",
            color = "green",
            start_selector = "section/p[2]",
            start_offset = 4,
            end_selector = "section/p[2]",
            end_offset = 15,
        }, { notes = true, none_color = true })

        assert.are.equal("remote note", annotation.readeck_synced_note)
        assert.are.equal("green", annotation.readeck_synced_color)
        assert.is.truthy(annotation.readeck_synced_at)
    end)

    it("plans remote-only linked note and color updates for local annotations", function()
        local plan = Highlights.plan_linked_sync({
            note = "old note",
            color = "yellow",
            readeck_synced_note = "old note",
            readeck_synced_color = "yellow",
        }, {
            note = "remote note",
            color = "blue",
        }, { notes = true, none_color = true }, "merge")

        assert.are.same({ note = "remote note", color = "blue" }, plan.local_update)
        assert.is_nil(plan.remote_update)
        assert.is_false(plan.conflict)
    end)

    it("plans local-only linked note and color updates for Readeck", function()
        local plan = Highlights.plan_linked_sync({
            note = "local note",
            color = "green",
            readeck_synced_note = "old note",
            readeck_synced_color = "yellow",
        }, {
            note = "old note",
            color = "yellow",
        }, { notes = true, none_color = true }, "merge")

        assert.is_nil(plan.local_update)
        assert.are.same({ note = "local note", color = "green" }, plan.remote_update)
        assert.is_false(plan.conflict)
    end)

    it("merges note conflicts and lets local color win by default", function()
        local plan = Highlights.plan_linked_sync({
            note = "local note",
            color = "green",
            readeck_synced_note = "old note",
            readeck_synced_color = "yellow",
        }, {
            note = "remote note",
            color = "blue",
        }, { notes = true, none_color = true }, "merge")

        assert.is.truthy(plan.remote_update.note:find("KOReader note", 1, true))
        assert.is.truthy(plan.remote_update.note:find("Readeck note", 1, true))
        assert.are.equal("green", plan.remote_update.color)
        assert.are.same({ note = plan.remote_update.note }, plan.local_update)
        assert.is_true(plan.conflict)
    end)

    it("can force Readeck or KOReader to win linked highlight updates", function()
        local remote_wins = Highlights.plan_linked_sync({
            note = "local note",
            color = "green",
        }, {
            note = "remote note",
            color = "blue",
        }, { notes = true, none_color = true }, "remote_wins")

        assert.are.same({ note = "remote note", color = "blue" }, remote_wins.local_update)
        assert.is_nil(remote_wins.remote_update)

        local local_wins = Highlights.plan_linked_sync({
            note = "local note",
            color = "green",
        }, {
            note = "remote note",
            color = "blue",
        }, { notes = true, none_color = true }, "local_wins")

        assert.is_nil(local_wins.local_update)
        assert.are.same({ note = "local note", color = "green" }, local_wins.remote_update)
    end)
end)
