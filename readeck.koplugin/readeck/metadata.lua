local Metadata = {}

local MANAGED_READING_TIME_PREFIX = "Reading time:"

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function split_keywords(value)
    local result = {}
    if type(value) ~= "string" then
        return result
    end
    for keyword in value:gmatch("[^\n]+") do
        local trimmed = trim(keyword)
        if trimmed ~= "" then
            table.insert(result, trimmed)
        end
    end
    return result
end

function Metadata.reading_time_keyword(minutes, label, minute_label)
    minutes = tonumber(minutes)
    if not minutes or minutes <= 0 then
        return nil
    end
    label = label or "Reading time"
    minute_label = minute_label or "min"
    return string.format("%s: %d %s", label, math.floor(minutes + 0.5), minute_label)
end

function Metadata.merge_keywords(existing, additions, managed_prefixes)
    local result = {}
    local seen = {}
    managed_prefixes = managed_prefixes or { MANAGED_READING_TIME_PREFIX }

    local function is_managed(keyword)
        for _, prefix in ipairs(managed_prefixes) do
            if keyword:sub(1, #prefix) == prefix then
                return true
            end
        end
        return false
    end

    local function add(keyword)
        keyword = trim(keyword)
        if keyword ~= "" and not seen[keyword] then
            table.insert(result, keyword)
            seen[keyword] = true
        end
    end

    for _, keyword in ipairs(split_keywords(existing)) do
        if not is_managed(keyword) then
            add(keyword)
        end
    end

    for _, keyword in ipairs(additions or {}) do
        add(keyword)
    end

    return table.concat(result, "\n")
end

function Metadata.article_keywords(article, existing_keywords, labels)
    labels = labels or {}
    local additions = {}

    if type(article) == "table" and type(article.labels) == "table" then
        for _, label in ipairs(article.labels) do
            table.insert(additions, label)
        end
    end

    if type(article) == "table" then
        local reading_time = Metadata.reading_time_keyword(article.reading_time, labels.reading_time, labels.minute)
        if reading_time then
            table.insert(additions, reading_time)
        end
    end

    local managed_prefixes = { MANAGED_READING_TIME_PREFIX }
    if labels.reading_time then
        table.insert(managed_prefixes, labels.reading_time .. ":")
    end

    return Metadata.merge_keywords(existing_keywords, additions, managed_prefixes)
end

function Metadata.save_article_keywords(doc_settings_module, path, article, labels)
    if not (doc_settings_module and path and article) then
        return false
    end

    local custom_metadata_file = doc_settings_module:findCustomMetadataFile(path)
    local settings
    if custom_metadata_file then
        settings = doc_settings_module.openSettingsFile(custom_metadata_file)
    else
        settings = doc_settings_module.openSettingsFile()
    end

    local doc_props = settings:readSetting("doc_props", {}) or {}
    settings:saveSetting("doc_props", doc_props)

    local custom_props = settings:readSetting("custom_props", {}) or {}
    local keywords = Metadata.article_keywords(article, custom_props.keywords or doc_props.keywords, labels)
    if keywords ~= "" then
        custom_props.keywords = keywords
        settings:saveSetting("custom_props", custom_props)
        return settings:flushCustomMetadata(path)
    end

    return false
end

return Metadata
