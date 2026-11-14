local BD = require("ui/bidi")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")

local Wikipedia = {}

Wikipedia.BUTTON_ID = "readeck"
-- Share a row with KOReader's vocabulary builder button.
Wikipedia.ANCHOR_BUTTON_ID = "vocabulary"
-- UTF-8 byte escapes rather than \u{...}, which plain Lua 5.1 (used by the
-- test suite) doesn't understand.
-- U+2714 heavy check mark; KOReader UI fonts render it (its keyboards offer it too).
Wikipedia.CHECKMARK = " \226\156\148"
Wikipedia.SPACE = " "
-- U+200A hair space, for fine width adjustments.
Wikipedia.HAIR_SPACE = "\226\128\138"

local function encode_title(title)
    title = tostring(title or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "_")
    return (
        title:gsub("([^%w%-%._~:/()!$*@;,'])", function(char)
            return string.format("%%%02X", string.byte(char))
        end)
    )
end

--- Builds the canonical article URL for a Wikipedia lookup.
function Wikipedia.article_url(lang, title)
    if not lang or lang == "" or not title or title == "" then
        return nil
    end
    local encoded = encode_title(title)
    if encoded == "" then
        return nil
    end
    return string.format("https://%s.wikipedia.org/wiki/%s", tostring(lang):lower(), encoded)
end

--- Puts `button_id` in the same row as `anchor_id` in a DictQuickLookup layout.
-- If no row holds the anchor yet, a new first row `{ anchor_id, button_id }` is
-- inserted; that matches where the vocabulary builder puts its own button
-- (`insert_first`), and anchors that don't end up shown are dropped at render time.
function Wikipedia.place_in_layout(layout, button_id, anchor_id)
    if type(layout) ~= "table" then
        return false
    end
    local anchor_row
    for _, row in ipairs(layout) do
        for _, id in ipairs(row) do
            if id == button_id then
                return true
            end
            if id == anchor_id then
                anchor_row = row
            end
        end
    end
    if anchor_row then
        table.insert(anchor_row, button_id)
    else
        table.insert(layout, 1, { anchor_id, button_id })
    end
    return true
end

--- Runs `fn(popup)` after each `popup:update()` call.
-- Only this popup instance is wrapped (the DictQuickLookup class is untouched),
-- and if the popup has no update method nothing happens. Errors raised by `fn`
-- are passed to `on_error` so they can never break the popup itself.
function Wikipedia.after_popup_update(popup, fn, on_error)
    if popup._readeck_update_hooked or type(popup.update) ~= "function" then
        return false
    end
    local original_update = popup.update
    popup._readeck_update_hooked = true
    popup.update = function(this, ...)
        local result = original_update(this, ...)
        local ok, err = pcall(fn, this)
        if not ok and on_error then
            on_error(err)
        end
        return result
    end
    return true
end

--- Builds an invisible prefix about `target` pixels wide, from regular spaces
-- plus hair spaces for fine adjustment, so a suffix (the checkmark) can be
-- balanced and the label stays visually centered in the button.
function Wikipedia.balancing_prefix(target, space_width, hair_width)
    if not target or target <= 0 or not space_width or space_width <= 0 then
        return ""
    end
    local has_hair = hair_width and hair_width > 0
    local best_spaces, best_hairs, best_error = 0, 0, target
    for spaces = 0, math.ceil(target / space_width) do
        local rest = target - spaces * space_width
        local hairs = has_hair and math.max(0, math.floor(rest / hair_width + 0.5)) or 0
        local err = math.abs(rest - hairs * (has_hair and hair_width or 0))
        -- Prefer the closest width, then the fewest characters.
        if err < best_error or (err == best_error and spaces + hairs < best_spaces + best_hairs) then
            best_spaces, best_hairs, best_error = spaces, hairs, err
        end
    end
    return string.rep(Wikipedia.SPACE, best_spaces) .. string.rep(Wikipedia.HAIR_SPACE, best_hairs)
end

--- Returns a function measuring text width in pixels with the given font, or
-- nil outside KOReader.
local function text_measurer(face, bold)
    local ok, TextWidget = pcall(require, "ui/widget/textwidget")
    if not ok or not face then
        return nil
    end
    return function(text)
        local widget = TextWidget:new({ text = text, face = face, bold = bold })
        local width = widget:getSize().w
        widget:free()
        return width
    end
end

--- Measures text the way a freshly built dictionary popup button renders it
-- (plugin buttons get Button's default font face and size).
local function default_button_measurer()
    local ok_font, Font = pcall(require, "ui/font")
    local ok_button, Button = pcall(require, "ui/widget/button")
    if not ok_font or not ok_button then
        return nil
    end
    local ok_face, face = pcall(Font.getFace, Font, Button.text_font_face, Button.text_font_size)
    return ok_face and text_measurer(face, false) or nil
end

function Wikipedia.install(Readeck, deps)
    local L = deps.L
    local T = deps.T
    local Log = deps.Log

    -- `measure` (text -> pixel width) lets the checkmark be balanced with an
    -- invisible prefix of the same width; without it the label is left as is.
    local function button_text(saved, measure)
        if not saved then
            return L("Readeck")
        end
        local prefix = ""
        if measure then
            local ok, result = pcall(function()
                return Wikipedia.balancing_prefix(
                    measure(Wikipedia.CHECKMARK),
                    measure(Wikipedia.SPACE),
                    measure(Wikipedia.HAIR_SPACE)
                )
            end)
            if ok then
                prefix = result
            else
                Log:debug("Could not balance Wikipedia button label:", result)
            end
        end
        return prefix .. L("Readeck") .. Wikipedia.CHECKMARK
    end

    function Readeck:getWikipediaPopupURL(dict_popup)
        local lang = dict_popup.lang or (dict_popup.wiki_languages and dict_popup.wiki_languages[1])
        return Wikipedia.article_url(lang, dict_popup.lookupword)
    end

    function Readeck:isWikipediaArticleSaved(article_url)
        return article_url ~= nil
            and self.wikipedia_saved_urls ~= nil
            and self.wikipedia_saved_urls[article_url] == true
    end

    function Readeck:onWikipediaReadeckButton(dict_popup)
        local article_url = self:getWikipediaPopupURL(dict_popup)
        if not article_url then
            Log:warn("Could not build Wikipedia URL for", dict_popup.lookupword or "nil", dict_popup.lang or "nil")
            return
        end
        if self:isWikipediaArticleSaved(article_url) then
            UIManager:show(InfoMessage:new({
                text = T(L("Already added to Readeck:\n%1"), BD.url(article_url)),
                timeout = 2,
            }))
            return
        end

        local result = self:addArticleWithFeedback(article_url)
        if result ~= "added" and result ~= "queued" then
            return
        end

        self.wikipedia_saved_urls = self.wikipedia_saved_urls or {}
        self.wikipedia_saved_urls[article_url] = true
        self:refreshWikipediaButton(dict_popup)
    end

    --- Re-renders the button label for the result the popup is currently showing.
    function Readeck:refreshWikipediaButton(dict_popup)
        local button = dict_popup.button_table and dict_popup.button_table:getButtonById(Wikipedia.BUTTON_ID)
        if not button then
            return
        end
        local measure = button.label_widget and text_measurer(button.label_widget.face, button.text_font_bold)
        local text = button_text(self:isWikipediaArticleSaved(self:getWikipediaPopupURL(dict_popup)), measure)
        if button.text == text then
            return
        end
        button:setText(text, button.width)
        UIManager:setDirty(dict_popup, function()
            return "ui", button.dimen
        end)
    end

    function Readeck:registerWikipediaButton()
        local dictionary = self.ui and self.ui.dictionary
        if not dictionary or type(dictionary.addToDictButtons) ~= "function" then
            Log:debug("Dictionary button API unavailable; skipping Wikipedia button")
            return false
        end

        dictionary:addToDictButtons({
            id = Wikipedia.BUTTON_ID,
            -- KOReader's Button calls text_func() without arguments, so fall back to the
            -- popup captured by show_func, which runs just before the button is built.
            text_func = function(dict_popup)
                dict_popup = dict_popup or self._wikipedia_popup_in_build
                self._wikipedia_popup_in_build = nil
                local article_url = dict_popup and self:getWikipediaPopupURL(dict_popup)
                local saved = self:isWikipediaArticleSaved(article_url)
                return button_text(saved, saved and default_button_measurer() or nil)
            end,
            font_bold = false,
            show_func = function(dict_popup)
                local show = dict_popup.is_wiki == true
                    and not dict_popup.is_wiki_fullpage
                    and self.server_url ~= nil
                    and self.server_url ~= ""
                self._wikipedia_popup_in_build = show and dict_popup or nil
                if show then
                    -- Swiping between results calls update() without rebuilding the
                    -- buttons, so refresh our label afterwards.
                    Wikipedia.after_popup_update(dict_popup, function(popup)
                        self:refreshWikipediaButton(popup)
                    end, function(err)
                        Log:warn("Wikipedia button refresh failed:", err)
                    end)
                end
                return show
            end,
            callback = function(dict_popup)
                self:onWikipediaReadeckButton(dict_popup)
            end,
        })

        -- Wikipedia popups always render ReaderDictionary.default_layout (they ignore
        -- the user's customized dictionary layout), so placing our id there is enough.
        Wikipedia.place_in_layout(dictionary.default_layout, Wikipedia.BUTTON_ID, Wikipedia.ANCHOR_BUTTON_ID)
        return true
    end
end

return Wikipedia
