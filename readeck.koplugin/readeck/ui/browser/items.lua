-- Item-table builders for the article browser.
--
-- Pure: no KOReader requires, no plugin state. Every builder takes a `ctx` carrying the
-- translation helpers and the few lookups a row needs, so the whole module is unit
-- testable and the browser widget stays free of formatting logic.
--
-- ctx fields:
--   L(text)            -- translated string
--   T(format, ...)     -- template substitution
--   downloaded         -- {[article id] = local path}, from Readeck:scanDownloadedIDs()
--   local_progress(id) -- device reading percentage, or nil
--   local_status(id)   -- device reading status, or nil

local Facets = require("readeck.browse.facets")

local Items = {}

-- FontAwesome cloud, marking a row that is on the server but not on the device.
-- nerdfonts/symbols.ttf is a standard KOReader font fallback, so this renders without
-- any font setup on the plugin's side.
Items.CLOUD = "\u{F0C2}"

-- Narrow no-break space before the percent sign, the same separator KOReader's own book
-- lists use so the browser lines up with the file manager.
local NNBSP = "\u{202F}"

local function ctx_L(ctx)
    return ctx.L or function(text)
        return text
    end
end

local function ctx_T(ctx)
    return ctx.T
        or function(format, ...)
            local args = { ... }
            return (
                format:gsub("%%(%d)", function(index)
                    return tostring(args[tonumber(index)] or "")
                end)
            )
        end
end

function Items.is_downloaded(entry, ctx)
    return (ctx.downloaded or {})[entry.id] ~= nil
end

-- The merged percentage: server progress and device progress are both partial views
-- (readeck.browse.facets explains why), so the row shows whichever is further along.
function Items.progress_of(entry, ctx)
    return math.floor(Facets.effective_progress(entry, ctx) + 0.5)
end

function Items.format_reading_time(minutes, ctx)
    minutes = tonumber(minutes)
    if minutes == nil or minutes <= 0 then
        return nil
    end
    return ctx_T(ctx)(ctx_L(ctx)("%1 min"), math.floor(minutes + 0.5))
end

-- Built eagerly as a plain string rather than a mandatory_func closure: a catalog of a
-- few thousand articles would otherwise mean a few thousand live closures.
function Items.mandatory_for(entry, ctx)
    local parts = {}
    if not Items.is_downloaded(entry, ctx) then
        table.insert(parts, Items.CLOUD)
    end
    local progress = Items.progress_of(entry, ctx)
    if progress > 0 then
        table.insert(parts, string.format("%d%s%%", progress, NNBSP))
    end
    local reading_time = Items.format_reading_time(entry.reading_time, ctx)
    if reading_time then
        table.insert(parts, reading_time)
    end
    return table.concat(parts, "  ")
end

function Items.article_row(entry, ctx)
    return {
        text = entry.title or entry.id,
        mandatory = Items.mandatory_for(entry, ctx),
        -- Offline, a row that is not on the device cannot be opened at all.
        dim = (ctx.can_download == false and not Items.is_downloaded(entry, ctx)) or nil,
        entry = entry,
        kind = "article",
    }
end

function Items.articles(entries, ctx)
    local rows = {}
    for _, entry in ipairs(entries or {}) do
        table.insert(rows, Items.article_row(entry, ctx))
    end
    return rows
end

-- The seven top-level buckets, in the order the requirements list them. `counts` and
-- `available` are supplied by the caller; a bucket the current catalog cannot answer
-- (the offline sidecar fallback knows nothing about archived or favorite) is shown
-- dimmed with an explanation on tap rather than silently listing nothing.
Items.BUCKET_LABELS = {
    all = "All",
    unread = "Unread",
    archived = "Archived",
    favorite = "Favorite",
    collections = "Collections",
    labels = "By label",
    sources = "By source",
}

function Items.buckets(counts, available, ctx)
    local L = ctx_L(ctx)
    counts = counts or {}
    available = available or {}

    local rows = {}
    for _, bucket in ipairs(Facets.BUCKETS) do
        local usable = available[bucket] ~= false
        table.insert(rows, {
            text = L(Items.BUCKET_LABELS[bucket]),
            mandatory = usable and tostring(counts[bucket] or 0) or "–",
            dim = not usable or nil,
            bucket = bucket,
            unavailable = not usable or nil,
            kind = "bucket",
        })
    end
    return rows
end

-- The label drill-down screen. The first row always offers to stop refining, so the user
-- is never forced another level down to see what they have already narrowed to.
function Items.labels(candidates, matching, ctx)
    local L, T = ctx_L(ctx), ctx_T(ctx)
    local rows = {
        {
            text = T(L("Show %1 articles"), matching or 0),
            bold = true,
            kind = "show_matching",
        },
    }
    for _, facet in ipairs(candidates or {}) do
        table.insert(rows, {
            text = facet.name,
            mandatory = tostring(facet.count),
            -- A label present on every remaining article would not narrow anything.
            -- Still listed, because hiding it looks like the label disappeared.
            mandatory_dim = facet.count == matching or nil,
            label = facet.name,
            kind = "label",
        })
    end
    return rows
end

function Items.sources(facets)
    local rows = {}
    for _, facet in ipairs(facets or {}) do
        table.insert(rows, {
            text = facet.name,
            mandatory = tostring(facet.count),
            site = facet.name,
            kind = "source",
        })
    end
    return rows
end

-- Collections carrying a server-side full-text `search` cannot be reproduced exactly on
-- the device, which has no article text. Those are prefixed and counted on their other
-- filters only; the browser says so in the subtitle rather than quietly being wrong.
function Items.collections(collections, count_of)
    local rows = {}
    for _, collection in ipairs(collections or {}) do
        local filter, approximate = Facets.collection_filter(collection)
        table.insert(rows, {
            text = approximate and ("~ " .. collection.name) or collection.name,
            mandatory = tostring(count_of(filter)),
            collection = collection,
            filter = filter,
            approximate = approximate or nil,
            kind = "collection",
        })
    end
    return rows
end

-- A screen with nothing on it is indistinguishable from a screen that failed to load,
-- so an empty result gets one inert row saying which it is. `kind` is deliberately not
-- one the browser dispatches on, which makes the row unselectable without a flag.
function Items.empty_state(rows, text)
    if #rows > 0 then
        return rows
    end
    return { { text = text, dim = true, kind = "empty" } }
end

-- Breadcrumb for the title bar: "Unread › research › python".
function Items.breadcrumb(parts, separator)
    local kept = {}
    for _, part in ipairs(parts or {}) do
        if part ~= nil and part ~= "" then
            table.insert(kept, part)
        end
    end
    return table.concat(kept, separator or " › ")
end

return Items
