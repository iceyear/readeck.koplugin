local Features = {}

local function parse_version(version)
    version = tostring(version or "")
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.?(%d*)")
    if not major then
        return nil
    end
    return {
        tonumber(major) or 0,
        tonumber(minor) or 0,
        tonumber(patch) or 0,
    }
end

function Features.has_feature(info, feature)
    if type(info) ~= "table" or type(info.features) ~= "table" then
        return nil
    end
    for _, value in ipairs(info.features) do
        if value == feature then
            return true
        end
    end
    return false
end

function Features.supports_oauth(info)
    return Features.has_feature(info, "oauth")
end

function Features.version(info)
    if type(info) ~= "table" or type(info.version) ~= "table" then
        return nil
    end
    return info.version.canonical or info.version.release
end

function Features.version_at_least(info, target)
    local current = parse_version(Features.version(info))
    local expected = parse_version(target)
    if not current or not expected then
        return false
    end

    for i = 1, 3 do
        if current[i] > expected[i] then
            return true
        end
        if current[i] < expected[i] then
            return false
        end
    end
    return true
end

function Features.supports_annotation_notes(info)
    return Features.has_feature(info, "annotation_notes") == true or Features.version_at_least(info, "0.22.2")
end

function Features.supports_annotation_none_color(info)
    return Features.has_feature(info, "annotation_none_color") == true or Features.version_at_least(info, "0.22.2")
end

function Features.highlight_payload_profile(info)
    return {
        notes = Features.supports_annotation_notes(info),
        none_color = Features.supports_annotation_none_color(info),
    }
end

return Features
