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

    it("keeps built-in language names in their native display form", function()
        assert.are.equal("English", I18n.language_native_name("en_US"))
        assert.are.equal("简体中文", I18n.language_native_name("zh_CN"))
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
        assert.are.equal("服务器 URL：%1", I18n.translate("Server URL: %1", nil, settings("zh_CN")))
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
        assert.are.equal("下载限制", I18n.translate("Download limits", nil, settings("zh_CN")))
        assert.are.equal("网络超时", I18n.translate("Network timeouts", nil, settings("zh_CN")))
        assert.are.equal("文章选择", I18n.translate("Article selection", nil, settings("zh_CN")))
        assert.are.equal("文章动作", I18n.translate("Article actions", nil, settings("zh_CN")))
        assert.are.equal("评分和评论标签", I18n.translate("Ratings and review tags", nil, settings("zh_CN")))
        assert.are.equal("日志等级：%1", I18n.translate("Log level: %1", nil, settings("zh_CN")))
        assert.are.equal("显示同步进度", I18n.translate("Show sync progress", nil, settings("zh_CN")))
        assert.are.equal("失败：%1", I18n.translate("Failed: %1", nil, settings("zh_CN")))
        assert.are.equal(
            "正在同步文章… 已检查 %1/%2",
            I18n.translate("Syncing articles… %1/%2 checked", nil, settings("zh_CN"))
        )
        assert.are.equal("正在同步高亮…", I18n.translate("Syncing highlights…", nil, settings("zh_CN")))
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
            "合并本地和远端变更",
            I18n.translate("Merge local and remote changes", nil, settings("zh_CN"))
        )
        assert.are.equal(
            "新版 Readeck（0.22.2+）",
            I18n.translate("Modern Readeck (0.22.2+)", nil, settings("zh_CN"))
        )
        assert.are.equal(
            "仅保留在本地的高亮：%1",
            I18n.translate("Highlights kept local only: %1", nil, settings("zh_CN"))
        )
        assert.are.equal("简体中文", I18n.translate("Simplified Chinese", nil, settings("zh_CN")))
        assert.are.equal("星级阈值", I18n.translate("Star rating threshold", nil, settings("zh_CN")))
    end)

    it("covers the article browser", function()
        local zh = settings("zh_CN")
        assert.are.equal("浏览文章", I18n.translate("Browse articles", nil, zh))
        assert.are.equal("显示 %1 篇文章", I18n.translate("Show %1 articles", nil, zh))
        assert.are.equal("%1 篇文章 · 更新于 %2", I18n.translate("%1 articles · updated %2", nil, zh))
        assert.are.equal(
            "%1 篇已下载文章 · 离线列表",
            I18n.translate("%1 downloaded articles · offline list", nil, zh)
        )
        assert.are.equal("按标签细分", I18n.translate("Refine by label", nil, zh))
        assert.are.equal("隐藏同步跳过的内容", I18n.translate("Hide what sync skips", nil, zh))
        assert.are.equal("%1 · 已隐藏 %2 篇", I18n.translate("%1 · %2 hidden", nil, zh))
        assert.are.equal("重建文章列表", I18n.translate("Rebuild article list", nil, zh))
        assert.are.equal(
            "暂无可浏览的内容。请连接服务器获取文章列表。",
            I18n.translate("Nothing to browse yet. Connect to the server to fetch the article list.", nil, zh)
        )
    end)

    it("covers the browser bucket and sort labels rendered through raw tables", function()
        local zh = settings("zh_CN")
        for english, chinese in pairs({
            ["All"] = "全部",
            ["Unread"] = "未读",
            ["Archived"] = "已归档",
            ["Favorite"] = "收藏",
            ["Collections"] = "收藏集",
            ["By label"] = "按标签",
            ["By source"] = "按来源",
            ["Newest first"] = "最新优先",
            ["Oldest first"] = "最早优先",
            ["Longest read"] = "阅读时长最长",
            ["Shortest read"] = "阅读时长最短",
            ["Most read"] = "阅读最多",
        }) do
            assert.are.equal(chinese, I18n.translate(english, nil, zh))
        end
    end)

    it("covers relative catalog ages", function()
        local zh = settings("zh_CN")
        assert.are.equal("刚刚", I18n.translate("just now", nil, zh))
        assert.are.equal("%1 小时前", I18n.translate("%1 hours ago", nil, zh))
        assert.are.equal("%1 天前", I18n.translate("%1 days ago", nil, zh))
        assert.are.equal("%1 分钟", I18n.translate("%1 min", nil, zh))
    end)
end)
