local _, ns = ...
local Tally = ns.core

-- Settings > AddOns > Tally.
--
-- Forever hangs when the Settings window is closed with the controller after
-- the gamepad cursor (SmartNavigation) has picked up addon-created controls,
-- and Blizzard's vertical-layout settings list triggers that on its own. So,
-- as in Rummage, this page is a canvas built once at login from plain
-- widgets, never announced to the cursor, and it opens no dropdown menus:
-- every choice is a click-to-cycle button.

ns.settings = {}
local controls = {}
local registered = false
local panel

local AMMO_MODES = {
    { value = "auto", label = "With a ranged weapon or quiver" },
    { value = "always", label = "Always" },
    { value = "never", label = "Never" },
}

local BAG_FORMATS = {
    { value = "free", label = "Free slots (23)" },
    { value = "freeTotal", label = "Free / total (23/80)" },
    { value = "usedTotal", label = "Used / total (57/80)" },
}

local REAGENT_BAGS = {
    { value = "combined", label = "With your bags" },
    { value = "separate", label = "Own counter per bag" },
}

local JUNK_PRICES = {
    { value = "auction", label = "Auction price when known" },
    { value = "vendor", label = "Vendor price" },
}

local WHITE_WORTH = {
    { value = 0, label = "Off" },
    { value = 100, label = "1 silver" },
    { value = 1000, label = "10 silver" },
    { value = 5000, label = "50 silver" },
    { value = 10000, label = "1 gold" },
    { value = 50000, label = "5 gold" },
}

local LAYOUTS = {
    { value = "row", label = "Side by side" },
    { value = "column", label = "Stacked" },
}

local function NumberOptions(values, zeroLabel)
    local options = {}
    for _, value in ipairs(values) do
        options[#options + 1] = { value = value, label = value == 0 and zeroLabel or tostring(value) }
    end
    return options
end

local BAG_WARNINGS = NumberOptions({ 0, 2, 4, 6, 8, 10, 15, 20 }, "Only when full")
local AMMO_WARNINGS = NumberOptions({ 0, 50, 100, 200, 400, 600, 1000 }, "Only when out")

local SCALES = {}
for _, value in ipairs({ 0.75, 0.85, 1.0, 1.15, 1.3, 1.5 }) do
    SCALES[#SCALES + 1] = { value = value, label = string.format("%d%%", math.floor(value * 100 + 0.5)) }
end

local function PanelVisible()
    return panel and panel:IsVisible()
end

local function AttachTooltip(control, title, text)
    control:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then
            GameTooltip:AddLine(text, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function OptionLabel(options, value)
    for _, option in ipairs(options) do
        if option.value == value then
            return option.label
        end
    end
    return tostring(value)
end

local function CreateCheckbox(parent, key, labelText, tooltip, y, indent)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 4 + (indent or 0), y)
    check:SetSize(26, 26)
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.label:SetText(labelText)
    check:SetScript("OnClick", function(self)
        Tally.Set(key, self:GetChecked() and true or false)
    end)
    if tooltip then
        AttachTooltip(check, labelText, tooltip)
    end
    check.Refresh = function()
        check:SetChecked(TallyDB[key] and true or false)
    end
    controls[#controls + 1] = check
    return y - 30
end

local function CreateCycleButton(parent, key, options, labelText, tooltip, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 12, y - 4)
    label:SetWidth(170)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(230, 22)
    button:SetPoint("TOPLEFT", 190, y)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouseButton)
        local step = mouseButton == "RightButton" and -1 or 1
        local index = 1
        for i, option in ipairs(options) do
            if option.value == TallyDB[key] then
                index = i
                break
            end
        end
        index = ((index - 1 + step) % #options) + 1
        Tally.Set(key, options[index].value)
    end)
    AttachTooltip(button, labelText, (tooltip and tooltip .. "\n\n" or "") .. "Left-click for the next choice, right-click for the previous one.")
    button.Refresh = function()
        button:SetText(OptionLabel(options, TallyDB[key]))
    end
    controls[#controls + 1] = button
    return y - 28
end

local function CreateHeader(parent, text, y)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetPoint("TOPLEFT", 6, y)
    divider:SetSize(540, 1)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 6, y - 10)
    header:SetText(text)
    return y - 32
end

function ns.settings.Refresh()
    if not PanelVisible() then
        return
    end
    for _, control in ipairs(controls) do
        control.Refresh()
    end
    if controls.status then
        local bags = Tally.bags
        local ammo = Tally.ammo
        local ammoText = ammo.itemID and string.format("%d x %s", ammo.count, Tally.GetItemName(ammo.itemID)) or "none equipped"
        controls.status:SetText(string.format("Now: %d of %d bag slots free, ammo %s.", bags.free, bags.total, ammoText))
    end
end

function ns.settings.Register()
    if registered or not Settings or type(Settings.RegisterCanvasLayoutCategory) ~= "function" then
        return
    end
    registered = true

    -- Hidden until the Settings window displays it, so OnShow always fires.
    panel = CreateFrame("Frame")
    panel.name = "Tally"
    panel:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(560, 1)
    scrollFrame:SetScrollChild(content)

    local y = -6
    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 6, y)
    title:SetText("Tally")
    y = y - 26

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 6, y)
    note:SetWidth(540)
    note:SetJustifyH("LEFT")
    note:SetText("Free bag slots and ammo in the bottom-right corner, for the gamepad HUD that shows neither. Hover a counter for the details per bag and per ammo type; click the bag counter to delete your cheapest grey item. With a controller, use the mouse on this page: the gamepad cursor cannot enter it without freezing Forever when Settings is closed.")
    y = y - (note:GetStringHeight() + 12)

    local status = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", 6, y)
    status:SetWidth(540)
    status:SetJustifyH("LEFT")
    controls.status = status
    y = y - 26

    y = CreateHeader(content, "Counters", y)
    y = CreateCheckbox(content, "showBags", "Show free bag slots", "Counts slots in bags that hold anything. Quivers, ammo pouches, soul bags and profession bags are listed in the tooltip but not counted.", y)
    y = CreateCycleButton(content, "bagFormat", BAG_FORMATS, "Bag slots as:", nil, y)
    y = CreateCycleButton(content, "reagentBags", REAGENT_BAGS, "Reagent bags:", "With your bags counts a reagent bag's free slots in the bag counter. Own counter per bag leaves them out of it and gives each reagent bag a counter of its own, with the bag's icon.", y)
    y = CreateCycleButton(content, "bagWarning", BAG_WARNINGS, "Yellow at free slots:", "The count turns yellow at this many free slots or fewer, and red when your bags are full.", y)
    y = CreateCheckbox(content, "clickToDelete", "Click the bag counter to delete greys", "The bag tooltip names your grey item with the lowest vendor value. Click once and the tooltip asks to delete it; click again to delete it. Moving away cancels.", y)
    y = CreateCheckbox(content, "deleteWhites", "Include white items", "White items can be offered too when they are worth the least. Ammo, quest items, keys (grey or white) and anything a vendor will not buy (such as your Hearthstone) are never offered.", y)
    y = CreateCheckbox(content, "keepTradeGoods", "Keep trade goods", "Never offer white cloth, herbs, ore, leather and other crafting materials.", y, 24)
    y = CreateCheckbox(content, "keepConsumables", "Keep consumables", "Never offer white food, drink, potions and bandages.", y, 24)
    y = CreateCheckbox(content, "keepReagents", "Keep reagents", "Never offer white reagents, such as class reagents for spells.", y, 24)
    y = CreateCheckbox(content, "keepRecipes", "Keep recipes", "Never offer white recipes.", y, 24)
    y = CreateCycleButton(content, "keepWhitesWorth", WHITE_WORTH, "Keep whites worth:", "Never offer a white stack worth this much or more, counting the auction price when it is known. Greys are not affected.", y)

    local forget = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    forget:SetPoint("TOPLEFT", 190, y - 2)
    forget:SetSize(230, 22)
    forget:SetScript("OnClick", Tally.ClearKept)
    AttachTooltip(forget, "Always kept items", "Right-click the bag counter to always keep the item it offers. /tally keep lists them; this button forgets them all.")
    forget.Refresh = function()
        local count = Tally.GetKeptCount()
        forget:SetText(string.format("Forget %d kept %s", count, count == 1 and "item" or "items"))
        forget:SetEnabled(count > 0)
    end
    controls[#controls + 1] = forget
    y = y - 32
    y = CreateCycleButton(content, "junkPrice", JUNK_PRICES, "Value greys by:", "With Auctionator, TradeSkillMaster or Auctioneer installed, a grey is worth the higher of its vendor and auction price, so a grey that sells well on the auction house is not the one offered for deletion. Without one of them, vendor price is used.", y)
    y = CreateCycleButton(content, "showAmmo", AMMO_MODES, "Show ammo:", "By default the ammo counter appears when you have a bow, gun or crossbow, a quiver or ammo pouch, or ammo equipped.", y)
    y = CreateCycleButton(content, "ammoWarning", AMMO_WARNINGS, "Yellow at ammo:", "The count turns yellow at this much ammo or less, and red when you are out.", y)
    y = y - 6

    y = CreateHeader(content, "Placement", y)
    y = CreateCheckbox(content, "gamepadOnly", "Only show in gamepad mode", "Hides the counters in mouse-and-keyboard mode, where the bag bar and action buttons already show these numbers. They stay visible while unlocked or in Edit Mode.", y)
    y = CreateCheckbox(content, "unlocked", "Unlock counters outside Edit Mode", "Drag the counters to move them. Edit Mode unlocks them too while it is open.", y)
    y = CreateCycleButton(content, "layout", LAYOUTS, "Layout:", "Side by side grows to the left from the corner; stacked grows upward.", y)
    y = CreateCycleButton(content, "scale", SCALES, "Size:", nil, y)

    local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reset:SetPoint("TOPLEFT", 190, y - 4)
    reset:SetSize(230, 22)
    reset:SetText("Back to bottom-right corner")
    reset:SetScript("OnClick", function()
        ns.display.ResetPosition()
    end)
    AttachTooltip(reset, "Reset position", "Moves the counters back to their default place in the bottom-right corner.")
    y = y - 40

    y = CreateHeader(content, "Troubleshooting", y)
    y = CreateCheckbox(content, "debug", "Debug output in chat", nil, y)

    content:SetHeight(-y + 10)

    -- Deliberately not announced to the gamepad cursor (SmartNavigation):
    -- the controls exist from login and are only reparented into the
    -- Settings window, so the cursor never picks them up on its own.
    panel:SetScript("OnShow", ns.settings.Refresh)

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ns.settings.category = category
end

function ns.settings.Open()
    if not registered then
        ns.settings.Register()
    end
    if ns.settings.category and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(ns.settings.category:GetID())
    end
end
