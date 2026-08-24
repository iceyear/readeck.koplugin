local Api = {}

-- Readeck rejects limit > 100 with HTTP 404 instead of clamping it, so callers must stay
-- under the cap themselves (internal/server/pagination.go validates `gte:0 lte:100`).
Api.MAX_LIMIT = 100

-- Query parameters accepted by GET /api/bookmarks. The order is fixed so generated URLs
-- are deterministic; the first six must keep their positions because existing callers and
-- specs depend on the exact string they produce.
Api.BOOKMARK_QUERY_KEYS = {
    "limit",
    "offset",
    "is_archived",
    "type",
    "labels",
    "sort",
    "search",
    "title",
    "author",
    "site",
    "lang",
    "is_marked",
    "is_loaded",
    "has_errors",
    "has_labels",
    "has_notes",
    "read_status",
    "collection",
    "id",
    "range_start",
    "range_end",
    "seed",
}

-- Parameters Readeck binds from repeated query values rather than a single value.
-- Everything else is a scalar; `labels` in particular is one space-separated string.
Api.BOOKMARK_ARRAY_KEYS = {
    type = true,
    sort = true,
    read_status = true,
    id = true,
}

local function encode_query_value(value)
    if value == nil then
        value = ""
    end
    -- tostring() rather than `value or ""` so that boolean false encodes as "false"
    -- instead of collapsing to an empty (and therefore skipped) value.
    return (
        tostring(value):gsub("([^%w%-%._~])", function(char)
            return string.format("%%%02X", string.byte(char))
        end)
    )
end

local function append_param(parts, key, value)
    if value == nil or value == "" then
        return
    end
    table.insert(parts, key .. "=" .. encode_query_value(value))
end

function Api.build_query(params, keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = params[key]
        if type(value) == "table" and Api.BOOKMARK_ARRAY_KEYS[key] then
            for _, item in ipairs(value) do
                append_param(parts, key, item)
            end
        else
            append_param(parts, key, value)
        end
    end
    return table.concat(parts, "&")
end

-- Readeck parses `labels` as a mini search expression: terms are space separated and
-- combined with AND, `-term` negates and `term*` is a prefix match. Quoting every term
-- keeps multi-word labels intact and neutralises those operators, which is exactly what
-- the server does when it builds href_bookmarks (internal/bookmarks/dataset/labels.go).
function Api.encode_label_terms(labels)
    if type(labels) ~= "table" then
        return labels
    end
    local terms = {}
    for _, name in ipairs(labels) do
        name = tostring(name or "")
        if name ~= "" then
            table.insert(terms, '"' .. (name:gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"')
        end
    end
    if #terms == 0 then
        return nil
    end
    return table.concat(terms, " ")
end

-- The inverse: the plain label names a stored `labels` expression asks for.
--
-- A collection keeps its label filter as the raw expression rather than a list (the server
-- types it `Labels string`), so reproducing a collection offline means reading that syntax
-- back. It lives next to the encoder because the two have to agree about quoting, and the
-- scan mirrors internal/searchstring/searchstring.go: `\` before the delimiter or before
-- itself yields that character, any other escape keeps both, and whitespace inside a quoted
-- term collapses to one space.
--
-- Operators are dropped rather than kept as text. `Facets.has_label` compares exactly, so a
-- literal `-draft` would ask for a label nobody has and empty the collection; dropping the
-- term loses a restriction instead, which is the direction that fails safely.
function Api.decode_label_terms(expression)
    if type(expression) ~= "string" then
        return {}
    end

    local names = {}
    local index, length = 1, #expression

    local function scan_quoted(delimiter)
        local chars = {}
        while index <= length do
            local char = expression:sub(index, index)
            index = index + 1
            if char == "\\" then
                local escaped = expression:sub(index, index)
                index = index + 1
                if escaped == delimiter or escaped == "\\" then
                    table.insert(chars, escaped)
                else
                    table.insert(chars, "\\" .. escaped)
                end
            elseif char == delimiter then
                break
            elseif char:match("%s") then
                table.insert(chars, " ")
            else
                table.insert(chars, char)
            end
        end
        return table.concat(chars)
    end

    -- Unquoted terms stop at `:` and `*` as well as whitespace, so the operator that
    -- follows is seen by the caller below rather than swallowed into the name.
    local function scan_bare()
        local from = index
        while index <= length do
            local char = expression:sub(index, index)
            if char:match("%s") or char == ":" or char == "*" then
                break
            end
            index = index + 1
        end
        return expression:sub(from, index - 1)
    end

    while index <= length do
        local char = expression:sub(index, index)
        if char:match("%s") then
            index = index + 1
        else
            local negated = false
            if char == "-" then
                negated = true
                index = index + 1
                char = expression:sub(index, index)
            end

            local name
            if char == '"' or char == "'" then
                index = index + 1
                name = scan_quoted(char)
            else
                name = scan_bare()
            end

            -- A trailing `*` is a prefix match and a `:` introduces a field-scoped term
            -- (`author:ada`); either way what precedes it is not a label name.
            local suffix = expression:sub(index, index)
            local dropped = negated or suffix == "*" or suffix == ":"
            while index <= length and expression:sub(index, index):match("[^%s]") do
                index = index + 1
            end

            if name ~= "" and not dropped then
                table.insert(names, name)
            end
        end
    end

    return names
end

Api.paths = {
    info = "/api/info",
    bookmarks = "/api/bookmarks",
    labels = "/api/bookmarks/labels",
    collections = "/api/bookmarks/collections",
    sync = "/api/bookmarks/sync",
    bookmark = function(id)
        return "/api/bookmarks/" .. tostring(id)
    end,
    bookmark_article = function(id)
        return "/api/bookmarks/" .. tostring(id) .. "/article.epub"
    end,
    annotations = function(id)
        return "/api/bookmarks/" .. tostring(id) .. "/annotations"
    end,
    annotation = function(bookmark_id, annotation_id)
        return "/api/bookmarks/" .. tostring(bookmark_id) .. "/annotations/" .. tostring(annotation_id)
    end,
}

function Api.bookmarks_query(params)
    params = params or {}

    local normalized = params
    local needs_copy = type(params.labels) == "table" or tonumber(params.limit or 0) > Api.MAX_LIMIT
    if needs_copy then
        normalized = {}
        for key, value in pairs(params) do
            normalized[key] = value
        end
        if type(params.labels) == "table" then
            normalized.labels = Api.encode_label_terms(params.labels)
        end
        if tonumber(normalized.limit or 0) > Api.MAX_LIMIT then
            normalized.limit = Api.MAX_LIMIT
        end
    end

    local query = Api.build_query(normalized, Api.BOOKMARK_QUERY_KEYS)
    if query == "" then
        return Api.paths.bookmarks
    end
    return Api.paths.bookmarks .. "?" .. query
end

function Api.sync_query(since)
    if since == nil or since == "" then
        return Api.paths.sync
    end
    return Api.paths.sync .. "?since=" .. encode_query_value(since)
end

-- Readeck paginates with response headers rather than a JSON envelope. socket.http
-- lowercases header names; normalise anyway so mock transports can use either casing.
function Api.pagination(headers)
    local result = {}
    if type(headers) ~= "table" then
        return result
    end
    local lowered = {}
    for key, value in pairs(headers) do
        lowered[tostring(key):lower()] = value
    end
    result.total_count = tonumber(lowered["total-count"])
    result.total_pages = tonumber(lowered["total-pages"])
    result.current_page = tonumber(lowered["current-page"])
    return result
end

-- Whether a paging loop should ask for another page. Defaults to false when the server
-- sends no pagination headers at all, so a missing header stops the loop instead of
-- spinning it forever.
function Api.has_next_page(pagination, fetched)
    pagination = pagination or {}
    if pagination.current_page and pagination.total_pages then
        return pagination.current_page < pagination.total_pages
    end
    if pagination.total_count then
        return (tonumber(fetched) or 0) < pagination.total_count
    end
    return false
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

function Api:list_labels()
    return self:request("GET", Api.paths.labels)
end

function Api:list_collections()
    return self:request("GET", Api.paths.collections)
end

function Api:sync_bookmarks(since)
    return self:request("GET", Api.sync_query(since))
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

function Api:update_annotation(bookmark_id, annotation_id, body)
    return self:request("PATCH", Api.paths.annotation(bookmark_id, annotation_id), body)
end

return Api
