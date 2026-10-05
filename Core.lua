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
Tally.bags = { free = 0, total = 0, list = {}, reagents = {} }
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
    clickToDelete = true,     -- click the bag counter twice to delete the cheapest grey
    deleteWhites = false,     -- white items can be the cheapest item too
    keepTradeGoods = true,    -- with whites on: never offer cloth, herbs, ore, leather...
    keepConsumables = true,   -- ...food, drink, potions, bandages
    keepReagents = true,      -- ...reagents
    keepRecipes = true,       -- ...recipes
    keepWhitesWorth = 0,      -- with whites on: never offer white stacks worth this much (copper; 0 = off)
    junkPrice = "auction",    -- "vendor" | "auction" (higher of vendor and auction addon price)
    reagentBags = "combined", -- "combined" | "separate" (each reagent bag gets its own counter)
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
    TallyDB.keep = TallyDB.keep or {}   -- [itemID] = true: never offered
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
local ITEM_CLASS_QUEST = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
local ITEM_CLASS_KEY = Enum and Enum.ItemClass and Enum.ItemClass.Key or 13
local ITEM_CLASS_CONSUMABLE = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
local ITEM_CLASS_REAGENT = Enum and Enum.ItemClass and Enum.ItemClass.Reagent or 5
local ITEM_CLASS_TRADEGOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local ITEM_CLASS_RECIPE = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
local ITEM_CLASS_MISC = Enum and Enum.ItemClass and Enum.ItemClass.Miscellaneous or 15
local ITEM_SUBCLASS_MISC_REAGENT = Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Reagent or 1
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

-- Bag slots past the regular four (Enum.BagIndex.ReagentBag) only take
-- reagents.
local function IsReagentBag(bag)
    return bag > (NUM_BAG_SLOTS or 4)
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

-- Returns itemID, stack count, quality, locked and link.
local function GetBagSlotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.itemID, info.stackCount or 1, info.quality, info.isLocked, info.hyperlink
        end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, locked, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        return itemID, count or 1, quality, locked, link
    end
    return nil
end

local function PickupBagSlot(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    elseif PickupContainerItem then
        PickupContainerItem(bag, slot)
    end
end

--------------------------------------------------------------------------------
-- Junk
--------------------------------------------------------------------------------

local ITEM_QUALITY_POOR = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0
local ITEM_QUALITY_COMMON = Enum and Enum.ItemQuality and Enum.ItemQuality.Common or 1

-- Items that are never offered, even when they are the cheapest: the ammo
-- you shoot, quest items and keys.
local NEVER_OFFERED_CLASSES = {
    [ITEM_CLASS_PROJECTILE] = true,
    [ITEM_CLASS_QUEST] = true,
    [ITEM_CLASS_KEY] = true,
}

-- White items you would rather sell or use, each kept by its own option.
-- Class reagents are filed as Reagent or as Miscellaneous > Reagent.
local function KeptWhiteCategory(classID, subclassID)
    if classID == ITEM_CLASS_TRADEGOODS then
        return TallyDB.keepTradeGoods
    elseif classID == ITEM_CLASS_CONSUMABLE then
        return TallyDB.keepConsumables
    elseif classID == ITEM_CLASS_REAGENT
        or (classID == ITEM_CLASS_MISC and subclassID == ITEM_SUBCLASS_MISC_REAGENT) then
        return TallyDB.keepReagents
    elseif classID == ITEM_CLASS_RECIPE then
        return TallyDB.keepRecipes
    end
    return false
end

local function GetSellPrice(itemID)
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getter then
        return nil
    end
    return (select(11, getter(itemID)))
end

-- Auction price addons, tried in order. None is required: each entry checks
-- for its addon's public API and every call is guarded, so a missing addon
-- or a changed API just falls through to the next one, then to vendor price.
local AUCTION_SOURCES = {
    {
        name = "Auctionator",
        api = function()
            return Auctionator and Auctionator.API and Auctionator.API.v1
        end,
        price = function(api, itemID)
            return api.GetAuctionPriceByItemID(ADDON_NAME, itemID)
        end,
    },
    {
        name = "TradeSkillMaster",
        api = function()
            return TSM_API
        end,
        price = function(api, itemID)
            return api.GetCustomPriceValue("DBMarket", "i:" .. itemID)
        end,
    },
    {
        name = "Auctioneer",
        api = function()
            return AucAdvanced and AucAdvanced.API
        end,
        price = function(api, _, link)
            return link and (api.GetMarketValue(link))
        end,
    },
}

local function GetAuctionPrice(itemID, link)
    for _, source in ipairs(AUCTION_SOURCES) do
        local api = source.api()
        if api then
            local ok, price = pcall(source.price, api, itemID, link)
            if ok and type(price) == "number" and price > 0 then
                return price, source.name
            end
        end
    end
    return nil
end

-- What one item is worth and where that figure came from. With auction
-- prices on, the higher of vendor and auction price counts: either way the
-- item could be turned into that much money.
local function GetJunkPrice(itemID, link)
    local vendor = GetSellPrice(itemID)
    if TallyDB and TallyDB.junkPrice == "auction" then
        local auction, source = GetAuctionPrice(itemID, link)
        if auction and auction > (vendor or 0) then
            return auction, source
        end
    end
    return vendor, "vendor"
end

-- Quest starters and quest drops can be grey (Noboru's Cudgel) and are not
-- always filed under the Quest item class.
local function IsQuestItem(bag, slot)
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local info = C_Container.GetContainerItemQuestInfo(bag, slot)
        return info ~= nil and (info.isQuestItem or info.questID ~= nil)
    end
    if GetContainerItemQuestInfo then
        local isQuestItem, questID = GetContainerItemQuestInfo(bag, slot)
        return isQuestItem or questID ~= nil
    end
    return false
end

-- Whether an item may be offered at all, before its price is looked at.
-- Kept items never are, nor ammo, quest items, keys or anything a vendor
-- will not buy (the Hearthstone, special greys). Of the rest, greys always
-- are; whites only with the option on and outside the kept categories.
local function IsJunkCandidate(itemID, quality, bag, slot)
    if TallyDB.keep[itemID] then
        return false
    end
    local isWhite = quality == ITEM_QUALITY_COMMON and TallyDB.deleteWhites
    if quality ~= ITEM_QUALITY_POOR and not isWhite then
        return false
    end
    local classID, subclassID = GetItemClass(itemID)
    if NEVER_OFFERED_CLASSES[classID] or (isWhite and KeptWhiteCategory(classID, subclassID)) then
        return false
    end
    if IsQuestItem(bag, slot) then
        return false
    end
    local vendor = GetSellPrice(itemID)
    return vendor ~= nil and vendor > 0
end

-- White stacks worth the threshold or more are worth selling instead.
local function IsTooValuable(quality, value)
    local threshold = TallyDB.keepWhitesWorth or 0
    return quality == ITEM_QUALITY_COMMON and threshold > 0 and value >= threshold
end

-- The grey (or white) stack worth the least, or nil. Stacks with no known
-- price yet are skipped rather than guessed at.
function Tally.FindCheapestJunk()
    if not TallyDB then
        return nil
    end
    local cheapest
    for bag = 0, LastBagIndex() do
        for slot = 1, GetNumSlots(bag) do
            local itemID, count, quality, locked, link = GetBagSlotItem(bag, slot)
            if itemID and not locked and IsJunkCandidate(itemID, quality, bag, slot) then
                local price, source = GetJunkPrice(itemID, link)
                if price and not IsTooValuable(quality, price * count)
                    and (not cheapest or price * count < cheapest.value) then
                    cheapest = {
                        bag = bag,
                        slot = slot,
                        itemID = itemID,
                        count = count,
                        quality = quality,
                        link = link or GetItemName(itemID),
                        value = price * count,
                        source = source,
                    }
                end
            end
        end
    end
    return cheapest
end

-- Deletes the stack FindCheapestJunk returned, but only if that exact stack
-- is still in that slot and the cursor was empty. Never opens a Blizzard
-- frame: picking up and deleting happen in the same click.
function Tally.DeleteJunk(target)
    if GetCursorInfo() then
        Print("put down what you are holding first.")
        return false
    end
    local itemID, count, quality, locked = GetBagSlotItem(target.bag, target.slot)
    if itemID ~= target.itemID or count ~= target.count or quality ~= target.quality or locked then
        Print("that item moved, nothing deleted.")
        return false
    end
    -- It may have been kept, become a quest item or fallen outside the
    -- settings since the first click.
    if not IsJunkCandidate(itemID, quality, target.bag, target.slot) then
        Print("%s is no longer offered, nothing deleted.", target.link)
        return false
    end
    PickupBagSlot(target.bag, target.slot)
    local kind, cursorItemID = GetCursorInfo()
    if kind ~= "item" or cursorItemID ~= target.itemID then
        ClearCursor()
        Print("could not pick up %s, nothing deleted.", target.link)
        return false
    end
    DeleteCursorItem()
    Print("deleted %s%s.", target.link, target.count > 1 and (" x" .. target.count) or "")
    return true
end

-- The keep list: items never offered for deletion, whatever their price.
function Tally.SetKept(itemID, kept)
    TallyDB.keep[itemID] = kept or nil
    Tally.RequestUpdate()
end

function Tally.ClearKept()
    wipe(TallyDB.keep)
    Tally.RequestUpdate()
end

function Tally.GetKeptCount()
    local count = 0
    for _ in pairs(TallyDB.keep) do
        count = count + 1
    end
    return count
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
    local bags = { free = 0, total = 0, list = {}, reagents = {} }
    local ammo = { count = 0, list = {}, bagFree = 0, bagTotal = 0, hasAmmoBag = false }
    local ammoByItem = {}
    local separateReagents = TallyDB and TallyDB.reagentBags == "separate"

    for bag = 0, LastBagIndex() do
        local slots = GetNumSlots(bag)
        -- An empty bag slot is no bag, whatever slot count the client reports
        -- for it: listing it showed a phantom "? Bag" quiver.
        local itemID = GetBagItemID(bag)
        if slots > 0 and (bag == 0 or itemID) then
            local free, family = GetFreeSlots(bag)
            local classID = GetItemClass(itemID)
            local isAmmoBag = classID == ITEM_CLASS_QUIVER
            local isReagentBag = IsReagentBag(bag)
            local entry = {
                bag = bag,
                itemID = itemID,
                name = bag == 0 and (BACKPACK_TOOLTIP or "Backpack") or GetItemName(itemID),
                icon = itemID and GetItemIcon(itemID) or "Interface\\Icons\\INV_Misc_Bag_08",
                free = free,
                total = slots,
                special = family ~= 0 and not isReagentBag,
                ammoBag = isAmmoBag,
                reagentBag = isReagentBag,
                separate = isReagentBag and separateReagents,
            }
            bags.list[#bags.list + 1] = entry
            if entry.separate then
                bags.reagents[#bags.reagents + 1] = entry
            end

            -- Only bags that hold anything count: a free quiver slot cannot
            -- take the loot that just filled your bags. Reagent bags count,
            -- whatever their family, unless they have their own counters.
            if (family == 0 or isReagentBag) and not entry.separate then
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
    -- Only arrows and bullets count as equipped ammo: Forever can report
    -- something else in the ammo slot with none equipped, which showed a
    -- phantom "?" counter.
    local equippedAmmo = GetInventoryItemID("player", INVSLOT_AMMO)
    if equippedAmmo and GetItemClass(equippedAmmo) == ITEM_CLASS_PROJECTILE then
        ammo.itemID = equippedAmmo
    end
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
        local note = entry.ammoBag and " (ammo)" or entry.separate and " (reagents, own counter)"
            or entry.reagentBag and " (reagents)" or entry.special and " (special, not counted)" or ""
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
    print("  /tally keep  - list the items never offered for deletion")
    print("  /tally keep <item>  - add or remove an item (shift-click it into chat)")
    print("  /tally keep clear  - forget all kept items")
    print("  /tally debug  - toggle debug output")
end

local function HandleKeep(arg)
    if not arg then
        if Tally.GetKeptCount() == 0 then
            Print("no kept items. Right-click the bag counter to always keep the item it offers.")
            return
        end
        Print("never offered for deletion:")
        for itemID in pairs(TallyDB.keep) do
            print("  " .. GetItemName(itemID))
        end
        return
    end
    if arg:lower() == "clear" then
        Tally.ClearKept()
        Print("forgot all kept items.")
        return
    end
    local itemID = tonumber(arg:match("item:(%d+)") or arg)
    if not itemID then
        Print("shift-click an item into chat after /tally keep, or give its item ID.")
        return
    end
    local kept = not TallyDB.keep[itemID]
    Tally.SetKept(itemID, kept)
    Print("%s %s", kept and "always keeping" or "no longer keeping", GetItemName(itemID))
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
    elseif command == "keep" then
        HandleKeep(input:match("^%S+%s+(.+)$"))
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
