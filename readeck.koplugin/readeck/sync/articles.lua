local Api = require("readeck.net.api")
local InfoMessage = require("ui/widget/infomessage")
local JSON = require("json")
local Status = require("readeck.sync.status")
local UIManager = require("ui/uimanager")
local util = require("util")

local Articles = {}

local function response_code(response)
    local code = response and (response.code or response.status)
    if type(code) == "string" then
        return tonumber(code) or tonumber(code:match("(%d%d%d)"))
    end
    return tonumber(code)
end

local function response_error(response)
    if not response then
        return "no response"
    end
    if response.error then
        local err = response.error
        if type(err) == "table" then
            return tostring(err.message or err.code or "network error")
        end
        return tostring(err)
    end
    return tostring(response_code(response) or "network error")
end

function Articles.install(Readeck, deps)
    local L = deps.L
    local T = deps.T
    local Log = deps.Log

    function Readeck:getArticleList(options)
        options = options or {}
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
                if not options.quiet then
                    UIManager:show(InfoMessage:new({
                        text = L("Requesting article list failed."),
                    }))
                end
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

    function Readeck:getArticleListHTTPClient()
        if self.article_list_http_client_disabled then
            return nil
        end
        if not (UIManager.looper and type(UIManager.looper.add_callback) == "function") then
            Log:info("KOReader async HTTP looper is not active; using blocking article list fetcher")
            return nil
        end
        local ok, client = pcall(require, "httpclient")
        if ok and type(client) == "table" and type(client.new) == "function" then
            return client
        end
        return nil
    end

    function Readeck:fetchArticleListBlockingAsync(done)
        Log:info("Using blocking article list fetcher")
        UIManager:scheduleIn(0, function()
            local articles, err = self:getArticleList({ quiet = true })
            done(articles, err)
        end)
        return false
    end

    function Readeck:disableArticleListHTTPClient(reason)
        self.article_list_http_client_disabled = true
        Log:warn("Disabling async article list fetcher:", reason or "request setup failed")
    end

    function Readeck:getArticleListAsync(done)
        local client = self:getArticleListHTTPClient()
        if not client then
            return self:fetchArticleListBlockingAsync(done)
        end

        local state = {
            article_list = {},
            offset = 0,
            limit = math.min(self.articles_per_sync, 30),
            retry_auth = false,
        }

        local fetch_next
        fetch_next = function()
            if #state.article_list >= self.articles_per_sync then
                done(state.article_list)
                return
            end

            local articles_url = Api.bookmarks_query({
                limit = state.limit,
                offset = state.offset,
                is_archived = 0,
                type = "article",
                labels = self.filter_tag,
                sort = self.sort_param,
            })

            Log:debug("Fetching article list with async URL:", articles_url)
            local ok, request_err = pcall(function()
                client:new():request({
                    url = self.server_url .. articles_url,
                    method = "GET",
                    on_headers = function(headers)
                        headers:add("Authorization", "Bearer " .. self.access_token)
                        headers:add("Accept", "application/json, */*")
                    end,
                }, function(response)
                    local code = response_code(response)
                    if code == 404 then
                        Log:debug("Couldn't get offset", state.offset)
                        done(state.article_list)
                        return
                    end

                    if (code == 401 or code == 403) and not state.retry_auth then
                        state.retry_auth = true
                        self.access_token = ""
                        self.token_expiry = 0
                        if
                            self:getBearerToken({
                                on_oauth_success = function()
                                    self:scheduleSyncAfterOAuth()
                                end,
                            })
                        then
                            fetch_next()
                        elseif self:isOAuthPollingActive() then
                            done(nil, "auth_pending")
                        else
                            done(nil, "auth_error")
                        end
                        return
                    end

                    if not code or code < 200 or code >= 300 then
                        Log:warn(
                            "Async article list failed at offset",
                            state.offset,
                            response_error(response),
                            code or ""
                        )
                        done(nil, "network_error")
                        return
                    end

                    local ok, articles_json = pcall(JSON.decode, response.body or "")
                    if not ok or type(articles_json) ~= "table" then
                        Log:warn("Async article list response was not valid JSON")
                        done(nil, "json_error")
                        return
                    end

                    local new_article_list = {}
                    for _, article in ipairs(articles_json) do
                        table.insert(new_article_list, article)
                    end

                    local pending_articles = #new_article_list >= state.limit
                    new_article_list = self:filterIgnoredTags(new_article_list)

                    for _, article in ipairs(new_article_list) do
                        if #state.article_list == self.articles_per_sync then
                            Log:debug("Hit the article target", self.articles_per_sync)
                            break
                        end
                        table.insert(state.article_list, article)
                    end

                    if not pending_articles then
                        Log:debug("No more articles to query")
                        done(state.article_list)
                        return
                    end

                    state.offset = state.offset + state.limit
                    fetch_next()
                end)
            end)
            if not ok then
                self:disableArticleListHTTPClient(request_err)
                self:fetchArticleListBlockingAsync(done)
            end
        end

        fetch_next()
        return true
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

    function Readeck:showSyncStatus(text)
        local info = InfoMessage:new({ text = text })
        UIManager:show(info)
        UIManager:forceRePaint()
        return info
    end

    function Readeck:closeSyncStatus(info)
        if info then
            UIManager:close(info)
            UIManager:forceRePaint()
        end
    end

    function Readeck:failSyncWithMessage(info, text)
        self:closeSyncStatus(info)
        if text then
            UIManager:show(InfoMessage:new({ text = text }))
        end
        self.sync_in_progress = false
        return false
    end

    function Readeck:finishSyncWithArticles(articles, highlight_counts)
        local action_counts = self:processLocalFiles("sync", {
            remote_articles_by_id = self:indexArticlesByID(articles),
        })
        if highlight_counts then
            action_counts.highlights_imported = highlight_counts.imported or 0
            action_counts.highlights_exported = highlight_counts.success or 0
            action_counts.highlights_updated_local = highlight_counts.updated_local or 0
            action_counts.highlights_updated_remote = highlight_counts.updated_remote or 0
            action_counts.highlights_conflicts = highlight_counts.conflicts or 0
            action_counts.highlights_local_only = highlight_counts.remote_deleted or 0
            action_counts.highlights_skipped = (highlight_counts.skipped or 0)
                + (highlight_counts.invalid or 0)
                + (highlight_counts.import_skipped or 0)
            action_counts.highlights_failed = (highlight_counts.error or 0) + (highlight_counts.import_failed or 0)
        end
        articles = self:filterArticlesProcessedEarlierInSync(articles, action_counts.processed_article_ids)
        Log:debug("Number of articles:", #articles)

        local info = self:showSyncStatus(L("Checking articles…"))
        UIManager:scheduleIn(0, function()
            self:closeSyncStatus(info)
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
        end)
    end

    function Readeck:syncHighlightsThenContinue(articles)
        if not self.export_highlights_before_sync then
            self:finishSyncWithArticles(articles)
            return
        end

        local info = self:showSyncStatus(L("Syncing highlights…"))
        self:syncHighlightsForLocalFilesAsync({
            quiet = true,
            on_progress = function(completed, total)
                self:closeSyncStatus(info)
                info = self:showSyncStatus(T(L("Syncing highlights… %1/%2"), completed, total))
            end,
        }, function(highlight_ok, highlight_counts)
            if highlight_ok == false and not highlight_counts then
                highlight_counts = { error = 1 }
            end
            self:closeSyncStatus(info)
            self:finishSyncWithArticles(articles, highlight_counts)
        end)
    end

    function Readeck:fetchArticlesThenContinue()
        local info = self:showSyncStatus(L("Getting article list…"))
        self:getArticleListAsync(function(articles, list_err)
            self:closeSyncStatus(info)
            if list_err == "auth_pending" then
                self.sync_in_progress = false
                return
            end
            if not articles then
                self:failSyncWithMessage(nil, L("Requesting article list failed."))
                return
            end
            self:syncHighlightsThenContinue(articles)
        end)
    end

    function Readeck:processDownloadQueueThenContinue()
        if self.download_queue and next(self.download_queue) ~= nil then
            local info = self:showSyncStatus(L("Adding articles from queue…"))
            UIManager:scheduleIn(0, function()
                for _, articleUrl in ipairs(self.download_queue) do
                    self:addArticle(articleUrl)
                end
                self.download_queue = {}
                self:saveSettings()
                self:closeSyncStatus(info)
                self:fetchArticlesThenContinue()
            end)
            return
        end

        self:fetchArticlesThenContinue()
    end

    function Readeck:synchronize()
        if self.sync_in_progress then
            Log:info("Sync requested while another sync is already running")
            return false
        end
        self.sync_in_progress = true
        local info = self:showSyncStatus(L("Connecting…"))
        UIManager:scheduleIn(0, function()
            if
                self:getBearerToken({
                    on_oauth_success = function()
                        self:scheduleSyncAfterOAuth()
                    end,
                }) == false
            then
                self:failSyncWithMessage(info)
                return
            end
            self:closeSyncStatus(info)
            if self.access_token ~= "" then
                self:processDownloadQueueThenContinue()
            else
                self.sync_in_progress = false
            end
        end)
        return true
    end
end

return Articles
