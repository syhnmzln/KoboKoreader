local _plugin_dir = (debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$") or ".") .. "/"

if not package.path:find(_plugin_dir, 1, true) then
    package.path = _plugin_dir .. "?.lua;" .. package.path
end

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AIHelper = require("aihelper")

local HighContext = WidgetContainer:extend{
    name = "highcontext",
}

local function trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end


local function show_long_text(title, text)
    UIManager:show(TextViewer:new{
        title = title,
        text = text,
    })
end

function HighContext:_injectClarifyMenuItem(menu_items, selected_text)
    local item = {
        text = _("Clarify"),
        callback = function() self:runClarify(selected_text) end,
        keep_menu_open = false,
    }

    if type(menu_items) ~= "table" then return end

    if menu_items.highcontext_clarify == nil then
        menu_items.highcontext_clarify = item
    end

    local is_array_like = (#menu_items > 0)
    if is_array_like then
        table.insert(menu_items, item)
    end
end

local function read_api_key_from_file(path)
    if not path or path == "" then return nil end
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return trim(content) ~= "" and trim(content) or nil
end

function HighContext:onDispatcherRegisterActions()
    Dispatcher:registerAction("highcontext_summarize_page", {
        category = "none", event = "HighContextSummarizePage",
        title = _("HighContext: summarize page"), general = true,
    })
end

function HighContext:init()
    self:onDispatcherRegisterActions()
    self.settings = G_reader_settings:readSetting("highcontext_settings", {
        api_key = "",
        api_key_file = _plugin_dir .. "api_key.txt",
        endpoint = "https://api.openai.com/v1/chat/completions",
        model = "gpt-4o-mini",
        system_prompt = "Summarize the text with concise bullet points and key context.",
        clarify_system_prompt = "Explain the highlighted text in simple terms. Keep it concise and accurate.",
    })
    self.ui.menu:registerToMainMenu(self)
end

function HighContext:addToMainMenu(menu_items)
    menu_items.highcontext = {
        text = _("HighContext"), sorting_hint = "tools",
        sub_item_table = {
            { text = _("Summarize current page"), callback = function() self:onHighContextSummarizePage() end },
            { text = _("API key file info"), callback = function() self:showApiKeyFileInfo() end },
        },
    }
end

function HighContext:showApiKeyFileInfo()
    local path = self.settings.api_key_file or (_plugin_dir .. "api_key.txt")
    UIManager:show(InfoMessage:new{ text = _("Place your API key in: ") .. path, timeout = 6 })
end

function HighContext:getCurrentPageText()
    if not self.ui or not self.ui.document then return nil, _("Reader document is unavailable.") end
    local ok_page, page = pcall(function() return self.ui:getCurrentPage() end)
    if not ok_page or type(page) ~= "number" then return nil, _("Could not resolve current page.") end
    local doc = self.ui.document
    if doc.getPageText then
        local ok_text, text = pcall(function() return doc:getPageText(page) end)
        if ok_text and type(text) == "string" and trim(text) ~= "" then return text end
    end
    if doc.getTextFromPage then
        local ok_text2, text2 = pcall(function() return doc:getTextFromPage(page) end)
        if ok_text2 and type(text2) == "string" and trim(text2) ~= "" then return text2 end
    end
    if doc.getPageTextFromPositions then
        local ok_text3, text3 = pcall(function() return doc:getPageTextFromPositions(page) end)
        if ok_text3 and type(text3) == "string" and trim(text3) ~= "" then return text3 end
    end
    return nil, _("This document backend does not expose page text extraction.")
end

function HighContext:getRuntimeSettings()
    local runtime_settings = {}
    for k, v in pairs(self.settings) do runtime_settings[k] = v end
    local key_from_file = read_api_key_from_file(self.settings.api_key_file)
    runtime_settings.api_key = key_from_file or self.settings.api_key
    return runtime_settings
end

function HighContext:runClarify(highlighted_text)
    local selected = trim(highlighted_text or "")
    if selected == "" and self.ui and self.ui.highlight and self.ui.highlight.getSelectedText then
        local ok_sel, text = pcall(function() return self.ui.highlight:getSelectedText() end)
        if ok_sel then selected = trim(text or "") end
    end
    if selected == "" then
        UIManager:show(InfoMessage:new{ text = _("No highlighted text found."), timeout = 3 })
        return
    end

    local page_context = ""
    local page_text = self:getCurrentPageText()
    if type(page_text) == "string" then page_context = page_text end

    local progress = InfoMessage:new{ text = _("HighContext: clarifying...") }
    UIManager:show(progress)
    local ok, result = AIHelper.generate_clarification(self:getRuntimeSettings(), selected, page_context)
    UIManager:close(progress)
    if ok then
        show_long_text(_("Clarify"), result)
    else
        UIManager:show(InfoMessage:new{ text = _("HighContext failed: ") .. result, timeout = 6 })
    end
end

function HighContext:addToSelectionMenu(menu_items, selected_text)
    self:_injectClarifyMenuItem(menu_items, selected_text)
end

function HighContext:addToHighlightDialog(highlight_dialog, menu_items, selected_text)
    self:_injectClarifyMenuItem(menu_items, selected_text)
end

function HighContext:onHighContextSummarizePage()
    local page_text, read_error = self:getCurrentPageText()
    if not page_text then
        UIManager:show(InfoMessage:new{ text = read_error or _("Could not read page text for this document/backend."), timeout = 3 })
        return
    end
    local progress = InfoMessage:new{ text = _("HighContext: generating summary...") }
    UIManager:show(progress)
    local ok, result = AIHelper.generate_summary(self:getRuntimeSettings(), page_text)
    UIManager:close(progress)
    if ok then
        show_long_text(_("Summary"), result)
    else
        UIManager:show(InfoMessage:new{ text = _("HighContext failed: ") .. result, timeout = 6 })
    end
end

return HighContext
