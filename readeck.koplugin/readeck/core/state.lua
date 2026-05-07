local Defaults = require("readeck.core.defaults")
local Dispatcher = require("dispatcher")
local I18n = require("readeck.i18n")

local State = {}

local function assign_if_set(plugin, settings, key, transform)
    if settings[key] ~= nil then
        plugin[key] = transform and transform(settings[key]) or settings[key]
    end
end

local function assign_with_legacy(plugin, settings, key, legacy_key)
    if settings[key] ~= nil then
        plugin[key] = settings[key]
    elseif settings[legacy_key] ~= nil then
        plugin[key] = settings[legacy_key]
    end
end

local function load_dateparser(plugin)
    if plugin.is_dateparser_checked then
        return
    end
    local ok
    ok, plugin.dateparser = pcall(require, "lib.dateparser")
    plugin.is_dateparser_available = ok
    plugin.is_dateparser_checked = true
end

function State.install(Readeck, deps)
    local L = deps.L
    local Log = deps.Log

    function Readeck:onDispatcherRegisterActions()
        Dispatcher:registerAction(
            "readeck_download",
            { category = "none", event = "SynchronizeReadeck", title = L("Readeck sync"), general = true }
        )
    end

    function Readeck:buildSortOptions()
        return {
            { "created", L("Added, oldest first") },
            { "-created", L("Added, most recent first") },
            { "published", L("Published, oldest first") },
            { "-published", L("Published, most recent first") },
            { "duration", L("Duration, shortest first") },
            { "-duration", L("Duration, longest first") },
            { "site", L("Site name, A to Z") },
            { "-site", L("Site name, Z to A") },
            { "title", L("Title, A to Z") },
            { "-title", L("Title, Z to A") },
        }
    end

    function Readeck:loadSettingsIntoState(settings)
        self.language_override = settings.language_override or ""
        I18n.set_language_override(self.language_override)
        self.sort_options = self:buildSortOptions()

        self.completion_action_sync_policy_version = settings.completion_action_sync_policy_version or 0
        assign_with_legacy(self, settings, "completion_action_finished_enabled", "is_delete_finished")
        assign_with_legacy(self, settings, "completion_action_read_enabled", "is_delete_read")
        assign_with_legacy(self, settings, "process_completion_on_sync", "is_auto_delete")
        assign_with_legacy(self, settings, "remove_local_missing_remote", "is_sync_remote_delete")
        assign_with_legacy(self, settings, "archive_instead_of_delete", "is_archiving_deleted")

        assign_if_set(self, settings, "sync_reading_progress")
        assign_if_set(self, settings, "send_review_as_tags")
        assign_if_set(self, settings, "filter_tag")
        assign_if_set(self, settings, "sort_param")
        assign_if_set(self, settings, "ignore_tags")
        assign_if_set(self, settings, "auto_tags")
        assign_if_set(self, settings, "articles_per_sync")
        assign_if_set(self, settings, "download_concurrency", function(value)
            return self:clampDownloadConcurrency(value)
        end)
        assign_if_set(self, settings, "experimental_async_downloads")
        assign_if_set(self, settings, "auto_export_highlights")
        assign_if_set(self, settings, "export_highlights_before_sync")
        assign_if_set(self, settings, "periodic_sync_enabled")
        assign_if_set(self, settings, "periodic_sync_interval_minutes")
        assign_if_set(self, settings, "block_timeout")
        assign_if_set(self, settings, "total_timeout")
        assign_if_set(self, settings, "file_block_timeout")
        assign_if_set(self, settings, "file_total_timeout")
        assign_if_set(self, settings, "remove_finished_from_history")
        assign_if_set(self, settings, "remove_read_from_history")

        self.download_queue = settings.download_queue or {}
        self.sync_star_status = settings.sync_star_status or false
        self.remote_star_threshold = settings.remote_star_threshold or 5
        self.sync_star_rating_as_label = settings.sync_star_rating_as_label or false
    end

    function Readeck:migrateSettingsIfNeeded(settings)
        if self.completion_action_sync_policy_version >= Defaults.COMPLETION_ACTION_SYNC_POLICY_VERSION then
            return false
        end
        if
            self.process_completion_on_sync == false
            and self.archive_instead_of_delete ~= false
            and self.completion_action_finished_enabled
        then
            self.process_completion_on_sync = true
            Log:info("Enabled completion actions during sync for archived completion workflow")
        end
        self.completion_action_sync_policy_version = Defaults.COMPLETION_ACTION_SYNC_POLICY_VERSION
        settings.completion_action_sync_policy_version = Defaults.COMPLETION_ACTION_SYNC_POLICY_VERSION
        return true
    end

    function Readeck:init()
        Log:info("Initializing Readeck plugin")
        Defaults.apply(self)
        self.sort_options = self:buildSortOptions()

        self:onDispatcherRegisterActions()
        self.ui.menu:registerToMainMenu(self)

        self.rd_settings = self:readSettings()
        local settings = self.rd_settings.data.readeck
        self.server_url = settings.server_url
        self.auth_token = settings.auth_token or ""
        self.directory = settings.directory
        self.access_token = settings.access_token or ""
        self.token_expiry = settings.token_expiry or 0
        self.cached_auth_token = settings.cached_auth_token or ""
        self.cached_server_url = settings.cached_server_url or ""
        self.cached_auth_method = settings.cached_auth_method or ""
        self.oauth_client_id = settings.oauth_client_id or ""
        self.oauth_refresh_token = settings.oauth_refresh_token or ""
        self.server_info = settings.server_info

        self:loadSettingsIntoState(settings)
        load_dateparser(self)
        self:registerExternalLinkHandler()

        if self:migrateSettingsIfNeeded(settings) then
            self:saveSettings()
        end
        Log:info("Readeck plugin initialization complete")
        self:reschedulePeriodicSync()
    end
end

return State
