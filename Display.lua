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
local DISENCHANT_ICON = "Interface\\Icons\\INV_Enchant_Disenchant"

local COLOR_NORMAL = { 1, 1, 1 }
local COLOR_WARNING = { 1, 0.82, 0 }
local COLOR_EMPTY = { 1, 0.28, 0.28 }
local COLOR_DIM = { 0.62, 0.62, 0.62 }

-- Native crossbar art (Blizzard_GamepadActionBars), with the addon's own
-- textures as fallback on builds without these atlases.
local ATLAS = {
    border = "gamepad-actionbar-circleslot-border-normal",
    shadow = "gamepad-actionbar-circleslot-dropshadow",
    circleMask = "CircleMask",
    editGlow = "gamepad-actionbar-fx-controls-behind",
}

local container
local readouts = { reagents = {} }
local editModeActive = false
local pendingDelete    -- the grey stack the first bag click offered to delete
local disenchantButton  -- secure, laid over the disenchant counter out of combat

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

local function FormatMoney(copper)
    if GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    return copper .. "c"
end

local function JunkValue(junk)
    local text = FormatMoney(junk.value)
    if junk.source ~= "vendor" then
        text = text .. " |cff9d9d9d(" .. junk.source .. ")|r"
    end
    return text
end

local function JunkText(junk)
    local text = IconText(Tally.GetItemIcon(junk.itemID), junk.link)
    if junk.count > 1 then
        text = text .. " x" .. junk.count
    end
    return text
end

local function AddJunkLines()
    if not TallyDB.clickToDelete then
        return
    end
    GameTooltip:AddLine(" ")
    if pendingDelete then
        GameTooltip:AddLine("Delete this item?", 1, 0.28, 0.28)
        GameTooltip:AddDoubleLine(JunkText(pendingDelete), JunkValue(pendingDelete), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine("Click again to delete it, right-click to always keep it, or move away to cancel.", 1, 0.28, 0.28, true)
        return
    end
    local junk = Tally.FindCheapestJunk()
    if junk then
        GameTooltip:AddLine(TallyDB.deleteWhites and "Cheapest grey or white item:" or "Cheapest grey item:", 0.62, 0.62, 0.62)
        GameTooltip:AddDoubleLine(JunkText(junk), JunkValue(junk), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine("Click to delete it, right-click to always keep it.", 0.62, 0.62, 0.62, true)
    else
        GameTooltip:AddLine(TallyDB.deleteWhites and "No grey or white items to delete." or "No grey items to delete.", 0.62, 0.62, 0.62)
    end
    local kept = Tally.GetKeptCount()
    if kept > 0 then
        GameTooltip:AddLine(string.format("%d %s always kept (/tally keep).", kept, kept == 1 and "item" or "items"), 0.62, 0.62, 0.62)
    end
end

local function ShowBagTooltip(owner)
    local bags = Tally.bags
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("Bags", 1, 1, 1)
    GameTooltip:AddLine(string.format("%d of %d slots free", bags.free, bags.total), nil, nil, nil, true)
    GameTooltip:AddLine(" ")
    for _, entry in ipairs(bags.list) do
        local slots = string.format("%d/%d", entry.free, entry.total)
        if entry.separate then
            GameTooltip:AddDoubleLine(IconText(entry.icon, entry.name), slots .. " |cff9d9d9d(own counter)|r", 0.62, 0.62, 0.62, 0.62, 0.62, 0.62)
        elseif entry.special then
            local note = entry.ammoBag and "ammo" or entry.reagentBag and "reagents" or "special"
            GameTooltip:AddDoubleLine(IconText(entry.icon, entry.name), slots .. " |cff9d9d9d(" .. note .. ")|r", 0.62, 0.62, 0.62, 0.62, 0.62, 0.62)
        elseif entry.reagentBag then
            GameTooltip:AddDoubleLine(IconText(entry.icon, entry.name), slots .. " |cff9d9d9d(reagents)|r", 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine(IconText(entry.icon, entry.name), slots, 1, 1, 1, 1, 1, 1)
        end
    end
    local hasSpecial = false
    for _, entry in ipairs(bags.list) do
        hasSpecial = hasSpecial or (entry.special and not entry.separate)
    end
    if hasSpecial then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Quivers, ammo pouches and other special bags are not counted: they cannot take loot.", 0.62, 0.62, 0.62, true)
    end
    AddJunkLines()
    GameTooltip:Show()
end

local function DisenchantResult(target)
    if not target.material then
        return "Result unknown for this item level.", 0.62, 0.62, 0.62
    end
    local material = IconText(Tally.GetItemIcon(target.material), Tally.GetItemName(target.material))
    if target.freesSlot then
        return "Frees a slot: likely " .. material .. ", and every possible result stacks with yours.", 0.25, 1, 0.25
    end
    return "Likely " .. material .. ". Not every possible result stacks with yours, so it may need a slot.", 0.62, 0.62, 0.62
end

local function AddDisenchantTarget(target)
    local value = target.value > 0 and FormatMoney(target.value) or ""
    GameTooltip:AddDoubleLine(IconText(Tally.GetItemIcon(target.itemID), target.link), value, 1, 1, 1, 1, 1, 1)
    local text, r, g, b = DisenchantResult(target)
    GameTooltip:AddLine(text, r, g, b, true)
end

local function ShowDisenchantTooltip(owner)
    local disenchant = Tally.disenchant
    local count = disenchant.count
    local boeCount = disenchant.boeCount or 0
    local items = count == 1 and "item" or "items"
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(IconText(Tally.GetDisenchantIcon() or DISENCHANT_ICON, "Disenchant"), 1, 1, 1)
    if count + boeCount == 0 then
        GameTooltip:AddLine(disenchant.tight and "Nothing to disenchant that frees a bag slot." or "Nothing to disenchant.", 0.62, 0.62, 0.62, true)
    elseif disenchant.tight then
        GameTooltip:AddLine(string.format("%d soulbound %s that free a bag slot", count, items), nil, nil, nil, true)
    else
        GameTooltip:AddLine(string.format("%d soulbound %s you can disenchant", count, items), nil, nil, nil, true)
    end
    if disenchant.safeCount > 0 and disenchant.safeCount < count then
        GameTooltip:AddLine(string.format("%d of them you can never wear", disenchant.safeCount), nil, nil, nil, true)
    end
    if boeCount > 0 then
        GameTooltip:AddLine(string.format("%d bind-on-equip %s", boeCount, boeCount == 1 and "green" or "greens"), nil, nil, nil, true)
    end
    GameTooltip:AddLine(" ")
    if InCombatLockdown() then
        GameTooltip:AddLine("Disenchanting waits until you leave combat.", 0.62, 0.62, 0.62, true)
    elseif count + boeCount > 0 then
        if disenchant.safeTarget then
            GameTooltip:AddLine("Click: gear you can never wear", 0.62, 0.62, 0.62)
            AddDisenchantTarget(disenchant.safeTarget)
        end
        if disenchant.unsafeTarget then
            if disenchant.safeTarget then
                GameTooltip:AddLine(" ")
            end
            GameTooltip:AddLine("Shift-click: gear you could wear", 1, 0.82, 0)
            AddDisenchantTarget(disenchant.unsafeTarget)
        elseif disenchant.boeTarget then
            if disenchant.safeTarget then
                GameTooltip:AddLine(" ")
            end
            GameTooltip:AddLine("Shift-click: bind-on-equip green", 1, 0.82, 0)
            AddDisenchantTarget(disenchant.boeTarget)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click (or shift-right-click) to always keep the item instead.", 0.62, 0.62, 0.62, true)
    end
    if disenchant.tight then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Your bags are nearly full, so only items whose materials stack with yours are offered.", 0.62, 0.62, 0.62, true)
    end
    if disenchant.upgrades and #disenchant.upgrades > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Never offered, better than what you wear:", 0.62, 0.62, 0.62)
        for _, upgrade in ipairs(disenchant.upgrades) do
            GameTooltip:AddDoubleLine(IconText(Tally.GetItemIcon(upgrade.itemID), upgrade.link), upgrade.reason, 1, 1, 1, 0.62, 0.62, 0.62)
        end
    end
    local kept = Tally.GetKeptCount()
    if kept > 0 then
        GameTooltip:AddLine(string.format("%d %s always kept (/tally keep).", kept, kept == 1 and "item" or "items"), 0.62, 0.62, 0.62)
    end
    GameTooltip:Show()
end

local function ShowReagentTooltip(owner)
    local entry = owner.entry
    if not entry then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(IconText(entry.icon, entry.name), 1, 1, 1)
    GameTooltip:AddLine(string.format("%d of %d slots free", entry.free, entry.total), nil, nil, nil, true)
    GameTooltip:AddLine(" ")
    if entry.professionBag then
        GameTooltip:AddLine("Profession bag: holds only its own kind of item (herbs, enchanting materials, soul shards and so on), so it can have room when your bags are full. It has its own counter and is not counted with your bags.", 0.62, 0.62, 0.62, true)
    else
        GameTooltip:AddLine("Reagent bag: holds only crafting reagents, so it has its own counter and is not counted with your bags.", 0.62, 0.62, 0.62, true)
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

-- The bag click asks in the tooltip (first click) and deletes on the second.
-- Clicks must never open a Blizzard frame, so no bags and no StaticPopup:
-- opening the bags from an addon click taints the gamepad controls that come
-- with them, and Forever then loops forever on the ADDON_ACTION_FORBIDDEN
-- popup for SetPreferredGamepadInteractTarget.
local function OnBagClick(readout, mouseButton)
    if not TallyDB.clickToDelete or IsEditable() then
        return
    end
    if mouseButton == "RightButton" then
        local target = pendingDelete or Tally.FindCheapestJunk()
        pendingDelete = nil
        if target then
            Tally.SetKept(target.itemID, true)
            Tally.Print("always keeping %s. /tally keep lists kept items.", target.link)
        end
    elseif mouseButton ~= "LeftButton" then
        return
    elseif pendingDelete then
        local target = pendingDelete
        pendingDelete = nil
        Tally.DeleteJunk(target)
    else
        pendingDelete = Tally.FindCheapestJunk()
    end
    ShowBagTooltip(readout)
end

-- Casting needs a secure button, so the disenchant counter gets one laid
-- over it. A plain click disenchants soulbound gear you can never wear,
-- which is safe to do at once. Gear you could wear, and then bind-on-equip
-- greens, take a shift-click, so they are never disenchanted by accident. PreClick checks the item again and
-- sets "/cast Disenchant" and "/use bag slot" for the secure handler to
-- run; PostClick clears it.
local function OnDisenchantPreClick(self, mouseButton)
    if InCombatLockdown() then
        return
    end
    self:SetAttribute("type", nil)
    self:SetAttribute("macrotext", nil)
    if IsEditable() then
        return
    end
    local disenchant = Tally.disenchant
    local shift = IsShiftKeyDown()
    local target
    if shift then
        target = disenchant.unsafeTarget or disenchant.safeTarget or disenchant.boeTarget
    else
        target = disenchant.safeTarget
    end
    if mouseButton == "RightButton" then
        if target then
            Tally.SetKept(target.itemID, true)
            Tally.Print("always keeping %s. /tally keep lists kept items.", target.link)
        end
    elseif mouseButton == "LeftButton" then
        if not target then
            if disenchant.unsafeTarget then
                Tally.Print("everything left is gear you could wear: shift-click to disenchant %s.", disenchant.unsafeTarget.link)
            elseif disenchant.boeTarget then
                Tally.Print("everything left is bind on equip: shift-click to disenchant %s.", disenchant.boeTarget.link)
            else
                Tally.Print("nothing to disenchant.")
            end
            return
        end
        local macro = Tally.PrepareDisenchant(target, not shift)
        if macro then
            self:SetAttribute("type", "macro")
            self:SetAttribute("macrotext", macro)
        end
    end
end

local function OnDisenchantPostClick(self)
    if not InCombatLockdown() then
        self:SetAttribute("type", nil)
        self:SetAttribute("macrotext", nil)
    end
    ShowDisenchantTooltip(self)
end

local function CreateDisenchantButton()
    local button = CreateFrame("Button", "TallyDisenchantButton", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    button:Hide()
    -- Put away as combat starts. This runs in the secure environment, which
    -- may hide and unanchor the button even once the lockdown has begun, so
    -- it does not depend on PLAYER_REGEN_DISABLED arriving first.
    button:SetAttribute("_onstate-tallycombat", [[
        if newstate == "1" then
            self:SetAttribute("type", nil)
            self:Hide()
            self:ClearAllPoints()
        end
    ]])
    RegisterStateDriver(button, "tallycombat", "[combat] 1; 0")
    button:SetFrameStrata(container:GetFrameStrata())
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Act on the release like the other counters, whatever the key-down CVar.
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", OnDisenchantPreClick)
    button:SetScript("PostClick", OnDisenchantPostClick)
    button:SetScript("OnEnter", ShowDisenchantTooltip)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return button
end

-- Lays the secure button over the counter while it is visible, out of
-- combat and outside Edit Mode. As combat starts the state driver hides and
-- unanchors it, so the counters stay free to move and resize in combat;
-- PLAYER_REGEN_DISABLED does the same here when it still comes before the
-- lockdown. It is only created out of combat, since a protected frame
-- cannot be set up during it.
function ns.display.UpdateDisenchantButton(enteringCombat)
    if not container or InCombatLockdown() then
        return
    end
    disenchantButton = disenchantButton or CreateDisenchantButton()
    local readout = readouts.disenchant
    disenchantButton:SetAttribute("type", nil)
    disenchantButton:SetAttribute("macrotext", nil)
    if enteringCombat or IsEditable() or not readout:IsVisible() then
        disenchantButton:Hide()
        disenchantButton:ClearAllPoints()
        if GameTooltip:IsOwned(disenchantButton) then
            GameTooltip:Hide()
        end
        return
    end
    disenchantButton:ClearAllPoints()
    disenchantButton:SetAllPoints(readout)
    disenchantButton:SetFrameLevel(container:GetFrameLevel() + 10)
    disenchantButton:Show()
end

local function CreateReadout(key, onEnter, onClick)
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
        pendingDelete = nil
        GameTooltip:Hide()
    end)
    if onClick then
        readout:SetScript("OnMouseUp", onClick)
    end

    readouts[key] = readout
    return readout
end

-- Reagent and profession bag counters are made as bags are equipped, one
-- per such bag, and hidden when there are fewer such bags than counters.
local function GetReagentReadout(index)
    local readout = readouts.reagents[index]
    if not readout then
        readout = CreateReadout("Reagents" .. index, ShowReagentTooltip)
        readouts.reagents[index] = readout
    end
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
    local order = { readouts.bags }
    for _, readout in ipairs(readouts.reagents) do
        order[#order + 1] = readout
    end
    order[#order + 1] = readouts.disenchant
    order[#order + 1] = readouts.ammo
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

    for index = 1, math.max(#bags.reagents, #readouts.reagents) do
        local entry = bags.reagents[index]
        local readout = GetReagentReadout(index)
        readout.entry = entry
        -- Reagent-slot bags go with the bag counter; profession bags have
        -- their own setting.
        readout:SetShown(entry ~= nil and (entry.professionBag or TallyDB.showBags))
        if entry then
            SetReadout(readout, entry.icon, BagText(entry), CountColor(entry.free, TallyDB.bagWarning))
        end
    end

    local disenchant = Tally.disenchant
    -- Shown even with nothing to offer, so it does not jump around the
    -- corner as loot comes in.
    local disenchantCount = disenchant.count + (disenchant.boeCount or 0)
    readouts.disenchant:SetShown(TallyDB.showDisenchant and disenchant.known)
    SetReadout(readouts.disenchant, Tally.GetDisenchantIcon() or DISENCHANT_ICON, tostring(disenchantCount),
        disenchantCount > 0 and COLOR_NORMAL or COLOR_DIM)

    readouts.ammo:SetShown(ammo.shown)
    SetReadout(readouts.ammo, ammo.icon or AMMO_ICON, FormatNumber(ammo.count), CountColor(ammo.count, TallyDB.ammoWarning))

    Layout()
    ns.display.UpdateDisenchantButton()

    -- Keep an open bag tooltip current, e.g. after a delete.
    if GameTooltip:IsShown() and GameTooltip:IsOwned(readouts.bags) then
        ShowBagTooltip(readouts.bags)
    end
    for _, readout in ipairs(readouts.reagents) do
        if readout.entry and GameTooltip:IsShown() and GameTooltip:IsOwned(readout) then
            ShowReagentTooltip(readout)
        end
    end
    if GameTooltip:IsShown() then
        if disenchantButton and disenchantButton:IsShown() and GameTooltip:IsOwned(disenchantButton) then
            ShowDisenchantTooltip(disenchantButton)
        elseif GameTooltip:IsOwned(readouts.disenchant) then
            ShowDisenchantTooltip(readouts.disenchant)
        end
    end
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
    ns.display.UpdateDisenchantButton()
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

    CreateReadout("bags", ShowBagTooltip, OnBagClick)
    -- Hover-only itself: out of combat the secure button covers it.
    CreateReadout("disenchant", ShowDisenchantTooltip)
    CreateReadout("ammo", ShowAmmoTooltip)
    container.editOverlay = CreateEditOverlay()

    RegisterEditModeIntegration()
    ns.display.ApplyAppearance()
end

function ns.display.ResetPosition()
    Tally.Set("position", nil)
end
