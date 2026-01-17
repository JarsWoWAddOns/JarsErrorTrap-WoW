-- Jar's Error Trap
-- Captures Lua errors silently and displays them in a review window

-- Initialize saved variables
local function InitDB()
    if not JarsErrorTrapDB then
        JarsErrorTrapDB = {
            errors = {},
            maxErrors = 100,
            iconX = -100,
            iconY = 100,
        }
    end
end

-- Error storage
local errorLog = {}
local errorCount = 0

-- Forward declarations
local iconFrame
local errorFrame

-- Create icon button
local function CreateIcon()
    local icon = CreateFrame("Button", "JET_Icon", UIParent)
    icon:SetSize(32, 32)
    icon:SetPoint("CENTER", UIParent, "CENTER", JarsErrorTrapDB.iconX or -100, JarsErrorTrapDB.iconY or 100)
    icon:SetMovable(true)
    icon:EnableMouse(true)
    icon:RegisterForDrag("LeftButton")
    icon:SetClampedToScreen(true)
    
    -- Background
    icon.bg = icon:CreateTexture(nil, "BACKGROUND")
    icon.bg:SetAllPoints()
    icon.bg:SetColorTexture(0.8, 0.2, 0.2, 0.9)
    
    -- Icon texture (exclamation mark style)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    
    -- Error count badge
    icon.count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    icon.count:SetPoint("CENTER", 0, -2)
    icon.count:SetTextColor(1, 1, 1)
    icon.count:SetText("0")
    
    -- Tooltip
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Jar's Error Trap")
        GameTooltip:AddLine(errorCount .. " errors captured", 1, 1, 1)
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
            -- Clear errors
            errorLog = {}
            errorCount = 0
            JarsErrorTrapDB.errors = {}
            icon.count:SetText("0")
            if errorFrame then
                errorFrame:Update()
            end
        end
    end)
    
    -- Drag to move
    icon:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    icon:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        JarsErrorTrapDB.iconX = x
        JarsErrorTrapDB.iconY = y
    end)
    
    return icon
end

-- Create error review window
local function CreateErrorFrame()
    local frame = CreateFrame("Frame", "JET_ErrorFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(700, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    
    -- Refresh error list when shown
    frame:SetScript("OnShow", function(self)
        self:Update()
    end)
    
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText("Jar's Error Trap - Captured Errors")
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "JET_ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    
    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(640, 1)
    scrollFrame:SetScrollChild(content)
    
    frame.content = content
    frame.scrollFrame = scrollFrame
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    clearBtn:SetSize(100, 25)
    clearBtn:SetPoint("BOTTOMLEFT", 10, 10)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        errorLog = {}
        errorCount = 0
        JarsErrorTrapDB.errors = {}
        if iconFrame then
            iconFrame.count:SetText("0")
        end
        frame:Update()
    end)
    
    -- Copy Last button
    local copyBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    copyBtn:SetSize(150, 25)
    copyBtn:SetPoint("LEFT", clearBtn, "RIGHT", 5, 0)
    copyBtn:SetText("Copy Last Error")
    copyBtn:SetScript("OnClick", function()
        if #errorLog > 0 then
            local lastError = errorLog[#errorLog]
            local copyText = string.format("[%s] %s\n%s", lastError.time, lastError.message, lastError.stack or "")
            -- Show in a dialog for copying
            StaticPopupDialogs["JET_COPY_ERROR"] = {
                text = "Press Ctrl+C to copy:",
                button1 = "Close",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                hasEditBox = true,
                editBoxWidth = 350,
                OnShow = function(self)
                    self.editBox:SetText(copyText)
                    self.editBox:HighlightText()
                    self.editBox:SetFocus()
                end,
            }
            StaticPopup_Show("JET_COPY_ERROR")
        end
    end)
    
    -- Update function to rebuild error list
    frame.Update = function(self)
        -- Clear existing error displays
        for _, child in ipairs({self.content:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
        
        local yOffset = -5
        for i = #errorLog, 1, -1 do  -- Reverse order, newest first
            local error = errorLog[i]
            
            -- Error container
            local errorBox = CreateFrame("Frame", nil, self.content)
            errorBox:SetPoint("TOPLEFT", 5, yOffset)
            errorBox:SetSize(620, 80)
            
            -- Background
            errorBox.bg = errorBox:CreateTexture(nil, "BACKGROUND")
            errorBox.bg:SetAllPoints()
            errorBox.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
            
            -- Timestamp
            errorBox.time = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            errorBox.time:SetPoint("TOPLEFT", 5, -5)
            errorBox.time:SetText(error.time)
            errorBox.time:SetTextColor(0.7, 0.7, 0.7)
            
            -- Error count badge
            errorBox.countText = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            errorBox.countText:SetPoint("TOPRIGHT", -5, -5)
            errorBox.countText:SetText("#" .. i)
            errorBox.countText:SetTextColor(1, 0.5, 0.5)
            
            -- Error message
            errorBox.message = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            errorBox.message:SetPoint("TOPLEFT", 5, -22)
            errorBox.message:SetPoint("RIGHT", -5, 0)
            errorBox.message:SetJustifyH("LEFT")
            errorBox.message:SetMaxLines(2)
            errorBox.message:SetText(error.message)
            errorBox.message:SetTextColor(1, 0.3, 0.3)
            
            -- Stack trace (truncated)
            if error.stack then
                errorBox.stack = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                errorBox.stack:SetPoint("TOPLEFT", 5, -50)
                errorBox.stack:SetPoint("RIGHT", -5, 0)
                errorBox.stack:SetJustifyH("LEFT")
                errorBox.stack:SetMaxLines(2)
                errorBox.stack:SetText(error.stack:sub(1, 200) .. (error.stack:len() > 200 and "..." or ""))
                errorBox.stack:SetTextColor(0.8, 0.8, 0.8)
            end
            
            yOffset = yOffset - 85
        end
        
        self.content:SetHeight(math.abs(yOffset) + 10)
    end
    
    return frame
end

-- Custom error handler
local function ErrorHandler(errMsg)
    -- Capture the error
    local stack = debugstack(3)  -- Skip error handler frames
    local timestamp = date("%H:%M:%S")
    
    local error = {
        message = tostring(errMsg),
        stack = stack,
        time = timestamp,
    }
    
    table.insert(errorLog, error)
    errorCount = errorCount + 1
    
    -- Update saved variables (keep last 100)
    table.insert(JarsErrorTrapDB.errors, error)
    if #JarsErrorTrapDB.errors > (JarsErrorTrapDB.maxErrors or 100) then
        table.remove(JarsErrorTrapDB.errors, 1)
    end
    
    -- Update icon count
    if iconFrame then
        iconFrame.count:SetText(tostring(errorCount))
    end
    
    -- Update error frame if visible
    if errorFrame and errorFrame:IsShown() then
        errorFrame:Update()
    end
    
    -- Flash the icon
    if iconFrame then
        UIFrameFlash(iconFrame, 0.3, 0.3, 0.5, true, 0, 0)
    end
    
    -- Return the error message (suppress display)
    return errMsg
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "JarsErrorTrap" then
            InitDB()
            
            -- Install error handler
            seterrorhandler(ErrorHandler)
            
            -- Load saved errors
            errorLog = JarsErrorTrapDB.errors or {}
            errorCount = #errorLog
        end
    elseif event == "PLAYER_LOGIN" then
        print("|cffff6666Jar's Error Trap|r loaded. " .. errorCount .. " errors in log.")
        
        -- Create UI
        iconFrame = CreateIcon()
        iconFrame.count:SetText(tostring(errorCount))
        
        errorFrame = CreateErrorFrame()
        errorFrame:Update()
    end
end)

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
        errorLog = {}
        errorCount = 0
        JarsErrorTrapDB.errors = {}
        if iconFrame then
            iconFrame.count:SetText("0")
        end
        if errorFrame then
            errorFrame:Update()
        end
        print("|cffff6666Jar's Error Trap|r Errors cleared.")
    elseif msg == "test" then
        -- Trigger a test error
        error("This is a test error from Jar's Error Trap")
    else
        print("|cffff6666Jar's Error Trap|r Commands:")
        print("  /jet - Toggle error window")
        print("  /jet clear - Clear all errors")
        print("  /jet test - Generate a test error")
    end
end
