-- Jar's Error Trap
-- Captures Lua errors silently and displays them in a review window

-- Modern UI Color Palette
local UI_PALETTE = {
    bg = {0.10, 0.10, 0.12, 0.95},
    header = {0.15, 0.15, 0.18, 1},
    accent = {1.0, 0.55, 0.0, 1},
    text = {0.95, 0.95, 0.95, 1},
    textDim = {0.70, 0.70, 0.70, 1},
    border = {0.20, 0.20, 0.22, 1},
}

local modernBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local issecretvalue = issecretvalue or function() return false end

local DEFAULTS = {
    maxErrors = 1000,
    minimapAngle = math.rad(45),
    passToPrevious = false,
    session = 0,
}

-- Initialize saved variables
local function InitDB()
    -- if not JarsErrorTrapDB then
    --     JarsErrorTrapDB = { errors = {}, maxErrors = 1000, minimapAngle = 45 }
    -- end
    if type(JarsErrorTrapDB) ~= "table" then
        JarsErrorTrapDB = {}
    end
    for k, v in pairs(DEFAULTS) do
        if JarsErrorTrapDB[k] == nil then
            JarsErrorTrapDB[k] = v
        end
    end
    if type(JarsErrorTrapDB.errors) ~= "table" then
        JarsErrorTrapDB.errors = {}
    end
    -- Update maxErrors if it was set to old default
    if JarsErrorTrapDB.maxErrors == 100 then
        JarsErrorTrapDB.maxErrors = 1000
    end
end

-- Error storage. this is just a buffer until ADDON_LOADED, then it becomes the DB table
local errorLog = {}
local seen = {}          -- dedupe key -> entry
local sessionCount = 0   -- new errors this session, the cap counts these
local session = 0
local MAX_ERRORS = 1000  -- Hard limit on total errors captured

-- Forward declarations
local iconFrame
local errorFrame

local function GetCap()
    return JarsErrorTrapDB and JarsErrorTrapDB.maxErrors or MAX_ERRORS
end

local function LimitReached()
    return sessionCount >= GetCap()
end

-- msg + first stack line
local function KeyOf(msg, stack)
    return msg .. "\n" .. (stack and stack:match("^[^\n]*") or "")
end

-- drop oldest when full
local function TrimLog()
    local cap = GetCap()
    while #errorLog > cap do
        local old = table.remove(errorLog, 1)
        seen[KeyOf(old.message, old.stack)] = nil
    end
end

local function UpdateIconCount()
    if not iconFrame then return end
    iconFrame.count:SetText(tostring(#errorLog))
    if LimitReached() then
        iconFrame.count:SetTextColor(1, 0, 0)
    else
        iconFrame.count:SetTextColor(1, 1, 1)
    end
end

local function FlashIcon()
    if not iconFrame then return end
    if not iconFrame.flashAnim then
        iconFrame.flashAnim = iconFrame:CreateAnimationGroup()
        local fadeOut = iconFrame.flashAnim:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.3)
        fadeOut:SetDuration(0.3)
        fadeOut:SetOrder(1)
        local fadeIn = iconFrame.flashAnim:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.3)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.3)
        fadeIn:SetOrder(2)
    end
    if not iconFrame.flashAnim:IsPlaying() then
        iconFrame.flashAnim:Play()
    end
end

-- batch ui updates so an error storm doesnt redraw every time
local refreshQueued = false
local function RefreshUI()
    refreshQueued = false
    UpdateIconCount()
    FlashIcon()
    if errorFrame and errorFrame:IsShown() then
        errorFrame:Update()
    end
end

local function ScheduleRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, RefreshUI)
end

local function AddEntry(msg, stack)
    if issecretvalue(msg) then
        msg = "<secret error message>"
    else
        msg = tostring(msg)
    end
    local key = KeyOf(msg, stack)
    local now = date("%Y-%m-%d %H:%M:%S")
    local entry = seen[key]

    if entry then
        entry.counter = (entry.counter or 1) + 1
        entry.time = now
        -- old session repeat, bump it back to the top
        if entry.session ~= session then
            for i = #errorLog, 1, -1 do
                if errorLog[i] == entry then
                    table.remove(errorLog, i)
                    break
                end
            end
            table.insert(errorLog, entry)
            entry.session = session
        end
    else
        entry = { message = msg, stack = stack, time = now, counter = 1, session = session }
        table.insert(errorLog, entry)
        seen[key] = entry
        sessionCount = sessionCount + 1
        TrimLog()
    end

    ScheduleRefresh()
end

local function ClearErrors()
    JarsErrorTrapDB.errors = {}
    errorLog = JarsErrorTrapDB.errors
    wipe(seen)
    sessionCount = 0
    UpdateIconCount()
    if errorFrame then
        wipe(errorFrame.expandedErrors)
        errorFrame:Update()
    end
end

-- Create icon button
local function CreateIcon()
    local icon = CreateFrame("Button", "JET_MinimapButton", Minimap)
    icon:SetSize(32, 32)
    icon:SetFrameStrata("MEDIUM")
    icon:SetFrameLevel(8)
    icon:EnableMouse(true)
    icon:RegisterForDrag("LeftButton")
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Position on minimap
    local angle = JarsErrorTrapDB.minimapAngle or math.rad(45)
    local radius = 110
    local x = math.cos(angle) * radius + 10
    local y = math.sin(angle) * radius - 10
    icon:SetPoint("CENTER", Minimap, "CENTER", x, y)

    -- Background
    icon.bg = icon:CreateTexture(nil, "BACKGROUND")
    icon.bg:SetSize(20, 20)
    icon.bg:SetPoint("CENTER", -10, 10)
    icon.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Icon texture (exclamation mark style)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetSize(18, 18)
    icon.texture:SetPoint("CENTER", -10, 10)
    icon.texture:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")

    -- Border
    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetSize(52, 52)
    icon.border:SetPoint("CENTER")
    icon.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Error count badge
    icon.count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- icon.count:SetPoint("BOTTOM", 0, 2)
    icon.count:SetPoint("CENTER")
    icon.count:SetTextColor(1, 1, 1)
    icon.count:SetText("0")

    -- Tooltip
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Jar's Error Trap")
        GameTooltip:AddLine(#errorLog .. " errors in log, " .. sessionCount .. " new this session", 1, 1, 1)
        if LimitReached() then
            GameTooltip:AddLine("LIMIT REACHED this session", 1, 0, 0)
            GameTooltip:AddLine("Oldest errors are being dropped", 1, 0.5, 0)
        end
        GameTooltip:AddLine("Click to view errors", 0.5, 0.5, 1)
        GameTooltip:AddLine("Right-click to clear", 1, 0.5, 0.5)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Click to open error window
    icon:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if errorFrame then
                errorFrame:SetShown(not errorFrame:IsShown())
            end
        elseif button == "RightButton" then
            ClearErrors()
        end
    end)

    -- Drag to move around minimap
    icon:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            -- Offset the center by 10px right and 10px down
            mx = mx + 10
            my = my - 10
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale

            local angle = math.atan2(py - my, px - mx)
            local radius = 110
            local x = math.cos(angle) * radius + 10
            local y = math.sin(angle) * radius - 10
            self:SetPoint("CENTER", Minimap, "CENTER", x, y)

            JarsErrorTrapDB.minimapAngle = angle
        end)
    end)
    icon:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    return icon
end

-- Create error detail window
local function CreateErrorDetailFrame()
    local detailFrame = CreateFrame("Frame", "JET_ErrorDetailFrame", UIParent, "BackdropTemplate")
    detailFrame:SetSize(650, 450)
    detailFrame:SetPoint("LEFT", "JET_ErrorFrame", "RIGHT", 10, 0)
    detailFrame:SetFrameStrata("FULLSCREEN")
    detailFrame:SetMovable(true)
    detailFrame:EnableMouse(true)
    detailFrame:RegisterForDrag("LeftButton")
    detailFrame:SetScript("OnDragStart", detailFrame.StartMoving)
    detailFrame:SetScript("OnDragStop", detailFrame.StopMovingOrSizing)
    detailFrame:SetClampedToScreen(true)
    detailFrame:Hide()

    -- Modern background
    detailFrame:SetBackdrop(modernBackdrop)
    detailFrame:SetBackdropColor(unpack(UI_PALETTE.bg))
    detailFrame:SetBackdropBorderColor(unpack(UI_PALETTE.border))

    -- Title bar with teal accent
    local titleBar = detailFrame:CreateTexture(nil, "OVERLAY")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(32)
    titleBar:SetColorTexture(UI_PALETTE.header[1], UI_PALETTE.header[2], UI_PALETTE.header[3], UI_PALETTE.header[4])

    local titleAccent = detailFrame:CreateTexture(nil, "OVERLAY")
    titleAccent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    titleAccent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    titleAccent:SetHeight(2)
    titleAccent:SetColorTexture(UI_PALETTE.accent[1], UI_PALETTE.accent[2], UI_PALETTE.accent[3], UI_PALETTE.accent[4])

    detailFrame.title = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailFrame.title:SetPoint("TOP", titleBar, "TOP", 0, -8)
    detailFrame.title:SetText("Error Details")
    detailFrame.title:SetTextColor(UI_PALETTE.text[1], UI_PALETTE.text[2], UI_PALETTE.text[3])

    -- Modern close button
    local closeBtn = CreateFrame("Button", nil, detailFrame)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    local closeBtnBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBtnBg:SetAllPoints()
    closeBtnBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeBtnText:SetPoint("CENTER", 0, 1)
    closeBtnText:SetText("x")
    closeBtnText:SetTextColor(UI_PALETTE.textDim[1], UI_PALETTE.textDim[2], UI_PALETTE.textDim[3])
    closeBtn:SetScript("OnEnter", function(self)
        closeBtnText:SetTextColor(UI_PALETTE.accent[1], UI_PALETTE.accent[2], UI_PALETTE.accent[3])
    end)
    closeBtn:SetScript("OnLeave", function(self)
        closeBtnText:SetTextColor(UI_PALETTE.textDim[1], UI_PALETTE.textDim[2], UI_PALETTE.textDim[3])
    end)
    closeBtn:SetScript("OnClick", function() detailFrame:Hide() end)

    -- Scrollable edit box for error text
    local scrollFrame = CreateFrame("ScrollFrame", "JET_DetailScrollFrame", detailFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetWidth(600)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() detailFrame:Hide() end)

    scrollFrame:SetScrollChild(editBox)
    detailFrame.editBox = editBox
    detailFrame.scrollFrame = scrollFrame

    -- show text pre-selected so ctrl+c just works
    detailFrame.ShowText = function(self, title, text)
        self.title:SetText(title)
        self.editBox:SetText(text)
        self:Show()
        self.scrollFrame:SetVerticalScroll(0)
        self.editBox:SetFocus()
        self.editBox:HighlightText()
    end

    -- Function to show error
    detailFrame.ShowError = function(self, error)
        local errorText = string.format("Time: %s\nCount: %d\n\nError Message:\n%s\n\nStack Trace:\n%s",
            error.time, error.counter or 1, error.message, error.stack or "No stack trace available")
        -- self.editBox:SetText(errorText)
        -- self.editBox:SetCursorPosition(0)
        -- self:Show()
        self:ShowText("Error Details - Ctrl+C to copy", errorText)
    end

    return detailFrame
end

local function AddLines(lines, text)
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
end

-- one block per unique error, repeats are allready merged w/ a counter
local function BuildExportLines()
    local version, build, _, iface = GetBuildInfo()
    local lines = {
        "Jar's Error Trap export - " .. date("%Y-%m-%d %H:%M:%S"),
        string.format("Client %s (%s) interface %s", version, build, iface),
        #errorLog .. " unique errors",
    }

    -- versions of addons that show up in the stacks
    local addons = {}
    for _, e in ipairs(errorLog) do
        for name in ((e.stack or "") .. "\n" .. (e.message or "")):gmatch("AddOns[/\\]([^/\\]+)[/\\]") do
            addons[name] = true
        end
    end
    local names = {}
    for name in pairs(addons) do table.insert(names, name) end
    table.sort(names)
    if #names > 0 then
        table.insert(lines, "Addons in stacks:")
        for _, name in ipairs(names) do
            local ok, v = pcall(C_AddOns.GetAddOnMetadata, name, "Version")
            table.insert(lines, "  " .. name .. " " .. tostring(ok and v or "?"))
        end
    end

    for i, e in ipairs(errorLog) do
        table.insert(lines, "")
        table.insert(lines, string.format("[%d] x%d  last seen %s", i, e.counter or 1, e.time or "?"))
        AddLines(lines, e.message)
        AddLines(lines, e.stack or "No stack trace available")
        table.insert(lines, "----")
    end
    return lines
end

local function ExportErrors()
    local lines = BuildExportLines()
    -- ends up in WTF\Account\<acct>\SavedVariables\JarsErrorTrap.lua after /reload or logout
    JarsErrorTrapDB.lastExport = lines
    if not errorFrame then return end
    if not errorFrame.errorDetailFrame then
        errorFrame.errorDetailFrame = CreateErrorDetailFrame()
    end
    errorFrame.errorDetailFrame:ShowText("Export - Ctrl+C to copy, /reload to save to disk", table.concat(lines, "\n"))
    print("|cffff6666Jar's Error Trap|r Exported " .. #errorLog .. " errors. /reload to write it to SavedVariables.")
end

-- Create error review window
local function CreateErrorFrame()
    local frame = CreateFrame("Frame", "JET_ErrorFrame", UIParent, "BackdropTemplate")
    frame:SetSize(650, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Modern background
    frame:SetBackdrop(modernBackdrop)
    frame:SetBackdropColor(unpack(UI_PALETTE.bg))
    frame:SetBackdropBorderColor(unpack(UI_PALETTE.border))

    -- Title bar with teal accent
    local titleBar = frame:CreateTexture(nil, "OVERLAY")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(32)
    titleBar:SetColorTexture(UI_PALETTE.header[1], UI_PALETTE.header[2], UI_PALETTE.header[3], UI_PALETTE.header[4])

    local titleAccent = frame:CreateTexture(nil, "OVERLAY")
    titleAccent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    titleAccent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    titleAccent:SetHeight(2)
    titleAccent:SetColorTexture(UI_PALETTE.accent[1], UI_PALETTE.accent[2], UI_PALETTE.accent[3], UI_PALETTE.accent[4])

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", titleBar, "TOP", 0, -8)

    -- Modern close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    local closeBtnBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBtnBg:SetAllPoints()
    closeBtnBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeBtnText:SetPoint("CENTER", 0, 1)
    closeBtnText:SetText("x")
    closeBtnText:SetTextColor(UI_PALETTE.textDim[1], UI_PALETTE.textDim[2], UI_PALETTE.textDim[3])
    closeBtn:SetScript("OnEnter", function(self)
        closeBtnText:SetTextColor(UI_PALETTE.accent[1], UI_PALETTE.accent[2], UI_PALETTE.accent[3])
    end)
    closeBtn:SetScript("OnLeave", function(self)
        closeBtnText:SetTextColor(UI_PALETTE.textDim[1], UI_PALETTE.textDim[2], UI_PALETTE.textDim[3])
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Refresh error list when shown
    frame:SetScript("OnShow", function(self)
        self:Update()
    end)

    -- Update title to show limit status
    frame.UpdateTitle = function(self)
        if LimitReached() then
            self.title:SetText("Jar's Error Trap - " .. #errorLog .. " Errors (LIMIT REACHED, dropping oldest)")
            self.title:SetTextColor(UI_PALETTE.accent[1], UI_PALETTE.accent[2], UI_PALETTE.accent[3])
        else
            self.title:SetText("Jar's Error Trap - " .. #errorLog .. " Errors")
            self.title:SetTextColor(UI_PALETTE.text[1], UI_PALETTE.text[2], UI_PALETTE.text[3])
        end
    end
    frame:UpdateTitle()

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "JET_ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(590, 1)
    scrollFrame:SetScrollChild(content)

    frame.content = content
    frame.scrollFrame = scrollFrame
    -- keyed by entry table so it survives the oldest getting dropped
    frame.expandedErrors = setmetatable({}, { __mode = "k" })

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    clearBtn:SetSize(100, 25)
    clearBtn:SetPoint("BOTTOMLEFT", 10, 10)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", ClearErrors)

    local exportBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    exportBtn:SetSize(100, 25)
    exportBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", ExportErrors)

    -- Reference to error detail frame
    frame.errorDetailFrame = nil

    -- build a row once, Update just fills it in
    local function CreateRow()
        local errorBox = CreateFrame("Button", nil, content)
        errorBox:SetSize(580, 30)

        errorBox.bg = errorBox:CreateTexture(nil, "BACKGROUND")
        errorBox.bg:SetAllPoints()
        errorBox.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

        errorBox.expandBtn = CreateFrame("Button", nil, errorBox)
        errorBox.expandBtn:SetSize(20, 20)
        errorBox.expandBtn:SetPoint("TOPLEFT", 5, -5)
        errorBox.expandBtn:SetScript("OnClick", function()
            local e = errorBox.entry
            frame.expandedErrors[e] = not frame.expandedErrors[e] or nil
            frame:Update()
        end)

        errorBox.time = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        errorBox.time:SetPoint("LEFT", errorBox.expandBtn, "RIGHT", 5, 0)
        errorBox.time:SetTextColor(0.7, 0.7, 0.7)

        errorBox.countText = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        errorBox.countText:SetPoint("TOPRIGHT", -40, -5)
        errorBox.countText:SetTextColor(1, 0.5, 0.5)

        errorBox.openBtn = CreateFrame("Button", nil, errorBox, "UIPanelButtonTemplate")
        errorBox.openBtn:SetSize(35, 20)
        errorBox.openBtn:SetPoint("RIGHT", -5, 0)
        errorBox.openBtn:SetText("Open")
        errorBox.openBtn:SetScript("OnClick", function()
            if not frame.errorDetailFrame then
                frame.errorDetailFrame = CreateErrorDetailFrame()
            end
            frame.errorDetailFrame:ShowError(errorBox.entry)
        end)

        errorBox.message = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        errorBox.message:SetPoint("LEFT", errorBox.time, "RIGHT", 5, 0)
        errorBox.message:SetPoint("RIGHT", errorBox.countText, "LEFT", -5, 0)
        errorBox.message:SetJustifyH("LEFT")
        errorBox.message:SetTextColor(1, 0.3, 0.3)

        errorBox.stackContainer = CreateFrame("Frame", nil, errorBox)
        errorBox.stackContainer:SetPoint("TOPLEFT", 30, -25)
        errorBox.stackContainer:SetPoint("RIGHT", -5, 0)

        errorBox.stack = errorBox.stackContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        errorBox.stack:SetPoint("TOPLEFT")
        errorBox.stack:SetPoint("RIGHT")
        errorBox.stack:SetJustifyH("LEFT")
        errorBox.stack:SetTextColor(0.8, 0.8, 0.8)

        return errorBox
    end

    -- Update function to rebuild error list
    frame._errorBoxPool = frame._errorBoxPool or {}
    frame.Update = function(self)
        -- Update title with current count
        self:UpdateTitle()

        -- Recycle existing error displays back to pool
        -- for _, child in ipairs({self.content:GetChildren()}) do
        --     child:Hide()
        --     table.insert(self._errorBoxPool, child)
        -- end
        local pool = self._errorBoxPool

        local yOffset = -5
        local n = 0
        for i = #errorLog, 1, -1 do  -- Reverse order, newest first
            local errEntry = errorLog[i]
            n = n + 1
            local errorBox = pool[n]
            if not errorBox then
                errorBox = CreateRow()
                pool[n] = errorBox
            end
            errorBox.entry = errEntry
            errorBox:ClearAllPoints()
            errorBox:SetPoint("TOPLEFT", 5, yOffset)
            errorBox:Show()

            local isExpanded = self.expandedErrors[errEntry] or false

            if isExpanded then
                errorBox.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                errorBox.expandBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
                errorBox.expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-MinusButton-Hilight", "ADD")
            else
                errorBox.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                errorBox.expandBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
                errorBox.expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
            end

            errorBox.time:SetText(errEntry.time)
            if (errEntry.counter or 1) > 1 then
                errorBox.countText:SetText("#" .. i .. " x" .. errEntry.counter)
            else
                errorBox.countText:SetText("#" .. i)
            end
            errorBox.message:SetText(errEntry.message)

            if isExpanded then
                errorBox.stackContainer:Show()
                errorBox.message:SetMaxLines(0)
            else
                errorBox.stackContainer:Hide()
                errorBox.message:SetMaxLines(1)
            end

            if errEntry.stack then
                errorBox.stack:SetText(errEntry.stack)
                errorBox.stack:Show()
                errorBox.stackContainer:SetHeight(errorBox.stack:GetStringHeight() + 5)
            else
                errorBox.stack:SetText("")
                errorBox.stack:Hide()
                errorBox.stackContainer:SetHeight(1)
            end

            -- Calculate errorBox height based on expansion state
            if isExpanded then
                local newHeight = 30 + (errorBox.stackContainer:GetHeight() or 0) + errorBox.message:GetStringHeight()
                errorBox:SetHeight(newHeight)
            else
                errorBox:SetHeight(30)
            end

            yOffset = yOffset - errorBox:GetHeight() - 5
        end

        for i = n + 1, #pool do
            pool[i]:Hide()
            pool[i].entry = nil
        end

        self.content:SetHeight(math.abs(yOffset) + 10)
    end

    return frame
end

-- Custom error handler
local prevHandler
local inHandler = false

local function ErrorHandler(errMsg)
    -- dont recurse if something in here blows up
    if inHandler then return errMsg end
    inHandler = true

    local stack = debugstack(3)  -- Skip error handler frames
    if issecretvalue(stack) then
        stack = "debugstack returned secrets"
    end
    pcall(AddEntry, errMsg, stack)

    inHandler = false

    if JarsErrorTrapDB and JarsErrorTrapDB.passToPrevious and prevHandler then
        prevHandler(errMsg)
    end

    -- Return the error message (suppress display)
    return errMsg
end

local function InstallHandler()
    local cur = geterrorhandler()
    if cur ~= ErrorHandler then
        prevHandler = cur
        seterrorhandler(ErrorHandler)
    end
end

-- go in as early as possible, errors buffer til ADDON_LOADED
InstallHandler()

-- merge saved + early buffered errors, cleans up the old double-inserted entries too
local function MergeEntry(e)
    if type(e) ~= "table" or type(e.message) ~= "string" then return end
    local key = KeyOf(e.message, e.stack)
    local have = seen[key]
    if have == e then return end
    if have then
        have.counter = (have.counter or 1) + (e.counter or 1)
        have.time = e.time
    else
        e.counter = e.counter or 1
        table.insert(errorLog, e)
        seen[key] = e
    end
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
eventFrame:RegisterEvent("LUA_WARNING")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "JarsErrorTrap" then
            InitDB()
            JarsErrorTrapDB.session = JarsErrorTrapDB.session + 1
            session = JarsErrorTrapDB.session

            -- Load saved errors
            local early = errorLog
            errorLog = {}
            wipe(seen)
            for _, e in ipairs(JarsErrorTrapDB.errors) do
                MergeEntry(e)
            end
            for _, e in ipairs(early) do
                e.session = session
                MergeEntry(e)
            end
            TrimLog()
            JarsErrorTrapDB.errors = errorLog
        end
    elseif event == "PLAYER_LOGIN" then
        -- someone may have swapped it out during load
        InstallHandler()
        if BugGrabber then
            print("|cffff6666Jar's Error Trap|r BugGrabber is loaded and owns the error handler, Lua errors will go there (blocked actions + warnings still land here).")
        end

        print("|cffff6666Jar's Error Trap|r loaded. " .. #errorLog .. " errors in log.")

        -- Create UI
        iconFrame = CreateIcon()
        UpdateIconCount()

        errorFrame = CreateErrorFrame()
        errorFrame:Update()
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addonName, func = ...
        AddEntry(string.format("%s: %s tried to call %s", event, tostring(addonName or "<name>"), tostring(func or "<func>")))
    elseif event == "LUA_WARNING" then
        local warningText = ...
        AddEntry("LUA_WARNING: " .. tostring(warningText or ""))
    end
end)

-- for JarsAddonConfig
function JarsErrorTrap_OpenConfig()
    if errorFrame then
        errorFrame:Show()
        errorFrame:Raise()
    end
end

-- Slash commands
SLASH_JARSERRORTRAP1 = "/jet"
SLASH_JARSERRORTRAP2 = "/errorstrap"
SlashCmdList["JARSERRORTRAP"] = function(msg)
    msg = msg:lower():trim()

    if msg == "show" or msg == "" then
        if errorFrame then
            errorFrame:SetShown(not errorFrame:IsShown())
        end
    elseif msg == "clear" then
        ClearErrors()
        print("|cffff6666Jar's Error Trap|r Errors cleared.")
    elseif msg == "export" then
        ExportErrors()
    elseif msg == "chain" then
        JarsErrorTrapDB.passToPrevious = not JarsErrorTrapDB.passToPrevious
        print("|cffff6666Jar's Error Trap|r Pass errors to previous handler: " .. (JarsErrorTrapDB.passToPrevious and "on" or "off"))
    elseif msg == "test" then
        -- Trigger a test error
        error("This is a test error from Jar's Error Trap")
    else
        print("|cffff6666Jar's Error Trap|r Commands:")
        print("  /jet - Toggle error window")
        print("  /jet clear - Clear all errors")
        print("  /jet export - Copyable export of all errors, also saved on /reload")
        print("  /jet chain - Toggle passing errors on to the previous handler")
        print("  /jet test - Generate a test error")
    end
end
