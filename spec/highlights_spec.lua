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
end)
