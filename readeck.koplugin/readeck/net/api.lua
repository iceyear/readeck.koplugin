local Api = {}

local function encode_query_value(value)
    return tostring(value or ""):gsub("([^%w%-%._~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function build_query(params, keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = params[key]
        if value ~= nil and value ~= "" then
            table.insert(parts, key .. "=" .. encode_query_value(value))
        end
    end
    return table.concat(parts, "&")
end

Api.paths = {
    info = "/api/info",
    bookmarks = "/api/bookmarks",
    bookmark = function(id)
        return "/api/bookmarks/" .. tostring(id)
    end,
    bookmark_article = function(id)
        return "/api/bookmarks/" .. tostring(id) .. "/article.epub"
    end,
    annotations = function(id)
        return "/api/bookmarks/" .. tostring(id) .. "/annotations"
    end,
}

function Api.bookmarks_query(params)
    params = params or {}
    local query = build_query(params, { "limit", "offset", "is_archived", "type", "labels", "sort" })
    if query == "" then
        return Api.paths.bookmarks
    end
    return Api.paths.bookmarks .. "?" .. query
end

function Api.new(transport)
    return setmetatable({ transport = transport }, { __index = Api })
end

function Api:request(method, path, body, headers)
    return self.transport({
        method = method,
        path = path,
        body = body,
        headers = headers or {},
    })
end

function Api:get_info()
    return self:request("GET", Api.paths.info)
end

function Api:list_bookmarks(params)
    return self:request("GET", Api.bookmarks_query(params))
end

function Api:create_bookmark(body)
    return self:request("POST", Api.paths.bookmarks, body)
end

function Api:archive_bookmark(id, body)
    body = body or {}
    body.is_archived = true
    return self:request("PATCH", Api.paths.bookmark(id), body)
end

function Api:delete_bookmark(id)
    return self:request("DELETE", Api.paths.bookmark(id))
end

function Api:download_article(id)
    return self:request("GET", Api.paths.bookmark_article(id))
end

function Api:list_annotations(id)
    return self:request("GET", Api.paths.annotations(id))
end

function Api:create_annotation(id, body)
    return self:request("POST", Api.paths.annotations(id), body)
end

return Api
