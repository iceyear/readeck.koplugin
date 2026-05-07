local BD = require("ui/bidi")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local ReadHistory = require("readhistory")
local UIManager = require("ui/uimanager")

local Events = {}

function Events.install(Readeck, deps)
    local L = deps.L
    local T = deps.T

    function Readeck:registerExternalLinkHandler()
        if self.ui and self.ui.link then
            self.ui.link:addToExternalLinkDialog("25_readeck", function(this, link_url)
                return {
                    text = L("Add to Readeck"),
                    callback = function()
                        UIManager:close(this.external_link_dialog)
                        this.ui:handleEvent(Event:new("AddReadeckArticle", link_url))
                    end,
                }
            end)
        end
    end

    function Readeck:onAddReadeckArticle(article_url)
        if not NetworkMgr:isOnline() then
            self:addToDownloadQueue(article_url)
            UIManager:show(InfoMessage:new({
                text = T(L("Article added to download queue:\n%1"), BD.url(article_url)),
                timeout = 1,
            }))
            return
        end

        local readeck_result, add_err = self:addArticle(article_url)
        if readeck_result then
            UIManager:show(InfoMessage:new({
                text = T(L("Article added to Readeck:\n%1"), BD.url(article_url)),
            }))
        elseif add_err == "auth_pending" then
            UIManager:show(InfoMessage:new({
                text = L("OAuth authorization started. Finish login and the article will be retried."),
            }))
        else
            UIManager:show(InfoMessage:new({
                text = T(L("Error adding link to Readeck:\n%1"), BD.url(article_url)),
            }))
        end

        return true
    end

    function Readeck:onSynchronizeReadeck()
        local connect_callback = function()
            self:synchronize()
            self:refreshCurrentDirIfNeeded()
        end
        NetworkMgr:runWhenOnline(connect_callback)

        return true
    end

    function Readeck:addToDownloadQueue(article_url)
        table.insert(self.download_queue, article_url)
        self:saveSettings()
    end

    function Readeck:onCloseDocument()
        local document_full_path = self.ui and self.ui.document and self.ui.document.file
        if self.auto_export_highlights and self:isReadeckDocumentPath(document_full_path) and NetworkMgr:isOnline() then
            local annotations = self:getCurrentAnnotations()
            NetworkMgr:runWhenOnline(function()
                self:syncHighlightsForPath(document_full_path, { quiet = true, annotations = annotations })
            end)
        end

        if document_full_path and (self.remove_finished_from_history or self.remove_read_from_history) then
            local summary = self.ui.doc_settings:readSetting("summary")
            local status = summary and summary.status
            local is_finished = status == "complete" or status == "abandoned"
            local is_read = self:getLastPercent() == 1

            if
                document_full_path
                and self.directory
                and ((self.remove_finished_from_history and is_finished) or (self.remove_read_from_history and is_read))
                and self:isReadeckDocumentPath(document_full_path)
            then
                ReadHistory:removeItemByPath(document_full_path)
                self.ui:setLastDirForFileBrowser(self.directory)
            end
        end
    end
end

return Events
