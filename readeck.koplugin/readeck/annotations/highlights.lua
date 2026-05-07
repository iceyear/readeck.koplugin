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

local KOREADER_HIGHLIGHT_COLORS = {
    blue = "blue",
    green = "green",
    none = "none",
    red = "red",
    yellow = "yellow",
}

local UNSAFE_BOUNDARY_ELEMENTS = {
    area = true,
    base = true,
    br = true,
    col = true,
    embed = true,
    hr = true,
    img = true,
    input = true,
    link = true,
    meta = true,
    param = true,
    source = true,
    track = true,
    wbr = true,
}

local function split_path(selector)
    local parts = {}
    for part in tostring(selector or ""):gmatch("[^/]+") do
        table.insert(parts, part)
    end
    return parts
end

function Highlights.selector_last_element(selector)
    local last
    for _, part in ipairs(split_path(selector)) do
        last = part
    end
    if not last then
        return nil
    end
    return tostring(last):match("^([^%[]+)"):lower()
end

function Highlights.is_safe_boundary_selector(selector)
    local element = Highlights.selector_last_element(selector)
    return element ~= nil and not UNSAFE_BOUNDARY_ELEMENTS[element]
end

function Highlights.selector_parent(selector)
    return tostring(selector or ""):match("^(.*)/[^/]+$") or ""
end

function Highlights.text_length(text)
    text = tostring(text or "")
    local count = 0
    for i = 1, #text do
        local byte = text:byte(i)
        if byte < 128 or byte >= 192 then
            count = count + 1
        end
    end
    return count
end

function Highlights.clean_selector(selector)
    if not selector then
        return ""
    end
    return tostring(selector)
        :gsub("/body/DocFragment/body/main/", "")
        :gsub("/text%(%)%[%d+%]$", "")
        :gsub("/text%(%)$", "")
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
    if not (h1 and h1.start_selector and h1.end_selector and h1.start_offset and h1.end_offset) then
        return false
    end
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

function Highlights.local_matches_remote_id(local_highlight, remote_highlight)
    return remote_highlight
        and remote_highlight.id
        and local_highlight
        and tostring(local_highlight.readeck_annotation_id or "") == tostring(remote_highlight.id)
end

function Highlights.remote_to_local_annotation(remote_highlight)
    if type(remote_highlight) ~= "table" then
        return nil, "invalid_annotation"
    end

    local start_selector = Highlights.clean_selector(remote_highlight.start_selector)
    local end_selector = Highlights.clean_selector(remote_highlight.end_selector)
    local start_offset = tonumber(remote_highlight.start_offset)
    local end_offset = tonumber(remote_highlight.end_offset)
    if start_selector == "" or end_selector == "" or start_offset == nil or end_offset == nil then
        return nil, "invalid_position"
    end

    if Highlights.compare_points(start_selector, start_offset, end_selector, end_offset) > 0 then
        start_selector, end_selector = end_selector, start_selector
        start_offset, end_offset = end_offset, start_offset
    end

    if
        not Highlights.is_safe_boundary_selector(start_selector)
        or not Highlights.is_safe_boundary_selector(end_selector)
    then
        return nil, "unsupported_selector"
    end

    local text = type(remote_highlight.text) == "string" and remote_highlight.text or ""
    local note = type(remote_highlight.note) == "string" and remote_highlight.note or nil
    if note == "" then
        note = nil
    end

    local datetime = remote_highlight.created or remote_highlight.updated
    if type(datetime) == "string" then
        datetime = datetime:gsub("T", " "):gsub("Z$", ""):gsub("%.%d+", "")
    else
        datetime = nil
    end

    local color = KOREADER_HIGHLIGHT_COLORS[tostring(remote_highlight.color or ""):lower()] or "yellow"
    local pos0 = start_selector .. "." .. tostring(start_offset)
    local pos1 = end_selector .. "." .. tostring(end_offset)

    return {
        page = pos0,
        pos0 = pos0,
        pos1 = pos1,
        text = text,
        datetime = datetime,
        drawer = "lighten",
        color = color,
        note = note,
        readeck_annotation_id = remote_highlight.id,
    }
end

function Highlights.build_payload(h, profile)
    profile = profile or {}
    if type(h) ~= "table" or not h.drawer or type(h.pos0) ~= "string" or type(h.pos1) ~= "string" then
        return nil, "invalid_annotation"
    end

    local start_selector, start_offset = h.pos0:match("(.*)%.(%d+)")
    local end_selector, end_offset = h.pos1:match("(.*)%.(%d+)")
    if not (start_selector and start_offset and end_selector and end_offset) then
        return nil, "invalid_position"
    end

    local s_offset = tonumber(start_offset)
    local e_offset = tonumber(end_offset)
    start_selector = Highlights.clean_selector(start_selector)
    end_selector = Highlights.clean_selector(end_selector)

    if start_selector == "" or end_selector == "" then
        return nil, "unsupported_selector"
    end

    if Highlights.compare_points(start_selector, s_offset, end_selector, e_offset) > 0 then
        start_selector, end_selector = end_selector, start_selector
        s_offset, e_offset = e_offset, s_offset
    end

    local text_length = Highlights.text_length(h.text)
    local same_parent = Highlights.selector_parent(start_selector) == Highlights.selector_parent(end_selector)
    if not Highlights.is_safe_boundary_selector(start_selector) then
        if same_parent and Highlights.is_safe_boundary_selector(end_selector) then
            start_selector = end_selector
            s_offset = math.max(0, e_offset - text_length)
        else
            return nil, "unsupported_selector"
        end
    end
    if not Highlights.is_safe_boundary_selector(end_selector) then
        if same_parent and Highlights.is_safe_boundary_selector(start_selector) then
            end_selector = start_selector
            e_offset = s_offset + text_length
        else
            return nil, "unsupported_selector"
        end
    end

    local note = type(h.note) == "string" and h.note or ""
    if #note > 1024 then
        note = note:sub(1, 1024)
    end

    local color = READECK_HIGHLIGHT_COLORS[tostring(h.color or ""):lower()] or "yellow"
    if color == "none" and not profile.none_color then
        color = "yellow"
    end

    local payload = {
        text = h.text,
        color = color,
        start_selector = start_selector,
        start_offset = s_offset,
        end_selector = end_selector,
        end_offset = e_offset,
    }

    if profile.notes then
        payload.note = note
    end

    return payload
end

return Highlights
