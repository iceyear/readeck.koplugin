local Api = require("readeck.net.api")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Features = require("readeck.core.features")
local InfoMessage = require("ui/widget/infomessage")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local NetworkMgr = require("ui/network/manager")
local OAuthForm = require("readeck.auth.form")
local QRMessage = require("ui/widget/qrmessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

local OAuth = {}

function OAuth.install(Readeck, deps)
    local L = deps.L
    local T = deps.T
    local Log = deps.Log
    local OAUTH_DEVICE_GRANT = deps.OAUTH_DEVICE_GRANT
    local DEFAULT_OAUTH_SCOPES = deps.DEFAULT_OAUTH_SCOPES
    local PLUGIN_VERSION = deps.PLUGIN_VERSION
    OAuthForm.install(Readeck, deps)

    function Readeck:refreshServerInfo(quiet)
        if self:isempty(self.server_url) then
            return nil
        end
        local info, err = self:callAPI("GET", Api.paths.info, {}, "", "", true)
        if type(info) == "table" then
            self.server_info = info
            self:saveSettings()
            return info
        end
        if not quiet then
            UIManager:show(InfoMessage:new({
                text = L("Could not fetch Readeck server information."),
            }))
        end
        Log:warn("Could not fetch server info", err or "")
        return self.server_info
    end

    function Readeck:serverSupportsOAuth()
        local support = Features.supports_oauth(self.server_info)
        if support == nil then
            support = Features.supports_oauth(self:refreshServerInfo(true))
        end
        return support
    end

    function Readeck:resetAccessToken()
        Log:info("Manually resetting access token")

        self.access_token = ""
        self.token_expiry = 0

        if
            self:getBearerToken({
                on_oauth_success = function()
                    UIManager:show(InfoMessage:new({
                        text = L("Access token reset successfully"),
                    }))
                end,
            })
        then
            UIManager:show(InfoMessage:new({
                text = L("Access token reset successfully"),
            }))
        elseif self:isOAuthPollingActive() then
            UIManager:show(InfoMessage:new({
                text = L("OAuth authorization started. Finish login to refresh access token."),
            }))
        else
            UIManager:show(InfoMessage:new({
                text = L("Failed to obtain new access token"),
            }))
        end
    end

    function Readeck:clearAllTokens()
        Log:info("Clearing all cached tokens")
        self:cancelOAuthPolling()

        self.access_token = ""
        self.token_expiry = 0
        self.cached_auth_token = ""
        self.cached_server_url = ""
        self.cached_auth_method = ""
        self.oauth_client_id = ""
        self.oauth_refresh_token = ""

        self:saveSettings()

        UIManager:show(InfoMessage:new({
            text = L("All cached tokens cleared"),
        }))
    end

    function Readeck:storeAccessToken(method, token, expires_in, auth_meta)
        local now = os.time()
        local ttl = tonumber(expires_in)
        if ttl and ttl > 0 then
            self.token_expiry = now + ttl
        else
            self.token_expiry = now + 365 * 24 * 60 * 60
        end
        self.access_token = token
        self.cached_auth_method = method
        self.cached_server_url = self.server_url

        if method == "api_token" then
            self.cached_auth_token = self.auth_token
        else
            self.cached_auth_token = ""
        end

        if auth_meta then
            if auth_meta.oauth_refresh_token ~= nil then
                self.oauth_refresh_token = auth_meta.oauth_refresh_token
            end
            if auth_meta.oauth_client_id ~= nil then
                self.oauth_client_id = auth_meta.oauth_client_id
            end
        end
        self:saveSettings()
    end

    function Readeck:authenticateWithApiToken()
        Log:info("Using provided API token")
        self:storeAccessToken("api_token", self.auth_token, 365 * 24 * 60 * 60)
        return true
    end

    function Readeck:refreshOAuthToken()
        if self:isempty(self.oauth_refresh_token) or self:isempty(self.oauth_client_id) then
            return false
        end

        Log:info("Attempting OAuth refresh token flow")
        local result = self:callOAuthFormAPI("/api/oauth/token", {
            grant_type = "refresh_token",
            client_id = self.oauth_client_id,
            refresh_token = self.oauth_refresh_token,
        })
        if result and result.access_token then
            Log:info("OAuth token refreshed")
            self:storeAccessToken("oauth", result.access_token, result.expires_in, {
                oauth_refresh_token = result.refresh_token or self.oauth_refresh_token,
                oauth_client_id = self.oauth_client_id,
            })
            return true
        end

        return false
    end

    function Readeck:getOAuthDeviceAuthorizationContext()
        if self:isempty(self.server_url) then
            UIManager:show(MultiConfirmBox:new({
                text = L("Please configure the Readeck server URL first."),
                choice1_text = L("Server settings"),
                choice1_callback = function()
                    self:editServerSettings()
                end,
                choice2_text = L("Cancel"),
                choice2_callback = function() end,
            }))
            return nil
        end

        local oauth_support = self:serverSupportsOAuth()
        if oauth_support == false then
            local version = Features.version(self.server_info) or L("unknown")
            UIManager:show(InfoMessage:new({
                text = T(
                    L(
                        "This Readeck server does not advertise OAuth support.\nServer version: %1\nUse an API token instead."
                    ),
                    version
                ),
            }))
            return nil
        end

        local client_name = "Readeck for KOReader"
        local software_id = self:makeOAuthSoftwareID()

        local client_info, client_err, client_code = self:callOAuthFormAPI("/api/oauth/client", {
            client_name = client_name,
            client_uri = "https://github.com/iceyear/readeck.koplugin",
            software_id = software_id,
            software_version = PLUGIN_VERSION,
            grant_types = { OAUTH_DEVICE_GRANT },
        })

        if not client_info or not client_info.client_id then
            Log:error("OAuth client registration failed", client_err or "", client_code or "")
            UIManager:show(InfoMessage:new({
                text = L("OAuth setup failed: could not register client."),
            }))
            return nil
        end

        local client_id = client_info.client_id
        local device_info, device_err, device_code = self:callOAuthFormAPI("/api/oauth/device", {
            client_id = client_id,
            scope = DEFAULT_OAUTH_SCOPES,
        })
        if not device_info or not device_info.device_code then
            Log:error("OAuth device code request failed", device_err or "", device_code or "")
            UIManager:show(InfoMessage:new({
                text = L("OAuth setup failed: could not request device code."),
            }))
            return nil
        end

        local verification_uri = device_info.verification_uri or ""
        local verification_uri_complete = device_info.verification_uri_complete or verification_uri
        local user_code = self:formatOAuthUserCode(device_info.user_code)
        local fallback_uri = verification_uri ~= "" and verification_uri or (self.server_url .. "/device")
        local interval = tonumber(device_info.interval) or 5
        if interval < 5 then
            interval = 5
        end
        local expires_in = tonumber(device_info.expires_in) or 300
        local deadline = os.time() + math.max(30, expires_in)

        return {
            client_id = client_id,
            device_code = device_info.device_code,
            interval = interval,
            deadline = deadline,
            verification_uri_complete = verification_uri_complete,
            fallback_uri = fallback_uri,
            user_code = user_code,
        }
    end

    function Readeck:closeOAuthPromptDialog()
        if not self.oauth_prompt_dialog then
            return
        end
        local prompt = self.oauth_prompt_dialog
        self.oauth_prompt_dialog = nil
        UIManager:close(prompt)
    end

    function Readeck:isOAuthPollingActive()
        return self.oauth_poll_state and not self.oauth_poll_state.done
    end

    function Readeck:showOAuthPollingPrompt(text)
        self:closeOAuthPromptDialog()
        self.oauth_prompt_dialog = ConfirmBox:new({
            text = text,
            cancel_text = L("Cancel"),
            cancel_callback = function()
                self:cancelOAuthPolling(L("OAuth authorization canceled."))
            end,
            no_ok_button = true,
            keep_dialog_open = true,
            other_buttons = {
                {
                    {
                        text = L("Show QR"),
                        callback = function()
                            self:showOAuthPollingQR()
                        end,
                    },
                },
            },
            other_buttons_first = true,
        })
        UIManager:show(self.oauth_prompt_dialog)
    end

    function Readeck:addOAuthSuccessCallback(state, callback)
        if type(callback) ~= "function" or not state then
            return
        end
        state.on_success_callbacks = state.on_success_callbacks or {}
        for _, existing in ipairs(state.on_success_callbacks) do
            if existing == callback then
                return
            end
        end
        table.insert(state.on_success_callbacks, callback)
    end

    function Readeck:evaluateOAuthDeviceTokenPoll(ctx, token_result, poll_err, poll_code, wait_interval)
        if token_result and token_result.access_token then
            self:storeAccessToken("oauth", token_result.access_token, token_result.expires_in, {
                oauth_refresh_token = token_result.refresh_token or "",
                oauth_client_id = ctx.client_id,
            })
            return "success"
        end

        local oauth_error = token_result and token_result.error or ""
        if oauth_error == "authorization_pending" then
            return "retry", wait_interval
        end
        if oauth_error == "slow_down" then
            return "retry", wait_interval + 5
        end
        if oauth_error == "access_denied" then
            return "fail", L("OAuth authorization was denied.")
        end
        if oauth_error == "expired_token" then
            return "fail", L("OAuth authorization request expired.")
        end
        if poll_code and poll_code >= 500 then
            Log:warn("OAuth token polling server error", poll_code)
            return "retry", wait_interval + 5
        end

        Log:error("OAuth token polling failed", poll_err or "", oauth_error or "", poll_code or "")
        return "fail", L("OAuth token request failed.")
    end

    function Readeck:cancelOAuthPolling(message)
        local state = self.oauth_poll_state
        if not state or state.done then
            return
        end

        state.done = true
        if state.poll_callback then
            UIManager:unschedule(state.poll_callback)
            state.poll_callback = nil
        end
        if state.qr_dialog then
            local dialog = state.qr_dialog
            state.qr_dialog = nil
            UIManager:close(dialog)
        end
        self:closeOAuthPromptDialog()
        self.oauth_poll_state = nil
        if message then
            UIManager:show(InfoMessage:new({
                text = message,
            }))
        end
    end

    function Readeck:showOAuthPollingQR()
        local state = self.oauth_poll_state
        if not state or state.done then
            UIManager:show(InfoMessage:new({
                text = L("No OAuth authorization is in progress."),
            }))
            return false
        end
        if not state.verification_uri_complete or state.verification_uri_complete == "" then
            UIManager:show(InfoMessage:new({
                text = L("No QR URL is available for this authorization flow."),
            }))
            return false
        end
        if state.qr_dialog then
            return true
        end

        state.qr_dialog = QRMessage:new({
            text = state.verification_uri_complete,
            width = Device.screen:getWidth(),
            height = Device.screen:getHeight(),
            dismiss_callback = function()
                if state and not state.done then
                    state.qr_dialog = nil
                end
            end,
        })
        UIManager:show(state.qr_dialog)
        return true
    end

    function Readeck:startOAuthPollingAsync(ctx, on_success)
        if not ctx then
            return false
        end
        if self.oauth_poll_state and not self.oauth_poll_state.done then
            self:cancelOAuthPolling()
        end

        local state = {
            done = false,
            poll_callback = nil,
            qr_dialog = nil,
            interval = ctx.interval,
            verification_uri_complete = ctx.verification_uri_complete,
            fallback_uri = ctx.fallback_uri,
            user_code = ctx.user_code,
            on_success_callbacks = {},
        }
        self:addOAuthSuccessCallback(state, on_success)
        self.oauth_poll_state = state

        local function finish(success, message)
            if state.done then
                return
            end
            state.done = true
            if state.poll_callback then
                UIManager:unschedule(state.poll_callback)
                state.poll_callback = nil
            end
            if state.qr_dialog then
                local dialog = state.qr_dialog
                state.qr_dialog = nil
                UIManager:close(dialog)
            end
            if self.oauth_poll_state == state then
                self.oauth_poll_state = nil
            end
            self:closeOAuthPromptDialog()
            if message then
                UIManager:show(InfoMessage:new({
                    text = message,
                }))
            end
            if success and state.on_success_callbacks then
                for _, cb in ipairs(state.on_success_callbacks) do
                    local callback = cb
                    UIManager:scheduleIn(0, function()
                        local ok, err = pcall(callback)
                        if not ok then
                            Log:error("OAuth success callback failed:", err)
                        end
                    end)
                end
            end
            return success
        end

        local function schedule_next_poll(delay)
            if state.done then
                return
            end
            state.poll_callback = function()
                state.poll_callback = nil
                if state.done then
                    return
                end
                if os.time() >= ctx.deadline then
                    finish(false, L("OAuth login timed out."))
                    return
                end

                local token_result, poll_err, poll_code = self:callOAuthFormAPI("/api/oauth/token", {
                    grant_type = OAUTH_DEVICE_GRANT,
                    client_id = ctx.client_id,
                    device_code = ctx.device_code,
                })
                local outcome, value =
                    self:evaluateOAuthDeviceTokenPoll(ctx, token_result, poll_err, poll_code, state.interval)
                if outcome == "success" then
                    finish(true, L("OAuth authorization successful."))
                    return
                end
                if outcome == "retry" then
                    state.interval = value
                    schedule_next_poll(state.interval)
                    return
                end
                finish(false, value)
            end
            UIManager:scheduleIn(delay, state.poll_callback)
        end

        schedule_next_poll(state.interval)
        return true
    end

    function Readeck:authorizeWithOAuthDeviceFlowAsync(options)
        Log:info("Starting OAuth device flow (async)")
        options = options or {}
        if self.oauth_poll_state and not self.oauth_poll_state.done then
            local current_state = self.oauth_poll_state
            self:addOAuthSuccessCallback(current_state, options.on_success)
            if options.auto_trigger then
                return false
            end
            local text = L("OAuth authorization is already in progress.")
            if current_state.fallback_uri and current_state.user_code then
                text = text
                    .. T(
                        L("\n\nOpen this URL in your browser:\n%1\nCode: %2"),
                        current_state.fallback_uri,
                        current_state.user_code
                    )
            end
            self:showOAuthPollingPrompt(text)
            return false
        end

        local ctx = self:getOAuthDeviceAuthorizationContext()
        if not ctx then
            return false
        end

        self:startOAuthPollingAsync(ctx, options.on_success)
        if not self.oauth_poll_state or self.oauth_poll_state.done then
            return false
        end

        self:showOAuthPollingPrompt(
            T(L("OAuth login started.\nOpen this URL in your browser:\n%1\nCode: %2"), ctx.fallback_uri, ctx.user_code)
        )
        return true
    end

    function Readeck:getCurrentAuthMethod()
        if not self:isempty(self.auth_token) then
            return "api_token"
        end

        local has_oauth_context = (self.cached_auth_method == "oauth") or (not self:isempty(self.oauth_refresh_token))

        if has_oauth_context then
            return "oauth"
        end
        return "oauth"
    end

    function Readeck:isAuthContextChanged(auth_method)
        if self.server_url ~= self.cached_server_url then
            return true
        end
        if auth_method ~= self.cached_auth_method then
            return true
        end

        if auth_method == "api_token" then
            return self.auth_token ~= self.cached_auth_token
        end
        return false
    end

    function Readeck:getBearerToken(options)
        Log:debug("Getting bearer token")
        options = options or {}
        local function authorize_with_oauth()
            self:authorizeWithOAuthDeviceFlowAsync({
                auto_trigger = true,
                on_success = options.on_oauth_success,
            })
            return self:isOAuthPollingActive()
        end

        local server_empty = self:isempty(self.server_url)
        local directory_empty = self:isempty(self.directory)
        if server_empty or directory_empty then
            Log:warn(
                "Configuration incomplete - Server:",
                server_empty and "missing" or "ok",
                ", Directory:",
                directory_empty and "missing" or "ok"
            )
            UIManager:show(MultiConfirmBox:new({
                text = L("Please configure the server settings and set a download folder."),
                choice1_text_func = function()
                    if server_empty then
                        return L("Server (★)")
                    else
                        return L("Server")
                    end
                end,
                choice1_callback = function()
                    self:editServerSettings()
                end,
                choice2_text_func = function()
                    if directory_empty then
                        return L("Folder (★)")
                    else
                        return L("Folder")
                    end
                end,
                choice2_callback = function()
                    self:setDownloadDirectory()
                end,
            }))
            return false
        end

        local dir_mode = lfs.attributes(self.directory, "mode")
        if dir_mode ~= "directory" then
            Log:warn("Invalid download directory:", self.directory)
            UIManager:show(InfoMessage:new({
                text = L("The download directory is not valid.\nPlease configure it in the settings."),
            }))
            return false
        end
        if string.sub(self.directory, -1) ~= "/" then
            self.directory = self.directory .. "/"
        end

        local now = os.time()
        local auth_method = self:getCurrentAuthMethod()
        local auth_changed = self:isAuthContextChanged(auth_method)
        if not self:isempty(self.access_token) and self.token_expiry > now + 300 and not auth_changed then
            Log:debug("Using cached token, still valid for", self.token_expiry - now, "seconds")
            return true
        end

        if auth_method == "api_token" then
            return self:authenticateWithApiToken()
        end

        if auth_method == "oauth" then
            if self:refreshOAuthToken() then
                return true
            end
            if authorize_with_oauth() then
                return false
            end
            return false
        end

        authorize_with_oauth()
        return false
    end

    function Readeck:scheduleSyncAfterOAuth()
        NetworkMgr:runWhenOnline(function()
            self:synchronize()
            self:refreshCurrentDirIfNeeded()
        end)
    end
end

return OAuth
