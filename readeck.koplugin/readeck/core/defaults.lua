local Defaults = {}

Defaults.ARTICLE_ID_SUFFIX = " [rd-id_"
Defaults.ARTICLE_ID_POSTFIX = "]"
Defaults.DOWNLOAD_FAILED = 1
Defaults.DOWNLOAD_SKIPPED = 2
Defaults.DOWNLOAD_DONE = 3
Defaults.OAUTH_DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"
Defaults.DEFAULT_OAUTH_SCOPES = "bookmarks:read bookmarks:write"
Defaults.COMPLETION_ACTION_SYNC_POLICY_VERSION = 1

Defaults.values = {
    access_token = "",
    archive_instead_of_delete = true,
    articles_per_sync = 30,
    async_http_client = nil,
    async_http_client_checked = false,
    auth_token = "",
    auto_export_highlights = false,
    auto_tags = "",
    block_timeout = 30,
    cached_auth_method = "",
    cached_auth_token = "",
    cached_server_url = "",
    completion_action_finished_enabled = true,
    completion_action_read_enabled = false,
    completion_action_sync_policy_version = Defaults.COMPLETION_ACTION_SYNC_POLICY_VERSION,
    cookies = {},
    dateparser = nil,
    directory = nil,
    download_concurrency = 2,
    download_queue = {},
    download_scheduler = nil,
    experimental_async_downloads = false,
    export_highlights_before_sync = true,
    file_block_timeout = 10,
    file_total_timeout = 30,
    filter_tag = "",
    highlight_sync_policy = "preserve_local",
    ignore_tags = "",
    is_dateparser_available = false,
    is_dateparser_checked = false,
    language_override = "",
    oauth_client_id = "",
    oauth_poll_state = nil,
    oauth_prompt_dialog = nil,
    oauth_refresh_token = "",
    oauth_rng_seeded = false,
    periodic_sync_callback = nil,
    periodic_sync_enabled = false,
    periodic_sync_interval_minutes = 60,
    process_completion_on_sync = true,
    remote_star_threshold = 5,
    remove_finished_from_history = false,
    remove_local_missing_remote = false,
    remove_read_from_history = false,
    send_review_as_tags = false,
    server_info = nil,
    server_url = nil,
    sort_param = "-created",
    sync_in_progress = false,
    sync_reading_progress = false,
    sync_star_rating_as_label = false,
    sync_star_status = false,
    token_expiry = 0,
    total_timeout = 120,
}

local function copy_default(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = v
    end
    return copy
end

function Defaults.apply(plugin)
    for key, value in pairs(Defaults.values) do
        plugin[key] = copy_default(value)
    end
end

return Defaults
