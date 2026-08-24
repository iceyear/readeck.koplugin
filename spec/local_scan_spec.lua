package.path = "./readeck.koplugin/?.lua;" .. package.path

local LocalScan = require("readeck.browse.local_scan")

local SUFFIX = " [rd-id_"

-- Minimal stand-ins for KOReader's lfs and DocSettings, built from a virtual tree.
local function fake_lfs(tree)
    return {
        attributes = function(path, what)
            local node = tree[path]
            if node == nil then
                return nil
            end
            if what == "mode" then
                return node.mode
            end
            return node
        end,
        -- Modelled on real LuaFileSystem, not on a bare closure: lfs.dir returns an
        -- iterator plus the directory handle the iterator needs as its argument, and it
        -- raises when called without one. Reproducing that here is what makes a caller
        -- who forwards only the function fail in the spec instead of on the device.
        dir = function(directory)
            local names = {}
            for path, node in pairs(tree) do
                if node.parent == directory then
                    table.insert(names, path:match("([^/]+)$"))
                end
            end
            table.sort(names)
            table.insert(names, 1, "..")
            table.insert(names, 1, ".")
            local handle = { index = 0 }
            local function iterator(state)
                if state ~= handle then
                    error("directory metatable expected, got " .. type(state), 2)
                end
                state.index = state.index + 1
                return names[state.index]
            end
            return iterator, handle
        end,
    }
end

local function fake_doc_settings(sidecars)
    return {
        findCustomMetadataFile = function(_, path)
            if sidecars[path] == nil then
                return nil
            end
            return path .. ".sdr/metadata.epub.lua"
        end,
        openSettingsFile = function(metadata_file)
            local path = metadata_file:gsub("%.sdr/metadata%.epub%.lua$", "")
            local record = sidecars[path]
            if record == "throws" then
                error("malformed sidecar")
            end
            return {
                readSetting = function(_, key)
                    return record[key]
                end,
            }
        end,
    }
end

local function get_article_id(path)
    local start_pos = path:find(SUFFIX, 1, true)
    if not start_pos then
        return nil
    end
    local end_pos = path:find("]", start_pos)
    if not end_pos then
        return nil
    end
    return path:sub(start_pos + #SUFFIX, end_pos - 1)
end

describe("readeck.browse.local_scan keywords", function()
    it("splits newline-separated keywords", function()
        assert.are.same({ "e-ink", "machine learning" }, LocalScan.split_keywords("e-ink\nmachine learning"))
    end)

    it("keeps multi-word labels intact", function()
        -- The PoC split on ", " and on spaces, which shredded these.
        assert.are.same({ "machine learning" }, LocalScan.split_keywords("machine learning"))
        assert.are.same({ "a, b" }, LocalScan.split_keywords("a, b"))
    end)

    it("trims blank lines and whitespace", function()
        assert.are.same({ "one", "two" }, LocalScan.split_keywords("\n one \n\n  two  \n"))
        assert.are.same({}, LocalScan.split_keywords(""))
        assert.are.same({}, LocalScan.split_keywords(nil))
        assert.are.same({}, LocalScan.split_keywords({}))
    end)

    it("hides the managed reading-time pseudo-keyword", function()
        local keywords = "e-ink\nReading time: 7 min\nlua"
        assert.are.same({ "e-ink", "lua" }, LocalScan.labels_from_keywords(keywords))
        assert.are.equal(7, LocalScan.reading_time_from_keywords(keywords))
    end)

    it("hides the localised reading-time pseudo-keyword too", function()
        local keywords = "e-ink\n\230\152\130\232\175\187: 12 \229\136\134\233\146\159"
        local label = "\230\152\130\232\175\187"
        assert.are.same({ "e-ink" }, LocalScan.labels_from_keywords(keywords, label))
        assert.are.equal(12, LocalScan.reading_time_from_keywords(keywords, label))
        -- Without the translation it is indistinguishable from a real label.
        assert.are.equal(2, #LocalScan.labels_from_keywords(keywords))
    end)

    it("returns no reading time when there is no managed keyword", function()
        assert.is_nil(LocalScan.reading_time_from_keywords("e-ink\nlua"))
        assert.is_nil(LocalScan.reading_time_from_keywords(nil))
    end)
end)

describe("readeck.browse.local_scan titles", function()
    it("recovers the title from the filename", function()
        assert.are.equal(
            "Why e-ink is slow",
            LocalScan.title_from_path("/mnt/onboard/readeck/Why e-ink is slow [rd-id_abc123].epub", SUFFIX)
        )
    end)

    it("returns nil for a file that is only an id", function()
        assert.is_nil(LocalScan.title_from_path("/x/ [rd-id_abc].epub", SUFFIX))
        assert.is_nil(LocalScan.title_from_path("", SUFFIX))
    end)

    it("leaves a filename with no id marker alone", function()
        assert.are.equal("Some book", LocalScan.title_from_path("/x/Some book.epub", SUFFIX))
    end)
end)

describe("readeck.browse.local_scan directory scan", function()
    local tree = {
        ["/rd/"] = { mode = "directory" },
        ["/rd/Alpha [rd-id_aaa].epub"] = { mode = "file", parent = "/rd/" },
        ["/rd/Beta [rd-id_bbb].epub"] = { mode = "file", parent = "/rd/" },
        ["/rd/Not a readeck book.epub"] = { mode = "file", parent = "/rd/" },
        ["/rd/Gamma [rd-id_ccc].sdr"] = { mode = "directory", parent = "/rd/" },
    }

    it("maps article ids to paths in one pass", function()
        local found = LocalScan.scan_directory(fake_lfs(tree), "/rd/", get_article_id)
        assert.are.same({
            aaa = "/rd/Alpha [rd-id_aaa].epub",
            bbb = "/rd/Beta [rd-id_bbb].epub",
        }, found)
    end)

    it("skips directories and unrelated files", function()
        local found = LocalScan.scan_directory(fake_lfs(tree), "/rd/", get_article_id)
        assert.is_nil(found.ccc)
    end)

    it("returns nothing for a missing or unset directory", function()
        assert.are.same({}, LocalScan.scan_directory(fake_lfs(tree), "/nope/", get_article_id))
        assert.are.same({}, LocalScan.scan_directory(fake_lfs(tree), "", get_article_id))
        assert.are.same({}, LocalScan.scan_directory(nil, "/rd/", get_article_id))
    end)
end)

describe("readeck.browse.local_scan sidecar reading", function()
    it("prefers custom_props keywords", function()
        local settings = fake_doc_settings({
            ["/rd/a.epub"] = { custom_props = { keywords = "e-ink" }, doc_props = { keywords = "stale" } },
        })
        assert.are.equal("e-ink", LocalScan.read_keywords(settings, "/rd/a.epub"))
    end)

    it("falls back to doc_props keywords", function()
        local settings = fake_doc_settings({ ["/rd/a.epub"] = { doc_props = { keywords = "from epub" } } })
        assert.are.equal("from epub", LocalScan.read_keywords(settings, "/rd/a.epub"))
    end)

    it("survives a sidecar with no custom_props at all", function()
        -- KOReader clears custom_props when the last custom property is removed, so
        -- indexing the result of readSetting("custom_props") would throw here.
        local settings = fake_doc_settings({ ["/rd/a.epub"] = {} })
        assert.is_nil(LocalScan.read_keywords(settings, "/rd/a.epub"))
    end)

    it("survives a malformed sidecar and a missing one", function()
        local settings = fake_doc_settings({ ["/rd/a.epub"] = "throws" })
        assert.is_nil(LocalScan.read_keywords(settings, "/rd/a.epub"))
        assert.is_nil(LocalScan.read_keywords(settings, "/rd/missing.epub"))
        assert.is_nil(LocalScan.read_keywords(nil, "/rd/a.epub"))
    end)
end)

describe("readeck.browse.local_scan fallback catalog", function()
    local tree = {
        ["/rd/"] = { mode = "directory" },
        ["/rd/Alpha [rd-id_aaa].epub"] = { mode = "file", parent = "/rd/" },
        ["/rd/Beta [rd-id_bbb].epub"] = { mode = "file", parent = "/rd/" },
    }
    local sidecars = {
        ["/rd/Alpha [rd-id_aaa].epub"] = {
            custom_props = { keywords = "e-ink\nmachine learning\nReading time: 7 min" },
        },
    }

    local function build()
        return LocalScan.build_fallback_catalog({
            lfs = fake_lfs(tree),
            doc_settings = fake_doc_settings(sidecars),
            directory = "/rd/",
            get_article_id = get_article_id,
            article_id_suffix = SUFFIX,
        })
    end

    it("recovers ids, titles, labels and reading time", function()
        local entries = build()
        assert.are.equal(2, #entries)
        assert.are.equal("aaa", entries[1].id)
        assert.are.equal("Alpha", entries[1].title)
        assert.are.same({ "e-ink", "machine learning" }, entries[1].labels)
        assert.are.equal(7, entries[1].reading_time)
        assert.are.equal("/rd/Alpha [rd-id_aaa].epub", entries[1].local_path)
    end)

    it("still lists a file with no sidecar", function()
        local entries = build()
        assert.are.equal("bbb", entries[2].id)
        assert.are.equal("Beta", entries[2].title)
        assert.are.same({}, entries[2].labels)
        assert.is_nil(entries[2].reading_time)
    end)

    it("marks entries partial so the UI does not treat them as authoritative", function()
        for _, entry in ipairs(build()) do
            assert.is_true(entry.partial)
        end
    end)

    it("reports which buckets it cannot answer", function()
        local _, available = build()
        assert.is_true(available.all)
        assert.is_true(available.labels)
        assert.is_false(available.archived)
        assert.is_false(available.favorite)
        assert.is_false(available.sources)
        assert.is_false(available.collections)
        assert.is_false(available.unread)
    end)

    it("returns an empty catalog when nothing is downloaded", function()
        local entries, available = LocalScan.build_fallback_catalog({})
        assert.are.same({}, entries)
        assert.is_false(available.sources)
    end)
end)
