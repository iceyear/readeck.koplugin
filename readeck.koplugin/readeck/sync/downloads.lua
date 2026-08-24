local Api = require("readeck.net.api")
local Dates = require("readeck.core.dates")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local Metadata = require("readeck.storage.metadata")
local Progress = require("readeck.sync.progress")
local ProgressMessage = require("readeck.ui.progress_message")
local Scheduler = require("readeck.sync.scheduler")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local socket = require("socket")
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

        -- Every download path -- blocking, async, subprocess, and the already-on-disk
        -- shortcut -- funnels through here, so this is the one place that knows an
        -- article's bytes and metadata are current. Refreshing the browse catalog from
        -- the same payload keeps the two from drifting apart between syncs.
        self:catalogUpsertBookmark(article)
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
        if self:clampDownloadConcurrency(self.download_concurrency) <= 1 then
            return nil
        end
        if not (UIManager.looper and type(UIManager.looper.add_callback) == "function") then
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

    function Readeck:canUseSubprocessDownloader()
        local is_windows = package.config:sub(1, 1) == "\\"
        return self:clampDownloadConcurrency(self.download_concurrency) > 1
            and self.experimental_async_downloads == true
            and not self.subprocess_downloads_disabled
            and not is_windows
            and type(FFIUtil.runInSubProcess) == "function"
            and type(FFIUtil.isSubProcessDone) == "function"
            and type(FFIUtil.terminateSubProcess) == "function"
            and type(FFIUtil.readAllFromFD) == "function"
    end

    function Readeck:disableSubprocessDownloader(reason)
        self.subprocess_downloads_disabled = true
        Log:warn("Disabling subprocess article downloader:", reason or "subprocess failed")
    end

    function Readeck:getParallelDownloadMode()
        if self:getAsyncHTTPClient() then
            return "turbo"
        end
        if self:canUseSubprocessDownloader() then
            return "subprocess"
        end
        return "blocking"
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

    function Readeck:runSubprocessDownload(local_path, request_url, access_token)
        if not self:canUseSubprocessDownloader() then
            return nil, "subprocess downloader unavailable"
        end
        local block_timeout = self.file_block_timeout
        local total_timeout = self.file_total_timeout
        local pid, read_fd = FFIUtil.runInSubProcess(function(_, write_fd)
            local function write_result(result, detail)
                FFIUtil.writeToFD(write_fd, result .. "\t" .. tostring(detail or ""), true)
            end

            local ok, err = pcall(function()
                local child_http = require("socket.http")
                local child_socket = require("socket")
                local child_socketutil = require("socketutil")

                local file, open_err = io.open(local_path, "wb")
                if not file then
                    write_result("failed", open_err or "file open failed")
                    return
                end

                child_socketutil:set_timeout(block_timeout, total_timeout)
                local request = {
                    url = request_url,
                    method = "GET",
                    headers = {
                        ["Authorization"] = "Bearer " .. access_token,
                        ["Accept"] = "application/epub+zip, */*",
                    },
                    sink = child_socketutil.file_sink(file),
                }

                local code, _, status = child_socket.skip(1, child_http.request(request))
                child_socketutil:reset_timeout()
                code = tonumber(code)

                if code and code >= 200 and code < 300 then
                    write_result("downloaded", code)
                    return
                end

                os.remove(local_path)
                write_result("failed", status or code or "network error")
            end)

            if not ok then
                os.remove(local_path)
                write_result("failed", err)
            end
        end, true)

        if not pid then
            return nil, read_fd
        end
        return {
            pid = pid,
            read_fd = read_fd,
            local_path = local_path,
            deadline = socket.gettime() + math.max(10, (tonumber(self.file_total_timeout) or 30) + 5),
        }
    end

    function Readeck:finishSubprocessDownload(job, article)
        local payload = ""
        if job.read_fd then
            payload = FFIUtil.readAllFromFD(job.read_fd) or ""
        end
        local result, detail = payload:match("^([^\t]*)\t?(.*)$")
        if result == "downloaded" then
            self:applyDownloadedArticleMetadata(job.local_path, article)
            self:syncReadingProgressFromRemote(job.local_path, article)
            return downloaded, detail
        end

        if lfs.attributes(job.local_path, "mode") == "file" then
            os.remove(job.local_path)
        end
        Log:warn("Subprocess article download failed:", article.id, detail or "unknown")
        return failed, detail
    end

    function Readeck:retryDownloadBlockingAfterSubprocessFailure(article, reason)
        self:disableSubprocessDownloader(reason)
        Log:warn("Retrying article download with blocking client:", article.id)
        return self:download(article)
    end

    function Readeck:downloadInSubprocess(article, done)
        local local_path, item_url = self:getDownloadTarget(article)
        if self:shouldSkipDownload(local_path, article) then
            self:applyDownloadedArticleMetadata(local_path, article)
            self:syncReadingProgressFromRemote(local_path, article)
            done(skipped)
            return Scheduler.ASYNC
        end

        local job, err = self:runSubprocessDownload(local_path, self.server_url .. item_url, self.access_token)
        if not job then
            self:disableSubprocessDownloader(err)
            UIManager:scheduleIn(0, function()
                done(self:download(article))
            end)
            return Scheduler.ASYNC
        end

        local function poll()
            if FFIUtil.isSubProcessDone(job.pid) then
                local result, detail = self:finishSubprocessDownload(job, article)
                if result == failed then
                    result = self:retryDownloadBlockingAfterSubprocessFailure(article, detail)
                end
                done(result)
                return
            end
            if socket.gettime() > job.deadline then
                FFIUtil.terminateSubProcess(job.pid)
                if lfs.attributes(local_path, "mode") == "file" then
                    os.remove(local_path)
                end
                Log:warn("Subprocess article download timed out:", article.id)
                done(self:retryDownloadBlockingAfterSubprocessFailure(article, "timeout"))
                return
            end
            UIManager:scheduleIn(0.1, poll)
        end

        UIManager:scheduleIn(0.1, poll)
        return Scheduler.ASYNC
    end

    function Readeck:downloadAsync(article, done)
        local client = self:getAsyncHTTPClient()
        if not client then
            if self:canUseSubprocessDownloader() then
                return self:downloadInSubprocess(article, done)
            else
                UIManager:scheduleIn(0, function()
                    done(self:download(article))
                end)
                return Scheduler.ASYNC
            end
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

    function Readeck:copyProgressCounts(counts)
        local copy = {}
        for key, value in pairs(counts or {}) do
            copy[key] = value
        end
        return copy
    end

    function Readeck:updateDownloadProgressState(counts, total, action_counts)
        self.download_progress_state = {
            active = true,
            action_counts = self:copyProgressCounts(action_counts),
            counts = self:copyProgressCounts(counts),
            total = total or 0,
        }
    end

    function Readeck:hasActiveDownloadProgress()
        return self.download_progress_state and self.download_progress_state.active == true
    end

    function Readeck:showDownloadProgress(counts, total, action_counts, force)
        self:updateDownloadProgressState(counts, total, action_counts)
        if self.download_progress_hidden and not force then
            return
        end

        local message = self:formatDownloadProgressMessage(counts, total, action_counts)
        if self.download_progress_info then
            if ProgressMessage.update(self.download_progress_info, message) then
                self.download_progress_hidden = false
                return
            end
            self:closeDownloadProgress()
        end

        local progress_info
        progress_info = InfoMessage:new({
            text = message,
            dismissable = true,
            dismiss_callback = function()
                if self.closing_download_progress then
                    return
                end
                if self.download_progress_info == progress_info then
                    self.download_progress_info = nil
                end
                self.download_progress_hidden = true
            end,
        })
        self.download_progress_info = progress_info
        self.download_progress_hidden = false
        UIManager:show(self.download_progress_info)
        UIManager:forceRePaint()
    end

    function Readeck:showExistingDownloadProgress()
        local state = self.download_progress_state
        if not (state and state.active) then
            UIManager:show(InfoMessage:new({ text = L("No sync progress to show.") }))
            return false
        end
        self.download_progress_hidden = false
        self:showDownloadProgress(state.counts, state.total, state.action_counts, true)
        return true
    end

    function Readeck:closeDownloadProgress(clear_state)
        if not self.download_progress_info then
            if clear_state then
                self.download_progress_state = nil
                self.download_progress_hidden = false
            end
            return
        end
        self.closing_download_progress = true
        UIManager:close(self.download_progress_info)
        self.closing_download_progress = false
        self.download_progress_info = nil
        if clear_state then
            self.download_progress_state = nil
            self.download_progress_hidden = false
        end
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

        self.download_progress_hidden = false
        self:showDownloadProgress(counts, total, options.action_counts)
        local download_mode = self:getParallelDownloadMode()
        local max_concurrent = download_mode ~= "blocking" and self:clampDownloadConcurrency(self.download_concurrency)
            or 1
        if download_mode == "blocking" then
            Log:info("Using blocking article downloader")
        elseif download_mode == "turbo" then
            Log:info("Using KOReader async article downloader with concurrency:", max_concurrent)
        else
            Log:info("Using asynchronous subprocess article downloader with concurrency:", max_concurrent)
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
                self:closeDownloadProgress(true)
                if options.on_finish then
                    options.on_finish(counts, remote_article_ids)
                end
            end,
        })
        return self.download_scheduler
    end
end

return Downloads
