--[[
    Local Translator Plugin for KOReader

    Sends selected text to another Android app (e.g. Translator by DavidVentura)
    via Intent, so the target app can show a floating translation popup
    without leaving KOReader.

    Uses dictLookup with parameter order (text, package, action),
    matching KOReader's internal doExternalDictLookup implementation.

    Actions:
      "text" = ACTION_PROCESS_TEXT (floating popup, recommended)
      "send" = ACTION_SEND (opens the full app)

    Usage:
      1. Long-press and select text in a document
      2. Tap "Local Translation" in the highlight popup
      3. The configured app receives the text and shows a popup

    Configuration:
      Settings → Local Translator
      Default: dev.davidv.translator (Translator by DavidVentura), action "text"
]]

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("ffi/util")
local _ = require("gettext")
local T = util.template

-- Only load android module on Android
local android = Device:isAndroid() and require("android") or nil

-- Plugin path for log file
local plugin_path = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
plugin_path = plugin_path and plugin_path:gsub("/$", "") or "."
local LOG_FILE = plugin_path .. "/localtranslator.log"

local SETTINGS_PREFIX = "localtranslator_"
local SETTING_PACKAGE = SETTINGS_PREFIX .. "package"
local SETTING_ACTION = SETTINGS_PREFIX .. "action"

-- Default target: Translator by DavidVentura (floating popup via PROCESS_TEXT)
local DEFAULT_PACKAGE = "dev.davidv.translator"
local DEFAULT_ACTION = "text"  -- "text" = PROCESS_TEXT (floating), "send" = ACTION_SEND (full app)

-- Common translator app presets (package name → display name, action)
local APP_PRESETS = {
    { name = "Translator (DavidVentura)", package = "dev.davidv.translator", action = "text" },
    { name = "Microsoft Translator",      package = "com.microsoft.translator",   action = "send" },
    { name = "Google Translate",          package = "com.google.android.apps.translate", action = "send" },
    { name = "DeepL Translate",           package = "com.deepl.translate",        action = "send" },
    { name = "Naver Papago",              package = "com.nhn.android.naversdic",  action = "send" },
    { name = "DictTango",                 package = "cn.jimex.dict",              action = "send" },
}

local LocalTranslator = WidgetContainer:extend{
    name = "localtranslator",
    is_doc_only = false,
    _last_logged_file = nil,
}

-- ============================================================
-- Logging
-- ============================================================

function LocalTranslator:log(msg)
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg) .. "\n")
        f:close()
    end
end

function LocalTranslator:logClear()
    local f = io.open(LOG_FILE, "w")
    if f then f:close() end
end

-- Clear log when a new document is opened
function LocalTranslator:logRotateIfNewDoc()
    local filepath = self.ui and self.ui.document and self.ui.document.file
    if not filepath then return end
    if self._last_logged_file ~= filepath then
        self._last_logged_file = filepath
        self:logClear()
        self:log("=== New document: " .. filepath .. " ===")
    end
end

-- ============================================================
-- Settings helpers
-- ============================================================

function LocalTranslator:getTargetPackage()
    return G_reader_settings:readSetting(SETTING_PACKAGE) or DEFAULT_PACKAGE
end

function LocalTranslator:setTargetPackage(pkg)
    if pkg and pkg ~= "" then
        G_reader_settings:saveSetting(SETTING_PACKAGE, pkg)
    else
        G_reader_settings:delSetting(SETTING_PACKAGE)
    end
end

function LocalTranslator:getAction()
    return G_reader_settings:readSetting(SETTING_ACTION) or DEFAULT_ACTION
end

function LocalTranslator:setAction(action)
    if action == "text" or action == "send" then
        G_reader_settings:saveSetting(SETTING_ACTION, action)
    end
end

-- ============================================================
-- Core: send text to target app via Intent
-- ============================================================

function LocalTranslator:translate(text)
    self:logRotateIfNewDoc()

    if not text or text == "" then
        self:log("translate: no text selected")
        UIManager:show(InfoMessage:new{ text = _("No selected text.") })
        return
    end

    self:log("translate: text length=" .. #text .. ", preview=" .. text:sub(1, 50):gsub("\n", " "))

    -- Check Android availability
    if not Device:isAndroid() then
        self:log("translate: ERROR - not on Android")
        UIManager:show(InfoMessage:new{
            text = _("Local translation is only supported on Android.")
        })
        return
    end
    self:log("translate: platform=Android")

    -- Check dictLookup API
    if not android then
        self:log("translate: ERROR - android module is nil")
        UIManager:show(InfoMessage:new{ text = _("Android module not available.") })
        return
    end
    if not android.dictLookup then
        self:log("translate: ERROR - android.dictLookup is nil")
        local keys = {}
        for k, _ in pairs(android) do table.insert(keys, k) end
        self:log("translate: android module keys: " .. table.concat(keys, ", "))
        UIManager:show(InfoMessage:new{ text = _("dictLookup API not available on this KOReader build.") })
        return
    end
    self:log("translate: android.dictLookup available")

    local package = self:getTargetPackage()
    local action = self:getAction()
    self:log("translate: package=" .. package .. ", action=" .. action)

    if not package or package == "" then
        self:log("translate: ERROR - no package configured")
        UIManager:show(InfoMessage:new{
            text = _("Please set the target app package in Settings → Local Translator.")
        })
        return
    end

    -- Log text preview (first 80 chars, no newlines)
    local preview = text:sub(1, 80):gsub("\n", " "):gsub("\r", "")
    -- CRITICAL: parameter order is (text, package, action), matching
    -- KOReader's internal doExternalDictLookup in device/android/device.lua
    self:log("translate: calling dictLookup(text, '" .. package .. "', '" .. action .. "')")
    self:log("translate: text preview: " .. preview)

    local ok, err = pcall(function()
        -- "text" action = ACTION_PROCESS_TEXT (floating popup)
        -- "send" action = ACTION_SEND (full app)
        android.dictLookup(text, package, action)
    end)

    if ok then
        self:log("translate: dictLookup returned successfully (no error)")
    else
        self:log("translate: dictLookup FAILED: " .. tostring(err))
        UIManager:show(InfoMessage:new{
            text = T(_("Failed to launch app:\n%1"), tostring(err))
        })
    end
end

-- ============================================================
-- Highlight popup integration
-- Adds "Local Translation" to the long-press text selection menu
-- ============================================================

function LocalTranslator:addToHighlightDialog()
    if not self.ui or not self.ui.highlight then
        return
    end
    self.ui.highlight:addToHighlightDialog("99_local_translation", function(this)
        return {
            text = _("Local Translation"),
            callback = function()
                local text = this.selected_text and this.selected_text.text
                if not text or text == "" then
                    UIManager:show(InfoMessage:new{ text = _("No selected text.") })
                    return
                end
                -- Close the highlight dialog before launching the app
                this:onClose(true)
                self:translate(text)
            end,
        }
    end)
end

-- ============================================================
-- Settings dialogs
-- ============================================================

function LocalTranslator:showPackageDialog()
    local current = self:getTargetPackage()
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Target app package"),
        input = current,
        input_hint = "dev.davidv.translator",
        input_type = "text",
        buttons = {{
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Save"),
                callback = function()
                    local pkg = input_dialog:getInputText()
                    self:setTargetPackage(pkg)
                    UIManager:close(input_dialog)
                    UIManager:show(InfoMessage:new{
                        text = pkg ~= "" and T(_("Saved: %1"), pkg) or _("Package cleared (using default).")
                    })
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function LocalTranslator:showPresetsMenu()
    local Menu = require("ui/widget/menu")
    local item_table = {}
    local menu
    local current = self:getTargetPackage()

    for _, preset in ipairs(APP_PRESETS) do
        table.insert(item_table, {
            text_func = function()
                local selected = current == preset.package
                return (selected and "✔ " or "") .. preset.name
            end,
            mandatory = preset.package,
            callback = function()
                self:setTargetPackage(preset.package)
                self:setAction(preset.action or DEFAULT_ACTION)
                UIManager:close(menu)
                UIManager:show(InfoMessage:new{
                    text = T(_("Set target to: %1\nAction: %2"), preset.name, preset.action or DEFAULT_ACTION)
                })
            end,
        })
    end

    menu = Menu:new{
        title = _("Select translator app"),
        item_table = item_table,
    }
    UIManager:show(menu)
end

-- ============================================================
-- Plugin lifecycle
-- ============================================================

function LocalTranslator:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    self:addToHighlightDialog()
    self:log("plugin initialized, default package=" .. DEFAULT_PACKAGE .. ", action=" .. DEFAULT_ACTION)
end

function LocalTranslator:addToMainMenu(menu_items)
    local self_ref = self
    menu_items.localtranslator = {
        text = _("Local Translator"),
        sorting_hint = "search_settings",
        sub_item_table = {
            {
                text_func = function()
                    local pkg = self_ref:getTargetPackage()
                    return pkg ~= "" and T(_("Target app: %1"), pkg) or _("Set target app package")
                end,
                callback = function()
                    self_ref:showPackageDialog()
                end,
            },
            {
                text = _("Choose from presets"),
                keep_menu_open = true,
                callback = function()
                    self_ref:showPresetsMenu()
                end,
            },
            -- Intent action as sub_item_table for immediate menu refresh
            {
                text_func = function()
                    local action = self_ref:getAction()
                    return T(_("Intent action: %1"), action)
                end,
                sub_item_table = {
                    {
                        text_func = function()
                            local selected = self_ref:getAction() == "text"
                            return (selected and "✔ " or "") .. _("PROCESS_TEXT (floating popup)")
                        end,
                        help_text = _("Uses Android's text processing intent. Target app must have a PROCESS_TEXT activity. Shows a floating dialog without leaving KOReader. Recommended for Translator (DavidVentura)."),
                        callback = function(touchmenu_instance)
                            self_ref:setAction("text")
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    },
                    {
                        text_func = function()
                            local selected = self_ref:getAction() == "send"
                            return (selected and "✔ " or "") .. _("ACTION_SEND (full app)")
                        end,
                        help_text = _("Standard share intent. Opens the target app's main activity. Use for apps that don't support PROCESS_TEXT."),
                        callback = function(touchmenu_instance)
                            self_ref:setAction("send")
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    },
                },
            },
            {
                text = _("Test with clipboard"),
                separator = true,
                callback = function()
                    local text = Device:hasClipboard() and Device.input.getClipboardText() or nil
                    if not text or text == "" then
                        UIManager:show(InfoMessage:new{ text = _("Clipboard is empty.") })
                        return
                    end
                    self_ref:translate(text)
                end,
                help_text = _("Sends the current clipboard text to the target app for testing."),
            },
            {
                text = _("About"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _([[Local Translator v1.1.0

Sends selected text to another Android app via Intent.
Default: Translator (DavidVentura) - dev.davidv.translator

Uses PROCESS_TEXT intent for floating popup translation.
Parameter order: dictLookup(text, package, action)
Log: plugin_dir/localtranslator.log]]),
                    })
                end,
            },
        },
    }
end

return LocalTranslator
