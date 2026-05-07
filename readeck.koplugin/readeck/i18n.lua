local I18n = {}

local language_modules = {
    ["zh"] = "readeck.i18n.zh_cn",
    ["zh-cn"] = "readeck.i18n.zh_cn",
    ["zh-hans"] = "readeck.i18n.zh_cn",
    ["zh-sg"] = "readeck.i18n.zh_cn",
    ["zh-tw"] = "readeck.i18n.zh_cn",
    ["zh-hant"] = "readeck.i18n.zh_cn",
}

local language_cache = {}
local override_language = ""

local function load_language(language)
    local module_name = language_modules[language]
    if not module_name then
        return nil
    end
    if language_cache[module_name] == nil then
        local ok, translations = pcall(require, module_name)
        language_cache[module_name] = ok and translations or false
    end
    return language_cache[module_name] or nil
end

function I18n.normalize_language(language)
    if type(language) ~= "string" or language == "" or language == "C" then
        return "en"
    end
    language = language:gsub("_", "-"):lower()
    if language == "zh" or language:match("^zh%-hans") or language:match("^zh%-cn") or language:match("^zh%-sg") then
        return "zh-cn"
    end
    if
        language:match("^zh%-hant")
        or language:match("^zh%-tw")
        or language:match("^zh%-hk")
        or language:match("^zh%-mo")
    then
        return "zh-tw"
    end
    if language:match("^zh") then
        return "zh-cn"
    end
    return "en"
end

function I18n.set_language_override(language)
    if type(language) ~= "string" or language == "" or language == "auto" then
        override_language = ""
    else
        override_language = I18n.normalize_language(language)
    end
end

function I18n.current_language(reader_settings, gettext)
    if override_language ~= "" then
        return override_language
    end
    local language
    if reader_settings and type(reader_settings.readSetting) == "function" then
        language = reader_settings:readSetting("language")
    end
    if (not language or language == "") and type(gettext) == "table" then
        language = gettext.current_lang
    end
    return I18n.normalize_language(language)
end

function I18n.translate(message, gettext, reader_settings)
    if
        override_language ~= "en"
        and (
            type(gettext) == "function"
            or (type(gettext) == "table" and getmetatable(gettext) and getmetatable(gettext).__call)
        )
    then
        local translated = gettext(message)
        if translated ~= message then
            return translated
        end
    end

    local translations = load_language(I18n.current_language(reader_settings, gettext))
    if translations then
        return translations[message] or message
    end
    return message
end

function I18n.with_gettext(gettext, reader_settings_provider)
    return function(message)
        local reader_settings = reader_settings_provider
        if type(reader_settings_provider) == "function" then
            reader_settings = reader_settings_provider()
        end
        return I18n.translate(message, gettext, reader_settings)
    end
end

return I18n
