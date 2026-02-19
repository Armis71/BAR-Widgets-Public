function widget:GetInfo()
    return {
        name      = "Energy Conversion",
        desc      = "Standalone Energy→Metal conversion control + stats. Edited to know if spectator mode or live play",
        author    = "Kerwin + Copilot",
        date      = "2026",
        license   = "GPLv2",
        layer     = 0,
        enabled   = true
    }
end

local compactMode = false

local FIXED_WIDGET_WIDTH  = 250
local FIXED_WIDGET_HEIGHT = 116

local tooltipFontSize = 14
local fontSize = 14
local buttonFontSize = 16
local padding = 8
local lineSpacing = 18

local mmLevel = 0.10
local pulse = 0

local glColor = gl.Color
local glRect  = gl.Rect
local glText  = gl.Text
local glGetTextWidth = gl.GetTextWidth

local convEnergy = 0
local convMetal  = 0
local convUtil   = 0
local convActive = 0
local convTotal  = 0

local energyConvKeepPercent = 0.10

-- function widget:Update(dt)
    -- -- UPDATE STATS FIRST
    -- UpdateConverterStats()

    -- -- SEND CONVERSION LEVEL
    -- if mmLevel then
        -- local convValue = math.floor((1 - mmLevel) * 100 + 0.5)
        -- Spring.SendLuaRulesMsg(string.format("%c%i", 137, convValue))
    -- end

    -- -- THROB LOGIC (only when producing metal)
    -- if (convMetal or 0) > 0 then
        -- pulse = (pulse + dt * 2.5) % 1
    -- else
        -- pulse = 0
    -- end
-- end


-- Spring.Echo("convMetal=", convMetal)
-- Spring.Echo("WG.convMetal=", WG.convMetal)

	local function IsReplayOrSpectating()
		local isReplay = Spring.IsReplay()
		local isSpec, fullView = Spring.GetSpectatingState()
		-- Show text if replay OR spectating (but not when you're an active player)
		return isReplay or (isSpec and not isReplay)
	end
	   

function widget:Update(dt)
-- rem Spring.Echo("convMetal=", convMetal, "pulse=", pulse)


    -- SEND CONVERSION LEVEL
    if mmLevel then
        local convValue = math.floor((1 - mmLevel) * 100 + 0.5)
        Spring.SendLuaRulesMsg(string.format("%c%i", 137, convValue))
    end

    -- THROB ONLY WHEN CONVERTERS ARE ACTIVE
	if (convMetal or 0) > 0 then
     -- pulse = (pulse + dt * 2.5) % 1   adjust the pulse
		pulse = (pulse + dt * 1.2) % 1
    else
        pulse = 0
    end
end

local bgColor = {0, 0, 0, 0.35}

local keepOptions = {
    {label = "10%", value = 0.10},
    {label = "20%", value = 0.20},
    {label = "30%", value = 0.30},
    {label = "40%", value = 0.40},
    {label = "50%", value = 0.50},
    {label = "60%", value = 0.60},
    {label = "70%", value = 0.70},
    {label = "80%", value = 0.80},
    {label = "90%", value = 0.90},
}

local posX, posY = 600, 300
local dragging = false
local dragOffsetX, dragOffsetY = 0, 0

local dropdownOpen = false
local dropdownRects = {}
local buttonRect = nil
local statsRect = nil

local convEnergy = 0
-- local convMetal = 0
local convUtil = 0

function widget:Initialize()
    -- Load saved position
    posX = Spring.GetConfigInt("econ_conv_posX", 1) or posX
    posY = Spring.GetConfigInt("econ_conv_posY", 1) or posY

    -- Determine game mode
    local isReplay = Spring.IsReplay()
    local isSpec, fullView = Spring.GetSpectatingState()

    if isReplay or isSpec then
        -- Spectator or Replay → ALWAYS compact mode
        compactMode = true
    else
        -- Live game → ALWAYS start in full mode
        compactMode = false
    end
end



local function DrawRect(x1, y1, x2, y2, color)
    glColor(color)
    glRect(x1, y1, x2, y2)
end

local function InRect(mx, my, r)
    return mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2
end

function UpdateConverterStats()

-- Spring.Echo("UpdateConverterStats CALLED")


    local teamID = Spring.GetMyTeamID()
    local mmUse      = Spring.GetTeamRulesParam(teamID, "mmUse") or 0
    local mmCapacity = Spring.GetTeamRulesParam(teamID, "mmCapacity") or 0
    local mmAvgEffi  = Spring.GetTeamRulesParam(teamID, "mmAvgEffi") or 0

    convEnergy = mmUse
    convMetal = mmUse * mmAvgEffi
	WG.convMetal = convMetal

    if mmCapacity > 0 then
        convUtil = math.floor((mmUse / mmCapacity) * 100 + 0.5)
    else
        convUtil = 0
    end
end   -- ⭐ THIS WAS MISSING

function widget:DrawScreen()
    UpdateConverterStats()

    local mx, my = Spring.GetMouseState()

    local x1 = posX
    local y1 = posY
    local x2 = posX + FIXED_WIDGET_WIDTH
    local y2 = posY + FIXED_WIDGET_HEIGHT

    --------------------------------------------------------
    -- COMPACT MODE
    --------------------------------------------------------
    if compactMode then
        --------------------------------------------------------
        -- BACKGROUND + BORDER
        --------------------------------------------------------
        glColor(0, 0, 0, 0.80)
        glRect(x1, y1, x2, y2)

        glColor(1,1,1,0.75)
        glRect(x1, y1, x2, y1+1)
        glRect(x1, y2-1, x2, y2)
        glRect(x1, y1, x1+1, y2)
        glRect(x2-1, y1, x2, y2)

        --------------------------------------------------------
        -- TITLE
        --------------------------------------------------------
        local cx = x1 + FIXED_WIDGET_WIDTH * 0.5
        local y  = y2 - padding - fontSize - 2.5

        glColor(1,1,1,1)
        glText("Energy to Metal Conversion", cx, y, fontSize + 2, "oc")

        y = y - (lineSpacing * 1.5)
        glText("Stats:", cx, y, fontSize + 1, "oc")

        y = y - 25

        --------------------------------------------------------
        -- FIXED-WIDTH STATS (same as full mode)
        --------------------------------------------------------
        local eText = string.format("-%de", math.floor(convEnergy + 0.5))
        local mText = string.format("+%dm", math.floor(convMetal + 0.5))
        local uText = string.format("%d%%", convUtil)

        local eW_fixed = glGetTextWidth("-999999e") * fontSize
        local mW_fixed = glGetTextWidth("+99999m") * fontSize
        local uW_fixed = glGetTextWidth("100%") * fontSize
        local bracketW = glGetTextWidth("[") * fontSize * 1.2

        local totalW = bracketW + eW_fixed + mW_fixed + uW_fixed + bracketW
        local startX = cx - totalW * 0.5

        glColor(1,1,1,1)
        glText("[", startX + bracketW * 0.5, y, fontSize, "oc")

        glColor(1,1,0.2,1)
        glText(eText, startX + bracketW + eW_fixed * 0.5, y, fontSize, "oc")

        glColor(0.2,1,1,1)
        glText(mText, startX + bracketW + eW_fixed + mW_fixed * 0.5, y, fontSize, "oc")

        glColor(1,1,1,1)
        glText(uText, startX + bracketW + eW_fixed + mW_fixed + uW_fixed * 0.5, y, fontSize, "oc")

        glColor(1,1,1,1)
        glText("]", startX + bracketW + eW_fixed + mW_fixed + uW_fixed + bracketW * 0.5, y, fontSize, "oc")

        --------------------------------------------------------
        -- COMPACT BUTTON (same size, no %)
        --------------------------------------------------------
        y = y - lineSpacing

        local labelText = "E-Conv"
        local labelWidth = glGetTextWidth(labelText) * buttonFontSize
        local bw = labelWidth + 14
        local bh = buttonFontSize + 6

        local bx1 = cx - bw * 0.5
        local by1 = y1 + 10
        local bx2 = bx1 + bw
        local by2 = by1 + bh

        -- pulsing background
        local r = 0
        local g = pulse
        local b = pulse
        local a = 0.55 + pulse * 0.1

        glColor(r, g, b, a)
        glRect(bx1, by1, bx2, by2)

        glColor(1,1,1,1)
        glText(labelText, (bx1+bx2)*0.5, (by1+by2)*0.5 - 5, buttonFontSize, "oc")

        buttonRect = {x1=bx1, y1=by1, x2=bx2, y2=by2}

        return
    end

    --------------------------------------------------------
    -- FULL MODE (original code)
    --------------------------------------------------------

    --------------------------------------------------------
    -- BACKGROUND + BORDER
    --------------------------------------------------------
    glColor(0, 0, 0, 0.80)
    glRect(x1, y1, x2, y2)

    glColor(1,1,1,0.75)
    glRect(x1, y1, x2, y1+1)
    glRect(x1, y2-1, x2, y2)
    glRect(x1, y1, x1+1, y2)
    glRect(x2-1, y1, x2, y2)

    --------------------------------------------------------
    -- TEXT BLOCK
    --------------------------------------------------------
    local cx = x1 + FIXED_WIDGET_WIDTH * 0.5
    local y  = y2 - padding - fontSize - 2.5

    glColor(1,1,1,1)
    glText("Energy to Metal Conversion", cx, y, fontSize + 2, "oc")

    y = y - (lineSpacing * 1.5)
    glText("Stats:", cx, y, fontSize + 1, "oc")

    y = y - 25

    --------------------------------------------------------
    -- FIXED-WIDTH STATS
    --------------------------------------------------------
    local eText = string.format("-%de", math.floor(convEnergy + 0.5))
    local mText = string.format("+%dm", math.floor(convMetal + 0.5))
    local uText = string.format("%d%%", convUtil)

    local eW_fixed = glGetTextWidth("-999999e") * fontSize
    local mW_fixed = glGetTextWidth("+99999m") * fontSize
    local uW_fixed = glGetTextWidth("100%") * fontSize
    local bracketW = glGetTextWidth("[") * fontSize * 1.2

    local totalW = bracketW + eW_fixed + mW_fixed + uW_fixed + bracketW
    local startX = cx - totalW * 0.5

    glColor(1,1,1,1)
    glText("[", startX + bracketW * 0.5, y, fontSize, "oc")

    glColor(1,1,0.2,1)
    glText(eText, startX + bracketW + eW_fixed * 0.5, y, fontSize, "oc")

    glColor(0.2,1,1,1)
    glText(mText, startX + bracketW + eW_fixed + mW_fixed * 0.5, y, fontSize, "oc")

    glColor(1,1,1,1)
    glText(uText, startX + bracketW + eW_fixed + mW_fixed + uW_fixed * 0.5, y, fontSize, "oc")

    glColor(1,1,1,1)
    glText("]", startX + bracketW + eW_fixed + mW_fixed + uW_fixed + bracketW * 0.5, y, fontSize, "oc")

    statsRect = {
        x1 = x1,
        y1 = y - fontSize,
        x2 = x2,
        y2 = y + fontSize
    }

    --------------------------------------------------------
    -- BUTTON (full mode)
    --------------------------------------------------------
    y = y - lineSpacing

    local labelText = string.format("E-Conv [%d%%]", math.floor(energyConvKeepPercent * 100 + 0.5))
    local labelWidth = glGetTextWidth(labelText) * buttonFontSize
    local bw = labelWidth + 14
    local bh = buttonFontSize + 6

    local bx1 = cx - bw * 0.5
    local by1 = y1 + 10
    local bx2 = bx1 + bw
    local by2 = by1 + bh

    -- pulsing background
    local r = 0
    local g = pulse
    local b = pulse
    local a = 0.55 + pulse * 0.1

    glColor(r, g, b, a)
    glRect(bx1, by1, bx2, by2)

    glColor(1,1,1,1)
    glText(labelText, (bx1+bx2)*0.5, (by1+by2)*0.5 - 5, buttonFontSize, "oc")

    buttonRect = {x1=bx1, y1=by1, x2=bx2, y2=by2}

    --------------------------------------------------------
    -- DROPDOWN (full mode only)
    --------------------------------------------------------
    if dropdownOpen then
        dropdownRects = {}

        local optionHeight = bh
        local gap = 2
        local totalDropdownHeight = (#keepOptions * (optionHeight + gap))

        local vsx, vsy = Spring.GetViewGeometry()

        local lowestY = by1 - totalDropdownHeight
        local flipUp = (lowestY < 0)

        local dy
        if flipUp then
            dy = by2 + 4
        else
            dy = by1 - 4
        end

        for i, opt in ipairs(keepOptions) do
            local ow = 80
            local ox1 = cx - ow * 0.5
            local ox2 = ox1 + ow

            local oy1, oy2
            if flipUp then
                oy1 = dy + ((i - 1) * (optionHeight + gap))
                oy2 = oy1 + optionHeight
            else
                oy2 = dy - ((i - 1) * (optionHeight + gap))
                oy1 = oy2 - optionHeight
            end

            local hovered = InRect(mx, my, {x1 = ox1, y1 = oy1, x2 = ox2, y2 = oy2})

            if hovered then
                DrawRect(ox1, oy1, ox2, oy2, {0, 0, 0, 0.45})
            else
                DrawRect(ox1, oy1, ox2, oy2, {0, 0, 0, 0.35})
            end

            glColor(1, 1, 1, 1)
            glText(opt.label, (ox1 + ox2) * 0.5, (oy1 + oy2) * 0.5 - 5, fontSize, "oc")

            dropdownRects[i] = {
                x1 = ox1, y1 = oy1,
                x2 = ox2, y2 = oy2,
                value = opt.value
            }
        end
    end

    --------------------------------------------------------
    -- TOOLTIP (full mode only)
    --------------------------------------------------------
    if buttonRect then
        if InRect(mx, my, buttonRect) and not dropdownOpen then

            local tip  = "Set amount of available energy"
            local tip1 = "to convert to metal"
            local pad  = 6

            local tw = math.max(
                glGetTextWidth(tip),
                glGetTextWidth(tip1)
            ) * tooltipFontSize + pad * 2

            local th = tooltipFontSize * 2 + pad * 3

            local tipX = mx + 18
            local tipY = my - th - 18

            glColor(1, 1, 1, 0.92)
            glRect(tipX, tipY, tipX + tw, tipY + th)

            glColor(0, 0, 0, 0.25)
            glRect(tipX,         tipY,         tipX + tw, tipY + 1)
            glRect(tipX,         tipY + th - 1, tipX + tw, tipY + th)
            glRect(tipX,         tipY,         tipX + 1,  tipY + th)
            glRect(tipX + tw - 1, tipY,         tipX + tw, tipY + th)

            glColor(0, 0, 0, 1)
            glText(tip,  tipX + tw * 0.5, tipY + th - pad - tooltipFontSize, tooltipFontSize, "oc")
            glText(tip1, tipX + tw * 0.5, tipY + pad,                        tooltipFontSize, "oc")
        end
    end
end


function widget:MousePress(mx,my,button)
    if button ~= 1 then return false end

    local x1 = posX
    local y1 = posY
    local x2 = posX + FIXED_WIDGET_WIDTH
    local y2 = posY + FIXED_WIDGET_HEIGHT

    local insideWidget = (mx>=x1 and mx<=x2 and my>=y1 and my<=y2)
    local overButton = buttonRect and InRect(mx,my,buttonRect)

    -- Ctrl + Left Click toggles compact mode
    if button == 1 then
        local alt, ctrl, meta, shift = Spring.GetModKeyState()
if ctrl and insideWidget then
    -- Only live players can toggle modes
    if not IsReplayOrSpectating() then
        compactMode = not compactMode
        Spring.SetConfigInt("econ_conv_compact", compactMode and 1 or 0)
    end
    return true
end

    end

    local overDropdown = false
    if dropdownOpen then
        for _,r in ipairs(dropdownRects) do
            if InRect(mx,my,r) then overDropdown=true break end
        end
    end

    if insideWidget and not overDropdown then
        if not overButton then
            dragging = true
            dragOffsetX = mx - posX
            dragOffsetY = my - posY
            return true
        end
    end

if overButton then
    if not compactMode and not IsReplayOrSpectating() then
        dropdownOpen = not dropdownOpen
    end
    return true
end


    if dropdownOpen then
        for _,r in ipairs(dropdownRects) do
            if InRect(mx,my,r) then
                energyConvKeepPercent = r.value
                mmLevel = r.value
                dropdownOpen = false
                return true
            end
        end
        dropdownOpen = false
        return true
    end

    return false
end


function widget:MouseMove(mx,my,dx,dy,button)
    if dragging then
        posX = mx - dragOffsetX
        posY = my - dragOffsetY
        return true
    end
end

function widget:MouseRelease(mx,my,button)
    if dragging then
        dragging = false
        Spring.SetConfigInt("econ_conv_posX", posX)
        Spring.SetConfigInt("econ_conv_posY", posY)
        return true
    end
end

			