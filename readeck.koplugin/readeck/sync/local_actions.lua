local Api = require("readeck.net.api")
local DocSettings = require("docsettings")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local JSON = require("json")
local Math = require("optmath")
local NetworkMgr = require("ui/network/manager")
local Progress = require("readeck.sync.progress")
local Status = require("readeck.sync.status")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local LocalActions = {}

function LocalActions.install(Readeck, deps)
    local L = deps.L
    local T = deps.T
    local Log = deps.Log

    function Readeck:processRemoteDeletes(remote_article_ids)
        local counts = Status.new_counts()
        if not self.remove_local_missing_remote then
            Log:debug("Processing of remote file removals disabled.")
            return counts
        end
        Log:debug("Articles IDs from server:", remote_article_ids)

        local candidates = self:collectRemoteDeleteCandidates(remote_article_ids)
        if #candidates == 0 then
            return counts
        end

        local info = InfoMessage:new({
            text = table.concat({
                L("Removing local files missing from Readeck…"),
                T(L("Will remove from KOReader: %1"), #candidates),
            }, "\n"),
        })
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)
        for _, entry_path in ipairs(candidates) do
            Log:debug("Deleting local file (deleted on server):", entry_path)
            counts.local_removed = counts.local_removed + self:deleteLocalArticle(entry_path)
        end
        return counts
    end

    function Readeck:collectRemoteDeleteCandidates(remote_article_ids)
        local candidates = {}
        for entry in lfs.dir(self.directory) do
            if entry ~= "." and entry ~= ".." then
                local entry_path = FFIUtil.joinPath(self.directory, entry)
                local id = self:getArticleID(entry_path)
                if id and not remote_article_ids[id] and lfs.attributes(entry_path, "mode") == "file" then
                    table.insert(candidates, entry_path)
                end
            end
        end
        return candidates
    end

    function Readeck:isCompletionProcessingEnabledForMode(mode)
        return not mode or mode == "manual" or self.process_completion_on_sync ~= false
    end

    function Readeck:getLocalCompletionAction(path, doc_settings)
        doc_settings = doc_settings or DocSettings:open(path)
        local summary = doc_settings:readSetting("summary")
        local status = summary and summary.status
        local percent_finished = doc_settings:readSetting("percent_finished")
        if status == "complete" or status == "abandoned" then
            if self.completion_action_finished_enabled then
                return {
                    mark_read_complete = (status == "complete") or (percent_finished == 1),
                }
            end
        elseif percent_finished == 1 then
            if self.completion_action_read_enabled then
                return {
                    mark_read_complete = true,
                }
            end
        end
    end

    function Readeck:getLocalReadingProgressAction(doc_settings, remote_article)
        local percent_finished = doc_settings:readSetting("percent_finished")
        if
            not Progress.should_update_remote_percent(
                percent_finished,
                remote_article and remote_article.read_progress or nil
            )
        then
            return nil
        end
        return {
            progress = Progress.percent_finished_to_readeck_progress(percent_finished),
        }
    end

    function Readeck:collectLocalFileActions(options)
        options = options or {}
        local completion_enabled = options.completion_enabled ~= false
        local completion_actions_enabled = completion_enabled
            and (self.completion_action_finished_enabled or self.completion_action_read_enabled)
        local should_scan = completion_actions_enabled or self.sync_reading_progress or self.send_review_as_tags
        local remote_articles_by_id = options.remote_articles_by_id or {}
        local files = {}
        local plan = {
            remote_archive_candidates = 0,
            remote_delete_candidates = 0,
            remote_progress_candidates = 0,
            local_remove_candidates = 0,
        }
        if not should_scan then
            return files, plan
        end

        for entry in lfs.dir(self.directory) do
            if entry ~= "." and entry ~= ".." then
                local entry_path = FFIUtil.joinPath(self.directory, entry)
                if lfs.attributes(entry_path, "mode") == "file" and DocSettings:hasSidecarFile(entry_path) then
                    local file_action = {
                        path = entry_path,
                    }
                    local article_id = self:getArticleID(entry_path)
                    local doc_settings = DocSettings:open(entry_path)
                    if completion_actions_enabled then
                        local completion_action = self:getLocalCompletionAction(entry_path, doc_settings)
                        if completion_action and article_id then
                            file_action.completion_action = completion_action
                            if self.archive_instead_of_delete then
                                plan.remote_archive_candidates = plan.remote_archive_candidates + 1
                            else
                                plan.remote_delete_candidates = plan.remote_delete_candidates + 1
                            end
                            plan.local_remove_candidates = plan.local_remove_candidates + 1
                        end
                    end
                    if self.sync_reading_progress and not file_action.completion_action and article_id then
                        local progress_action = self:getLocalReadingProgressAction(
                            doc_settings,
                            remote_articles_by_id[tostring(article_id)]
                        )
                        if progress_action then
                            file_action.progress_action = progress_action
                            plan.remote_progress_candidates = plan.remote_progress_candidates + 1
                        end
                    end
                    table.insert(files, file_action)
                end
            end
        end
        return files, plan
    end

    function Readeck:processLocalFiles(mode, options)
        options = options or {}
        local counts = Status.new_counts()
        local completion_enabled = self:isCompletionProcessingEnabledForMode(mode)
        if not completion_enabled then
            counts.completion_actions_disabled = 1
            if not self.send_review_as_tags and not self.sync_reading_progress then
                Log:debug("Automatic processing of local completion actions disabled.")
                return counts
            end
        end

        if
            self:getBearerToken({
                on_oauth_success = function()
                    NetworkMgr:runWhenOnline(function()
                        self:processLocalFiles(mode)
                        self:refreshCurrentDirIfNeeded()
                    end)
                end,
            }) == false
        then
            return counts
        end

        local local_files, plan = self:collectLocalFileActions({
            completion_enabled = completion_enabled,
            remote_articles_by_id = options.remote_articles_by_id,
        })
        if #local_files > 0 then
            local message = L("Processing local files…")
            if
                completion_enabled and (self.completion_action_finished_enabled or self.completion_action_read_enabled)
            then
                message = self:formatCompletionPlanMessage(plan)
            end
            local info = InfoMessage:new({ text = message })
            UIManager:show(info)
            UIManager:forceRePaint()
            UIManager:close(info)
        end
        for _, local_file in ipairs(local_files) do
            if self.send_review_as_tags then
                self:addTags(local_file.path)
            end
            if local_file.completion_action then
                Status.add(counts, self:removeArticle(local_file.path, local_file.completion_action.mark_read_complete))
            elseif local_file.progress_action then
                Status.add(counts, self:syncReadingProgress(local_file.path, local_file.progress_action.progress))
            end
        end
        return counts
    end

    function Readeck:syncReadingProgress(path, progress)
        local counts = Status.new_counts()
        local id = self:getArticleID(path)
        progress = tonumber(progress)
        if not id or not progress then
            return counts
        end

        local bodyJSON = JSON.encode({
            read_progress = math.max(0, math.min(100, Math.round(progress))),
        })
        local headers = {
            ["Content-type"] = "application/json",
            ["Accept"] = "application/json, */*",
            ["Content-Length"] = tostring(#bodyJSON),
            ["Authorization"] = "Bearer " .. self.access_token,
        }
        local remote_ok = self:callAPI("PATCH", Api.paths.bookmark(id), headers, bodyJSON, "")
        if remote_ok then
            counts.remote_progress_updated = counts.remote_progress_updated + 1
        else
            counts.failed = counts.failed + 1
        end
        return counts
    end

    function Readeck:addArticle(article_url)
        Log:debug("Adding article", article_url)

        if not article_url then
            return false
        end
        if
            self:getBearerToken({
                on_oauth_success = function()
                    NetworkMgr:runWhenOnline(function()
                        self:addArticle(article_url)
                        self:refreshCurrentDirIfNeeded()
                    end)
                end,
            }) == false
        then
            if self:isOAuthPollingActive() then
                return nil, "auth_pending"
            end
            return false
        end

        local body = {
            url = article_url,
        }

        if self.auto_tags and self.auto_tags ~= "" then
            local tags = {}
            for tag in util.gsplit(self.auto_tags, "[,]+", false) do
                table.insert(tags, tag:gsub("^%s*(.-)%s*$", "%1"))
            end
            body.labels = tags
        end

        local body_JSON = JSON.encode(body)

        local headers = {
            ["Content-type"] = "application/json",
            ["Accept"] = "application/json, */*",
            ["Content-Length"] = tostring(#body_JSON),
            ["Authorization"] = "Bearer " .. self.access_token,
        }

        return self:callAPI("POST", Api.paths.bookmarks, headers, body_JSON, "")
    end

    function Readeck:addTags(path)
        Log:debug("Managing tags for article", path)
        local id = self:getArticleID(path)
        if id then
            local doc_settings = DocSettings:open(path)
            local summary = doc_settings:readSetting("summary")
            local tags_text = summary and summary.note
            if tags_text and tags_text ~= "" then
                Log:debug("Sending tags", tags_text, "for", path)

                local tags = {}
                for tag in util.gsplit(tags_text, "[,]+", false) do
                    table.insert(tags, tag:gsub("^%s*(.-)%s*$", "%1"))
                end

                local body = {
                    add_labels = tags,
                }

                local bodyJSON = JSON.encode(body)

                local headers = {
                    ["Content-type"] = "application/json",
                    ["Accept"] = "application/json, */*",
                    ["Content-Length"] = tostring(#bodyJSON),
                    ["Authorization"] = "Bearer " .. self.access_token,
                }

                self:callAPI("PATCH", Api.paths.bookmark(id), headers, bodyJSON, "")
            else
                Log:debug("No tags to send for", path)
            end
        end
    end

    function Readeck:removeArticle(path, mark_read_complete)
        Log:debug("Removing article", path)
        local counts = Status.new_counts()
        local id = self:getArticleID(path)
        if id then
            local highlights_ok = self:syncHighlightsForPath(path, { quiet = true })
            if highlights_ok == false then
                Log:warn("Skipping completion action because highlight sync failed:", path)
                counts.failed = counts.failed + 1
                return counts
            end

            local remote_ok
            if self.archive_instead_of_delete then
                local body = {
                    is_archived = true,
                }
                if mark_read_complete then
                    body.read_progress = 100
                end
                if self.sync_star_status then
                    local doc_settings = DocSettings:open(path)
                    local summary = doc_settings:readSetting("summary")
                    if summary and summary.rating then
                        if summary.rating > 0 and self.sync_star_rating_as_label == true then
                            local label = { summary.rating .. "-star" }
                            body.add_labels = label
                        end
                        if summary.rating >= self.remote_star_threshold then
                            body.is_marked = true
                        end
                    end
                end
                local bodyJSON = JSON.encode(body)

                local headers = {
                    ["Content-type"] = "application/json",
                    ["Accept"] = "application/json, */*",
                    ["Content-Length"] = tostring(#bodyJSON),
                    ["Authorization"] = "Bearer " .. self.access_token,
                }

                remote_ok = self:callAPI("PATCH", Api.paths.bookmark(id), headers, bodyJSON, "")
                if remote_ok then
                    counts.remote_archived = counts.remote_archived + 1
                end
            else
                remote_ok = self:callAPI("DELETE", Api.paths.bookmark(id), nil, "", "")
                if remote_ok then
                    counts.remote_deleted = counts.remote_deleted + 1
                end
            end
            if remote_ok then
                counts.processed_article_ids = {
                    [tostring(id)] = true,
                }
                counts.local_removed = counts.local_removed + self:deleteLocalArticle(path)
            else
                counts.failed = counts.failed + 1
            end
        end
        return counts
    end

    function Readeck:deleteLocalArticle(path)
        if lfs.attributes(path, "mode") == "file" then
            FileManager:deleteFile(path, true)
            return 1
        end
        return 0
    end
end

return LocalActions
