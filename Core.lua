local ADDON_NAME, ns = ...

-- Tally counts what Forever's gamepad HUD leaves out: free bag slots and the
-- ammo you have left. The core owns the counting, saved variables, events
-- and the slash command; Display.lua draws the readouts and Settings.lua the
-- options page.

Tally = Tally or {}
local Tally = Tally
ns.core = Tally

local UPDATE_DELAY = 0.1
local updateScheduled = false

-- Latest counts, filled by Recount. Display.lua and the tooltips read these.
Tally.bags = { free = 0, total = 0, list = {} }
Tally.ammo = { shown = false, count = 0, list = {} }

local function Print(fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print("|cff7fd8ffTally|r: " .. msg)
end
Tally.Print = Print

local function Debug(fmt, ...)
    if TallyDB and TallyDB.debug then
        Print("[debug] " .. fmt, ...)
    end
end
Tally.Debug = Debug

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local DEFAULTS = {
    debug = false,
    showBags = true,
    showAmmo = "auto",        -- "auto" | "always" | "never"
    bagFormat = "free",       -- "free" | "freeTotal" | "usedTotal"
    bagWarning = 4,           -- free slots at or below this turn yellow
    ammoWarning = 200,        -- ammo at or below this turns yellow
    layout = "row",           -- "row" | "column"
    scale = 1.0,
    gamepadOnly = true,
    unlocked = false,
    position = nil,           -- { point, relativePoint, x, y }; nil = default corner
}

local function InitSavedVariables()
    TallyDB = TallyDB or {}
    for key, value in pairs(DEFAULTS) do
        if TallyDB[key] == nil then
            TallyDB[key] = value
        end
    end
end

function Tally.GetDefault(key)
    return DEFAULTS[key]
end

-- Changes one option and redraws everything that shows it.
function Tally.Set(key, value)
    TallyDB[key] = value
    Tally.RequestUpdate()
    if ns.display and ns.display.ApplyAppearance then
        ns.display.ApplyAppearance()
    end
    if ns.settings and ns.settings.Refresh then
        ns.settings.Refresh()
    end
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

local ITEM_CLASS_WEAPON = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
local ITEM_CLASS_PROJECTILE = Enum and Enum.ItemClass and Enum.ItemClass.Projectile or 6
local ITEM_CLASS_QUIVER = Enum and Enum.ItemClass and Enum.ItemClass.Quiver or 11
local INVSLOT_AMMO = INVSLOT_AMMO or 0
local INVSLOT_RANGED = INVSLOT_RANGED or 18

-- Ranged weapons that fire ammo. Thrown weapons and wands do not.
local AMMO_WEAPONS = {
    [2] = true,   -- bows
    [3] = true,   -- guns
    [18] = true,  -- crossbows
}

local function GetItemClass(itemID)
    local getter = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getter or not itemID then
        return nil
    end
    local _, _, _, _, _, classID, subclassID = getter(itemID)
    return classID, subclassID
end

local function GetItemName(itemID)
    local getter = (C_Item and C_Item.GetItemNameByID) or (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = getter and getter(itemID)
    return name or ("item:" .. tostring(itemID))
end
Tally.GetItemName = GetItemName

local function GetItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    if GetItemIcon then
        return GetItemIcon(itemID)
    end
    return nil
end
Tally.GetItemIcon = GetItemIcon

--------------------------------------------------------------------------------
-- Bags
--------------------------------------------------------------------------------

local function LastBagIndex()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

local function GetNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

-- Returns free slots and the bag family (0 = holds anything; quivers, ammo
-- pouches, soul bags and profession bags have their own family bits).
local function GetFreeSlots(bag)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        return free or 0, family or 0
    end
    if GetContainerNumFreeSlots then
        local free, family = GetContainerNumFreeSlots(bag)
        return free or 0, family or 0
    end
    return 0, 0
end

local function GetBagItemID(bag)
    if bag == 0 then
        return nil
    end
    local inventoryID
    if C_Container and C_Container.ContainerIDToInventoryID then
        inventoryID = C_Container.ContainerIDToInventoryID(bag)
    elseif ContainerIDToInventoryID then
        inventoryID = ContainerIDToInventoryID(bag)
    end
    return inventoryID and GetInventoryItemID("player", inventoryID)
end

local function GetBagSlotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.itemID, info.stackCount or 1
        end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
        return itemID, count or 1
    end
    return nil
end

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

local function HasAmmoWeapon()
    local itemID = GetInventoryItemID("player", INVSLOT_RANGED)
    if not itemID then
        return false
    end
    local classID, subclassID = GetItemClass(itemID)
    return classID == ITEM_CLASS_WEAPON and AMMO_WEAPONS[subclassID] == true
end

local function Recount()
    local bags = { free = 0, total = 0, list = {} }
    local ammo = { count = 0, list = {}, bagFree = 0, bagTotal = 0, hasAmmoBag = false }
    local ammoByItem = {}

    for bag = 0, LastBagIndex() do
        local slots = GetNumSlots(bag)
        if slots > 0 then
            local free, family = GetFreeSlots(bag)
            local itemID = GetBagItemID(bag)
            local classID = GetItemClass(itemID)
            local isAmmoBag = classID == ITEM_CLASS_QUIVER
            local entry = {
                bag = bag,
                itemID = itemID,
                name = bag == 0 and (BACKPACK_TOOLTIP or "Backpack") or (itemID and GetItemName(itemID)) or ("Bag " .. bag),
                icon = itemID and GetItemIcon(itemID) or "Interface\\Icons\\INV_Misc_Bag_08",
                free = free,
                total = slots,
                special = family ~= 0,
                ammoBag = isAmmoBag,
            }
            bags.list[#bags.list + 1] = entry

            -- Only bags that hold anything count: a free quiver slot cannot
            -- take the loot that just filled your bags.
            if family == 0 then
                bags.free = bags.free + free
                bags.total = bags.total + slots
            end
            if isAmmoBag then
                ammo.hasAmmoBag = true
                ammo.bagFree = ammo.bagFree + free
                ammo.bagTotal = ammo.bagTotal + slots
            end

            for slot = 1, slots do
                local slotItemID, count = GetBagSlotItem(bag, slot)
                if slotItemID and GetItemClass(slotItemID) == ITEM_CLASS_PROJECTILE then
                    ammoByItem[slotItemID] = (ammoByItem[slotItemID] or 0) + count
                end
            end
        end
    end

    -- The equipped ammo is what the weapon fires; the count is every stack of
    -- that ammo in your bags. Other ammo in the bags goes in the tooltip.
    ammo.itemID = GetInventoryItemID("player", INVSLOT_AMMO)
    if ammo.itemID then
        ammo.count = ammoByItem[ammo.itemID] or GetInventoryItemCount("player", INVSLOT_AMMO) or 0
        ammo.icon = GetInventoryItemTexture("player", INVSLOT_AMMO) or GetItemIcon(ammo.itemID)
    end
    for itemID, count in pairs(ammoByItem) do
        ammo.list[#ammo.list + 1] = { itemID = itemID, count = count, equipped = itemID == ammo.itemID }
    end
    table.sort(ammo.list, function(a, b)
        if a.equipped ~= b.equipped then
            return a.equipped
        end
        return a.count > b.count
    end)

    ammo.hasWeapon = HasAmmoWeapon()
    local mode = TallyDB and TallyDB.showAmmo or "auto"
    if mode == "always" then
        ammo.shown = true
    elseif mode == "never" then
        ammo.shown = false
    else
        ammo.shown = ammo.hasAmmoBag or ammo.hasWeapon or ammo.itemID ~= nil
    end

    Tally.bags = bags
    Tally.ammo = ammo
    Debug("bags %d/%d free, ammo %d (shown: %s)", bags.free, bags.total, ammo.count, tostring(ammo.shown))
end

local function RunUpdate()
    updateScheduled = false
    Recount()
    if ns.display and ns.display.Refresh then
        ns.display.Refresh()
    end
    if ns.settings and ns.settings.Refresh then
        ns.settings.Refresh()
    end
end

-- Several bag events arrive per loot or shot; they are merged into one count.
function Tally.RequestUpdate()
    if updateScheduled then
        return
    end
    updateScheduled = true
    C_Timer.After(UPDATE_DELAY, RunUpdate)
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

local function PrintStatus()
    local bags = Tally.bags
    Print("bags: %d of %d slots free", bags.free, bags.total)
    for _, entry in ipairs(bags.list) do
        local note = entry.ammoBag and " (ammo)" or entry.special and " (special, not counted)" or ""
        print(string.format("  %s: %d/%d free%s", entry.name, entry.free, entry.total, note))
    end
    local ammo = Tally.ammo
    if ammo.itemID then
        Print("ammo: %d x %s", ammo.count, GetItemName(ammo.itemID))
    else
        Print("ammo: none equipped")
    end
    for _, entry in ipairs(ammo.list) do
        if not entry.equipped then
            print(string.format("  also in bags: %d x %s", entry.count, GetItemName(entry.itemID)))
        end
    end
end

local function PrintHelp()
    Print("commands:")
    print("  /tally  - open Settings > AddOns > Tally")
    print("  /tally status  - print bag slots and ammo in chat")
    print("  /tally unlock  - move the counters outside Edit Mode")
    print("  /tally lock  - lock the counters")
    print("  /tally reset  - put the counters back in the bottom-right corner")
    print("  /tally debug  - toggle debug output")
end

local function HandleSlash(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local command = (input:match("^(%S+)") or ""):lower()

    if command == "" or command == "config" or command == "options" or command == "settings" then
        if ns.settings and ns.settings.Open then
            ns.settings.Open()
        end
    elseif command == "status" then
        Recount()
        PrintStatus()
    elseif command == "unlock" then
        Tally.Set("unlocked", true)
        Print("unlocked. Drag the counters, then /tally lock.")
    elseif command == "lock" then
        Tally.Set("unlocked", false)
        Print("locked. Edit Mode still unlocks them while it is open.")
    elseif command == "reset" then
        Tally.Set("position", nil)
        Print("counters moved back to the bottom-right corner.")
    elseif command == "debug" then
        TallyDB.debug = not TallyDB.debug
        Print("debug output %s", TallyDB.debug and "on" or "off")
    else
        PrintHelp()
    end
end

SLASH_TALLY1 = "/tally"
SlashCmdList.TALLY = HandleSlash

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
-- Switching between gamepad and mouse-and-keyboard shows or hides the
-- counters. Not every client has these events.
pcall(frame.RegisterEvent, frame, "INPUT_DEVICE_INTERFACE_TRANSITION")
pcall(frame.RegisterEvent, frame, "GAME_PAD_ACTIVE_CHANGED")
pcall(frame.RegisterEvent, frame, "GAME_PAD_CONFIGS_CHANGED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitSavedVariables()
        end
    elseif event == "PLAYER_LOGIN" then
        if ns.display and ns.display.Create then
            ns.display.Create()
        end
        if ns.settings and ns.settings.Register then
            ns.settings.Register()
        end
        Tally.RequestUpdate()
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" or event == "GAME_PAD_ACTIVE_CHANGED"
        or event == "GAME_PAD_CONFIGS_CHANGED" then
        if ns.display and ns.display.UpdateVisibility then
            ns.display.UpdateVisibility()
        end
    else
        Tally.RequestUpdate()
    end
end)
