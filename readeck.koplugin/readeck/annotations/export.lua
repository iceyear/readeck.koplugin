local Api = require("readeck.net.api")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local Features = require("readeck.core.features")
local Highlights = require("readeck.annotations.highlights")
local InfoMessage = require("ui/widget/infomessage")
local JSON = require("json")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

local Export = {}

local function new_highlight_counts()
    return {
        success = 0,
        error = 0,
        skipped = 0,
        invalid = 0,
        imported = 0,
        import_skipped = 0,
        import_failed = 0,
    }
end

local function add_highlight_counts(target, source)
    target = target or new_highlight_counts()
    for key, value in pairs(source or {}) do
        target[key] = (target[key] or 0) + (tonumber(value) or 0)
    end
    return target
end

function Export.install(Readeck, deps)
    local L = deps.L
    local T = deps.T
    local Log = deps.Log

    function Readeck:getCurrentAnnotations()
        if self.ui and self.ui.annotation and self.ui.annotation.annotations then
            return self.ui.annotation.annotations
        end
        if self.ui and self.ui.view and self.ui.view.ui and self.ui.view.ui.annotation then
            return self.ui.view.ui.annotation.annotations
        end
    end

    function Readeck:getAnnotationsForPath(path, options)
        options = options or {}
        if options.annotations then
            return options.annotations
        end
        if self.ui and self.ui.document and self.ui.document.file == path then
            return self:getCurrentAnnotations()
        end
        if DocSettings:hasSidecarFile(path) then
            return DocSettings:open(path):readSetting("annotations")
        end
    end

    function Readeck:saveAnnotationsForPath(path, annotations)
        if not path or not annotations then
            return true
        end

        local settings
        local is_current_document = self.ui and self.ui.document and self.ui.document.file == path
        if is_current_document and self.ui.doc_settings then
            settings = self.ui.doc_settings
        else
            settings = DocSettings:open(path)
        end
        if not settings or type(settings.saveSetting) ~= "function" then
            return false
        end

        settings:saveSetting("annotations", annotations)
        if not is_current_document then
            settings:saveSetting("annotations_externally_modified", true)
        end
        if type(settings.flush) == "function" then
            settings:flush()
        end
        return true
    end

    function Readeck:localHighlightOverlapsRemote(local_highlight, remote_highlight, profile)
        if Highlights.local_matches_remote_id(local_highlight, remote_highlight) then
            return true
        end
        local local_payload = Highlights.build_payload(local_highlight, profile)
        return local_payload and Highlights.overlap(local_payload, remote_highlight) or false
    end

    function Readeck:remoteHighlightExistsLocally(annotations, remote_highlight, profile)
        for _, local_highlight in pairs(annotations or {}) do
            if self:localHighlightOverlapsRemote(local_highlight, remote_highlight, profile) then
                return true
            end
        end
        return false
    end

    function Readeck:addRemoteHighlightToAnnotations(path, annotations, remote_highlight, options)
        local local_annotation, reason = Highlights.remote_to_local_annotation(remote_highlight)
        if not local_annotation then
            return false, reason
        end

        local is_current_document = self.ui and self.ui.document and self.ui.document.file == path
        if is_current_document and self.ui.annotation and type(self.ui.annotation.addItem) == "function" then
            if self.ui.toc and type(self.ui.toc.getTocTitleByPage) == "function" then
                local_annotation.chapter = self.ui.toc:getTocTitleByPage(local_annotation.page)
            end
            local index = self.ui.annotation:addItem(local_annotation)
            annotations = self.ui.annotation.annotations or annotations
            if self.ui.handleEvent then
                self.ui:handleEvent(Event:new("AnnotationsModified", {
                    local_annotation,
                    nb_highlights_added = 1,
                    index_modified = index,
                }))
            end
        else
            table.insert(annotations, local_annotation)
        end

        if not self:saveAnnotationsForPath(path, annotations, options) then
            return false, "save_failed"
        end
        return true
    end

    function Readeck:importRemoteHighlightsForPath(path, annotations, remote_highlights, profile, counts, options)
        if not path then
            return counts
        end
        annotations = annotations or {}
        counts = counts or new_highlight_counts()

        for _, remote_highlight in ipairs(remote_highlights or {}) do
            if self:remoteHighlightExistsLocally(annotations, remote_highlight, profile) then
                counts.import_skipped = counts.import_skipped + 1
            else
                local ok, reason = self:addRemoteHighlightToAnnotations(path, annotations, remote_highlight, options)
                if ok then
                    counts.imported = counts.imported + 1
                else
                    counts.import_failed = counts.import_failed + 1
                    Log:info("Skipping remote highlight import:", reason)
                end
            end
        end

        return counts
    end

    function Readeck:formatHighlightSyncMessage(counts)
        counts = counts or {}
        local message_parts = {}
        if (counts.imported or 0) > 0 then
            table.insert(message_parts, T(L("Imported: %1"), counts.imported))
        end
        if (counts.success or 0) > 0 then
            table.insert(message_parts, T(L("Exported: %1"), counts.success))
        end
        if (counts.error or 0) > 0 then
            table.insert(message_parts, T(L("Failed: %1"), counts.error))
        end
        if (counts.skipped or 0) > 0 then
            table.insert(message_parts, T(L("Skipped (overlap): %1"), counts.skipped))
        end
        if (counts.invalid or 0) > 0 then
            table.insert(message_parts, T(L("Skipped (unsupported): %1"), counts.invalid))
        end
        if (counts.import_failed or 0) > 0 then
            table.insert(message_parts, T(L("Import failed: %1"), counts.import_failed))
        end

        if #message_parts > 0 then
            return T(L("Finished syncing highlights.\n%1"), table.concat(message_parts, "\n"))
        end
        return L("Finished syncing highlights. No local or remote changes found.")
    end

    function Readeck:formatHighlightExportMessage(counts)
        return self:formatHighlightSyncMessage(counts)
    end

    function Readeck:syncHighlightsForArticle(article_id, path, annotations, options)
        options = options or {}
        annotations = annotations or {}

        if
            self:getBearerToken({
                on_oauth_success = function()
                    NetworkMgr:runWhenOnline(function()
                        self:syncHighlightsForArticle(article_id, path, annotations, options)
                    end)
                end,
            }) == false
        then
            return false, add_highlight_counts(new_highlight_counts(), { error = 1 })
        end

        local existing_highlights_raw, err = self:callAPI("GET", Api.paths.annotations(article_id), nil, "", "", true)
        local existing_highlights = {}
        if err then
            if err == "auth_pending" then
                return false, add_highlight_counts(new_highlight_counts(), { error = 1 })
            end
            if not options.quiet then
                UIManager:show(InfoMessage:new({
                    text = L("Could not fetch existing highlights from Readeck. Aborting highlight sync."),
                }))
            end
            return false, add_highlight_counts(new_highlight_counts(), { error = 1 })
        end
        if existing_highlights_raw and type(existing_highlights_raw) == "table" then
            existing_highlights = existing_highlights_raw
        end

        local highlight_profile = Features.highlight_payload_profile(self.server_info or self:refreshServerInfo(true))
        local counts = new_highlight_counts()
        self:importRemoteHighlightsForPath(path, annotations, existing_highlights, highlight_profile, counts, options)

        for _, h in pairs(annotations) do
            local local_highlight, skip_reason = Highlights.build_payload(h, highlight_profile)

            if local_highlight then
                local is_overlapping = false
                local is_remote_linked = false
                for _, remote_h in ipairs(existing_highlights) do
                    if Highlights.local_matches_remote_id(h, remote_h) then
                        is_overlapping = true
                        is_remote_linked = true
                        break
                    elseif Highlights.overlap(local_highlight, remote_h) then
                        is_overlapping = true
                        break
                    end
                end

                if is_overlapping then
                    if not is_remote_linked then
                        counts.skipped = counts.skipped + 1
                        Log:info("Skipping overlapping highlight:", local_highlight.text)
                    end
                else
                    local bodyJSON = JSON.encode(local_highlight)
                    Log:debug(
                        "Start selector:",
                        local_highlight.start_selector,
                        "End selector:",
                        local_highlight.end_selector
                    )
                    local headers = {
                        ["Content-type"] = "application/json",
                        ["Accept"] = "application/json, */*",
                        ["Content-Length"] = tostring(#bodyJSON),
                        ["Authorization"] = "Bearer " .. self.access_token,
                    }

                    local result = self:callAPI("POST", Api.paths.annotations(article_id), headers, bodyJSON, "", true)
                    if result then
                        counts.success = counts.success + 1
                        table.insert(existing_highlights, local_highlight)
                    else
                        counts.error = counts.error + 1
                    end
                end
            elseif skip_reason then
                counts.invalid = counts.invalid + 1
                Log:info("Skipping unsupported highlight:", skip_reason)
            end
        end

        if not options.quiet then
            UIManager:show(InfoMessage:new({ text = self:formatHighlightSyncMessage(counts) }))
        end
        return counts.error == 0 and counts.import_failed == 0, counts
    end

    function Readeck:exportHighlightsForArticle(article_id, annotations, options)
        return self:syncHighlightsForArticle(article_id, nil, annotations, options)
    end

    function Readeck:syncHighlightsForPath(path, options)
        options = options or {}
        local article_id = self:getArticleID(path)
        if not article_id then
            if not options.quiet then
                UIManager:show(InfoMessage:new({ text = L("Could not find Readeck article ID for this document.") }))
            end
            return false, add_highlight_counts(new_highlight_counts(), { error = 1 })
        end
        return self:syncHighlightsForArticle(article_id, path, self:getAnnotationsForPath(path, options), options)
    end

    function Readeck:exportHighlightsForPath(path, options)
        return self:syncHighlightsForPath(path, options)
    end

    function Readeck:syncHighlightsForLocalFiles(options)
        options = options or {}
        if self:isempty(self.directory) or lfs.attributes(self.directory, "mode") ~= "directory" then
            return true, new_highlight_counts()
        end

        local ok = true
        local total_counts = new_highlight_counts()
        for entry in lfs.dir(self.directory) do
            if entry ~= "." and entry ~= ".." then
                local path = FFIUtil.joinPath(self.directory, entry)
                if self:getArticleID(path) and lfs.attributes(path, "mode") == "file" then
                    local export_ok, export_counts = self:syncHighlightsForPath(path, options)
                    add_highlight_counts(total_counts, export_counts)
                    if export_ok == false then
                        ok = false
                    end
                end
            end
        end
        return ok, total_counts
    end

    function Readeck:exportHighlightsForLocalFiles(options)
        return self:syncHighlightsForLocalFiles(options)
    end

    function Readeck:syncCurrentDocumentHighlights(options)
        local document = self.ui.document
        if not document then
            if not (options and options.quiet) then
                UIManager:show(InfoMessage:new({ text = L("No document opened.") }))
            end
            return true
        end
        return self:syncHighlightsForPath(document.file, options)
    end

    function Readeck:exportCurrentDocumentHighlights(options)
        return self:syncCurrentDocumentHighlights(options)
    end

    function Readeck:syncHighlights()
        return self:syncCurrentDocumentHighlights({ quiet = false })
    end

    function Readeck:exportHighlights()
        return self:syncHighlights()
    end
end

return Export
