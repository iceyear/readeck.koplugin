local plugin_dir = os.getenv("READECK_PLUGIN_DIR") or arg[1]
local server_url = os.getenv("READECK_MOCK_URL") or arg[2]
local expected_version = os.getenv("READECK_EXPECT_VERSION") or "0.22.2"
local legacy_annotations = os.getenv("READECK_EXPECT_LEGACY") == "1"
assert(plugin_dir and plugin_dir ~= "", "READECK_PLUGIN_DIR is required")
assert(server_url and server_url ~= "", "READECK_MOCK_URL is required")

package.path = "./?.lua;./?/init.lua;" .. plugin_dir .. "/?.lua;" .. package.path

dofile("setupkoenv.lua")
dofile("spec/front/unit/commonrequire.lua")

local Defaults = require("readeck.core.defaults")
local PluginMetadata = dofile(plugin_dir .. "/_meta.lua")
local Readeck = dofile(plugin_dir .. "/main.lua")
local FFIUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local socket = require("socket")

local version_path = expected_version:gsub("%W", "-")
local download_dir = "/tmp/readeck-network-probe-" .. version_path .. "-" .. tostring(os.time())
lfs.mkdir(download_dir)

local instance = setmetatable({}, { __index = Readeck })
Defaults.apply(instance)
instance.server_url = server_url
instance.directory = download_dir
instance.auth_token = "api-token"
instance.block_timeout = 5
instance.total_timeout = 10
instance.file_block_timeout = 5
instance.file_total_timeout = 10
instance.experimental_async_downloads = true
instance.highlight_sync_policy = "respect_remote_deletions"
instance.ui = {}
instance.rd_settings = {
    saveSetting = function() end,
    flush = function() end,
}
instance.saveSettings = function() end

assert(instance:getBearerToken() == true, "API token authentication failed")
assert(instance.access_token == "api-token", "API token was not cached as bearer token")

local info = instance:refreshServerInfo(true)
assert(info and info.version and info.version.canonical == expected_version, "server info request failed")

local oauth_context = instance:getOAuthDeviceAuthorizationContext()
assert(oauth_context and oauth_context.client_id == "mock-client", "OAuth client/device flow setup failed")
local oauth_token = instance:callOAuthFormAPI("/api/oauth/token", {
    grant_type = Defaults.OAUTH_DEVICE_GRANT,
    client_id = oauth_context.client_id,
    device_code = oauth_context.device_code,
})
assert(oauth_token and oauth_token.access_token == "oauth-access", "OAuth token request failed")

local articles = instance:getArticleList()
assert(type(articles) == "table" and #articles == 1, "bookmark list request failed")
local article_id = articles[1].id
assert(type(article_id) == "string" and article_id:match("^[A-Za-z0-9]+$"), "unexpected article id")

local subprocess_path = download_dir .. "/subprocess-download.epub"
local subprocess_job = instance:runSubprocessDownload(
    subprocess_path,
    server_url .. "/api/bookmarks/" .. article_id .. "/article.epub",
    instance.access_token
)
assert(subprocess_job, "subprocess downloader did not start")
local subprocess_deadline = socket.gettime() + 10
while not FFIUtil.isSubProcessDone(subprocess_job.pid) do
    assert(socket.gettime() < subprocess_deadline, "subprocess downloader timed out")
    socket.sleep(0.05)
end
local subprocess_result = instance:finishSubprocessDownload(subprocess_job, articles[1])
assert(subprocess_result == Defaults.DOWNLOAD_DONE, "subprocess article download failed")
assert(lfs.attributes(subprocess_path, "mode") == "file", "subprocess article file missing")

local download_result = instance:download(articles[1])
assert(download_result == Defaults.DOWNLOAD_DONE, "article download failed")
local downloaded_path = instance:findLocalArticlePathByID(article_id)
assert(downloaded_path and lfs.attributes(downloaded_path, "mode") == "file", "downloaded article file missing")

local local_annotations = {
    {
        drawer = "lighten",
        text = "local text",
        note = "local note",
        color = "none",
        pos0 = "section/p[2].4",
        pos1 = "section/p[2].14",
    },
    {
        readeck_annotation_id = "remote-existing",
        drawer = "lighten",
        text = "remote text",
        note = "updated local note",
        color = "green",
        readeck_synced_note = "remote note",
        readeck_synced_color = "yellow",
        pos0 = "section/p[1].0",
        pos1 = "section/p[1].11",
    },
    {
        readeck_annotation_id = "deleted-remotely",
        drawer = "lighten",
        text = "remote deleted",
        color = "yellow",
        pos0 = "section/p[3].0",
        pos1 = "section/p[3].14",
    },
}
local ok, counts = instance:syncHighlightsForArticle(article_id, nil, local_annotations, { quiet = true })
assert(ok == true, "highlight sync failed")
assert(counts.imported == 0, "pathless network probe should not import local sidecar highlights")
assert(counts.success == 1, "local highlight was not exported")
assert(counts.updated_remote == 1, "linked local highlight update was not patched to Readeck")
assert(counts.remote_deleted == 1, "remote deletion policy was not applied")
assert(local_annotations[1].readeck_annotation_id == "created-1", "exported annotation id was not retained")

-- The baseline cursor a first-ever catalog refresh sends has to be one the server will
-- actually bind. The mock rejects anything else exactly as Readeck does, so this asserts
-- the real round trip rather than the constant's spelling.
local Refresh = require("readeck.browse.refresh")
local sync_log, sync_err, sync_code = instance:fetchSyncLog(Refresh.BASELINE_CURSOR)
assert(sync_code == 200, "baseline sync request was rejected: " .. tostring(sync_code) .. " " .. tostring(sync_err))
assert(type(sync_log) == "table" and sync_log[1] and sync_log[1].id == article_id, "baseline sync log was empty")

-- Collections, through the real JSON decoder. Readeck sends `null` for a filter it does not
-- constrain, and KOReader decodes null to a sentinel *function* rather than nil -- so this
-- is the only layer that can catch the class of bug that emptied every collection. The
-- busted specs stub the decoder and cannot see it.
local Catalog = require("readeck.browse.catalog")
local Facets = require("readeck.browse.facets")
local catalog = Catalog.empty()
assert(instance:refreshCollections(catalog) == 2, "collections were not fetched")

local unrestricted = catalog.collections[1]
assert(unrestricted.name == "Everything", "collection name did not survive decoding")
assert(unrestricted.filters.is_archived == nil, "a null filter flag must decode to nil, not to a sentinel")
assert(unrestricted.filters.is_marked == nil, "a null filter flag must decode to nil, not to a sentinel")

local library = { Catalog.entry_from_bookmark({ id = article_id, title = "Probe", labels = { "rust" } }) }
local filter = Facets.collection_filter(unrestricted)
assert(Facets.count(library, filter) == 1, "an unrestricted collection matched nothing")

-- The second collection carries a real flag and a quoted multi-word label, so this also
-- pins that a set filter still narrows and that the label expression is parsed, not split.
local restricted = catalog.collections[2]
assert(restricted.filters.is_archived == true, "a set filter flag was lost")
assert(
    restricted.filters.labels[1] == "long read" and restricted.filters.labels[2] == "rust",
    "the collection label expression was not parsed back into names"
)

-- Nothing the decoder produced may reach the settings file: dump.lua writes a function as
-- `function: 0x...`, which is not loadable Lua, and LuaSettings then silently falls back to
-- the .old backup.
local dump = require("dump")
assert(not dump(catalog):find("function:", 1, true), "the catalog holds a value that cannot be serialised")

local state = instance:callAPI("GET", server_url .. "/__state", {}, "", "", true)
assert(#state.sync_rejections == 0, "the server refused a sync cursor the plugin sent")
assert(state.sync_requests[1] == Refresh.BASELINE_CURSOR, "baseline sync did not send the epoch cursor")
assert(state and state.oauth_token_requests == 1, "mock OAuth token endpoint was not hit")
assert(#state.oauth_clients == 1, "unexpected number of OAuth client registration requests")
assert(
    state.oauth_clients[1].software_version == PluginMetadata.version,
    "OAuth client registration did not use the plugin version"
)
assert(#state.annotation_posts == 1, "unexpected number of annotation POST requests")
assert(#state.annotation_patches == 1, "unexpected number of annotation PATCH requests")
assert(
    state.annotation_posts[1].color == (legacy_annotations and "yellow" or "none"),
    "annotation POST body used the wrong version-compatible color"
)
assert(state.annotation_patches[1].color == "green", "annotation PATCH body used the wrong color")
if legacy_annotations then
    assert(state.annotation_posts[1].note == nil, "legacy annotation POST body should omit note")
    assert(state.annotation_patches[1].note == nil, "legacy annotation PATCH body should omit note")
else
    assert(state.annotation_posts[1].note == "local note", "annotation POST body did not include note")
    assert(state.annotation_patches[1].note == "updated local note", "annotation PATCH body did not include note")
end

print("KOReader network smoke passed for Readeck " .. expected_version)
