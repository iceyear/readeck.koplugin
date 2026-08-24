local function install_koreader_stubs()
    for name in pairs(package.loaded) do
        if name == "readeck" or name:match("^readeck%.") then
            package.loaded[name] = nil
        end
    end

    local function widget()
        return {
            new = function(_, options)
                return options or {}
            end,
        }
    end

    local function template(text, ...)
        local values = { ... }
        return (
            text:gsub("%%(%d+)", function(index)
                return tostring(values[tonumber(index)] or "")
            end)
        )
    end

    package.preload["ui/bidi"] = function()
        return {
            dirpath = function(path)
                return path
            end,
            url = function(url)
                return url
            end,
        }
    end
    package.preload["datastorage"] = function()
        return {
            getSettingsDir = function()
                return "/tmp"
            end,
        }
    end
    package.preload["device"] = function()
        return {
            canOpenLink = true,
            openLink = function()
                return true
            end,
            screen = {
                getWidth = function()
                    return 600
                end,
                getHeight = function()
                    return 800
                end,
            },
        }
    end
    package.preload["dispatcher"] = function()
        return {
            registerAction = function() end,
        }
    end
    package.preload["docsettings"] = function()
        return {
            hasSidecarFile = function()
                return false
            end,
        }
    end
    package.preload["ui/event"] = function()
        return {
            new = function(_, name, payload)
                return { name = name, payload = payload }
            end,
        }
    end
    package.preload["ffi/util"] = function()
        return {
            template = template,
            joinPath = function(left, right)
                return left .. "/" .. right
            end,
        }
    end
    package.preload["apps/filemanager/filemanager"] = function()
        return {
            showFiles = function() end,
            deleteFile = function() end,
        }
    end
    package.preload["apps/filemanager/filemanagerutil"] = function()
        return {
            abbreviate = function(path)
                return path
            end,
            openFile = function() end,
        }
    end
    package.preload["ui/widget/infomessage"] = function()
        return widget()
    end
    package.preload["ui/widget/inputdialog"] = function()
        return widget()
    end
    package.preload["ui/widget/buttondialog"] = function()
        return widget()
    end
    package.preload["ui/widget/confirmbox"] = function()
        return widget()
    end
    package.preload["ui/widget/qrmessage"] = function()
        return widget()
    end
    package.preload["ui/widget/radiobuttonwidget"] = function()
        return widget()
    end
    package.preload["frontend/luasettings"] = function()
        return {
            open = function()
                return {
                    data = { readeck = {} },
                    readSetting = function() end,
                    saveSetting = function() end,
                    flush = function() end,
                }
            end,
        }
    end
    package.preload["optmath"] = function()
        return {
            roundPercent = function(value)
                return value
            end,
            round = function(value)
                return math.floor(value + 0.5)
            end,
        }
    end
    package.preload["ui/widget/multiconfirmbox"] = function()
        return widget()
    end
    package.preload["ui/widget/multiinputdialog"] = function()
        return widget()
    end
    package.preload["ui/network/manager"] = function()
        return {
            isOnline = function()
                return true
            end,
            isConnected = function()
                return true
            end,
            -- Both are called colon-style everywhere in the plugin, so the stub has to
            -- take self; without it the callback lands in the self slot and is never run.
            runWhenOnline = function(_, callback)
                callback()
            end,
            runWhenConnected = function(_, callback)
                callback()
            end,
        }
    end
    package.preload["ui/widget/booklist"] = function()
        local BookList = {
            book_info_cache = {},
            extend = function(parent, class)
                class = class or {}
                for key, value in pairs(parent) do
                    if class[key] == nil then
                        class[key] = value
                    end
                end
                class.new = function(cls, options)
                    local instance = options or {}
                    for key, value in pairs(cls) do
                        if instance[key] == nil then
                            instance[key] = value
                        end
                    end
                    if instance.init then
                        instance:init()
                    end
                    return instance
                end
                return class
            end,
            init = function() end,
            getBookInfo = function()
                return { been_opened = false }
            end,
            resetBookInfoCache = function() end,
            switchItemTable = function() end,
            updateItems = function() end,
        }
        return BookList
    end
    package.preload["ui/trapper"] = function()
        return {
            wrap = function(_, task)
                task()
            end,
            isWrapped = function()
                return true
            end,
            info = function()
                return true
            end,
            clear = function() end,
            confirm = function()
                return false
            end,
        }
    end
    package.preload["readhistory"] = function()
        return {
            removeItemByPath = function() end,
        }
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function() end,
            close = function() end,
            forceRePaint = function() end,
            nextTick = function(_, callback)
                callback()
            end,
            scheduleIn = function(_, delay_or_callback, maybe_callback)
                local callback = maybe_callback or delay_or_callback
                callback()
            end,
            unschedule = function() end,
        }
    end
    package.preload["ui/widget/container/widgetcontainer"] = function()
        return {
            extend = function(_, class)
                return class
            end,
        }
    end
    package.preload["json"] = function()
        return {
            encode = function()
                return "{}"
            end,
            decode = function()
                return {}
            end,
        }
    end
    package.preload["libs/libkoreader-lfs"] = function()
        return {
            attributes = function()
                return nil
            end,
            dir = function()
                return function()
                    return nil
                end
            end,
            touch = function()
                return true
            end,
        }
    end
    package.preload["logger"] = function()
        return {
            info = function() end,
            warn = function() end,
            err = function() end,
        }
    end
    package.preload["ltn12"] = function()
        return {
            sink = {
                file = function()
                    return function() end
                end,
                table = function()
                    return function() end
                end,
            },
            source = {
                string = function()
                    return function() end
                end,
            },
        }
    end
    package.preload["socket"] = function()
        return {
            skip = function(_, ...)
                return ...
            end,
            gettime = function()
                return 0
            end,
        }
    end
    package.preload["socket.http"] = function()
        return {
            request = function()
                return nil
            end,
        }
    end
    package.preload["socketutil"] = function()
        return {
            set_timeout = function() end,
            reset_timeout = function() end,
            file_sink = function(handle)
                return function(chunk)
                    if chunk and handle then
                        handle:write(chunk)
                    end
                    return 1
                end
            end,
            table_sink = function(target)
                return function(chunk)
                    if chunk then
                        table.insert(target, chunk)
                    end
                    return 1
                end
            end,
        }
    end
    package.preload["util"] = function()
        return {
            getSafeFilename = function(title)
                return title or "article"
            end,
            gsplit = function()
                return function()
                    return nil
                end
            end,
        }
    end
    package.preload["gettext"] = function()
        return setmetatable({ current_lang = "en" }, {
            __call = function(_, text)
                return text
            end,
        })
    end
end

local function collect_menu_texts(items, texts)
    texts = texts or {}
    for _, item in ipairs(items or {}) do
        local text = item.text
        if not text and item.text_func then
            local ok, value = pcall(item.text_func)
            assert.is_true(ok, value)
            text = value
        end
        if text then
            table.insert(texts, text)
        end
        local sub_items = item.sub_item_table
        if not sub_items and item.sub_item_table_func then
            sub_items = item.sub_item_table_func()
        end
        collect_menu_texts(sub_items, texts)
    end
    return texts
end

local function find_menu_item(items, expected_text)
    for _, item in ipairs(items or {}) do
        local text = item.text
        if not text and item.text_func then
            local ok, value = pcall(item.text_func)
            assert.is_true(ok, value)
            text = value
        end
        if text == expected_text then
            return item
        end
    end
end

local function stub_instance(overrides)
    local instance = {
        directory = "/tmp/readeck",
        ui = {},
        language_override = "",
        filter_tag = "",
        sort_param = "-created",
        sort_options = { { "-created", "Added, most recent first" } },
        ignore_tags = "",
        auto_tags = "",
        completion_action_finished_enabled = true,
        completion_action_read_enabled = false,
        archive_instead_of_delete = true,
        process_completion_on_sync = false,
        sync_reading_progress = true,
        remove_local_missing_remote = false,
        export_highlights_before_sync = true,
        auto_export_highlights = true,
        periodic_sync_enabled = false,
        periodic_sync_interval_minutes = 60,
        remote_star_threshold = 0,
        sync_star_rating_as_label = false,
        send_review_as_tags = false,
        remove_finished_from_history = false,
        remove_read_from_history = false,
        sync_star_status = false,
        auth_token = "",
        access_token = "",
        oauth_refresh_token = "",
        isempty = function(_, value)
            return value == nil or value == ""
        end,
        getLanguageOverrideLabel = function()
            return "Follow KOReader language"
        end,
        getLogLevelLabel = function()
            return "Info"
        end,
        getArticleID = function()
            return nil
        end,
    }
    for key, value in pairs(overrides or {}) do
        instance[key] = value
    end
    return instance
end

local function run_menu_smoke()
    package.path = "./readeck.koplugin/?.lua;" .. package.path
    install_koreader_stubs()
    local Readeck = dofile("readeck.koplugin/main.lua")
    local menu_items = {}
    Readeck.addToMainMenu(stub_instance(), menu_items)
    assert.is.truthy(menu_items.readeck)
    assert.are.equal("Readeck", menu_items.readeck.text)

    local texts = collect_menu_texts(menu_items.readeck.sub_item_table_func())
    assert.is_true(table.concat(texts, "\n"):find("Highlights", 1, true) ~= nil)
    assert.is_true(table.concat(texts, "\n"):find("Periodic sync", 1, true) ~= nil)
    assert.is_true(table.concat(texts, "\n"):find("Configure Readeck client", 1, true) ~= nil)
    assert.is_true(table.concat(texts, "\n"):find("About", 1, true) ~= nil)
    assert.is_true(table.concat(texts, "\n"):find("Restore default settings", 1, true) ~= nil)
    assert.is_false(table.concat(texts, "\n"):find("Sync current article highlights", 1, true) ~= nil)
end

describe("KOReader smoke", function()
    it("loads the plugin class and builds the main menu with KOReader-shaped APIs", function()
        run_menu_smoke()
        local metadata = dofile("readeck.koplugin/_meta.lua")
        assert.are.equal("0.1.1", metadata.version)
    end)

    it("shows license and source repository in the About dialog", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local shown
        package.loaded["ui/widget/infomessage"] = nil
        package.preload["ui/widget/infomessage"] = function()
            return {
                new = function(_, options)
                    return options or {}
                end,
            }
        end
        package.loaded["ui/uimanager"] = nil
        package.preload["ui/uimanager"] = function()
            return {
                show = function(_, widget)
                    shown = widget
                end,
                close = function() end,
                forceRePaint = function() end,
                scheduleIn = function(_, delay_or_callback, maybe_callback)
                    local callback = maybe_callback or delay_or_callback
                    callback()
                end,
                unschedule = function() end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({}, { __index = Readeck })
        instance:showAboutDialog()

        assert.is.truthy(shown)
        assert.is_true(shown.text:find("Version: 0.1.1", 1, true) ~= nil)
        assert.is_true(shown.text:find("License: MIT", 1, true) ~= nil)
        assert.is_true(shown.text:find("https://github.com/iceyear/readeck.koplugin", 1, true) ~= nil)
    end)

    it("groups client network controls under the Readeck client submenu", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local menu_items = {}
        Readeck.addToMainMenu(stub_instance(), menu_items)

        local readeck_items = menu_items.readeck.sub_item_table_func()
        local settings_item = find_menu_item(readeck_items, "Settings")
        assert.is.truthy(settings_item)

        local settings_items = settings_item.sub_item_table_func()
        assert.is_nil(find_menu_item(settings_items, "Experimental subprocess downloads"))
        assert.is_nil(find_menu_item(settings_items, "Network timeouts"))

        local client_item = find_menu_item(settings_items, "Configure Readeck client")
        assert.is.truthy(client_item)
        local client_items = client_item.sub_item_table_func()
        assert.is.truthy(find_menu_item(client_items, "Download limits"))
        assert.is.truthy(find_menu_item(client_items, "Experimental subprocess downloads"))
        assert.is.truthy(find_menu_item(client_items, "Network timeouts"))
    end)

    it("shows current-article highlight sync only for opened Readeck articles", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local menu_items = {}
        Readeck.addToMainMenu(
            stub_instance({
                ui = {
                    document = {
                        file = "/tmp/readeck/Article [rd-id_abc123].epub",
                    },
                },
                getArticleID = function(_, path)
                    return path:match("%[rd%-id_([^%]]+)%]")
                end,
            }),
            menu_items
        )

        local texts = table.concat(collect_menu_texts(menu_items.readeck.sub_item_table_func()), "\n")
        assert.is_true(texts:find("Sync current article highlights", 1, true) ~= nil)
    end)

    it("fetches article lists through KOReader async HTTP when available", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local request_url
        local request_headers

        package.loaded["json"] = nil
        package.preload["json"] = function()
            return {
                encode = function()
                    return "{}"
                end,
                decode = function()
                    return {
                        { id = "article-a", labels = {} },
                        { id = "article-b", labels = {} },
                    }
                end,
            }
        end
        package.loaded.httpclient = nil
        package.preload.httpclient = function()
            return {
                new = function()
                    return {
                        request = function(_, request, callback)
                            request_url = request.url
                            local headers = {
                                values = {},
                                add = function(self, key, value)
                                    self.values[key] = value
                                end,
                            }
                            request.on_headers(headers)
                            request_headers = headers.values
                            callback({ code = 200, body = "[]" })
                        end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        require("ui/uimanager").looper = {
            add_callback = function() end,
        }
        local instance = setmetatable({
            access_token = "token",
            articles_per_sync = 2,
            filter_tag = "",
            ignore_tags = "",
            server_url = "https://readeck.example",
            sort_param = "-created",
        }, { __index = Readeck })

        local done_articles
        local done_err
        local async = instance:getArticleListAsync(function(articles, err)
            done_articles = articles
            done_err = err
        end)

        assert.is_true(async)
        assert.is_nil(done_err)
        assert.are.equal(2, #done_articles)
        assert.are.equal(
            "https://readeck.example/api/bookmarks?limit=2&offset=0&is_archived=0&type=article&sort=-created",
            request_url
        )
        assert.are.equal("Bearer token", request_headers.Authorization)
    end)

    it("falls back to blocking article list fetch when KOReader async HTTP cannot start", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()

        package.loaded.httpclient = nil
        package.preload.httpclient = function()
            return {
                new = function()
                    return {
                        request = function()
                            error("frontend/httpclient.lua:18: attempt to index field 'looper'")
                        end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        require("ui/uimanager").looper = {
            add_callback = function() end,
        }
        local blocking_fetches = 0
        local instance = setmetatable({
            access_token = "token",
            articles_per_sync = 2,
            filter_tag = "",
            ignore_tags = "",
            server_url = "https://readeck.example",
            sort_param = "-created",
            getArticleList = function()
                blocking_fetches = blocking_fetches + 1
                return {
                    { id = "fallback-article", labels = {} },
                }
            end,
        }, { __index = Readeck })

        local done_articles
        local done_err
        instance:getArticleListAsync(function(articles, err)
            done_articles = articles
            done_err = err
        end)

        assert.is_nil(done_err)
        assert.are.equal(1, blocking_fetches)
        assert.are.equal("fallback-article", done_articles[1].id)
        assert.is_true(instance.article_list_http_client_disabled)
    end)

    it("does not start KOReader async HTTP when the turbo looper is inactive", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()

        local UIManager = require("ui/uimanager")
        UIManager.looper = nil

        package.loaded.httpclient = nil
        package.preload.httpclient = function()
            error("httpclient should not be required without an active looper")
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local blocking_fetches = 0
        local instance = setmetatable({
            access_token = "token",
            articles_per_sync = 2,
            filter_tag = "",
            ignore_tags = "",
            server_url = "https://readeck.example",
            sort_param = "-created",
            getArticleList = function()
                blocking_fetches = blocking_fetches + 1
                return {
                    { id = "blocking-article", labels = {} },
                }
            end,
        }, { __index = Readeck })

        local done_articles
        local async = instance:getArticleListAsync(function(articles)
            done_articles = articles
        end)

        assert.is_false(async)
        assert.are.equal(1, blocking_fetches)
        assert.are.equal("blocking-article", done_articles[1].id)
    end)

    it("opens the active OAuth verification link through KOReader's device API", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local opened_link
        package.loaded["device"] = nil
        package.preload["device"] = function()
            return {
                canOpenLink = function()
                    return true
                end,
                openLink = function(_, link)
                    opened_link = link
                    return true
                end,
                screen = {
                    getWidth = function()
                        return 600
                    end,
                    getHeight = function()
                        return 800
                    end,
                },
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            oauth_poll_state = {
                done = false,
                verification_uri_complete = "https://readeck.example/device?user_code=ABCD",
                fallback_uri = "https://readeck.example/device",
            },
        }, { __index = Readeck })

        assert.is_true(instance:openOAuthPollingLink())
        assert.are.equal("https://readeck.example/device?user_code=ABCD", opened_link)
    end)

    it("restores defaults and clears credentials", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local saved_settings
        local rescheduled = false
        local instance = setmetatable({
            rd_settings = {
                saveSetting = function(_, key, value)
                    if key == "readeck" then
                        saved_settings = value
                    end
                end,
                flush = function() end,
            },
            server_url = "https://readeck.example",
            auth_token = "api-secret",
            access_token = "access-secret",
            oauth_client_id = "client-id",
            oauth_refresh_token = "refresh-secret",
            cached_auth_token = "api-secret",
            cached_server_url = "https://readeck.example",
            cached_auth_method = "api_token",
            directory = "/tmp/readeck",
            download_queue = { "https://example/article" },
            periodic_sync_enabled = true,
            language_override = "zh-cn",
            reschedulePeriodicSync = function()
                rescheduled = true
            end,
        }, { __index = Readeck })

        instance:resetSettingsToDefaults()

        assert.is_nil(instance.server_url)
        assert.is_nil(instance.directory)
        assert.are.equal("", instance.auth_token)
        assert.are.equal("", instance.access_token)
        assert.are.equal("", instance.oauth_client_id)
        assert.are.equal("", instance.oauth_refresh_token)
        assert.are.same({}, instance.download_queue)
        assert.is_false(instance.periodic_sync_enabled)
        assert.are.equal("", instance.language_override)
        assert.is_true(rescheduled)
        assert.are.equal("", saved_settings.auth_token)
        assert.are.equal("", saved_settings.access_token)
        assert.are.equal("", saved_settings.oauth_refresh_token)
    end)

    it("migrates legacy subprocess downloads back to explicit opt-in", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local Defaults = require("readeck.core.defaults")
        local instance = setmetatable({}, { __index = Readeck })
        Defaults.apply(instance)

        local settings = {
            completion_action_sync_policy_version = Defaults.COMPLETION_ACTION_SYNC_POLICY_VERSION,
            experimental_async_downloads = true,
        }
        instance:loadSettingsIntoState(settings)

        assert.is_true(instance.experimental_async_downloads)
        assert.is_true(instance:migrateSettingsIfNeeded(settings))
        assert.is_false(instance.experimental_async_downloads)
        assert.is_false(settings.experimental_async_downloads)
        assert.are.equal(
            Defaults.EXPERIMENTAL_ASYNC_DOWNLOADS_OPT_IN_VERSION,
            instance.experimental_async_downloads_opt_in_version
        )
        assert.are.equal(
            Defaults.EXPERIMENTAL_ASYNC_DOWNLOADS_OPT_IN_VERSION,
            settings.experimental_async_downloads_opt_in_version
        )
    end)

    it("loads the configured plugin log level into the logger filter", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local Defaults = require("readeck.core.defaults")
        local Log = require("readeck.core.log")
        local instance = setmetatable({}, { __index = Readeck })
        Defaults.apply(instance)

        instance:loadSettingsIntoState({ log_level = "warn" })

        assert.are.equal("warn", instance.log_level)
        assert.are.equal(Log.WARN, Log.level)
        assert.are.equal("Warnings", instance:getLogLevelLabel())
    end)

    it("imports Readeck annotations into KOReader sidecars during highlight sync", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Article [rd-id_abc123].epub"
        local saved_annotations
        local post_count = 0

        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                hasSidecarFile = function()
                    return false
                end,
                open = function()
                    return {
                        saveSetting = function(_, key, value)
                            if key == "annotations" then
                                saved_annotations = value
                            end
                        end,
                        flush = function() end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            access_token = "token",
            server_info = { version = { canonical = "0.22.2" } },
            getBearerToken = function()
                return true
            end,
            getArticleID = function()
                return "abc123"
            end,
            callAPI = function(_, method, path)
                if method == "GET" and path == "/api/bookmarks/abc123/annotations" then
                    return {
                        {
                            id = "remote-1",
                            text = "remote text",
                            note = "remote note",
                            color = "green",
                            start_selector = "section/p[2]",
                            start_offset = 4,
                            end_selector = "section/p[2]",
                            end_offset = 15,
                            created = "2026-05-06T17:47:45Z",
                        },
                    }
                end
                if method == "POST" then
                    post_count = post_count + 1
                end
                return true
            end,
        }, { __index = Readeck })

        local ok, counts = instance:syncHighlightsForPath(article_path, { quiet = true })

        assert.is_true(ok)
        assert.are.equal(1, counts.imported)
        assert.are.equal(0, counts.success)
        assert.are.equal(0, post_count)
        assert.are.equal("remote-1", saved_annotations[1].readeck_annotation_id)
        assert.are.equal("section/p[2].4", saved_annotations[1].pos0)
        assert.are.equal("remote note", saved_annotations[1].note)
    end)

    it("keeps remote-deleted linked highlights local-only when configured", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local post_count = 0
        local instance = setmetatable({
            access_token = "token",
            highlight_sync_policy = "respect_remote_deletions",
            server_info = { version = { canonical = "0.22.2" } },
            getBearerToken = function()
                return true
            end,
            callAPI = function(_, method, path)
                if method == "GET" and path == "/api/bookmarks/abc123/annotations" then
                    return {}
                end
                if method == "POST" then
                    post_count = post_count + 1
                end
                return true
            end,
        }, { __index = Readeck })

        local ok, counts = instance:syncHighlightsForArticle("abc123", nil, {
            {
                readeck_annotation_id = "deleted-remote-id",
                drawer = "lighten",
                text = "local text",
                pos0 = "section/p[2].4",
                pos1 = "section/p[2].15",
            },
        }, { quiet = true })

        assert.is_true(ok)
        assert.are.equal(0, post_count)
        assert.are.equal(1, counts.remote_deleted)
        assert.are.equal(0, counts.success)
    end)

    it("stores returned Readeck annotation IDs after exporting local highlights", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Article [rd-id_abc123].epub"
        local local_annotations = {
            {
                drawer = "lighten",
                text = "local text",
                pos0 = "section/p[2].4",
                pos1 = "section/p[2].15",
            },
        }
        local saved_annotations

        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                hasSidecarFile = function()
                    return true
                end,
                open = function()
                    return {
                        readSetting = function()
                            return local_annotations
                        end,
                        saveSetting = function(_, key, value)
                            if key == "annotations" then
                                saved_annotations = value
                            end
                        end,
                        flush = function() end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            access_token = "token",
            highlight_sync_policy = "preserve_local",
            server_info = { version = { canonical = "0.22.2" } },
            getBearerToken = function()
                return true
            end,
            getArticleID = function()
                return "abc123"
            end,
            callAPI = function(_, method, path)
                if method == "GET" and path == "/api/bookmarks/abc123/annotations" then
                    return {}
                end
                if method == "POST" and path == "/api/bookmarks/abc123/annotations" then
                    return {
                        id = "created-remote-id",
                        start_selector = "section/p[2]",
                        start_offset = 4,
                        end_selector = "section/p[2]",
                        end_offset = 15,
                    }
                end
                return true
            end,
        }, { __index = Readeck })

        local ok, counts = instance:syncHighlightsForPath(article_path, { quiet = true })

        assert.is_true(ok)
        assert.are.equal(1, counts.success)
        assert.are.equal("created-remote-id", local_annotations[1].readeck_annotation_id)
        assert.are.equal("created-remote-id", saved_annotations[1].readeck_annotation_id)
    end)

    it("syncs local highlight files in scheduled slices", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local scheduled = 0
        local entries = { "First [rd-id_a].epub", "Second [rd-id_b].epub" }

        package.loaded["ui/uimanager"] = nil
        package.preload["ui/uimanager"] = function()
            return {
                show = function() end,
                close = function() end,
                forceRePaint = function() end,
                scheduleIn = function(_, delay_or_callback, maybe_callback)
                    local callback = maybe_callback or delay_or_callback
                    scheduled = scheduled + 1
                    callback()
                end,
                unschedule = function() end,
            }
        end
        package.loaded["libs/libkoreader-lfs"] = nil
        package.preload["libs/libkoreader-lfs"] = function()
            return {
                attributes = function(path, key)
                    local attrs
                    if path == "/tmp/readeck" then
                        attrs = { mode = "directory" }
                    elseif path:match("%.epub$") then
                        attrs = { mode = "file" }
                    end
                    if attrs and key then
                        return attrs[key]
                    end
                    return attrs
                end,
                dir = function()
                    local index = 0
                    return function()
                        index = index + 1
                        return entries[index]
                    end
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local synced_paths = {}
        local progress = {}
        local done_counts
        local instance = setmetatable({
            directory = "/tmp/readeck",
            isempty = function(_, value)
                return value == nil or value == ""
            end,
            getArticleID = function(_, path)
                return path:match("%[rd%-id_([^%]]+)%]")
            end,
            syncHighlightsForPath = function(_, path)
                table.insert(synced_paths, path)
                return true, { success = 1 }
            end,
        }, { __index = Readeck })

        instance:syncHighlightsForLocalFilesAsync({
            on_progress = function(completed, total)
                table.insert(progress, completed .. "/" .. total)
            end,
        }, function(_, counts)
            done_counts = counts
        end)

        assert.are.same({
            "/tmp/readeck/First [rd-id_a].epub",
            "/tmp/readeck/Second [rd-id_b].epub",
        }, synced_paths)
        assert.are.same({ "0/2", "1/2", "2/2" }, progress)
        assert.are.equal(2, done_counts.success)
        assert.is_true(scheduled >= 2)
    end)

    it("updates linked KOReader highlights when Readeck note or color changed", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Article [rd-id_abc123].epub"
        local local_annotations = {
            {
                readeck_annotation_id = "remote-1",
                drawer = "lighten",
                text = "local text",
                note = "old note",
                color = "yellow",
                readeck_synced_note = "old note",
                readeck_synced_color = "yellow",
                pos0 = "section/p[2].4",
                pos1 = "section/p[2].15",
            },
        }
        local saved_annotations
        local patch_count = 0

        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                hasSidecarFile = function()
                    return true
                end,
                open = function()
                    return {
                        readSetting = function()
                            return local_annotations
                        end,
                        saveSetting = function(_, key, value)
                            if key == "annotations" then
                                saved_annotations = value
                            end
                        end,
                        flush = function() end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            access_token = "token",
            highlight_feature_policy = "modern",
            getBearerToken = function()
                return true
            end,
            getArticleID = function()
                return "abc123"
            end,
            callAPI = function(_, method, path)
                if method == "GET" and path == "/api/bookmarks/abc123/annotations" then
                    return {
                        {
                            id = "remote-1",
                            text = "local text",
                            note = "remote note",
                            color = "blue",
                            start_selector = "section/p[2]",
                            start_offset = 4,
                            end_selector = "section/p[2]",
                            end_offset = 15,
                        },
                    }
                end
                if method == "PATCH" then
                    patch_count = patch_count + 1
                end
                return true
            end,
        }, { __index = Readeck })

        local ok, counts = instance:syncHighlightsForPath(article_path, { quiet = true })

        assert.is_true(ok)
        assert.are.equal(1, counts.updated_local)
        assert.are.equal(0, counts.updated_remote)
        assert.are.equal(0, patch_count)
        assert.are.equal("remote note", local_annotations[1].note)
        assert.are.equal("blue", local_annotations[1].color)
        assert.are.equal("remote note", saved_annotations[1].readeck_synced_note)
        assert.are.equal("blue", saved_annotations[1].readeck_synced_color)
    end)

    it("patches linked Readeck annotations when KOReader note or color changed", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local encoded_body

        package.loaded["json"] = nil
        package.preload["json"] = function()
            return {
                encode = function(body)
                    encoded_body = body
                    return "{}"
                end,
                decode = function()
                    return {}
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local patch_path
        local local_annotations = {
            {
                readeck_annotation_id = "remote-1",
                drawer = "lighten",
                text = "local text",
                note = "local note",
                color = "green",
                readeck_synced_note = "old note",
                readeck_synced_color = "yellow",
                pos0 = "section/p[2].4",
                pos1 = "section/p[2].15",
            },
        }
        local instance = setmetatable({
            access_token = "token",
            highlight_feature_policy = "modern",
            getBearerToken = function()
                return true
            end,
            callAPI = function(_, method, path)
                if method == "GET" and path == "/api/bookmarks/abc123/annotations" then
                    return {
                        {
                            id = "remote-1",
                            text = "local text",
                            note = "old note",
                            color = "yellow",
                            start_selector = "section/p[2]",
                            start_offset = 4,
                            end_selector = "section/p[2]",
                            end_offset = 15,
                        },
                    }
                end
                if method == "PATCH" then
                    patch_path = path
                    return {
                        annotations = {
                            {
                                id = "remote-1",
                                text = "local text",
                                note = encoded_body.note,
                                color = encoded_body.color,
                                start_selector = "section/p[2]",
                                start_offset = 4,
                                end_selector = "section/p[2]",
                                end_offset = 15,
                            },
                        },
                    }
                end
                return true
            end,
        }, { __index = Readeck })

        local ok, counts = instance:syncHighlightsForArticle("abc123", nil, local_annotations, { quiet = true })

        assert.is_true(ok)
        assert.are.equal(1, counts.updated_remote)
        assert.are.equal("/api/bookmarks/abc123/annotations/remote-1", patch_path)
        assert.are.equal("local note", encoded_body.note)
        assert.are.equal("green", encoded_body.color)
        assert.are.equal("local note", local_annotations[1].readeck_synced_note)
        assert.are.equal("green", local_annotations[1].readeck_synced_color)
    end)

    it("caches server info during automatic highlight feature detection", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local encoded_body

        package.loaded["json"] = nil
        package.preload["json"] = function()
            return {
                encode = function(body)
                    encoded_body = body
                    return "{}"
                end,
                decode = function()
                    return {}
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local refresh_count = 0
        local instance = setmetatable({
            access_token = "token",
            server_info = nil,
            highlight_feature_policy = "auto",
            getBearerToken = function()
                return true
            end,
            refreshServerInfo = function(self)
                refresh_count = refresh_count + 1
                self.server_info = { version = { canonical = "0.22.3" } }
                return self.server_info
            end,
            callAPI = function(_, method, path)
                if method == "GET" and path == "/api/bookmarks/abc123/annotations" then
                    return {}
                end
                if method == "POST" and path == "/api/bookmarks/abc123/annotations" then
                    return { id = "created-remote-id", note = encoded_body.note, color = encoded_body.color }
                end
                return true
            end,
        }, { __index = Readeck })

        local ok, counts = instance:syncHighlightsForArticle("abc123", nil, {
            {
                drawer = "lighten",
                text = "local text",
                note = "local note",
                color = "none",
                pos0 = "section/p[2].4",
                pos1 = "section/p[2].15",
            },
        }, { quiet = true })

        assert.is_true(ok)
        assert.are.equal(1, counts.success)
        assert.are.equal(1, refresh_count)
        assert.are.equal("local note", encoded_body.note)
        assert.are.equal("none", encoded_body.color)

        local profile = instance:getHighlightPayloadProfile()
        assert.is_true(profile.notes)
        assert.are.equal(1, refresh_count)
    end)

    it("falls back to the blocking downloader when KOReader async HTTP fails", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        package.loaded.httpclient = nil
        package.preload.httpclient = function()
            return {
                new = function()
                    return {
                        request = function(_, _, callback)
                            callback({ error = { message = "connection failed" } })
                        end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        require("ui/uimanager").looper = {
            add_callback = function() end,
        }
        local blocking_downloads = 0
        local skip_checks = 0
        local instance = setmetatable({
            access_token = "token",
            async_http_client_checked = false,
            download_concurrency = 2,
            experimental_async_downloads = true,
            server_url = "https://readeck.example",
            getDownloadTarget = function(_, article)
                return "/tmp/readeck-" .. article.id .. ".epub", "/api/bookmarks/" .. article.id .. "/article.epub"
            end,
            shouldSkipDownload = function()
                skip_checks = skip_checks + 1
                return false
            end,
            download = function()
                blocking_downloads = blocking_downloads + 1
                return "downloaded-by-blocking-client"
            end,
        }, { __index = Readeck })

        local done_result
        instance:downloadAsync({ id = "article1" }, function(result)
            done_result = result
        end)

        assert.are.equal("downloaded-by-blocking-client", done_result)
        assert.are.equal(1, blocking_downloads)
        assert.is_nil(instance.async_http_client)
        assert.is_true(instance.async_http_client_checked)
    end)

    it("uses the blocking downloader when no parallel backend is available", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        package.loaded.httpclient = nil
        package.preload.httpclient = function()
            error("async httpclient should stay disabled by default")
        end
        require("ui/uimanager").looper = nil

        local Readeck = dofile("readeck.koplugin/main.lua")
        local blocking_downloads = 0
        local skip_checks = 0
        local instance = setmetatable({
            access_token = "token",
            async_http_client_checked = false,
            download_concurrency = 2,
            experimental_async_downloads = false,
            server_url = "https://readeck.example",
            getDownloadTarget = function(_, article)
                return "/tmp/readeck-" .. article.id .. ".epub", "/api/bookmarks/" .. article.id .. "/article.epub"
            end,
            shouldSkipDownload = function()
                skip_checks = skip_checks + 1
                return false
            end,
            download = function()
                blocking_downloads = blocking_downloads + 1
                return "downloaded-by-blocking-client"
            end,
        }, { __index = Readeck })

        local done_result
        instance:downloadAsync({ id = "article1" }, function(result)
            done_result = result
        end)

        assert.are.equal("downloaded-by-blocking-client", done_result)
        assert.are.equal(1, blocking_downloads)
        assert.are.equal(0, skip_checks)
        assert.is_false(instance.async_http_client_checked)
    end)

    it("uses a subprocess downloader without the KOReader turbo looper", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()

        package.loaded.httpclient = nil
        package.preload.httpclient = function()
            error("turbo httpclient should not be required for subprocess downloads")
        end
        require("ui/uimanager").looper = nil

        package.loaded["ffi/util"] = nil
        package.preload["ffi/util"] = function()
            return {
                template = function(text, ...)
                    local values = { ... }
                    return (
                        text:gsub("%%(%d+)", function(index)
                            return tostring(values[tonumber(index)] or "")
                        end)
                    )
                end,
                joinPath = function(left, right)
                    return left .. "/" .. right
                end,
                gsplit = function()
                    return function()
                        return nil
                    end
                end,
                runInSubProcess = function()
                    return 123, 45
                end,
                isSubProcessDone = function(pid)
                    return pid == 123
                end,
                terminateSubProcess = function() end,
                readAllFromFD = function(fd)
                    assert.are.equal(45, fd)
                    return "downloaded\t200"
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local metadata_applied = false
        local progress_synced = false
        local instance = setmetatable({
            access_token = "token",
            download_concurrency = 2,
            experimental_async_downloads = true,
            server_url = "https://readeck.example",
            getDownloadTarget = function(_, article)
                return "/tmp/readeck-" .. article.id .. ".epub", "/api/bookmarks/" .. article.id .. "/article.epub"
            end,
            shouldSkipDownload = function()
                return false
            end,
            applyDownloadedArticleMetadata = function()
                metadata_applied = true
            end,
            syncReadingProgressFromRemote = function()
                progress_synced = true
            end,
        }, { __index = Readeck })

        local done_result
        instance:downloadAsync({ id = "article1" }, function(result)
            done_result = result
        end)

        assert.are.equal(3, done_result)
        assert.is_true(metadata_applied)
        assert.is_true(progress_synced)
        assert.are.equal("subprocess", instance:getParallelDownloadMode())
    end)

    it("retries with the blocking downloader when a subprocess download fails", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        require("ui/uimanager").looper = nil

        package.loaded["ffi/util"] = nil
        package.preload["ffi/util"] = function()
            return {
                template = function(text, ...)
                    local values = { ... }
                    return (
                        text:gsub("%%(%d+)", function(index)
                            return tostring(values[tonumber(index)] or "")
                        end)
                    )
                end,
                joinPath = function(left, right)
                    return left .. "/" .. right
                end,
                runInSubProcess = function()
                    return 123, 45
                end,
                isSubProcessDone = function()
                    return true
                end,
                terminateSubProcess = function() end,
                readAllFromFD = function()
                    return "failed\tTLS stalled"
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local blocking_downloads = 0
        local instance = setmetatable({
            access_token = "token",
            download_concurrency = 2,
            experimental_async_downloads = true,
            server_url = "https://readeck.example",
            getDownloadTarget = function(_, article)
                return "/tmp/readeck-" .. article.id .. ".epub", "/api/bookmarks/" .. article.id .. "/article.epub"
            end,
            shouldSkipDownload = function()
                return false
            end,
            download = function()
                blocking_downloads = blocking_downloads + 1
                return "downloaded-by-blocking-client"
            end,
        }, { __index = Readeck })

        local done_result
        instance:downloadAsync({ id = "article1" }, function(result)
            done_result = result
        end)

        assert.are.equal("downloaded-by-blocking-client", done_result)
        assert.are.equal(1, blocking_downloads)
        assert.is_true(instance.subprocess_downloads_disabled)
        assert.are.equal("blocking", instance:getParallelDownloadMode())
    end)

    it("skips an already downloaded article by Readeck ID", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local existing_path = "/tmp/readeck/Old title [rd-id_abc123].epub"
        package.loaded["libs/libkoreader-lfs"] = nil
        package.preload["libs/libkoreader-lfs"] = function()
            return {
                attributes = function(path, key)
                    local attrs
                    if path == "/tmp/readeck" then
                        attrs = { mode = "directory" }
                    elseif path == existing_path then
                        attrs = { mode = "file", modification = 1 }
                    end
                    if attrs and key then
                        return attrs[key]
                    end
                    return attrs
                end,
                dir = function(path)
                    local entries = { ".", "..", "Old title [rd-id_abc123].epub" }
                    local index = 0
                    return function()
                        if path ~= "/tmp/readeck" then
                            return nil
                        end
                        index = index + 1
                        return entries[index]
                    end
                end,
                touch = function()
                    return true
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            directory = "/tmp/readeck",
            isempty = function(_, value)
                return value == nil or value == ""
            end,
        }, { __index = Readeck })
        local article = {
            id = "abc123",
            title = "New title from server",
            created = "2026-01-01T00:00:00Z",
        }

        local local_path = instance:getDownloadTarget(article)
        assert.are.equal(existing_path, local_path)
        assert.is_true(instance:shouldSkipDownload(local_path, article))
    end)

    it("archives completed local files during sync when completion actions are enabled", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Finished [rd-id_abc123].epub"
        local deleted_paths = {}
        local api_calls = {}

        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                hasSidecarFile = function(_, path)
                    return path == article_path
                end,
                open = function()
                    return {
                        readSetting = function(_, key)
                            if key == "summary" then
                                return { status = "complete" }
                            end
                            if key == "percent_finished" then
                                return 1
                            end
                        end,
                    }
                end,
            }
        end
        package.loaded["libs/libkoreader-lfs"] = nil
        package.preload["libs/libkoreader-lfs"] = function()
            return {
                attributes = function(path, key)
                    local attrs
                    if path == article_path then
                        attrs = { mode = "file" }
                    end
                    if attrs and key then
                        return attrs[key]
                    end
                    return attrs
                end,
                dir = function(path)
                    local entries = { ".", "..", "Finished [rd-id_abc123].epub" }
                    local index = 0
                    return function()
                        if path ~= "/tmp/readeck" then
                            return nil
                        end
                        index = index + 1
                        return entries[index]
                    end
                end,
                touch = function()
                    return true
                end,
            }
        end
        package.loaded["apps/filemanager/filemanager"] = nil
        package.preload["apps/filemanager/filemanager"] = function()
            return {
                deleteFile = function(_, path)
                    table.insert(deleted_paths, path)
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            directory = "/tmp/readeck",
            access_token = "token",
            completion_action_finished_enabled = true,
            completion_action_read_enabled = false,
            archive_instead_of_delete = true,
            process_completion_on_sync = true,
            send_review_as_tags = false,
            sync_star_status = false,
            getBearerToken = function()
                return true
            end,
            syncHighlightsForPath = function()
                return true
            end,
            callAPI = function(_, method, path)
                table.insert(api_calls, { method = method, path = path })
                return true
            end,
        }, { __index = Readeck })

        local counts = instance:processLocalFiles("sync")

        assert.are.equal(1, counts.remote_archived)
        assert.are.equal(1, counts.local_removed)
        assert.is_true(counts.processed_article_ids.abc123)
        assert.are.equal(1, #api_calls)
        assert.are.equal("PATCH", api_calls[1].method)
        assert.are.equal("/api/bookmarks/abc123", api_calls[1].path)
        assert.are.same({ article_path }, deleted_paths)
    end)

    it("does not archive completed local files during sync when completion actions are disabled", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local api_calls = 0

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            process_completion_on_sync = false,
            send_review_as_tags = false,
            getBearerToken = function()
                api_calls = api_calls + 1
                return true
            end,
        }, { __index = Readeck })

        local counts = instance:processLocalFiles("sync")

        assert.are.equal(0, api_calls)
        assert.are.equal(1, counts.completion_actions_disabled)
        assert.are.equal(0, counts.remote_archived)
    end)

    it("syncs reading progress for local articles that are not being completed", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/In progress [rd-id_abc123].epub"
        local encoded_body

        package.loaded["json"] = nil
        package.preload["json"] = function()
            return {
                encode = function(body)
                    encoded_body = body
                    return "{}"
                end,
                decode = function()
                    return {}
                end,
            }
        end
        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                hasSidecarFile = function(_, path)
                    return path == article_path
                end,
                open = function()
                    return {
                        readSetting = function(_, key)
                            if key == "summary" then
                                return { status = "reading" }
                            end
                            if key == "percent_finished" then
                                return 0.37
                            end
                        end,
                    }
                end,
            }
        end
        package.loaded["libs/libkoreader-lfs"] = nil
        package.preload["libs/libkoreader-lfs"] = function()
            return {
                attributes = function(path, key)
                    local attrs
                    if path == article_path then
                        attrs = { mode = "file" }
                    end
                    if attrs and key then
                        return attrs[key]
                    end
                    return attrs
                end,
                dir = function(path)
                    local entries = { ".", "..", "In progress [rd-id_abc123].epub" }
                    local index = 0
                    return function()
                        if path ~= "/tmp/readeck" then
                            return nil
                        end
                        index = index + 1
                        return entries[index]
                    end
                end,
                touch = function()
                    return true
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local api_calls = {}
        local instance = setmetatable({
            directory = "/tmp/readeck",
            access_token = "token",
            completion_action_finished_enabled = true,
            completion_action_read_enabled = false,
            archive_instead_of_delete = true,
            process_completion_on_sync = true,
            sync_reading_progress = true,
            send_review_as_tags = false,
            getBearerToken = function()
                return true
            end,
            callAPI = function(_, method, path)
                table.insert(api_calls, { method = method, path = path })
                return true
            end,
        }, { __index = Readeck })

        local counts = instance:processLocalFiles("sync")

        assert.are.equal(1, counts.remote_progress_updated)
        assert.are.equal(1, #api_calls)
        assert.are.equal("PATCH", api_calls[1].method)
        assert.are.equal("/api/bookmarks/abc123", api_calls[1].path)
        assert.are.equal(37, encoded_body.read_progress)
    end)

    it("syncs reading progress even when sync completion actions are disabled", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Still reading [rd-id_progress123].epub"
        local encoded_body

        package.loaded["json"] = nil
        package.preload["json"] = function()
            return {
                encode = function(body)
                    encoded_body = body
                    return "{}"
                end,
                decode = function()
                    return {}
                end,
            }
        end
        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                hasSidecarFile = function(_, path)
                    return path == article_path
                end,
                open = function()
                    return {
                        readSetting = function(_, key)
                            if key == "summary" then
                                return { status = "reading" }
                            end
                            if key == "percent_finished" then
                                return 0.42
                            end
                        end,
                    }
                end,
            }
        end
        package.loaded["libs/libkoreader-lfs"] = nil
        package.preload["libs/libkoreader-lfs"] = function()
            return {
                attributes = function(path, key)
                    local attrs
                    if path == article_path then
                        attrs = { mode = "file" }
                    end
                    if attrs and key then
                        return attrs[key]
                    end
                    return attrs
                end,
                dir = function(path)
                    local entries = { ".", "..", "Still reading [rd-id_progress123].epub" }
                    local index = 0
                    return function()
                        if path ~= "/tmp/readeck" then
                            return nil
                        end
                        index = index + 1
                        return entries[index]
                    end
                end,
                touch = function()
                    return true
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local api_calls = {}
        local instance = setmetatable({
            directory = "/tmp/readeck",
            access_token = "token",
            completion_action_finished_enabled = true,
            completion_action_read_enabled = true,
            archive_instead_of_delete = true,
            process_completion_on_sync = false,
            sync_reading_progress = true,
            send_review_as_tags = false,
            getBearerToken = function()
                return true
            end,
            callAPI = function(_, method, path)
                table.insert(api_calls, { method = method, path = path })
                return true
            end,
        }, { __index = Readeck })

        local counts = instance:processLocalFiles("sync")

        assert.are.equal(1, counts.completion_actions_disabled)
        assert.are.equal(1, counts.remote_progress_updated)
        assert.are.equal(1, #api_calls)
        assert.are.equal("PATCH", api_calls[1].method)
        assert.are.equal("/api/bookmarks/progress123", api_calls[1].path)
        assert.are.equal(42, encoded_body.read_progress)
    end)

    it("does not sync 100 percent progress as a regular progress update", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Complete [rd-id_done123].epub"

        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                hasSidecarFile = function(_, path)
                    return path == article_path
                end,
                open = function()
                    return {
                        readSetting = function(_, key)
                            if key == "summary" then
                                return { status = "reading" }
                            end
                            if key == "percent_finished" then
                                return 1
                            end
                        end,
                    }
                end,
            }
        end
        package.loaded["libs/libkoreader-lfs"] = nil
        package.preload["libs/libkoreader-lfs"] = function()
            return {
                attributes = function(path, key)
                    local attrs
                    if path == article_path then
                        attrs = { mode = "file" }
                    end
                    if attrs and key then
                        return attrs[key]
                    end
                    return attrs
                end,
                dir = function(path)
                    local entries = { ".", "..", "Complete [rd-id_done123].epub" }
                    local index = 0
                    return function()
                        if path ~= "/tmp/readeck" then
                            return nil
                        end
                        index = index + 1
                        return entries[index]
                    end
                end,
                touch = function()
                    return true
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local api_calls = {}
        local instance = setmetatable({
            directory = "/tmp/readeck",
            access_token = "token",
            completion_action_finished_enabled = false,
            completion_action_read_enabled = false,
            process_completion_on_sync = false,
            sync_reading_progress = true,
            send_review_as_tags = false,
            getBearerToken = function()
                return true
            end,
            callAPI = function(_, method, path)
                table.insert(api_calls, { method = method, path = path })
                return true
            end,
        }, { __index = Readeck })

        local counts = instance:processLocalFiles("sync")

        assert.are.equal(1, counts.completion_actions_disabled)
        assert.are.equal(0, counts.remote_progress_updated)
        assert.are.equal(0, #api_calls)
    end)

    it("updates KOReader progress from newer incomplete Readeck progress", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Remote newer [rd-id_remote123].epub"
        local saved_percent
        local ui_saved_percent
        local flushed = false
        local events = {}

        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                open = function()
                    return {
                        readSetting = function(_, key)
                            if key == "percent_finished" then
                                return 0.12
                            end
                        end,
                        saveSetting = function(_, key, value)
                            if key == "percent_finished" then
                                saved_percent = value
                            end
                        end,
                        flush = function()
                            flushed = true
                        end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            sync_reading_progress = true,
            ui = {
                document = { file = article_path },
                handleEvent = function(_, event)
                    table.insert(events, event)
                end,
                doc_settings = {
                    saveSetting = function(_, key, value)
                        if key == "percent_finished" then
                            ui_saved_percent = value
                        end
                    end,
                },
            },
        }, { __index = Readeck })

        assert.is_true(instance:syncReadingProgressFromRemote(article_path, { read_progress = 45 }))
        assert.are.equal(0.45, saved_percent)
        assert.are.equal(0.45, ui_saved_percent)
        assert.is_true(flushed)
        assert.are.equal("GotoPercent", events[1].name)
        assert.are.equal(45, events[1].payload)
        assert.are.equal("SaveSettings", events[2].name)
    end)

    it("does not overwrite newer local KOReader progress from Readeck", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Local newer [rd-id_local123].epub"
        local saved = false

        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                open = function()
                    return {
                        readSetting = function(_, key)
                            if key == "percent_finished" then
                                return 0.72
                            end
                        end,
                        saveSetting = function()
                            saved = true
                        end,
                        flush = function() end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            sync_reading_progress = true,
        }, { __index = Readeck })

        assert.is_false(instance:syncReadingProgressFromRemote(article_path, { read_progress = 45 }))
        assert.is_false(instance:syncReadingProgressFromRemote(article_path, { read_progress = 100 }))
        assert.is_false(saved)
    end)

    it("stores remote progress as the next open position for unopened Readeck EPUBs", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local article_path = "/tmp/readeck/Unopened remote newer [rd-id_unopened123].epub"
        local saved = {}
        local deleted = {}

        package.loaded["docsettings"] = nil
        package.preload["docsettings"] = function()
            return {
                open = function()
                    return {
                        readSetting = function(_, key)
                            if key == "percent_finished" then
                                return 0.12
                            end
                        end,
                        saveSetting = function(_, key, value)
                            saved[key] = value
                        end,
                        delSetting = function(_, key)
                            deleted[key] = true
                        end,
                        flush = function() end,
                    }
                end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({
            sync_reading_progress = true,
            ui = {
                document = { file = "/tmp/readeck/Other.epub" },
            },
        }, { __index = Readeck })

        assert.is_true(instance:syncReadingProgressFromRemote(article_path, { read_progress = 45 }))
        assert.are.equal(0.45, saved.percent_finished)
        assert.are.equal(0.45, saved.last_percent)
        assert.is_true(deleted.last_xpointer)
    end)

    it("formats article sync progress with checked, downloaded, skipped, and local action counts", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({}, { __index = Readeck })

        local message = instance:formatDownloadProgressMessage(
            {
                completed = 3,
                downloaded = 1,
                skipped = 2,
                failed = 0,
            },
            14,
            {
                remote_archived = 1,
                remote_progress_updated = 1,
                local_removed = 1,
            }
        )

        assert.is_true(message:find("Syncing articles", 1, true) ~= nil)
        assert.is_true(message:find("3/14", 1, true) ~= nil)
        assert.is_true(message:find("Downloaded: 1", 1, true) ~= nil)
        assert.is_true(message:find("Skipped: 2", 1, true) ~= nil)
        assert.is_true(message:find("Archived in Readeck: 1", 1, true) ~= nil)
        assert.is_true(message:find("Reading progress synced: 1", 1, true) ~= nil)
        assert.is_true(message:find("Removed from KOReader: 1", 1, true) ~= nil)
    end)

    it("lets dismissed article download progress be shown again from saved state", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local shown = {}
        local closed = {}

        package.loaded["ui/widget/infomessage"] = nil
        package.preload["ui/widget/infomessage"] = function()
            return {
                new = function(_, options)
                    return options or {}
                end,
            }
        end
        package.loaded["ui/uimanager"] = nil
        package.preload["ui/uimanager"] = function()
            return {
                show = function(_, widget)
                    table.insert(shown, widget)
                end,
                close = function(_, widget)
                    table.insert(closed, widget)
                end,
                forceRePaint = function() end,
                scheduleIn = function(_, delay_or_callback, maybe_callback)
                    local callback = maybe_callback or delay_or_callback
                    callback()
                end,
                unschedule = function() end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({}, { __index = Readeck })

        instance:showDownloadProgress({ completed = 0, downloaded = 0, skipped = 0, failed = 0 }, 2)
        assert.are.equal(1, #shown)
        assert.is_nil(shown[1].timeout)
        assert.is_true(shown[1].dismissable)
        assert.is_nil(closed[1])

        shown[1].dismiss_callback()
        assert.is_nil(instance.download_progress_info)
        assert.is_true(instance.download_progress_hidden)

        instance:showDownloadProgress({ completed = 1, downloaded = 1, skipped = 0, failed = 0 }, 2)
        assert.are.equal(1, #shown)
        assert.are.equal(1, instance.download_progress_state.counts.completed)
        assert.is_true(instance:hasActiveDownloadProgress())

        assert.is_true(instance:showExistingDownloadProgress())
        assert.are.equal(2, #shown)
        assert.is_false(instance.download_progress_hidden)
        assert.is_true(shown[2].dismissable)

        instance:closeDownloadProgress(true)
        assert.are.equal(shown[2], closed[1])
        assert.is_nil(instance.download_progress_info)
        assert.is_nil(instance.download_progress_state)
    end)

    it("updates visible article download progress without closing and re-showing it", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local shown = {}
        local closed = {}
        local dirty_count = 0

        package.loaded["ui/widget/infomessage"] = nil
        package.preload["ui/widget/infomessage"] = function()
            return {
                new = function(_, options)
                    options = options or {}
                    options.free = function(self)
                        self.free_count = (self.free_count or 0) + 1
                    end
                    options.init = function(self)
                        self.init_count = (self.init_count or 0) + 1
                        self.movable = self.movable or {}
                    end
                    options:init()
                    return options
                end,
            }
        end
        package.loaded["ui/uimanager"] = nil
        package.preload["ui/uimanager"] = function()
            return {
                show = function(_, widget)
                    table.insert(shown, widget)
                end,
                close = function(_, widget)
                    table.insert(closed, widget)
                end,
                forceRePaint = function() end,
                setDirty = function()
                    dirty_count = dirty_count + 1
                end,
                scheduleIn = function(_, delay_or_callback, maybe_callback)
                    local callback = maybe_callback or delay_or_callback
                    callback()
                end,
                unschedule = function() end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({}, { __index = Readeck })

        instance:showDownloadProgress({ completed = 0, downloaded = 0, skipped = 0, failed = 0 }, 2)
        instance:showDownloadProgress({ completed = 1, downloaded = 1, skipped = 0, failed = 0 }, 2)

        assert.are.equal(1, #shown)
        assert.are.equal(0, #closed)
        assert.are.equal(1, shown[1].free_count)
        assert.are.equal(2, shown[1].init_count)
        assert.is_true(dirty_count > 0)
        assert.is_true(shown[1].text:find("1/2", 1, true) ~= nil)
    end)

    it("updates highlight sync progress without closing and re-showing it", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local shown = {}
        local closed = {}

        package.loaded["ui/widget/infomessage"] = nil
        package.preload["ui/widget/infomessage"] = function()
            return {
                new = function(_, options)
                    options = options or {}
                    options.free = function(self)
                        self.free_count = (self.free_count or 0) + 1
                    end
                    options.init = function(self)
                        self.init_count = (self.init_count or 0) + 1
                        self.movable = self.movable or {}
                    end
                    options:init()
                    return options
                end,
            }
        end
        package.loaded["ui/uimanager"] = nil
        package.preload["ui/uimanager"] = function()
            return {
                show = function(_, widget)
                    table.insert(shown, widget)
                end,
                close = function(_, widget)
                    table.insert(closed, widget)
                end,
                forceRePaint = function() end,
                setDirty = function() end,
                scheduleIn = function(_, delay_or_callback, maybe_callback)
                    local callback = maybe_callback or delay_or_callback
                    callback()
                end,
                unschedule = function() end,
            }
        end

        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({}, { __index = Readeck })

        local info = instance:showSyncStatus("Syncing highlights…")
        info = instance:showSyncStatus("Syncing highlights… 1/2", info)

        assert.are.equal(1, #shown)
        assert.are.equal(0, #closed)
        assert.are.equal(shown[1], info)
        assert.are.equal("Syncing highlights… 1/2", shown[1].text)
        assert.are.equal(1, shown[1].free_count)
        assert.are.equal(2, shown[1].init_count)
    end)

    it("formats highlight sync counts in article sync results", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({}, { __index = Readeck })

        local message = instance:formatSyncMessage(0, 1, 0, {
            highlights_imported = 3,
            highlights_exported = 2,
            highlights_updated_local = 5,
            highlights_updated_remote = 6,
            highlights_conflicts = 7,
            highlights_local_only = 4,
            highlights_skipped = 1,
            highlights_failed = 1,
        })

        assert.is_true(message:find("Highlights imported: 3", 1, true) ~= nil)
        assert.is_true(message:find("Highlights exported: 2", 1, true) ~= nil)
        assert.is_true(message:find("Highlights updated in KOReader: 5", 1, true) ~= nil)
        assert.is_true(message:find("Highlights updated in Readeck: 6", 1, true) ~= nil)
        assert.is_true(message:find("Highlight conflicts merged: 7", 1, true) ~= nil)
        assert.is_true(message:find("Highlights kept local only: 4", 1, true) ~= nil)
        assert.is_true(message:find("Highlights skipped: 1", 1, true) ~= nil)
        assert.is_true(message:find("Highlight sync failed: 1", 1, true) ~= nil)
    end)

    it("filters articles processed earlier in the same sync from the download list", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({}, { __index = Readeck })

        local articles = instance:filterArticlesProcessedEarlierInSync({
            { id = "abc123", title = "Already archived" },
            { id = "def456", title = "Still active" },
        }, {
            abc123 = true,
        })

        assert.are.equal(1, #articles)
        assert.are.equal("def456", articles[1].id)
    end)

    describe("full catalog refresh", function()
        local function refresh_instance(responses)
            package.path = "./readeck.koplugin/?.lua;" .. package.path
            install_koreader_stubs()
            local Catalog = dofile("readeck.koplugin/readeck/browse/catalog.lua")
            local Readeck = dofile("readeck.koplugin/main.lua")
            local calls = {}
            local instance = setmetatable({
                catalog = Catalog.empty(),
                access_token = "token",
                saved_synced_at = false,
                callAPI = function(_, method, url)
                    table.insert(calls, url)
                    return responses(method, url)
                end,
                saveCatalog = function(plugin, synced_at)
                    plugin.saved_synced_at = synced_at
                    return true
                end,
                refreshCollections = function()
                    return 0
                end,
            }, { __index = Readeck })
            return instance, calls
        end

        it("still rebuilds when the server refuses the baseline sync cursor", function()
            local instance, calls = refresh_instance(function(_, url)
                if url:find("/sync", 1, true) then
                    return nil, "Unprocessable Entity", 422
                end
                if url:find("offset=0", 1, true) then
                    return { { id = "abc123", title = "Paged article" } }, nil, 200, {}
                end
                return {}, nil, 200, {}
            end)

            assert.is_true(instance:refreshCatalogFull())
            assert.are.equal("Paged article", instance.catalog.entries.abc123.title)
            assert.is_string(instance.saved_synced_at)
            assert.is_truthy(calls[1]:find("/sync", 1, true))
        end)

        it("does not prune from a census it never received", function()
            local instance = refresh_instance(function(_, url)
                if url:find("/sync", 1, true) then
                    return nil, "Unprocessable Entity", 422
                end
                return {}, nil, 200, {}
            end)
            instance.catalog.entries.older = { id = "older", title = "Already known" }

            assert.is_true(instance:refreshCatalogFull())
            assert.is_not_nil(instance.catalog.entries.older)
        end)

        it("reports failure and leaves the sync stamp alone when paging breaks", function()
            local instance = refresh_instance(function(_, url)
                if url:find("/sync", 1, true) then
                    return nil, "Unprocessable Entity", 422
                end
                return nil, "connection refused", nil
            end)

            assert.is_false(instance:refreshCatalogFull())
            assert.is_false(instance.saved_synced_at)
        end)
    end)

    describe("browser article activation", function()
        -- Builds one ArticleBrowser against the stubs, with just the state the two
        -- activation paths read. `plugin.download` records the call and pretends the
        -- article landed at the path findLocalArticlePathByID then reports.
        local function browser(opts)
            opts = opts or {}
            package.path = "./readeck.koplugin/?.lua;" .. package.path
            install_koreader_stubs()
            local opened = {}
            -- install_koreader_stubs only clears readeck.* from package.loaded, so a
            -- UIManager required by an earlier test would be reused here -- and the
            -- earlier ones have no nextTick.
            package.loaded["ui/uimanager"] = nil
            package.loaded["apps/filemanager/filemanagerutil"] = nil
            package.preload["apps/filemanager/filemanagerutil"] = function()
                return {
                    abbreviate = function(path)
                        return path
                    end,
                    openFile = function(_, file)
                        table.insert(opened, file)
                    end,
                }
            end

            local Readeck = dofile("readeck.koplugin/main.lua")
            local Browser = require("readeck.ui.browser")
            local downloads = {}
            local plugin = setmetatable({
                directory = "/tmp/readeck",
                download = function(_, article)
                    table.insert(downloads, article.id)
                    return "downloaded"
                end,
                findLocalArticlePathByID = function(_, id)
                    if opts.missing_after_download then
                        return nil
                    end
                    return "/tmp/readeck/article [" .. id .. "].epub"
                end,
            }, { __index = Readeck })

            local instance = setmetatable({
                plugin = plugin,
                ctx = { downloaded = opts.downloaded or {} },
                item_table = {},
                refreshed = 0,
            }, { __index = Browser.ArticleBrowserClass })
            instance.refreshRow = function(self)
                self.refreshed = self.refreshed + 1
            end
            return instance, downloads, opened
        end

        local function row()
            return { kind = "article", idx = 1, entry = { id = "abc123", title = "An article" } }
        end

        it("opens an already downloaded article without downloading it again", function()
            local instance, downloads, opened =
                browser({ downloaded = { abc123 = "/tmp/readeck/article [abc123].epub" } })

            instance:openOrDownload(row())

            assert.are.same({}, downloads)
            assert.are.same({ "/tmp/readeck/article [abc123].epub" }, opened)
        end)

        it("downloads and then opens, so one tap is enough", function()
            local instance, downloads, opened = browser()

            instance:openOrDownload(row())

            assert.are.same({ "abc123" }, downloads)
            assert.are.same({ "/tmp/readeck/article [abc123].epub" }, opened)
            -- The browser is closing behind the reader, so it must not repaint on the way.
            assert.are.equal(0, instance.refreshed)
        end)

        it("stays on the list for the long-press download action", function()
            local instance, downloads, opened = browser()

            instance:openOrDownload(row(), true)

            assert.are.same({ "abc123" }, downloads)
            assert.are.same({}, opened)
            assert.are.equal(1, instance.refreshed)
            assert.are.equal("/tmp/readeck/article [abc123].epub", instance.ctx.downloaded.abc123)
        end)

        it("does not try to open anything when the downloaded file cannot be found", function()
            local instance, downloads, opened = browser({ missing_after_download = true })

            instance:openOrDownload(row())

            assert.are.same({ "abc123" }, downloads)
            assert.are.same({}, opened)
        end)
    end)

    describe("sync tag exclusions", function()
        local function sync_instance(overrides)
            package.path = "./readeck.koplugin/?.lua;" .. package.path
            install_koreader_stubs()
            local Readeck = dofile("readeck.koplugin/main.lua")
            return setmetatable(overrides or {}, { __index = Readeck })
        end

        local function ids(list)
            local result = {}
            for _, article in ipairs(list) do
                table.insert(result, article.id)
            end
            return result
        end

        it("drops articles carrying an ignored tag", function()
            local instance = sync_instance({ ignore_tags = "spam,ads" })
            local kept = instance:filterIgnoredTags({
                { id = "1", title = "keep", labels = { "news" } },
                { id = "2", title = "drop", labels = { "news", "ads" } },
                { id = "3", title = "keep", labels = {} },
            })
            assert.are.same({ "1", "3" }, ids(kept))
        end)

        it("trims the ignore list, so a space after the comma still matches", function()
            local instance = sync_instance({ ignore_tags = "spam, ads" })
            local kept = instance:filterIgnoredTags({
                { id = "1", title = "drop", labels = { "ads" } },
                { id = "2", title = "keep", labels = { "news" } },
            })
            assert.are.same({ "2" }, ids(kept))
        end)

        it("keeps everything when nothing is ignored", function()
            local instance = sync_instance({ ignore_tags = "" })
            local kept = instance:filterIgnoredTags({
                { id = "1", labels = { "news" } },
                { id = "2", labels = { "ads" } },
            })
            assert.are.same({ "1", "2" }, ids(kept))
        end)
    end)

    describe("browse catalog write-through", function()
        local function loaded_instance()
            package.path = "./readeck.koplugin/?.lua;" .. package.path
            install_koreader_stubs()
            local Catalog = dofile("readeck.koplugin/readeck/browse/catalog.lua")
            local Readeck = dofile("readeck.koplugin/main.lua")
            local catalog = Catalog.empty()
            Catalog.upsert(catalog, {
                id = "abc123",
                title = "An article",
                labels = { "python" },
                is_archived = false,
                is_marked = false,
                read_progress = 10,
            })
            return setmetatable({ catalog = catalog }, { __index = Readeck }), catalog
        end

        it("does nothing at all while no catalog is in memory", function()
            package.path = "./readeck.koplugin/?.lua;" .. package.path
            install_koreader_stubs()
            local Readeck = dofile("readeck.koplugin/main.lua")
            local instance = setmetatable({}, { __index = Readeck })

            assert.is_false(instance:catalogPatch("abc123", { is_archived = true }))
            assert.is_false(instance:catalogRemove("abc123"))
            assert.is_false(instance:catalogUpsertBookmark({ id = "abc123" }))
            assert.is_false(instance:catalogAddLabels("abc123", { "python" }))
            assert.is_nil(instance.catalog)
            assert.is_nil(instance.catalog_dirty)
        end)

        it("applies an archive PATCH body field by field", function()
            local instance, catalog = loaded_instance()

            assert.is_true(instance:catalogApplyArchive("abc123", {
                is_archived = true,
                read_progress = 100,
                is_marked = true,
                add_labels = { "done" },
            }))

            local entry = catalog.entries.abc123
            assert.is_true(entry.is_archived)
            assert.are.equal(100, entry.read_progress)
            assert.is_true(entry.is_marked)
            assert.are.same({ "python", "done" }, entry.labels)
            assert.is_true(instance.catalog_dirty)
        end)

        it("unions labels instead of replacing them, and never duplicates one", function()
            local instance, catalog = loaded_instance()

            assert.is_true(instance:catalogAddLabels("abc123", { "python", "rust" }))

            assert.are.same({ "python", "rust" }, catalog.entries.abc123.labels)
        end)

        it("refreshes an entry from a downloaded article payload", function()
            local instance, catalog = loaded_instance()

            assert.is_true(instance:catalogUpsertBookmark({
                id = "abc123",
                title = "Renamed upstream",
                labels = { "rust" },
                read_progress = 55,
            }))

            local entry = catalog.entries.abc123
            assert.are.equal("Renamed upstream", entry.title)
            assert.are.same({ "rust" }, entry.labels)
            assert.are.equal(55, entry.read_progress)
        end)

        it("drops an article that was deleted on the server", function()
            local instance, catalog = loaded_instance()

            assert.is_true(instance:catalogRemove("abc123"))
            assert.is_nil(catalog.entries.abc123)
            assert.is_false(instance:catalogRemove("abc123"))
        end)

        it("ignores a mutation for an article the catalog has never seen", function()
            local instance = loaded_instance()

            assert.is_false(instance:catalogPatch("missing", { is_archived = true }))
            assert.is_false(instance:catalogAddLabels("missing", { "python" }))
            assert.is_nil(instance.catalog_dirty)
        end)
    end)
end)
