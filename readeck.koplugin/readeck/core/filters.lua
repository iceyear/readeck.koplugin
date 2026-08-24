-- Which bookmarks the synchronisation settings admit.
--
-- The sync has always applied three rules: the server enforces the include label and the
-- article type, and `filterIgnoredTags` drops anything carrying an excluded label. The
-- browser has to apply them itself, because the catalog mirrors the whole server rather
-- than one sync's scope. Both go through this module, so the list the browser shows and
-- the list the sync downloads can never disagree about what the user asked to leave out.
--
-- Pure: no KOReader requires and no plugin state, so it is directly testable.

local Filters = {}

-- Readeck types every bookmark as article, video or photo. A video bookmark is a link to
-- something the device cannot play and has no readable text to paginate, so the browser
-- hides it. Photos are deliberately left visible: the sync's `type=article` query drops
-- them, but they do carry a page worth reading, and nothing was asked about them.
Filters.HIDDEN_TYPES = { video = true }

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A comma-separated list of label names: trimmed, de-duplicated, empties dropped.
--
-- The trimming matters. `filterIgnoredTags` used to split on commas alone, so "work, later"
-- ignored a label named `work` and one named ` later` -- which no server ever sends. Every
-- caller now shares this parser, so the settings dialog's own comma-and-space phrasing
-- finally does what it says.
function Filters.parse_label_list(text)
    local names, seen = {}, {}
    for chunk in tostring(text or ""):gmatch("[^,]+") do
        local name = trim(chunk)
        if name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end
    return names
end

local function lookup_of(names)
    local set = {}
    for _, name in ipairs(names or {}) do
        set[name] = true
    end
    return set
end

local function has_label(entry, label)
    for _, name in ipairs(entry.labels or {}) do
        if name == label then
            return true
        end
    end
    return false
end

-- `settings` is the plugin itself in production and a plain table in the specs; only
-- `filter_tag` and `ignore_tags` are read.
function Filters.rules_from(settings)
    settings = settings or {}
    local exclude = Filters.parse_label_list(settings.ignore_tags)
    return {
        hidden_types = Filters.HIDDEN_TYPES,
        -- AND-combined, which is what the server does with the quoted terms the sync
        -- sends it. One tag is the ordinary case; a list narrows further.
        include = Filters.parse_label_list(settings.filter_tag),
        exclude = exclude,
        exclude_lookup = lookup_of(exclude),
    }
end

-- The first excluded label the entry carries, or nil. Split out of `admits` so the sync
-- can keep naming the offending tag in its debug log.
function Filters.excluded_label(entry, rules)
    local lookup = (rules or {}).exclude_lookup
    if not lookup then
        return nil
    end
    for _, name in ipairs(entry.labels or {}) do
        if lookup[name] then
            return name
        end
    end
    return nil
end

-- A nil `rules` admits everything, which is how the browser's toggle switches the whole
-- hide off without any caller growing a branch.
function Filters.admits(entry, rules)
    if type(entry) ~= "table" then
        return false
    end
    if rules == nil then
        return true
    end
    if (rules.hidden_types or {})[entry.type] then
        return false
    end
    for _, name in ipairs(rules.include or {}) do
        if not has_label(entry, name) then
            return false
        end
    end
    return Filters.excluded_label(entry, rules) == nil
end

-- Returns the admitted entries and how many were dropped. The count is not a diagnostic:
-- the browser puts it in its subtitle, because an article missing from a list the user
-- expected it on has to be explainable.
function Filters.apply(entries, rules)
    if rules == nil then
        return entries or {}, 0
    end
    local kept, hidden = {}, 0
    for _, entry in ipairs(entries or {}) do
        if Filters.admits(entry, rules) then
            table.insert(kept, entry)
        else
            hidden = hidden + 1
        end
    end
    return kept, hidden
end

return Filters
