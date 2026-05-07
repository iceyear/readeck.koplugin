local Highlights = {}

local READECK_HIGHLIGHT_COLORS = {
    blue = "blue",
    cyan = "blue",
    gray = "yellow",
    green = "green",
    none = "none",
    olive = "green",
    orange = "yellow",
    purple = "blue",
    red = "red",
    yellow = "yellow",
}

local function split_path(selector)
    local parts = {}
    for part in tostring(selector or ""):gmatch("[^/]+") do
        table.insert(parts, part)
    end
    return parts
end

function Highlights.clean_selector(selector)
    if not selector then
        return ""
    end
    return tostring(selector):gsub("/body/DocFragment/body/main/", ""):gsub("/text%(%)$", "")
end

function Highlights.normalize_selector(selector)
    if not selector then
        return ""
    end

    local parts = {}
    for _, part in ipairs(split_path(selector)) do
        if not part:find("%[") then
            part = part .. "[1]"
        end
        table.insert(parts, part)
    end

    return table.concat(parts, "/"):gsub("%[(%d+)%]", function(d)
        return string.format("[%05d]", tonumber(d))
    end)
end

function Highlights.compare_points(s1, o1, s2, o2)
    local norm_s1 = Highlights.normalize_selector(s1)
    local norm_s2 = Highlights.normalize_selector(s2)

    if norm_s1 < norm_s2 then
        return -1
    end
    if norm_s1 > norm_s2 then
        return 1
    end

    o1 = tonumber(o1) or 0
    o2 = tonumber(o2) or 0
    if o1 < o2 then
        return -1
    end
    if o1 > o2 then
        return 1
    end
    return 0
end

function Highlights.overlap(h1, h2)
    if not (h2 and h2.start_selector and h2.end_selector and h2.start_offset and h2.end_offset) then
        return false
    end

    local h2_start_s, h2_start_o, h2_end_s, h2_end_o
    local clean_s1 = Highlights.clean_selector(h2.start_selector)
    local clean_s2 = Highlights.clean_selector(h2.end_selector)
    if Highlights.compare_points(clean_s1, h2.start_offset, clean_s2, h2.end_offset) <= 0 then
        h2_start_s, h2_start_o, h2_end_s, h2_end_o = clean_s1, h2.start_offset, clean_s2, h2.end_offset
    else
        h2_start_s, h2_start_o, h2_end_s, h2_end_o = clean_s2, h2.end_offset, clean_s1, h2.start_offset
    end

    local start1_before_end2 = Highlights.compare_points(h1.start_selector, h1.start_offset, h2_end_s, h2_end_o) < 0
    local start2_before_end1 = Highlights.compare_points(h2_start_s, h2_start_o, h1.end_selector, h1.end_offset) < 0

    return start1_before_end2 and start2_before_end1
end

function Highlights.build_payload(h)
    if type(h) ~= "table" or not h.drawer or type(h.pos0) ~= "string" or type(h.pos1) ~= "string" then
        return nil
    end

    local start_selector, start_offset = h.pos0:match("(.*)%.(%d+)")
    local end_selector, end_offset = h.pos1:match("(.*)%.(%d+)")
    if not (start_selector and start_offset and end_selector and end_offset) then
        return nil
    end

    local s_offset = tonumber(start_offset)
    local e_offset = tonumber(end_offset)
    start_selector = Highlights.clean_selector(start_selector)
    end_selector = Highlights.clean_selector(end_selector)

    if Highlights.compare_points(start_selector, s_offset, end_selector, e_offset) > 0 then
        start_selector, end_selector = end_selector, start_selector
        s_offset, e_offset = e_offset, s_offset
    end

    local note = type(h.note) == "string" and h.note or ""
    if #note > 1024 then
        note = note:sub(1, 1024)
    end

    local color = READECK_HIGHLIGHT_COLORS[tostring(h.color or ""):lower()] or "yellow"

    return {
        text = h.text,
        color = color,
        note = note,
        start_selector = start_selector,
        start_offset = s_offset,
        end_selector = end_selector,
        end_offset = e_offset,
    }
end

return Highlights
