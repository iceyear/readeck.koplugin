local Api = require("readeck.net.api")
local Dates = require("readeck.core.dates")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local Metadata = require("readeck.storage.metadata")
local Progress = require("readeck.sync.progress")
local Scheduler = require("readeck.sync.scheduler")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local Downloads = {}

function Downloads.install(Readeck, deps)
    local L = deps.L
    local Log = deps.Log
    local article_id_suffix = deps.article_id_suffix
    local article_id_postfix = deps.article_id_postfix
    local failed = deps.failed
    local skipped = deps.skipped
    local downloaded = deps.downloaded

    function Readeck:applyDownloadedArticleMetadata(local_path, article)
        local timestamp = Dates.article_timestamp(article, self.is_dateparser_available and self.dateparser or nil)
        if timestamp then
            local ok, err = pcall(lfs.touch, local_path, timestamp, timestamp)
            if not ok then
                Log:warn("Could not set downloaded article timestamp:", local_path, err)
            end
        end

        local ok, err = pcall(Metadata.save_article_keywords, DocSettings, local_path, article, {
            reading_time = L("Reading time"),
            minute = L("min"),
        })
        if not ok then
            Log:warn("Could not save Readeck article metadata:", local_path, err)
        end
    end

    function Readeck:syncReadingProgressFromRemote(local_path, article)
        if not (self.sync_reading_progress and local_path and article) then
            return false
        end

        local remote_progress = article.read_progress
        if remote_progress == nil then
            return false
        end

        local doc_settings = DocSettings:open(local_path)
        local local_percent = doc_settings:readSetting("percent_finished")
        if not Progress.should_update_local_percent(local_percent, remote_progress) then
            return false
        end

        local percent_finished = Progress.readeck_progress_to_percent_finished(remote_progress)
        doc_settings:saveSetting("percent_finished", percent_finished)
        if self.ui and self.ui.document and self.ui.document.file == local_path and self.ui.doc_settings then
            if type(self.ui.handleEvent) == "function" then
                self.ui:handleEvent(Event:new("GotoPercent", percent_finished * 100))
            end
            self.ui.doc_settings:saveSetting("percent_finished", percent_finished)
            if type(self.ui.handleEvent) == "function" then
                self.ui:handleEvent(Event:new("SaveSettings"))
            end
        else
            doc_settings:saveSetting("last_percent", percent_finished)
            if type(doc_settings.delSetting) == "function" then
                doc_settings:delSetting("last_xpointer")
            end
        end
        if type(doc_settings.flush) == "function" then
            doc_settings:flush()
        end
        if self.sync_in_progress then
            self.local_progress_updates_in_sync = (self.local_progress_updates_in_sync or 0) + 1
        end
        Log:info("Updated KOReader reading progress from Readeck:", local_path, remote_progress)
        return true
    end

    function Readeck:getDownloadDirectory()
        local directory = self.directory or ""
        if directory ~= "" and directory:sub(-1) ~= "/" then
            directory = directory .. "/"
        end
        return directory
    end

    function Readeck:findLocalArticlePathByID(article_id)
        if self:isempty(self.directory) or not article_id then
            return nil
        end
        if lfs.attributes(self.directory, "mode") ~= "directory" then
            return nil
        end

        local expected_id = tostring(article_id)
        for entry in lfs.dir(self.directory) do
            if entry ~= "." and entry ~= ".." then
                local entry_path = FFIUtil.joinPath(self.directory, entry)
                if self:getArticleID(entry_path) == expected_id and lfs.attributes(entry_path, "mode") == "file" then
                    return entry_path
                end
            end
        end
        return nil
    end

    function Readeck:getDownloadTarget(article)
        local existing_path = self:findLocalArticlePathByID(article.id)
        if existing_path then
            return existing_path, Api.paths.bookmark_article(article.id)
        end

        local title = util.getSafeFilename(article.title, self.directory, 230, 0)
        local file_ext = ".epub"
        local local_path = self:getDownloadDirectory()
            .. title
            .. article_id_suffix
            .. article.id
            .. article_id_postfix
            .. file_ext
        return local_path, Api.paths.bookmark_article(article.id)
    end

    function Readeck:shouldSkipDownload(local_path, article)
        Log:debug("DOWNLOAD: id:", article.id)
        Log:debug("DOWNLOAD: title:", article.title)
        Log:debug("DOWNLOAD: filename:", local_path)

        local attr = lfs.attributes(local_path)
        if attr then
            Log:debug("Skipping existing local article:", local_path)
            return true
        end

        local existing_path = self:findLocalArticlePathByID(article.id)
        if existing_path then
            Log:debug("Skipping existing local article by Readeck ID:", existing_path)
            return true
        end

        return false
    end

    function Readeck:getAsyncHTTPClient()
        if not self.experimental_async_downloads or self:clampDownloadConcurrency(self.download_concurrency) <= 1 then
            return nil
        end
        if self.async_http_client_checked then
            return self.async_http_client
        end
        self.async_http_client_checked = true
        local ok, client = pcall(require, "httpclient")
        if ok and type(client) == "table" and type(client.new) == "function" then
            self.async_http_client = client
        end
        return self.async_http_client
    end

    function Readeck:disableAsyncHTTPClient(reason)
        if self.async_http_client then
            Log:warn("Disabling async article downloader:", reason or "download failed")
        end
        self.async_http_client = nil
        self.async_http_client_checked = true
    end

    function Readeck:writeDownloadedArticle(local_path, body)
        local file, err = io.open(local_path, "wb")
        if not file then
            Log:error("Could not open downloaded article file:", local_path, err or "")
            return false
        end
        file:write(body or "")
        file:close()
        return true
    end

    function Readeck:getAsyncResponseCode(response)
        local code = response and (response.code or response.status)
        if type(code) == "string" then
            return tonumber(code) or tonumber(code:match("(%d%d%d)"))
        end
        return tonumber(code)
    end

    function Readeck:formatAsyncDownloadFailure(response)
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
        return tostring(self:getAsyncResponseCode(response) or "network error")
    end

    function Readeck:isAsyncClientFailure(response)
        return not response or response.error ~= nil or self:getAsyncResponseCode(response) == nil
    end

    function Readeck:handleAsyncDownloadResponse(article, local_path, response)
        local code = self:getAsyncResponseCode(response)
        if code and code >= 200 and code < 300 and response.body then
            if self:writeDownloadedArticle(local_path, response.body) then
                self:applyDownloadedArticleMetadata(local_path, article)
                self:syncReadingProgressFromRemote(local_path, article)
                return downloaded
            end
        end

        if lfs.attributes(local_path, "mode") == "file" then
            os.remove(local_path)
        end
        Log:warn("Async article download failed:", article.id, self:formatAsyncDownloadFailure(response))
        return failed
    end

    function Readeck:downloadAsync(article, done)
        local client = self:getAsyncHTTPClient()
        if not client then
            UIManager:scheduleIn(0, function()
                done(self:download(article))
            end)
            return Scheduler.ASYNC
        end

        local local_path, item_url = self:getDownloadTarget(article)
        if self:shouldSkipDownload(local_path, article) then
            self:applyDownloadedArticleMetadata(local_path, article)
            self:syncReadingProgressFromRemote(local_path, article)
            done(skipped)
            return Scheduler.ASYNC
        end

        client:new():request({
            url = self.server_url .. item_url,
            method = "GET",
            on_headers = function(headers)
                headers:add("Authorization", "Bearer " .. self.access_token)
                headers:add("Accept", "application/epub+zip, */*")
            end,
        }, function(response)
            local result = self:handleAsyncDownloadResponse(article, local_path, response)
            if result == failed then
                if self:isAsyncClientFailure(response) then
                    self:disableAsyncHTTPClient(self:formatAsyncDownloadFailure(response))
                end
                Log:warn("Retrying article download with blocking client:", article.id)
                result = self:download(article)
            end
            done(result)
        end)

        return Scheduler.ASYNC
    end

    function Readeck:download(article)
        local local_path, item_url = self:getDownloadTarget(article)
        if not self:shouldSkipDownload(local_path, article) then
            local ok, err, code = self:callAPI("GET", item_url, nil, "", local_path)
            if ok then
                self:applyDownloadedArticleMetadata(local_path, article)
                self:syncReadingProgressFromRemote(local_path, article)
                return downloaded
            end
            Log:warn("Article download failed:", article.id, err or "unknown", code or "")
            return failed
        end
        self:applyDownloadedArticleMetadata(local_path, article)
        self:syncReadingProgressFromRemote(local_path, article)
        return skipped
    end

    function Readeck:showDownloadProgress(counts, total, action_counts)
        local message = self:formatDownloadProgressMessage(counts, total, action_counts)
        UIManager:show(InfoMessage:new({
            text = message,
            timeout = 1,
        }))
        UIManager:forceRePaint()
    end

    function Readeck:downloadArticlesAsync(articles, options)
        options = options or {}
        local counts = {
            downloaded = 0,
            skipped = 0,
            failed = 0,
            completed = 0,
        }
        local remote_article_ids = {}
        local total = #articles

        if total == 0 then
            if options.on_finish then
                options.on_finish(counts, remote_article_ids)
            end
            return nil
        end

        self:showDownloadProgress(counts, total, options.action_counts)
        local max_concurrent = self:getAsyncHTTPClient() and self:clampDownloadConcurrency(self.download_concurrency)
            or 1
        if max_concurrent <= 1 then
            Log:info("Using blocking article downloader")
        else
            Log:info("Using experimental async article downloader with concurrency:", max_concurrent)
        end
        self.download_scheduler = Scheduler.run(articles, {
            max_concurrent = max_concurrent,
            schedule = function(callback, delay)
                UIManager:scheduleIn(delay or 0, callback)
            end,
            worker = function(article, done)
                Log:debug("Processing article ID:", article.id)
                remote_article_ids[tostring(article.id)] = true
                return self:downloadAsync(article, done)
            end,
            on_result = function(_, result)
                if result == downloaded then
                    counts.downloaded = counts.downloaded + 1
                elseif result == skipped then
                    counts.skipped = counts.skipped + 1
                else
                    counts.failed = counts.failed + 1
                end
                counts.completed = counts.completed + 1
                self:showDownloadProgress(counts, total, options.action_counts)
            end,
            on_finish = function()
                self.download_scheduler = nil
                if options.on_finish then
                    options.on_finish(counts, remote_article_ids)
                end
            end,
        })
        return self.download_scheduler
    end
end

return Downloads
