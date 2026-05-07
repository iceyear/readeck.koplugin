local DataStorage = require("datastorage")
local LuaSettings = require("frontend/luasettings")

local Settings = {}

function Settings.install(Readeck)
    function Readeck:saveSettings()
        local tempsettings = {
            server_url = self.server_url,
            auth_token = self.auth_token,
            oauth_client_id = self.oauth_client_id,
            oauth_refresh_token = self.oauth_refresh_token,
            directory = self.directory,
            language_override = self.language_override,
            filter_tag = self.filter_tag,
            sort_param = self.sort_param,
            ignore_tags = self.ignore_tags,
            auto_tags = self.auto_tags,
            completion_action_finished_enabled = self.completion_action_finished_enabled,
            completion_action_read_enabled = self.completion_action_read_enabled,
            archive_instead_of_delete = self.archive_instead_of_delete,
            process_completion_on_sync = self.process_completion_on_sync,
            completion_action_sync_policy_version = self.completion_action_sync_policy_version,
            sync_reading_progress = self.sync_reading_progress,
            remove_local_missing_remote = self.remove_local_missing_remote,
            is_delete_finished = self.completion_action_finished_enabled,
            is_delete_read = self.completion_action_read_enabled,
            is_archiving_deleted = self.archive_instead_of_delete,
            is_auto_delete = self.process_completion_on_sync,
            is_sync_remote_delete = self.remove_local_missing_remote,
            articles_per_sync = self.articles_per_sync,
            download_concurrency = self.download_concurrency,
            experimental_async_downloads = self.experimental_async_downloads,
            auto_export_highlights = self.auto_export_highlights,
            export_highlights_before_sync = self.export_highlights_before_sync,
            highlight_sync_policy = self.highlight_sync_policy,
            periodic_sync_enabled = self.periodic_sync_enabled,
            periodic_sync_interval_minutes = self.periodic_sync_interval_minutes,
            send_review_as_tags = self.send_review_as_tags,
            remove_finished_from_history = self.remove_finished_from_history,
            remove_read_from_history = self.remove_read_from_history,
            download_queue = self.download_queue,
            block_timeout = self.block_timeout,
            total_timeout = self.total_timeout,
            file_block_timeout = self.file_block_timeout,
            file_total_timeout = self.file_total_timeout,
            access_token = self.access_token,
            token_expiry = self.token_expiry,
            cached_auth_token = self.cached_auth_token,
            cached_server_url = self.cached_server_url,
            cached_auth_method = self.cached_auth_method,
            server_info = self.server_info,
            sync_star_status = self.sync_star_status,
            remote_star_threshold = self.remote_star_threshold,
            sync_star_rating_as_label = self.sync_star_rating_as_label,
        }
        self.rd_settings:saveSetting("readeck", tempsettings)
        self.rd_settings:flush()
    end

    function Readeck:readSettings()
        local rd_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/readeck.lua")
        rd_settings:readSetting("readeck", {})
        return rd_settings
    end

    function Readeck:saveRDSettings(setting)
        if not self.rd_settings then
            self.rd_settings = self:readSettings()
        end
        self.rd_settings:saveSetting("readeck", setting)
        self.rd_settings:flush()
    end
end

return Settings
