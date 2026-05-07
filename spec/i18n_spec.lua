package.path = "./readeck.koplugin/?.lua;" .. package.path

local I18n = require("readeck.i18n")

local function settings(language)
    return {
        readSetting = function(_, key)
            if key == "language" then
                return language
            end
        end,
    }
end

describe("readeck.i18n", function()
    after_each(function()
        I18n.set_language_override("")
    end)

    it("defaults to English", function()
        assert.are.equal("Readeck sync", I18n.translate("Readeck sync", nil, settings("en_US")))
    end)

    it("uses Chinese supplement for Chinese KOReader language", function()
        assert.are.equal("Readeck 同步", I18n.translate("Readeck sync", nil, settings("zh_CN")))
    end)

    it("can override the KOReader language", function()
        I18n.set_language_override("zh-cn")
        assert.are.equal("Readeck 同步", I18n.translate("Readeck sync", nil, settings("en_US")))

        I18n.set_language_override("en")
        assert.are.equal("Readeck sync", I18n.translate("Readeck sync", nil, settings("zh_CN")))
        assert.are.equal(
            "Cancel",
            I18n.translate("Cancel", function()
                return "取消"
            end, settings("zh_CN"))
        )
    end)

    it("prefers KOReader gettext when it already has a translation", function()
        local gettext = function(message)
            if message == "Cancel" then
                return "KO Cancel"
            end
            return message
        end

        assert.are.equal("KO Cancel", I18n.translate("Cancel", gettext, settings("zh_CN")))
    end)

    it("covers Readeck menu labels that KOReader does not own", function()
        assert.are.equal("全部文章", I18n.translate("All articles", nil, settings("zh_CN")))
        assert.are.equal("文章排序", I18n.translate("Sort articles by", nil, settings("zh_CN")))
        assert.are.equal(
            "添加时间，最新优先",
            I18n.translate("Added, most recent first", nil, settings("zh_CN"))
        )
        local like_label = I18n.translate("Like entries in Readeck: %1", nil, settings("zh_CN"))
            :gsub("%%1", "已禁用")
        assert.are.equal("在 Readeck 中喜欢条目：已禁用", like_label)
        assert.are.equal(
            "用星级标签标记 Readeck 条目",
            I18n.translate("Label entries in Readeck with their star rating", nil, settings("zh_CN"))
        )
        assert.are.equal("认证", I18n.translate("Authentication", nil, settings("zh_CN")))
        assert.are.equal("失败：%1", I18n.translate("Failed: %1", nil, settings("zh_CN")))
        assert.are.equal(
            "正在同步文章… 已检查 %1/%2",
            I18n.translate("Syncing articles… %1/%2 checked", nil, settings("zh_CN"))
        )
        assert.are.equal(
            "即将在 Readeck 中归档：%1",
            I18n.translate("Will archive in Readeck: %1", nil, settings("zh_CN"))
        )
        assert.are.equal(
            "同步阅读进度到 Readeck",
            I18n.translate("Sync reading progress to Readeck", nil, settings("zh_CN"))
        )
        assert.are.equal(
            "同步阅读进度到 Readeck（Beta）",
            I18n.translate("Sync reading progress to Readeck (beta)", nil, settings("zh_CN"))
        )
        assert.are.equal(
            "已同步阅读进度：%1",
            I18n.translate("Reading progress synced: %1", nil, settings("zh_CN"))
        )
        assert.are.equal("已导入高亮：%1", I18n.translate("Highlights imported: %1", nil, settings("zh_CN")))
        assert.are.equal("已导出高亮：%1", I18n.translate("Highlights exported: %1", nil, settings("zh_CN")))
        assert.are.equal(
            "同步当前文章高亮",
            I18n.translate("Sync current article highlights", nil, settings("zh_CN"))
        )
        assert.are.equal("尊重远端删除", I18n.translate("Respect remote deletions", nil, settings("zh_CN")))
        assert.are.equal(
            "仅保留在本地的高亮：%1",
            I18n.translate("Highlights kept local only: %1", nil, settings("zh_CN"))
        )
        assert.are.equal("简体中文", I18n.translate("Simplified Chinese", nil, settings("zh_CN")))
        assert.are.equal("星级阈值", I18n.translate("Star rating threshold", nil, settings("zh_CN")))
    end)
end)
