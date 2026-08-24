local socket_http_ok, socket_http = pcall(require, "socket.http")
local ltn12_ok, ltn12 = pcall(require, "ltn12")

local AIHelper = {}

local function escape_json(str)
    return (str or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end

local function extract_content(body)
    if not body then return nil end
    local content = body:match('"content"%s*:%s*"(.-)"')
    if not content then return nil end
    return content:gsub('\\n', '\n'):gsub('\\"', '"')
end

local function call_chat(opts, system_prompt, user_prompt)
    if not opts or not opts.api_key or opts.api_key == "" then
        return false, "Missing API key. Put it in HighContext/api_key.txt or plugin settings."
    end
    if not socket_http_ok or not ltn12_ok then
        return false, "LuaSocket is unavailable in this KOReader build."
    end

    local payload = string.format(
        '{"model":"%s","messages":[{"role":"system","content":"%s"},{"role":"user","content":"%s"}],"temperature":0.2}',
        escape_json(opts.model or "gpt-4o-mini"),
        escape_json(system_prompt),
        escape_json(user_prompt)
    )

    local response_chunks = {}
    local _, code = socket_http.request {
        url = opts.endpoint or "https://api.openai.com/v1/chat/completions",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. opts.api_key,
            ["Content-Length"] = tostring(#payload),
        },
        source = ltn12.source.string(payload),
        sink = ltn12.sink.table(response_chunks),
    }

    if code ~= 200 then return false, "API request failed (HTTP " .. tostring(code) .. ")" end
    local content = extract_content(table.concat(response_chunks))
    if not content or content == "" then return false, "API response could not be parsed." end
    return true, content
end

function AIHelper.generate_summary(opts, input_text)
    return call_chat(opts,
        opts.system_prompt or "Summarize the user text with key points and actionable insights.",
        input_text or "")
end

function AIHelper.generate_clarification(opts, selected_text, page_context)
    local user_prompt = "Highlighted text:\n" .. (selected_text or "") .. "\n\n"
    if page_context and page_context ~= "" then
        user_prompt = user_prompt .. "Page context:\n" .. page_context .. "\n\n"
    end
    user_prompt = user_prompt .. "Please clarify the highlighted text in plain language."
    return call_chat(opts,
        opts.clarify_system_prompt or "Explain the highlighted text in simple terms, grounded in the provided page context.",
        user_prompt)
end

return AIHelper
