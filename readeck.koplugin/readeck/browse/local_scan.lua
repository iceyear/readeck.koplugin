-- Reconstructs a browsable catalog from what is already on the device.
--
-- This is the degraded path: it runs only when there is no catalog yet AND no network,
-- so the browser can still show something instead of an empty screen. What it can
-- recover is limited to what the plugin persists locally -- labels, a lossy title from
-- the filename, and reading time -- so callers must tell the user which buckets are
-- unavailable rather than showing them as empty.
--
-- Pure and injection-based, like readeck.storage.metadata: the lfs and DocSettings
-- modules are passed in so the whole thing is testable without KOReader.

local LocalScan = {}

LocalScan.DEFAULT_READING_TIME_PREFIX = "Reading time:"

-- Sidecar keywords are newline-separated (readeck.storage.metadata joins with "\n").
-- Newline is the one character a Readeck label cannot contain, and KOReader's own
-- keyword editor treats the field as multi-line, so it round-trips cleanly.
function LocalScan.split_keywords(value)
    local result = {}
    if type(value) ~= "string" then
        return result
    end
    for keyword in value:gmatch("[^\n]+") do
        keyword = keyword:match("^%s*(.-)%s*$")
        if keyword ~= "" then
            table.insert(result, keyword)
        end
    end
    return result
end

local function managed_prefixes(reading_time_label)
    local prefixes = { LocalScan.DEFAULT_READING_TIME_PREFIX }
    if reading_time_label and reading_time_label ~= "" then
        table.insert(prefixes, reading_time_label .. ":")
    end
    return prefixes
end

local function is_managed(keyword, prefixes)
    for _, prefix in ipairs(prefixes) do
        if keyword:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-- The plugin's own "Reading time: 7 min" pseudo-keyword must not show up as a label.
-- It is only distinguishable by prefix, and the prefix is localised, so the caller
-- passes the translated word in.
function LocalScan.labels_from_keywords(keywords, reading_time_label)
    local prefixes = managed_prefixes(reading_time_label)
    local labels = {}
    for _, keyword in ipairs(LocalScan.split_keywords(keywords)) do
        if not is_managed(keyword, prefixes) then
            table.insert(labels, keyword)
        end
    end
    return labels
end

function LocalScan.reading_time_from_keywords(keywords, reading_time_label)
    local prefixes = managed_prefixes(reading_time_label)
    for _, keyword in ipairs(LocalScan.split_keywords(keywords)) do
        if is_managed(keyword, prefixes) then
            local minutes = keyword:match("(%d+)")
            if minutes then
                return tonumber(minutes)
            end
        end
    end
    return nil
end

-- Files are named "<title> [rd-id_<id>].epub". The title is lossy: getSafeFilename has
-- already stripped path-unsafe characters and truncated to 230 bytes.
function LocalScan.title_from_path(path, article_id_suffix)
    local name = tostring(path or ""):match("([^/\\]+)$") or ""
    name = name:gsub("%.epub$", "")
    local marker = name:find(article_id_suffix or " [rd-id_", 1, true)
    if marker then
        name = name:sub(1, marker - 1)
    end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then
        return nil
    end
    return name
end

-- One lfs.dir pass over the download directory, returning id -> path. The existing
-- Readeck:findLocalArticlePathByID does this scan per article; doing it once and keeping
-- the map is what makes opening the browser with a few thousand files affordable.
function LocalScan.scan_directory(lfs_module, directory, get_article_id)
    local found = {}
    if not (lfs_module and directory and directory ~= "" and get_article_id) then
        return found
    end
    if lfs_module.attributes(directory, "mode") ~= "directory" then
        return found
    end

    -- lfs.dir returns an iterator AND the directory handle it needs as its argument.
    -- Both have to survive the pcall and both have to reach the generic for: dropping
    -- the handle leaves the iterator to be called with nil, which raises "directory
    -- metatable expected, got nil" on the first step. `for entry in lfs.dir(dir) do`
    -- forwards both implicitly; going through pcall makes it explicit work.
    local ok, iterator, handle = pcall(lfs_module.dir, directory)
    if not ok or type(iterator) ~= "function" then
        return found
    end

    for entry in iterator, handle do
        if entry ~= "." and entry ~= ".." then
            local path = directory .. entry
            if lfs_module.attributes(path, "mode") == "file" then
                local id = get_article_id(path)
                if id and id ~= "" then
                    found[id] = path
                end
            end
        end
    end
    return found
end

-- Reads one sidecar's keywords. Both lookups are guarded: openSettingsFile can throw on a
-- malformed sidecar, and readSetting("custom_props") returns nil for a sidecar KOReader
-- wrote after the user cleared the last custom property.
function LocalScan.read_keywords(doc_settings_module, path)
    if not (doc_settings_module and path) then
        return nil
    end

    local ok, metadata_file = pcall(doc_settings_module.findCustomMetadataFile, doc_settings_module, path)
    if not ok or not metadata_file then
        return nil
    end

    local opened, settings = pcall(doc_settings_module.openSettingsFile, metadata_file)
    if not opened or type(settings) ~= "table" then
        return nil
    end

    local read_ok, keywords = pcall(function()
        local custom_props = settings:readSetting("custom_props")
        if type(custom_props) == "table" and custom_props.keywords then
            return custom_props.keywords
        end
        local doc_props = settings:readSetting("doc_props")
        if type(doc_props) == "table" then
            return doc_props.keywords
        end
        return nil
    end)
    if not read_ok then
        return nil
    end
    return keywords
end

-- Builds catalog entries for the files on disk. opts:
--   lfs, doc_settings, directory, get_article_id, article_id_suffix, reading_time_label
--
-- Returns entries (array) and a `limits` table naming what could not be recovered, so
-- the UI can say so instead of rendering a misleading empty bucket.
function LocalScan.build_fallback_catalog(opts)
    opts = opts or {}
    local paths = LocalScan.scan_directory(opts.lfs, opts.directory, opts.get_article_id)

    local entries = {}
    for id, path in pairs(paths) do
        local keywords = LocalScan.read_keywords(opts.doc_settings, path)
        table.insert(entries, {
            id = id,
            title = LocalScan.title_from_path(path, opts.article_id_suffix) or id,
            labels = LocalScan.labels_from_keywords(keywords, opts.reading_time_label),
            authors = {},
            reading_time = LocalScan.reading_time_from_keywords(keywords, opts.reading_time_label),
            -- Not recoverable from disk: the sync only ever downloads unarchived
            -- articles and persists neither the flag nor the source.
            is_archived = false,
            is_marked = false,
            read_progress = 0,
            type = "article",
            local_path = path,
            partial = true,
        })
    end
    table.sort(entries, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)

    -- Which buckets the fallback can answer honestly.
    local available = {
        all = true,
        labels = true,
        unread = false,
        archived = false,
        favorite = false,
        sources = false,
        collections = false,
    }
    return entries, available
end

return LocalScan
