-- Plans and applies catalog refreshes. Pure: it decides what to fetch and folds
-- responses into the catalog, but never touches the network itself -- readeck.browse.service
-- does that under Trapper.
--
-- The shape of this module follows what the server actually guarantees:
--
--   * GET /api/bookmarks/sync is an unpaginated {id, time, type} log, and it is the only
--     authoritative id census. It carries no metadata.
--   * GET /api/bookmarks does carry metadata but its offset paging is NOT stable: the
--     default order is `created DESC` with no id tiebreak, and on SQLite the sort key is
--     truncated to whole seconds, so a bulk-imported batch can share one key. Paging it
--     alone will silently skip and duplicate rows.
--
-- So the strategy is: take the id set from sync, hydrate metadata by paging, then
-- reconcile the two and backfill whatever paging missed via ?id= batches.

local Catalog = require("readeck.browse.catalog")
local Dates = require("readeck.core.dates")

local Refresh = {}

-- Readeck caps `limit` at 100 and answers 404 above it; limit=0 silently means 50.
Refresh.PAGE_SIZE = 100
Refresh.ID_BATCH_SIZE = 100

-- The sync read is a plain non-serialisable SELECT, and `updated` is stamped at write
-- time rather than commit time, so a transaction that stamped T1 but committed after our
-- query ran is invisible to us even though T1 < the max time we saw. Rewinding the cursor
-- past that window trades a few redundant rows for not losing writes; applying an update
-- twice is a no-op.
Refresh.CURSOR_SAFETY_SECONDS = 60

-- The baseline cursor for a full rebuild. It has to be a real RFC3339 timestamp: the
-- server binds `since` as a time and validates the result, so `since=0` fails to bind,
-- falls back to Go's year-1 zero time, and comes back 422 "invalid value" -- which is a
-- hard failure on the one request a first-ever refresh cannot do without. The Unix epoch
-- binds cleanly and is far enough back to mean "everything".
Refresh.BASELINE_CURSOR = "1970-01-01T00:00:00Z"

local function is_sync_item(item)
    return type(item) == "table"
        and type(item.id) == "string"
        and item.id ~= ""
        and (item.type == "update" or item.type == "delete")
end

-- Validates the sync log and finds the newest timestamp in it. The rows are ordered by a
-- lexicographic comparison across a UNION of two different serialisation formats, so the
-- first element is not reliably the maximum -- compute it over every row.
function Refresh.parse_sync_items(payload)
    local items, max_time = {}, nil
    if type(payload) ~= "table" then
        return items, nil
    end
    for _, item in ipairs(payload) do
        if is_sync_item(item) then
            -- Times are RFC3339Nano with a variable number of fractional digits
            -- (Go trims trailing zeros), so this must not be a fixed-width parse.
            local timestamp = Dates.parse(item.time)
            table.insert(items, { id = item.id, type = item.type, time = item.time, timestamp = timestamp })
            if timestamp and (max_time == nil or timestamp > max_time) then
                max_time = timestamp
            end
        end
    end
    return items, max_time
end

-- Folds a sync log into the catalog. Returns the ids that need metadata hydration and
-- the ids that were removed.
--
-- Deletes win ties: the UNION can carry both an `update` and a later `delete` row for one
-- id, and an id that is gone must not be queued for hydration.
function Refresh.apply_sync(catalog, items)
    local deleted_set = {}
    for _, item in ipairs(items or {}) do
        if item.type == "delete" then
            deleted_set[item.id] = true
        end
    end

    local removed = {}
    for id in pairs(deleted_set) do
        if Catalog.remove(catalog, id) then
            table.insert(removed, id)
        end
    end
    table.sort(removed)

    local stale, seen = {}, {}
    for _, item in ipairs(items or {}) do
        if item.type == "update" and not deleted_set[item.id] and not seen[item.id] then
            seen[item.id] = true
            local entry = Catalog.get(catalog, item.id)
            -- Re-fetch when we have never seen the article, or when the server's mtime
            -- has moved past the one we recorded. The `since` bound is inclusive, so the
            -- boundary rows come back on every call; skipping unchanged ones is what
            -- keeps a delta from turning into a full rehydration.
            if entry == nil or entry.updated == nil or entry.updated ~= item.time then
                table.insert(stale, item.id)
            end
        end
    end

    return { stale = stale, removed = removed }
end

-- Everything in the catalog that the census did not mention is gone. Only valid on a
-- complete census -- a `since`-bounded sync is a delta, and treating its absences as
-- deletions would wipe the library.
function Refresh.reconcile(catalog, items, complete_census)
    if not complete_census then
        return {}
    end
    local live = {}
    for _, item in ipairs(items or {}) do
        live[item.id] = true
    end
    local removed = {}
    for _, entry in ipairs(Catalog.all(catalog)) do
        if not live[entry.id] then
            Catalog.remove(catalog, entry.id)
            table.insert(removed, entry.id)
        end
    end
    return removed
end

function Refresh.cursor_from(max_time, margin)
    if max_time == nil then
        return nil
    end
    margin = margin or Refresh.CURSOR_SAFETY_SECONDS
    return Dates.to_rfc3339(max_time - margin)
end

function Refresh.batches(list, size)
    size = size or Refresh.ID_BATCH_SIZE
    local batches = {}
    for index, item in ipairs(list or {}) do
        local batch_index = math.floor((index - 1) / size) + 1
        batches[batch_index] = batches[batch_index] or {}
        table.insert(batches[batch_index], item)
    end
    return batches
end

-- Folds a page of bookmarks into the catalog. Matching is by the `id` field, never by
-- position: the ?id= route documents that it preserves the order the ids were given, but
-- the default `-created` sort overwrites that ordering on every API request.
function Refresh.hydrate(catalog, bookmarks)
    local count = 0
    for _, bookmark in ipairs(bookmarks or {}) do
        local entry = Catalog.entry_from_bookmark(bookmark)
        if entry then
            Catalog.upsert(catalog, entry)
            count = count + 1
        end
    end
    return count
end

-- Which ids the census knows about but the catalog still lacks metadata for, after
-- paging. These are the rows offset paging skipped.
function Refresh.missing_ids(catalog, items)
    local missing = {}
    for _, item in ipairs(items or {}) do
        if item.type == "update" and Catalog.get(catalog, item.id) == nil then
            table.insert(missing, item.id)
        end
    end
    return missing
end

-- Interprets a callAPI result for the sync endpoint.
--   304 -> nothing changed; leave the cursor exactly where it is.
--   422 -> the server rejected our persisted cursor, so it is corrupt; rebaseline
--          rather than retrying it forever.
--   404 -> the endpoint predates this server (sync arrived in Readeck 0.20.0); the
--          caller must fall back to a full page-through.
function Refresh.classify_sync_response(result, err, code)
    if code == 304 then
        return "unchanged"
    end
    if code == 422 then
        return "bad_cursor"
    end
    if code == 404 then
        return "unsupported"
    end
    if err or type(result) ~= "table" then
        return "error"
    end
    return "ok"
end

function Refresh.progress_fraction(done, total)
    total = tonumber(total)
    if total == nil or total <= 0 then
        return nil
    end
    local fraction = (tonumber(done) or 0) / total
    if fraction < 0 then
        return 0
    end
    if fraction > 1 then
        return 1
    end
    return fraction
end

return Refresh
