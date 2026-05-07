local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")

local DevicePolling = {}

local function close_state_dialogs(plugin, state)
    if state.qr_dialog then
        local dialog = state.qr_dialog
        state.qr_dialog = nil
        UIManager:close(dialog)
    end
    plugin:closeOAuthPromptDialog()
end

function DevicePolling.install(Readeck, deps)
    local L = deps.L
    local Log = deps.Log
    local OAUTH_DEVICE_GRANT = deps.OAUTH_DEVICE_GRANT

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

    function Readeck:finishOAuthPolling(state, success, message)
        if state.done then
            return
        end
        state.done = true
        if state.poll_callback then
            UIManager:unschedule(state.poll_callback)
            state.poll_callback = nil
        end
        close_state_dialogs(self, state)
        if self.oauth_poll_state == state then
            self.oauth_poll_state = nil
        end
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
        close_state_dialogs(self, state)
        self.oauth_poll_state = nil
        if message then
            UIManager:show(InfoMessage:new({
                text = message,
            }))
        end
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
                    self:finishOAuthPolling(state, false, L("OAuth login timed out."))
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
                    self:finishOAuthPolling(state, true, L("OAuth authorization successful."))
                    return
                end
                if outcome == "retry" then
                    state.interval = value
                    schedule_next_poll(state.interval)
                    return
                end
                self:finishOAuthPolling(state, false, value)
            end
            UIManager:scheduleIn(delay, state.poll_callback)
        end

        schedule_next_poll(state.interval)
        return true
    end
end

return DevicePolling
