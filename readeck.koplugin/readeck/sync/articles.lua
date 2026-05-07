local Api = require("readeck.net.api")
local InfoMessage = require("ui/widget/infomessage")
local Status = require("readeck.sync.status")
local UIManager = require("ui/uimanager")
local util = require("util")

local Articles = {}

function Articles.install(Readeck, deps)
    local L = deps.L
    local Log = deps.Log

    function Readeck:getArticleList()
        local article_list = {}
        local offset = 0
        local limit = math.min(self.articles_per_sync, 30)

        while #article_list < self.articles_per_sync do
            local articles_url = Api.bookmarks_query({
                limit = limit,
                offset = offset,
                is_archived = 0,
                type = "article",
                labels = self.filter_tag,
                sort = self.sort_param,
            })

            Log:debug("Fetching article list with URL:", articles_url)
            local articles_json, err, code = self:callAPI("GET", articles_url, nil, "", "", true)

            if err == "http_error" and code == 404 then
                Log:debug("Couldn't get offset", offset)
                break
            elseif err == "auth_pending" then
                Log:info("OAuth authorization started while requesting article list")
                return nil, err
            elseif err or articles_json == nil then
                Log:warn("Download at offset", offset, "failed with", err, code)
                UIManager:show(InfoMessage:new({
                    text = L("Requesting article list failed."),
                }))
                return
            end

            local new_article_list = {}
            for _, article in ipairs(articles_json) do
                table.insert(new_article_list, article)
            end

            local pending_articles = #new_article_list >= limit

            new_article_list = self:filterIgnoredTags(new_article_list)

            for _, article in ipairs(new_article_list) do
                if #article_list == self.articles_per_sync then
                    Log:debug("Hit the article target", self.articles_per_sync)
                    break
                end
                table.insert(article_list, article)
            end

            if not pending_articles then
                Log:debug("No more articles to query")
                break
            end

            offset = offset + limit
        end

        return article_list
    end

    function Readeck:filterIgnoredTags(article_list)
        local ignoring = {}
        if self.ignore_tags ~= "" then
            for tag in util.gsplit(self.ignore_tags, "[,]+", false) do
                ignoring[tag] = true
            end
        end

        local filtered_list = {}
        for _, article in ipairs(article_list) do
            local skip_article = false
            for _, tag in ipairs(article.labels or {}) do
                if ignoring[tag] then
                    skip_article = true
                    Log:debug("Ignoring tag", tag, "in article", article.id, ":", article.title)
                    break
                end
            end
            if not skip_article then
                table.insert(filtered_list, article)
            end
        end

        return filtered_list
    end

    function Readeck:filterArticlesProcessedEarlierInSync(articles, processed_article_ids)
        if type(processed_article_ids) ~= "table" then
            return articles
        end

        local filtered = {}
        for _, article in ipairs(articles or {}) do
            if processed_article_ids[tostring(article.id)] then
                Log:debug("Skipping article already processed during this sync:", article.id)
            else
                table.insert(filtered, article)
            end
        end
        return filtered
    end

    function Readeck:indexArticlesByID(articles)
        local by_id = {}
        for _, article in ipairs(articles or {}) do
            if article.id then
                by_id[tostring(article.id)] = article
            end
        end
        return by_id
    end

    function Readeck:synchronize()
        if self.sync_in_progress then
            Log:info("Sync requested while another sync is already running")
            return false
        end
        self.sync_in_progress = true
        local info = InfoMessage:new({ text = L("Connecting…") })
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)

        if
            self:getBearerToken({
                on_oauth_success = function()
                    self:scheduleSyncAfterOAuth()
                end,
            }) == false
        then
            self.sync_in_progress = false
            return false
        end
        if self.download_queue and next(self.download_queue) ~= nil then
            info = InfoMessage:new({ text = L("Adding articles from queue…") })
            UIManager:show(info)
            UIManager:forceRePaint()
            for _, articleUrl in ipairs(self.download_queue) do
                self:addArticle(articleUrl)
            end
            self.download_queue = {}
            self:saveSettings()
            UIManager:close(info)
        end

        info = InfoMessage:new({ text = L("Getting article list…") })
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)

        if self.access_token ~= "" then
            local articles, list_err = self:getArticleList()
            if list_err == "auth_pending" then
                self.sync_in_progress = false
                return false
            end
            if articles then
                local highlight_counts
                if self.export_highlights_before_sync then
                    local highlight_ok
                    highlight_ok, highlight_counts = self:syncHighlightsForLocalFiles({ quiet = true })
                    if highlight_ok == false and not highlight_counts then
                        highlight_counts = { error = 1 }
                    end
                end

                local action_counts = self:processLocalFiles("sync", {
                    remote_articles_by_id = self:indexArticlesByID(articles),
                })
                if highlight_counts then
                    action_counts.highlights_imported = highlight_counts.imported or 0
                    action_counts.highlights_exported = highlight_counts.success or 0
                    action_counts.highlights_local_only = highlight_counts.remote_deleted or 0
                    action_counts.highlights_skipped = (highlight_counts.skipped or 0)
                        + (highlight_counts.invalid or 0)
                        + (highlight_counts.import_skipped or 0)
                    action_counts.highlights_failed = (highlight_counts.error or 0)
                        + (highlight_counts.import_failed or 0)
                end
                articles = self:filterArticlesProcessedEarlierInSync(articles, action_counts.processed_article_ids)
                Log:debug("Number of articles:", #articles)

                info = InfoMessage:new({ text = L("Checking articles…") })
                UIManager:show(info)
                UIManager:forceRePaint()
                UIManager:close(info)

                self.local_progress_updates_in_sync = 0
                self:downloadArticlesAsync(articles, {
                    action_counts = action_counts,
                    on_finish = function(download_counts, remote_article_ids)
                        if (self.local_progress_updates_in_sync or 0) > 0 then
                            action_counts.local_progress_updated = (action_counts.local_progress_updated or 0)
                                + self.local_progress_updates_in_sync
                        end
                        self.local_progress_updates_in_sync = 0
                        Status.add(action_counts, self:processRemoteDeletes(remote_article_ids))

                        UIManager:show(InfoMessage:new({
                            text = self:formatSyncMessage(
                                download_counts.downloaded,
                                download_counts.skipped,
                                download_counts.failed,
                                action_counts
                            ),
                        }))
                        self.sync_in_progress = false
                        self:refreshCurrentDirIfNeeded()
                    end,
                })
                return true
            end
        end
        self.sync_in_progress = false
    end
end

return Articles
