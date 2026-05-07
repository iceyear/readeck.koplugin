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
            runWhenOnline = function(callback)
                callback()
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
        assert.are.equal("0.1.0", metadata.version)
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

    it("uses the blocking downloader by default even when concurrency is configured", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        package.loaded.httpclient = nil
        package.preload.httpclient = function()
            error("async httpclient should stay disabled by default")
        end

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

    it("formats highlight sync counts in article sync results", function()
        package.path = "./readeck.koplugin/?.lua;" .. package.path
        install_koreader_stubs()
        local Readeck = dofile("readeck.koplugin/main.lua")
        local instance = setmetatable({}, { __index = Readeck })

        local message = instance:formatSyncMessage(0, 1, 0, {
            highlights_imported = 3,
            highlights_exported = 2,
            highlights_local_only = 4,
            highlights_skipped = 1,
            highlights_failed = 1,
        })

        assert.is_true(message:find("Highlights imported: 3", 1, true) ~= nil)
        assert.is_true(message:find("Highlights exported: 2", 1, true) ~= nil)
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
end)
