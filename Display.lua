local ADDON_NAME, ns = ...
local Tally = ns.core

-- The counters in the bottom-right corner: one round slot per readout in the
-- style of Forever's crossbar, with the number beside it. Nothing here is
-- secure, so it can be shown, hidden and moved in combat.

ns.display = {}

local MEDIA_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local ICON_SIZE = 34
local SHADOW_DISTANCE = 4
local TEXT_GAP = 6
local READOUT_GAP = 16
local FONT_SIZE = 17
local DEFAULT_POSITION = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -36, y = 30 }

local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local AMMO_ICON = "Interface\\Icons\\INV_Ammo_Arrow_02"

local COLOR_NORMAL = { 1, 1, 1 }
local COLOR_WARNING = { 1, 0.82, 0 }
local COLOR_EMPTY = { 1, 0.28, 0.28 }

-- Native crossbar art (Blizzard_GamepadActionBars), with the addon's own
-- textures as fallback on builds without these atlases.
local ATLAS = {
    border = "gamepad-actionbar-circleslot-border-normal",
    shadow = "gamepad-actionbar-circleslot-dropshadow",
    circleMask = "CircleMask",
    editGlow = "gamepad-actionbar-fx-controls-behind",
}

local container
local readouts = {}
local editModeActive = false

local function AtlasExists(name)
    if not name or not C_Texture or type(C_Texture.GetAtlasInfo) ~= "function" then
        return false
    end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

local function ApplyArt(texture, atlas, fallbackFile)
    if AtlasExists(atlas) then
        texture:SetAtlas(atlas)
        return true
    end
    texture:SetTexture(fallbackFile)
    return fallbackFile ~= nil
end

local function FormatNumber(value)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end
    return tostring(value)
end

local function IsGamepadInterfaceActive()
    if C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function" then
        local ok, style = pcall(C_InputInterfaceStyle.GetCurrentStyle)
        if ok and style ~= nil then
            local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad or 1
            return style == gamepad
        end
    end
    if type(IsGamePadEnabled) == "function" then
        local ok, enabled = pcall(IsGamePadEnabled)
        return ok and enabled == true
    end
    return true
end

local function IsEditable()
    return (TallyDB and TallyDB.unlocked == true) or editModeActive
end

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------

local function IconText(icon, text)
    if icon then
        return "|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t " .. text
    end
    return text
end

local function ShowBagTooltip(owner)
    local bags = Tally.bags
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("Bags", 1, 1, 1)
    GameTooltip:AddLine(string.format("%d of %d slots free", bags.free, bags.total), nil, nil, nil, true)
    GameTooltip:AddLine(" ")
    for _, entry in ipairs(bags.list) do
        local slots = string.format("%d/%d", entry.free, entry.total)
        if entry.special then
            local note = entry.ammoBag and "ammo" or "special"
            GameTooltip:AddDoubleLine(IconText(entry.icon, entry.name), slots .. " |cff9d9d9d(" .. note .. ")|r", 0.62, 0.62, 0.62, 0.62, 0.62, 0.62)
        else
            GameTooltip:AddDoubleLine(IconText(entry.icon, entry.name), slots, 1, 1, 1, 1, 1, 1)
        end
    end
    local hasSpecial = false
    for _, entry in ipairs(bags.list) do
        hasSpecial = hasSpecial or entry.special
    end
    if hasSpecial then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Quivers, ammo pouches and other special bags are not counted: they cannot take loot.", 0.62, 0.62, 0.62, true)
    end
    GameTooltip:Show()
end

local function ShowAmmoTooltip(owner)
    local ammo = Tally.ammo
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    if ammo.itemID then
        GameTooltip:SetText(IconText(ammo.icon, Tally.GetItemName(ammo.itemID)), 1, 1, 1)
        GameTooltip:AddLine(string.format("%s left in your bags", FormatNumber(ammo.count)), nil, nil, nil, true)
    else
        GameTooltip:SetText("Ammo", 1, 1, 1)
        GameTooltip:AddLine("No ammo equipped. Right-click arrows or bullets in your bags to use them.", 1, 0.28, 0.28, true)
    end
    if ammo.hasAmmoBag then
        GameTooltip:AddLine(string.format("Quiver: %d of %d slots free", ammo.bagFree, ammo.bagTotal), 1, 1, 1)
    end
    local others = false
    for _, entry in ipairs(ammo.list) do
        if not entry.equipped then
            if not others then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Also in your bags:", 0.62, 0.62, 0.62)
                others = true
            end
            GameTooltip:AddDoubleLine(IconText(Tally.GetItemIcon(entry.itemID), Tally.GetItemName(entry.itemID)), FormatNumber(entry.count), 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Readouts
--------------------------------------------------------------------------------

-- Hover-only on purpose. Opening the bags from an addon click taints the
-- gamepad controls that come with them, and Forever then loops forever on the
-- ADDON_ACTION_FORBIDDEN popup for SetPreferredGamepadInteractTarget.
local function CreateReadout(key, onEnter)
    local readout = CreateFrame("Frame", "TallyReadout" .. key, container)
    readout:SetHeight(ICON_SIZE)
    readout:EnableMouse(true)

    local slot = CreateFrame("Frame", nil, readout)
    slot:SetSize(ICON_SIZE, ICON_SIZE)
    slot:SetPoint("RIGHT")
    readout.slot = slot

    slot.shadow = slot:CreateTexture(nil, "BACKGROUND", nil, -1)
    slot.shadow:SetPoint("TOPLEFT", -SHADOW_DISTANCE, SHADOW_DISTANCE)
    slot.shadow:SetPoint("BOTTOMRIGHT", SHADOW_DISTANCE, -SHADOW_DISTANCE)
    if not ApplyArt(slot.shadow, ATLAS.shadow, nil) then
        slot.shadow:Hide()
    end

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 3, -3)
    slot.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    if slot.CreateMaskTexture and slot.icon.AddMaskTexture then
        slot.mask = slot:CreateMaskTexture()
        slot.mask:SetAllPoints(slot.icon)
        if AtlasExists(ATLAS.circleMask) then
            slot.mask:SetAtlas(ATLAS.circleMask)
        else
            slot.mask:SetTexture(MEDIA_PATH .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        slot.icon:AddMaskTexture(slot.mask)
    else
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end

    slot.border = slot:CreateTexture(nil, "ARTWORK", nil, 1)
    slot.border:SetAllPoints()
    ApplyArt(slot.border, ATLAS.border, MEDIA_PATH .. "SlotRing")

    readout.text = readout:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    local font = readout.text:GetFont()
    if font then
        readout.text:SetFont(font, FONT_SIZE, "OUTLINE")
    end
    readout.text:SetShadowOffset(1, -1)
    readout.text:SetShadowColor(0, 0, 0, 0.8)
    readout.text:SetPoint("RIGHT", slot, "LEFT", -TEXT_GAP, 0)
    readout.text:SetJustifyH("RIGHT")

    readout:SetScript("OnEnter", onEnter)
    readout:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    readouts[key] = readout
    return readout
end

local function SetReadout(readout, icon, text, color)
    readout.slot.icon:SetTexture(icon)
    readout.text:SetText(text)
    readout.text:SetTextColor(color[1], color[2], color[3])
    readout:SetWidth(math.ceil(readout.text:GetStringWidth()) + TEXT_GAP + ICON_SIZE)
end

local function CountColor(value, warning)
    if value <= 0 then
        return COLOR_EMPTY
    elseif value <= (warning or 0) then
        return COLOR_WARNING
    end
    return COLOR_NORMAL
end

local function BagText(bags)
    local format = TallyDB.bagFormat
    if format == "freeTotal" then
        return string.format("%d/%d", bags.free, bags.total)
    elseif format == "usedTotal" then
        return string.format("%d/%d", bags.total - bags.free, bags.total)
    end
    return tostring(bags.free)
end

-- Stacks the visible readouts from the anchor corner: right to left in a
-- row, bottom to top in a column. The container is sized to fit them so the
-- edit overlay and dragging cover exactly what is on screen.
local function Layout()
    local order = { readouts.bags, readouts.ammo }
    local visible = {}
    for _, readout in ipairs(order) do
        if readout:IsShown() then
            visible[#visible + 1] = readout
        end
    end

    local column = TallyDB.layout == "column"
    local width, height = 0, 0
    local previous
    for _, readout in ipairs(visible) do
        readout:ClearAllPoints()
        if not previous then
            readout:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        elseif column then
            readout:SetPoint("BOTTOMRIGHT", previous, "TOPRIGHT", 0, READOUT_GAP / 2)
        else
            readout:SetPoint("BOTTOMRIGHT", previous, "BOTTOMLEFT", -READOUT_GAP, 0)
        end
        if column then
            width = math.max(width, readout:GetWidth())
            height = height + readout:GetHeight() + (previous and READOUT_GAP / 2 or 0)
        else
            width = width + readout:GetWidth() + (previous and READOUT_GAP or 0)
            height = math.max(height, readout:GetHeight())
        end
        previous = readout
    end
    container:SetSize(math.max(width, ICON_SIZE), math.max(height, ICON_SIZE))
end

function ns.display.Refresh()
    if not container then
        return
    end
    local bags = Tally.bags
    local ammo = Tally.ammo

    readouts.bags:SetShown(TallyDB.showBags)
    SetReadout(readouts.bags, BAG_ICON, BagText(bags), CountColor(bags.free, TallyDB.bagWarning))

    readouts.ammo:SetShown(ammo.shown)
    SetReadout(readouts.ammo, ammo.icon or AMMO_ICON, FormatNumber(ammo.count), CountColor(ammo.count, TallyDB.ammoWarning))

    Layout()
end

--------------------------------------------------------------------------------
-- Position and visibility
--------------------------------------------------------------------------------

local function ApplyPosition()
    local pos = TallyDB.position or DEFAULT_POSITION
    container:ClearAllPoints()
    container:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
end

local function SavePosition()
    -- Always saved from the bottom-right corner, so the counters grow
    -- leftward and upward from where they were dropped, like the default.
    -- Offsets are in the container's own (scaled) units.
    local ratio = UIParent:GetEffectiveScale() / container:GetEffectiveScale()
    TallyDB.position = {
        point = "BOTTOMRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = container:GetRight() - UIParent:GetRight() * ratio,
        y = container:GetBottom() - UIParent:GetBottom() * ratio,
    }
    ApplyPosition()
end

function ns.display.UpdateVisibility()
    if not container then
        return
    end
    local editable = IsEditable()
    container.editOverlay:SetShown(editable)
    container:SetShown(not TallyDB.gamepadOnly or IsGamepadInterfaceActive() or editable)
end

function ns.display.ApplyAppearance()
    if not container then
        return
    end
    container:SetScale(TallyDB.scale or 1)
    ApplyPosition()
    ns.display.UpdateVisibility()
    ns.display.Refresh()
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------

local function CreateEditOverlay()
    local overlay = CreateFrame("Button", nil, container)
    overlay:SetPoint("TOPLEFT", -6, 6)
    overlay:SetPoint("BOTTOMRIGHT", 6, -6)
    overlay:SetFrameLevel(container:GetFrameLevel() + 20)
    overlay:RegisterForDrag("LeftButton", "RightButton")
    overlay:Hide()

    overlay.fill = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.fill:SetAllPoints()
    overlay.fill:SetColorTexture(0.95, 0.72, 0.16, 0.10)

    local function CreateEdge(point1, point2, isHorizontal)
        local edge = overlay:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(point1, 0, 0)
        edge:SetPoint(point2, 0, 0)
        if isHorizontal then
            edge:SetHeight(2)
        else
            edge:SetWidth(2)
        end
        edge:SetColorTexture(1.0, 0.82, 0.28, 0.95)
        return edge
    end
    CreateEdge("TOPLEFT", "TOPRIGHT", true)
    CreateEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    CreateEdge("TOPLEFT", "BOTTOMLEFT", false)
    CreateEdge("TOPRIGHT", "BOTTOMRIGHT", false)

    overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.text:SetPoint("BOTTOM", overlay, "TOP", 0, 4)
    overlay.text:SetText("TALLY - DRAG TO MOVE")

    overlay:SetScript("OnDragStart", function()
        if IsEditable() then
            container:StartMoving()
        end
    end)
    overlay:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SavePosition()
    end)
    return overlay
end

local function RegisterEditModeIntegration()
    if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        editModeActive = true
        ns.display.UpdateVisibility()
    end, ns.display)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        editModeActive = false
        ns.display.UpdateVisibility()
    end, ns.display)

    -- Reloading the UI while Edit Mode is open does not send EditMode.Enter.
    if EditModeManagerFrame and type(EditModeManagerFrame.IsEditModeActive) == "function" then
        local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
        editModeActive = ok and active or false
    end
end

function ns.display.Create()
    if container then
        return
    end
    container = CreateFrame("Frame", "TallyFrame", UIParent)
    container:SetFrameStrata("LOW")
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:SetSize(ICON_SIZE, ICON_SIZE)

    CreateReadout("bags", ShowBagTooltip)
    CreateReadout("ammo", ShowAmmoTooltip)
    container.editOverlay = CreateEditOverlay()

    RegisterEditModeIntegration()
    ns.display.ApplyAppearance()
end

function ns.display.ResetPosition()
    Tally.Set("position", nil)
end
