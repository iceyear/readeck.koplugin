local Features = {}

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

return Features
