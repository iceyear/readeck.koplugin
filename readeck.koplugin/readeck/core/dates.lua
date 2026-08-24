local Dates = {}

local function days_from_civil(year, month, day)
    year = year - (month <= 2 and 1 or 0)
    local era = math.floor((year >= 0 and year or year - 399) / 400)
    local yoe = year - era * 400
    local month_adjusted = month + (month > 2 and -3 or 9)
    local doy = math.floor((153 * month_adjusted + 2) / 5) + day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function timegm(year, month, day, hour, min, sec)
    return days_from_civil(year, month, day) * 86400 + hour * 3600 + min * 60 + sec
end

function Dates.parse(value, dateparser)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    if dateparser and type(dateparser.parse) == "function" then
        local ok, parsed = pcall(dateparser.parse, value)
        if ok and type(parsed) == "number" then
            return parsed
        end
    end

    local year, month, day, hour, min, sec, tz
    year, month, day, hour, min, sec = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)%.?%d*([Zz]?)$")
    if year then
        return timegm(tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(min), tonumber(sec))
    end

    year, month, day, hour, min, sec, tz =
        value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)%.?%d*([%+%-]%d%d:?%d%d)$")
    if year then
        local timestamp =
            timegm(tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(min), tonumber(sec))
        local sign, offset_hour, offset_min = tz:match("^([%+%-])(%d%d):?(%d%d)$")
        local offset = tonumber(offset_hour) * 3600 + tonumber(offset_min) * 60
        if sign == "+" then
            timestamp = timestamp - offset
        else
            timestamp = timestamp + offset
        end
        return timestamp
    end

    year, month, day, hour, min, sec = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)")
    if year then
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec),
        })
    end

    year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if year then
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = 0,
            min = 0,
            sec = 0,
        })
    end

    return nil
end

-- Formats an epoch timestamp as strict RFC3339 in UTC with a trailing "Z".
--
-- That exact form matters for the Readeck sync cursor: a "+HH:MM" offset in a query
-- string is decoded server-side as a space, which makes the whole request a 422.
function Dates.to_rfc3339(timestamp)
    timestamp = tonumber(timestamp)
    if timestamp == nil then
        return nil
    end
    return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(timestamp))
end

-- Hours between an RFC3339 timestamp and now, or nil when it cannot be parsed. Used to
-- decide whether the catalog is stale enough to say so in the browser subtitle.
function Dates.age_in_hours(value, now)
    local timestamp = Dates.parse(value)
    if timestamp == nil then
        return nil
    end
    return ((now or os.time()) - timestamp) / 3600
end

-- Coarse, translatable age. Deliberately not minute-accurate: the only question the
-- browser asks is "is this list old enough that I should refresh before trusting it".
function Dates.humanize_age(hours, L, T)
    hours = tonumber(hours) or 0
    if hours >= 48 then
        return T(L("%1 days ago"), math.floor(hours / 24))
    end
    if hours >= 1 then
        return T(L("%1 hours ago"), math.floor(hours))
    end
    return L("just now")
end

function Dates.article_timestamp(article, dateparser)
    if type(article) ~= "table" then
        return nil
    end
    return Dates.parse(article.created, dateparser)
        or Dates.parse(article.published, dateparser)
        or Dates.parse(article.updated, dateparser)
end

return Dates
