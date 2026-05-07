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
local Readeck = dofile(plugin_dir .. "/main.lua")
local lfs = require("libs/libkoreader-lfs")

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
assert(counts.remote_deleted == 1, "remote deletion policy was not applied")
assert(local_annotations[1].readeck_annotation_id == "created-1", "exported annotation id was not retained")

local state = instance:callAPI("GET", server_url .. "/__state", {}, "", "", true)
assert(state and state.oauth_token_requests == 1, "mock OAuth token endpoint was not hit")
assert(#state.oauth_clients == 1, "unexpected number of OAuth client registration requests")
assert(
    state.oauth_clients[1].software_version == Defaults.PLUGIN_VERSION,
    "OAuth client registration did not use the plugin version"
)
assert(#state.annotation_posts == 1, "unexpected number of annotation POST requests")
assert(
    state.annotation_posts[1].color == (legacy_annotations and "yellow" or "none"),
    "annotation POST body used the wrong version-compatible color"
)
if legacy_annotations then
    assert(state.annotation_posts[1].note == nil, "legacy annotation POST body should omit note")
else
    assert(state.annotation_posts[1].note == "local note", "annotation POST body did not include note")
end

print("KOReader network smoke passed for Readeck " .. expected_version)
