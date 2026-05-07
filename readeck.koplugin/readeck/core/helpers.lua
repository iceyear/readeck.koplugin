local FileManager = require("apps/filemanager/filemanager")
local Math = require("optmath")

local Helpers = {}

function Helpers.install(Readeck, deps)
    local article_id_suffix = deps.article_id_suffix
    local article_id_postfix = deps.article_id_postfix

    function Readeck:isempty(s)
        return s == nil or s == ""
    end

    function Readeck:clampDownloadConcurrency(value)
        return math.max(1, math.min(3, math.floor(tonumber(value) or 1)))
    end

    function Readeck:isReadeckDocumentPath(path)
        if not (path and self.directory and self.directory ~= "") then
            return false
        end
        local directory = self.directory
        if string.sub(directory, -1) ~= "/" then
            directory = directory .. "/"
        end
        return self:getArticleID(path) ~= nil and directory == string.sub(path, 1, string.len(directory))
    end

    function Readeck:getArticleID(path)
        local start_pos = path:find(article_id_suffix, 1, true)
        if not start_pos then
            return
        end

        local end_pos = path:find(article_id_postfix, start_pos)
        if not end_pos then
            return
        end

        local id_start = start_pos + article_id_suffix:len()
        local id_end = end_pos - 1
        return path:sub(id_start, id_end)
    end

    function Readeck:refreshCurrentDirIfNeeded()
        if FileManager.instance then
            FileManager.instance:onRefresh()
        end
    end

    function Readeck:getLastPercent()
        local percent = self.ui.paging and self.ui.paging:getLastPercent() or self.ui.rolling:getLastPercent()
        return Math.roundPercent(percent)
    end
end

return Helpers
