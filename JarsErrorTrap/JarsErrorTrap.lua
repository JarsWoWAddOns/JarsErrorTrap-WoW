-- Jar's Error Trap
-- Captures Lua errors silently and displays them in a review window

-- Initialize saved variables
local function InitDB()
    if not JarsErrorTrapDB then
        JarsErrorTrapDB = {
            errors = {},
            maxErrors = 1000,
            minimapAngle = 45,
        }
    end
    -- Update maxErrors if it was set to old default
    if JarsErrorTrapDB.maxErrors == 100 then
        JarsErrorTrapDB.maxErrors = 1000
    end
end

-- Error storage
local errorLog = {}
local errorCount = 0
local MAX_ERRORS = 1000  -- Hard limit on total errors captured

-- Forward declarations
local iconFrame
local errorFrame

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
    local angle = JarsErrorTrapDB.minimapAngle or 45
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
        if errorCount >= MAX_ERRORS then
            GameTooltip:AddLine(errorCount .. " errors captured (LIMIT REACHED)", 1, 0, 0)
            GameTooltip:AddLine("No new errors will be captured", 1, 0.5, 0)
        else
            GameTooltip:AddLine(errorCount .. " errors captured", 1, 1, 1)
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
            -- Clear errors
            errorLog = {}
            errorCount = 0
            JarsErrorTrapDB.errors = {}
            icon.count:SetText("0")
            icon.count:SetTextColor(1, 1, 1)
            if errorFrame then
                errorFrame:Update()
            end
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
    local detailFrame = CreateFrame("Frame", "JET_ErrorDetailFrame", UIParent, "BasicFrameTemplateWithInset")
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
    
    detailFrame.title = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailFrame.title:SetPoint("TOP", 0, -5)
    detailFrame.title:SetText("Error Details")
    
    -- Scrollable edit box for error text
    local scrollFrame = CreateFrame("ScrollFrame", "JET_DetailScrollFrame", detailFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    
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
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, detailFrame, "GameMenuButtonTemplate")
    closeBtn:SetSize(80, 25)
    closeBtn:SetPoint("BOTTOM", 0, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() detailFrame:Hide() end)
    
    -- Function to show error
    detailFrame.ShowError = function(self, error)
        local errorText = string.format("Time: %s\n\nError Message:\n%s\n\nStack Trace:\n%s", 
            error.time, error.message, error.stack or "No stack trace available")
        self.editBox:SetText(errorText)
        self.editBox:SetCursorPosition(0)
        self:Show()
    end
    
    return detailFrame
end

-- Create error review window
local function CreateErrorFrame()
    local frame = CreateFrame("Frame", "JET_ErrorFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(650, 600)
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
    
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -5)
    
    -- Update title to show limit status
    frame.UpdateTitle = function(self)
        if errorCount >= MAX_ERRORS then
            self.title:SetText("Jar's Error Trap - " .. errorCount .. " Errors (LIMIT REACHED)")
            self.title:SetTextColor(1, 0.3, 0.3)
        else
            self.title:SetText("Jar's Error Trap - " .. errorCount .. " Errors")
            self.title:SetTextColor(1, 0.82, 0)
        end
    end
    frame:UpdateTitle()
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "JET_ScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    
    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(590, 1)
    scrollFrame:SetScrollChild(content)
    
    frame.content = content
    frame.scrollFrame = scrollFrame
    frame.expandedErrors = {}  -- Track which errors are expanded
    
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
            iconFrame.count:SetTextColor(1, 1, 1)
        end
        frame:Update()
    end)
    
    -- Reference to error detail frame
    frame.errorDetailFrame = nil
    
    -- Update function to rebuild error list
    frame._errorBoxPool = frame._errorBoxPool or {}
    frame.Update = function(self)
        -- Update title with current count
        self:UpdateTitle()

        -- Recycle existing error displays back to pool
        for _, child in ipairs({self.content:GetChildren()}) do
            child:Hide()
            table.insert(self._errorBoxPool, child)
        end
        
        local yOffset = -5
        for i = #errorLog, 1, -1 do  -- Reverse order, newest first
            local errEntry = errorLog[i]
            
            -- Check if this error is expanded
            local isExpanded = self.expandedErrors[i] or false
            
            -- Error container
            local errorBox = CreateFrame("Button", nil, self.content)
            errorBox:SetPoint("TOPLEFT", 5, yOffset)
            errorBox:SetSize(580, 30)  -- Start collapsed
            
            -- Background
            errorBox.bg = errorBox:CreateTexture(nil, "BACKGROUND")
            errorBox.bg:SetAllPoints()
            errorBox.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
            
            -- Expand/collapse button
            errorBox.expandBtn = CreateFrame("Button", nil, errorBox)
            errorBox.expandBtn:SetSize(20, 20)
            errorBox.expandBtn:SetPoint("TOPLEFT", 5, -5)
            
            if isExpanded then
                errorBox.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                errorBox.expandBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
                errorBox.expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-MinusButton-Hilight", "ADD")
            else
                errorBox.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                errorBox.expandBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
                errorBox.expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
            end
            
            -- Timestamp
            errorBox.time = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            errorBox.time:SetPoint("LEFT", errorBox.expandBtn, "RIGHT", 5, 0)
            errorBox.time:SetText(errEntry.time)
            errorBox.time:SetTextColor(0.7, 0.7, 0.7)
            
            -- Error count badge
            errorBox.countText = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            errorBox.countText:SetPoint("TOPRIGHT", -40, -5)
            errorBox.countText:SetText("#" .. i)
            errorBox.countText:SetTextColor(1, 0.5, 0.5)
            
            -- Open button for this error
            errorBox.openBtn = CreateFrame("Button", nil, errorBox, "UIPanelButtonTemplate")
            errorBox.openBtn:SetSize(35, 20)
            errorBox.openBtn:SetPoint("RIGHT", -5, 0)
            errorBox.openBtn:SetText("Open")
            errorBox.openBtn:SetScript("OnClick", function()
                if not self.errorDetailFrame then
                    self.errorDetailFrame = CreateErrorDetailFrame()
                end
                self.errorDetailFrame:ShowError(errEntry)
            end)
            
            -- Error message (always visible)
            errorBox.message = errorBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            errorBox.message:SetPoint("LEFT", errorBox.time, "RIGHT", 5, 0)
            errorBox.message:SetPoint("RIGHT", errorBox.countText, "LEFT", -5, 0)
            errorBox.message:SetJustifyH("LEFT")
            errorBox.message:SetText(errEntry.message)
            errorBox.message:SetTextColor(1, 0.3, 0.3)
            
            -- Stack trace container (initially hidden)
            errorBox.stackContainer = CreateFrame("Frame", nil, errorBox)
            errorBox.stackContainer:SetPoint("TOPLEFT", 30, -25)
            errorBox.stackContainer:SetPoint("RIGHT", -5, 0)
            
            if isExpanded then
                errorBox.stackContainer:Show()
                errorBox.message:SetMaxLines(0)
            else
                errorBox.stackContainer:Hide()
                errorBox.message:SetMaxLines(1)
            end
            
            if errEntry.stack then
                errorBox.stack = errorBox.stackContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                errorBox.stack:SetPoint("TOPLEFT")
                errorBox.stack:SetPoint("RIGHT")
                errorBox.stack:SetJustifyH("LEFT")
                errorBox.stack:SetText(errEntry.stack)
                errorBox.stack:SetTextColor(0.8, 0.8, 0.8)
                
                -- Calculate stack trace height
                local stackHeight = errorBox.stack:GetStringHeight()
                errorBox.stackContainer:SetHeight(stackHeight + 5)
            end
            
            -- Calculate errorBox height based on expansion state
            if isExpanded then
                local newHeight = 30 + (errorBox.stackContainer:GetHeight() or 0) + errorBox.message:GetStringHeight()
                errorBox:SetHeight(newHeight)
            else
                errorBox:SetHeight(30)
            end
            
            -- Toggle expand/collapse
            local errorIndex = i  -- Capture in closure
            errorBox.expandBtn:SetScript("OnClick", function()
                self.expandedErrors[errorIndex] = not self.expandedErrors[errorIndex]
                self:Update()
            end)
            
            yOffset = yOffset - errorBox:GetHeight() - 5
        end
        
        self.content:SetHeight(math.abs(yOffset) + 10)
    end
    
    return frame
end

-- Custom error handler
local function ErrorHandler(errMsg)
    -- Check if we've hit the error limit
    if errorCount >= MAX_ERRORS then
        -- Discard new errors once we hit the limit
        return errMsg
    end
    
    -- Capture the error
    local stack = debugstack(3)  -- Skip error handler frames
    local timestamp = date("%H:%M:%S")
    
    local errorEntry = {
        message = tostring(errMsg),
        stack = stack,
        time = timestamp,
    }

    table.insert(errorLog, errorEntry)
    errorCount = errorCount + 1

    -- Update saved variables (keep last 1000)
    table.insert(JarsErrorTrapDB.errors, errorEntry)
    if #JarsErrorTrapDB.errors > (JarsErrorTrapDB.maxErrors or MAX_ERRORS) then
        table.remove(JarsErrorTrapDB.errors, 1)
    end
    
    -- Update icon count
    if iconFrame then
        if errorCount >= MAX_ERRORS then
            iconFrame.count:SetText("MAX")
            iconFrame.count:SetTextColor(1, 0, 0)
        else
            iconFrame.count:SetText(tostring(errorCount))
            iconFrame.count:SetTextColor(1, 1, 1)
        end
    end
    
    -- Update error frame if visible
    if errorFrame and errorFrame:IsShown() then
        errorFrame:Update()
    end
    
    -- Flash the icon safely (avoid UIFrameFlash which may be deprecated)
    if iconFrame then
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
            iconFrame.count:SetTextColor(1, 1, 1)
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
