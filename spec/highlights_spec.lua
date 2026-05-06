package.path = "./readeck.koplugin/?.lua;" .. package.path

local Highlights = require("readeck.highlights")

describe("readeck.highlights", function()
    it("builds Readeck annotation payloads with notes", function()
        local payload = Highlights.build_payload({
            drawer = "lighten",
            color = "green",
            text = "highlighted text",
            note = "reader note",
            pos0 = "/body/DocFragment/body/main/section/p[2]/text().4",
            pos1 = "/body/DocFragment/body/main/section/p[2]/text().18",
        })

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
end)
