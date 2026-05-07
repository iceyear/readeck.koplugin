local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")

local Form = {}

function Form.install(Readeck, deps)
    local Log = deps.Log

    function Readeck:urlEncodeFormValue(value)
        local s = tostring(value or "")
        s = s:gsub("\n", "\r\n")
        s = s:gsub(" ", "+")
        s = s:gsub("([^%w%+%-_%.~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        return s
    end

    function Readeck:encodeFormData(fields)
        local parts = {}
        for key, value in pairs(fields or {}) do
            if type(value) == "table" then
                for _, item in ipairs(value) do
                    table.insert(parts, self:urlEncodeFormValue(key) .. "=" .. self:urlEncodeFormValue(item))
                end
            else
                table.insert(parts, self:urlEncodeFormValue(key) .. "=" .. self:urlEncodeFormValue(value))
            end
        end
        table.sort(parts)
        return table.concat(parts, "&")
    end

    function Readeck:callOAuthFormAPI(apiurl, form_data)
        if self:isempty(self.server_url) then
            Log:warn("OAuth request attempted without configured server URL")
            return nil, "config_error"
        end

        local sink = {}
        local body = self:encodeFormData(form_data)
        local request = {
            method = "POST",
            url = self.server_url .. apiurl,
            sink = ltn12.sink.table(sink),
            source = ltn12.source.string(body),
            headers = {
                ["Content-type"] = "application/x-www-form-urlencoded",
                ["Accept"] = "application/json, */*",
                ["Content-Length"] = tostring(#body),
            },
        }

        socketutil:set_timeout(self.block_timeout, self.total_timeout)
        local code, resp_headers = socket.skip(1, http.request(request))
        socketutil:reset_timeout()
        if not resp_headers then
            return nil, "network_error"
        end
        local code_num = tonumber(code)

        local content = table.concat(sink)
        local result
        if content ~= "" then
            local ok, parsed = pcall(JSON.decode, content)
            if ok then
                result = parsed
            end
        end
        if code_num and code_num >= 200 and code_num < 300 then
            return result or {}, nil, code_num
        end
        return result, "http_error", code_num or code
    end

    function Readeck:makeOAuthSoftwareID()
        if not self.oauth_rng_seeded then
            local seed = os.time()
            if socket and socket.gettime then
                seed = seed + math.floor(socket.gettime() * 1000)
            end
            math.randomseed(seed)
            self.oauth_rng_seeded = true
        end
        local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
        return (
            template:gsub("[xy]", function(c)
                local v
                if c == "x" then
                    v = math.random(0, 15)
                else
                    v = math.random(8, 11)
                end
                return string.format("%x", v)
            end)
        )
    end

    function Readeck:formatOAuthUserCode(user_code)
        if not user_code or user_code == "" then
            return ""
        end
        if #user_code == 8 then
            return user_code:sub(1, 4) .. "-" .. user_code:sub(5)
        end
        return user_code
    end
end

return Form
