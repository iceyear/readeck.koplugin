package.path = "./readeck.koplugin/?.lua;" .. package.path

-- Assign stubs directly: other specs may have left different ones behind.
package.loaded["ui/bidi"] = {
    url = function(url)
        return url
    end,
}
package.loaded["ui/widget/infomessage"] = {
    new = function(_, options)
        return options or {}
    end,
}
package.loaded["ui/uimanager"] = {
    show = function() end,
    setDirty = function() end,
}
package.loaded["readeck.ui.wikipedia"] = nil

local Wikipedia = require("readeck.ui.wikipedia")

describe("readeck.ui.wikipedia", function()
    describe("article_url", function()
        it("builds a canonical article URL", function()
            assert.are.equal("https://en.wikipedia.org/wiki/E-reader", Wikipedia.article_url("en", "E-reader"))
        end)

        it("replaces spaces with underscores and lowercases the language", function()
            assert.are.equal(
                "https://fr.wikipedia.org/wiki/Victor_Hugo",
                Wikipedia.article_url("FR", "  Victor   Hugo ")
            )
        end)

        it("keeps parentheses and colons but percent-encodes reserved and non-ASCII characters", function()
            assert.are.equal(
                "https://en.wikipedia.org/wiki/Mercury_(planet)",
                Wikipedia.article_url("en", "Mercury (planet)")
            )
            assert.are.equal(
                "https://en.wikipedia.org/wiki/Portal:Science%3F%23%26",
                Wikipedia.article_url("en", "Portal:Science?#&")
            )
            assert.are.equal("https://de.wikipedia.org/wiki/K%C3%B6ln", Wikipedia.article_url("de", "Köln"))
        end)

        it("returns nil without a language or title", function()
            assert.is_nil(Wikipedia.article_url(nil, "E-reader"))
            assert.is_nil(Wikipedia.article_url("en", nil))
            assert.is_nil(Wikipedia.article_url("en", ""))
            assert.is_nil(Wikipedia.article_url("en", "   "))
        end)
    end)

    describe("place_in_layout", function()
        it("joins the vocabulary builder row when it exists", function()
            local layout = {
                { "vocabulary" },
                { "prev_dict", "highlight", "next_dict" },
                { "wikipedia", "search", "close" },
            }
            assert.is_true(Wikipedia.place_in_layout(layout, "readeck", "vocabulary"))
            assert.are.same({ "vocabulary", "readeck" }, layout[1])
            assert.are.equal(3, #layout)
        end)

        it("adds a shared first row when the vocabulary button is not placed yet", function()
            local layout = {
                { "prev_dict", "highlight", "next_dict" },
                { "wikipedia", "search", "close" },
            }
            Wikipedia.place_in_layout(layout, "readeck", "vocabulary")
            assert.are.same({ "vocabulary", "readeck" }, layout[1])
            assert.are.equal(3, #layout)
        end)

        it("is idempotent", function()
            local layout = { { "vocabulary" } }
            Wikipedia.place_in_layout(layout, "readeck", "vocabulary")
            Wikipedia.place_in_layout(layout, "readeck", "vocabulary")
            assert.are.same({ { "vocabulary", "readeck" } }, layout)
        end)

        it("ignores a missing layout", function()
            assert.is_false(Wikipedia.place_in_layout(nil, "readeck", "vocabulary"))
        end)
    end)

    describe("balancing_prefix", function()
        local function count(text, char)
            local _, n = text:gsub(char, "")
            return n
        end

        it("matches the target width with spaces and hair spaces", function()
            -- 23px target, 6px spaces, 1px hair spaces -> 3 spaces + 5 hair spaces
            local prefix = Wikipedia.balancing_prefix(23, 6, 1)
            assert.are.equal(3, count(prefix, Wikipedia.SPACE))
            assert.are.equal(5, count(prefix, Wikipedia.HAIR_SPACE))
        end)

        it("uses only regular spaces when they fit exactly", function()
            assert.are.equal("    ", Wikipedia.balancing_prefix(24, 6, 1))
        end)

        it("rounds to the nearest space when hair spaces are unavailable", function()
            assert.are.equal("    ", Wikipedia.balancing_prefix(22, 6, 0))
            assert.are.equal("   ", Wikipedia.balancing_prefix(20, 6, nil))
        end)

        it("returns an empty prefix for unusable measurements", function()
            assert.are.equal("", Wikipedia.balancing_prefix(0, 6, 1))
            assert.are.equal("", Wikipedia.balancing_prefix(10, 0, 1))
            assert.are.equal("", Wikipedia.balancing_prefix(nil, 6, 1))
        end)
    end)

    describe("after_popup_update", function()
        it("runs the hook after the popup's own update, once per call", function()
            local calls = {}
            local popup = {
                update = function(this, arg)
                    table.insert(calls, "update:" .. tostring(arg))
                    return this
                end,
            }
            assert.is_true(Wikipedia.after_popup_update(popup, function(this)
                assert.are.equal(popup, this)
                table.insert(calls, "hook")
            end))
            -- A second registration on the same popup is ignored.
            assert.is_false(Wikipedia.after_popup_update(popup, function()
                table.insert(calls, "second hook")
            end))
            assert.are.equal(popup, popup:update(1))
            popup:update(2)
            assert.are.same({ "update:1", "hook", "update:2", "hook" }, calls)
        end)

        it("does nothing when the popup has no update method", function()
            local popup = {}
            assert.is_false(Wikipedia.after_popup_update(popup, function() end))
            assert.is_nil(popup.update)
        end)

        it("contains hook errors", function()
            local reported
            local popup = {
                update = function()
                    return "updated"
                end,
            }
            Wikipedia.after_popup_update(popup, function()
                error("boom")
            end, function(err)
                reported = err
            end)
            assert.are.equal("updated", popup:update())
            assert.truthy(tostring(reported):find("boom"))
        end)
    end)

    describe("button label", function()
        local function new_plugin()
            local Readeck = {}
            local identity = function(text)
                return text
            end
            Wikipedia.install(Readeck, {
                L = identity,
                T = identity,
                Log = { warn = function() end, debug = function() end },
            })
            return Readeck
        end

        local function new_popup(results)
            local button = {
                text = "Readeck",
                setText = function(this, text)
                    this.text = text
                end,
            }
            local popup = {
                is_wiki = true,
                results = results,
                button_table = {
                    getButtonById = function(_, id)
                        return id == Wikipedia.BUTTON_ID and button or nil
                    end,
                },
                update = function() end,
            }
            function popup:changeDictionary(index)
                self.lookupword = self.results[index].word
                self.lang = self.results[index].lang
                self:update()
            end
            popup:changeDictionary(1)
            return popup, button
        end

        it("follows the shown result when swiping between results", function()
            local plugin = new_plugin()
            plugin.server_url = "https://readeck.example"
            plugin.wikipedia_saved_urls = { ["https://en.wikipedia.org/wiki/Mercury_(planet)"] = true }

            local popup, button = new_popup({
                { word = "Mercury (planet)", lang = "en" },
                { word = "Mercury (element)", lang = "en" },
            })
            -- Simulate what KOReader does when building the popup.
            local spec
            plugin.ui = {
                dictionary = {
                    default_layout = {},
                    addToDictButtons = function(_, s)
                        spec = s
                    end,
                },
            }
            plugin:registerWikipediaButton()
            assert.is_true(spec.show_func(popup))
            button.text = spec.text_func()
            assert.are.equal("Readeck" .. Wikipedia.CHECKMARK, button.text)

            popup:changeDictionary(2)
            assert.are.equal("Readeck", button.text)

            popup:changeDictionary(1)
            assert.are.equal("Readeck" .. Wikipedia.CHECKMARK, button.text)
        end)

        it("balances the checkmark with an invisible prefix in KOReader", function()
            -- Fake TextWidget: checkmark 14px, space 5px, hair space 1px.
            local widths = { [Wikipedia.CHECKMARK] = 14, [Wikipedia.SPACE] = 5, [Wikipedia.HAIR_SPACE] = 1 }
            local previous = package.loaded["ui/widget/textwidget"]
            package.loaded["ui/widget/textwidget"] = {
                new = function(_, options)
                    return {
                        getSize = function()
                            return { w = widths[options.text] or 0 }
                        end,
                        free = function() end,
                    }
                end,
            }
            finally(function()
                package.loaded["ui/widget/textwidget"] = previous
            end)

            local plugin = new_plugin()
            plugin.wikipedia_saved_urls = { ["https://en.wikipedia.org/wiki/Mercury_(planet)"] = true }
            local popup, button = new_popup({ { word = "Mercury (planet)", lang = "en" } })
            button.label_widget = { face = {} }

            plugin:refreshWikipediaButton(popup)
            local expected = string.rep(Wikipedia.SPACE, 2)
                .. string.rep(Wikipedia.HAIR_SPACE, 4)
                .. "Readeck"
                .. Wikipedia.CHECKMARK
            assert.are.equal(expected, button.text)
        end)
    end)
end)
