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
Tally.disenchant = { known = false, count = 0 }

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
    professionBags = true,    -- herb, enchanting, soul and other profession bags get their own counter
    showDisenchant = true,    -- disenchant counter, when you know Disenchant
    keepUpgrades = true,      -- never offer gear better than what you wear
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
-- Disenchanting
--------------------------------------------------------------------------------

local DISENCHANT_SPELL = 13262
local ITEM_CLASS_ARMOR = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
local ITEM_QUALITY_UNCOMMON = Enum and Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2
local ITEM_QUALITY_EPIC = Enum and Enum.ItemQuality and Enum.ItemQuality.Epic or 4

-- What Classic gear disenchants into, by item level band. Items past the
-- table have no known result, so they never count as freeing a slot.
local DISENCHANT_BANDS = {
    { maxLevel = 15, dust = 10940, essence = 10938, shard = 10978 },
    { maxLevel = 20, dust = 10940, essence = 10939, shard = 10978 },
    { maxLevel = 25, dust = 10940, essence = 10998, shard = 10978 },
    { maxLevel = 30, dust = 11083, essence = 11082, shard = 11084 },
    { maxLevel = 35, dust = 11083, essence = 11134, shard = 11138 },
    { maxLevel = 40, dust = 11137, essence = 11135, shard = 11139 },
    { maxLevel = 45, dust = 11137, essence = 11174, shard = 11177 },
    { maxLevel = 50, dust = 11176, essence = 11175, shard = 11178 },
    { maxLevel = 55, dust = 11176, essence = 16202, shard = 14343 },
    { maxLevel = 65, dust = 16204, essence = 16203, shard = 14344, crystal = 20725 },
    -- Classic endgame epics up to level 88 still give Nexus Crystals.
    -- Green and blue gear this high is not Classic, so it stays unknown.
    { maxLevel = 99, crystal = 20725 },
}

-- The most one disenchant gives of each kind, and its stack size for when
-- the client has not cached the material yet.
local MATERIAL_YIELD = { dust = 6, essence = 2, shard = 1, epicShard = 5, crystal = 2 }
local MATERIAL_STACK = { dust = 20, essence = 10, shard = 20, epicShard = 20, crystal = 20 }

function Tally.KnowsDisenchant()
    if IsPlayerSpell then
        return IsPlayerSpell(DISENCHANT_SPELL) == true
    end
    return IsSpellKnown ~= nil and IsSpellKnown(DISENCHANT_SPELL) == true
end

-- The localized spell name, for the /cast line of the disenchant button.
function Tally.GetDisenchantSpellName()
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(DISENCHANT_SPELL)
    end
    return GetSpellInfo and (GetSpellInfo(DISENCHANT_SPELL)) or nil
end

function Tally.GetDisenchantIcon()
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(DISENCHANT_SPELL)
    end
    return GetSpellTexture and GetSpellTexture(DISENCHANT_SPELL) or nil
end

local scanTooltip

-- A hidden tooltip holding a bag item, for what only its text tells.
local function ScanBagItem(bag, slot)
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "TallyScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTooltip:ClearLines()
    scanTooltip:SetBagItem(bag, slot)
    return scanTooltip
end

-- Bound to you alone and not marked "Cannot be disenchanted". C_Item.IsBound
-- is also true for account-bound items, which another character could
-- still use, so the tooltip has to say "Soulbound".
local function IsSoulboundAndDisenchantable(bag, slot)
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local ok, bound = pcall(C_Item.IsBound, ItemLocation:CreateFromBagAndSlot(bag, slot))
        if ok and not bound then
            return false
        end
    end
    local tooltip = ScanBagItem(bag, slot)
    local soulbound = false
    for i = 2, tooltip:NumLines() do
        local line = _G["TallyScanTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text == (ITEM_SOULBOUND or "Soulbound") then
            soulbound = true
        elseif text == (ITEM_DISENCHANT_NOT_DISENCHANTABLE or "Cannot be disenchanted") then
            soulbound = false
            break
        end
    end
    tooltip:Hide()
    return soulbound
end

local function GetItemLevel(itemID, link)
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return getter and (select(4, getter(link or itemID))) or nil
end

local function GetMaxStack(itemID, kind)
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return getter and (select(8, getter(itemID))) or MATERIAL_STACK[kind]
end

-- Every material a disenchant can give, as { itemID, kind } pairs with the
-- likely one first, or nil when the item level is past the table. Green
-- gear rolls dust, essence or a shard; blue gear a shard, or rarely a Nexus
-- Crystal from level 56; purple gear a Nexus Crystal from level 56.
local function PossibleMaterials(classID, quality, level)
    if not level then
        return nil
    end
    for _, band in ipairs(DISENCHANT_BANDS) do
        if level <= band.maxLevel then
            if not band.shard and quality ~= ITEM_QUALITY_EPIC then
                return nil
            end
            if quality == ITEM_QUALITY_EPIC then
                if band.crystal then
                    return { { band.crystal, "crystal" } }
                end
                return { { band.shard, "epicShard" } }
            elseif quality > ITEM_QUALITY_UNCOMMON then
                local materials = { { band.shard, "shard" } }
                if band.crystal then
                    materials[2] = { band.crystal, "crystal" }
                end
                return materials
            end
            local dust, essence = { band.dust, "dust" }, { band.essence, "essence" }
            if classID == ITEM_CLASS_WEAPON then
                return { essence, dust, { band.shard, "shard" } }
            end
            return { dust, essence, { band.shard, "shard" } }
        end
    end
    return nil
end

-- Soulbound green, blue and purple weapons and armor: they cannot go to the
-- auction house, so disenchanting them loses only vendor money. Kept items
-- and quest items are never offered.
local function IsDisenchantCandidate(itemID, quality, bag, slot)
    if TallyDB.keep[itemID] or not quality then
        return false
    end
    if quality < ITEM_QUALITY_UNCOMMON or quality > ITEM_QUALITY_EPIC then
        return false
    end
    local classID = GetItemClass(itemID)
    if classID ~= ITEM_CLASS_WEAPON and classID ~= ITEM_CLASS_ARMOR then
        return false
    end
    return IsSoulboundAndDisenchantable(bag, slot) and not IsQuestItem(bag, slot)
end

-- Where each kind of gear goes. One-handers also count the off hand when a
-- weapon is in it, or it is empty and you can dual wield, so a shield is
-- not compared with a sword.
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
    INVTYPE_TABARD = { 19 },
}
local OFF_HAND_SLOT = 17
local MAIN_HAND_SLOT = 16

-- Whether a one-handed weapon could go in your empty off hand.
local function CanOffHandWeapon()
    if not CanDualWield or not CanDualWield() then
        return false
    end
    local mainHand = GetInventoryItemID("player", MAIN_HAND_SLOT)
    if not mainHand then
        return true
    end
    local getter = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local equipLoc = getter and select(4, getter(mainHand))
    return equipLoc ~= "INVTYPE_2HWEAPON"
end

-- A broken item's durability line is red, but it can be repaired.
local DURABILITY_PATTERN = "^" .. (DURABILITY_TEMPLATE or "Durability %d / %d"):gsub("%%d", "%%d+") .. "$"
-- "Classes: %s" and "Races: %s" restrictions are for good.
local CLASSES_PREFIX = "^" .. (ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("%%s.*", "")
local RACES_PREFIX = "^" .. (ITEM_RACES_ALLOWED or "Races: %s"):gsub("%%s.*", "")

-- Armor and weapon types each Classic class can ever learn, counting
-- proficiencies trained later (mail and plate at level 40, weapon skills
-- from a weapon master). Types a class might learn are listed rather than
-- left out: a type missing here would let a plain click disenchant gear
-- the class could still wear. Classes not listed are never ruled out.
local ARMOR = {
    misc = 0, cloth = 1, leather = 2, mail = 3, plate = 4, shield = 6,
    libram = 7, idol = 8, totem = 9,
}
local WEAPON = {
    axe1 = 0, axe2 = 1, bow = 2, gun = 3, mace1 = 4, mace2 = 5, polearm = 6,
    sword1 = 7, sword2 = 8, staff = 10, fist = 13, misc = 14, dagger = 15,
    thrown = 16, spear = 17, crossbow = 18, wand = 19, fishing = 20,
}
local function TypeSet(names, ids)
    local set = {}
    for _, name in ipairs(names) do
        set[ids[name]] = true
    end
    return set
end
local LEARNABLE = {
    WARRIOR = {
        armor = TypeSet({ "misc", "cloth", "leather", "mail", "plate", "shield" }, ARMOR),
        weapon = TypeSet({ "axe1", "axe2", "bow", "gun", "mace1", "mace2", "polearm", "sword1", "sword2",
            "staff", "fist", "misc", "dagger", "thrown", "spear", "crossbow", "fishing" }, WEAPON),
    },
    PALADIN = {
        armor = TypeSet({ "misc", "cloth", "leather", "mail", "plate", "shield", "libram" }, ARMOR),
        weapon = TypeSet({ "axe1", "axe2", "mace1", "mace2", "polearm", "sword1", "sword2", "misc", "spear",
            "fishing" }, WEAPON),
    },
    HUNTER = {
        armor = TypeSet({ "misc", "cloth", "leather", "mail" }, ARMOR),
        weapon = TypeSet({ "axe1", "axe2", "bow", "gun", "polearm", "sword1", "sword2", "staff", "fist",
            "misc", "dagger", "thrown", "spear", "crossbow", "fishing" }, WEAPON),
    },
    ROGUE = {
        armor = TypeSet({ "misc", "cloth", "leather" }, ARMOR),
        weapon = TypeSet({ "axe1", "bow", "gun", "mace1", "sword1", "fist", "misc", "dagger", "thrown",
            "crossbow", "fishing" }, WEAPON),
    },
    PRIEST = {
        armor = TypeSet({ "misc", "cloth" }, ARMOR),
        weapon = TypeSet({ "mace1", "staff", "misc", "dagger", "wand", "fishing" }, WEAPON),
    },
    SHAMAN = {
        armor = TypeSet({ "misc", "cloth", "leather", "mail", "shield", "totem" }, ARMOR),
        weapon = TypeSet({ "axe1", "axe2", "mace1", "mace2", "staff", "fist", "misc", "dagger", "fishing" }, WEAPON),
    },
    MAGE = {
        armor = TypeSet({ "misc", "cloth" }, ARMOR),
        weapon = TypeSet({ "sword1", "staff", "misc", "dagger", "wand", "fishing" }, WEAPON),
    },
    WARLOCK = {
        armor = TypeSet({ "misc", "cloth" }, ARMOR),
        weapon = TypeSet({ "sword1", "staff", "misc", "dagger", "wand", "fishing" }, WEAPON),
    },
    DRUID = {
        armor = TypeSet({ "misc", "cloth", "leather", "idol" }, ARMOR),
        weapon = TypeSet({ "mace1", "mace2", "polearm", "staff", "fist", "misc", "dagger", "fishing" }, WEAPON),
    },
}

local function ClassCanEverLearn(itemID)
    local learnable = LEARNABLE[select(2, UnitClass("player"))]
    if not learnable then
        return true
    end
    local classID, subclassID = GetItemClass(itemID)
    local types = classID == ITEM_CLASS_WEAPON and learnable.weapon
        or classID == ITEM_CLASS_ARMOR and learnable.armor
    return not types or subclassID == nil or types[subclassID] == true
end

-- Whether you can wear an item: "now", "later" or "never". Only a class or
-- race restriction, or red text on an armor or weapon type your class can
-- never learn, is "never". Any other red text (level, an untrained but
-- learnable proficiency, a profession, reputation) is "later".
local function WearState(bag, slot, itemID)
    ScanBagItem(bag, slot)
    local state = "now"
    for i = 2, scanTooltip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local line = _G["TallyScanTooltipText" .. side .. i]
            local text = line and line:IsShown() and line:GetText()
            if text then
                local r, g, b = line:GetTextColor()
                if r > 0.99 and g < 0.2 and b < 0.2 and not text:match(DURABILITY_PATTERN) then
                    if text:match(CLASSES_PREFIX) or text:match(RACES_PREFIX) then
                        scanTooltip:Hide()
                        return "never"
                    end
                    state = "later"
                end
            end
        end
    end
    scanTooltip:Hide()
    if state == "later" and not ClassCanEverLearn(itemID) then
        return "never"
    end
    return state
end

-- Pawn answers nil for "not sure yet" (item data not loaded, or its
-- per-frame budget spent), so such items are held back and asked again on a
-- later recount. After this many tries in a row the item level decides,
-- so an item Pawn never rates does not stay hidden for good.
local PAWN_RETRY_DELAY = 1
local PAWN_MAX_TRIES = 10
local pawnTries = {}
local pawnRetryScheduled = false

local function SchedulePawnRetry()
    if not pawnRetryScheduled then
        pawnRetryScheduled = true
        C_Timer.After(PAWN_RETRY_DELAY, function()
            pawnRetryScheduled = false
            Tally.RequestUpdate()
        end)
    end
end

-- Pawn's upgrade arrow: true or false, "pending" while Pawn is not sure
-- yet, or nil without Pawn (or once it has been asked often enough).
local function PawnSaysUpgrade(link)
    if type(PawnShouldItemLinkHaveUpgradeArrow) ~= "function" then
        return nil
    end
    local ok, upgrade = pcall(PawnShouldItemLinkHaveUpgradeArrow, link)
    if not ok then
        return nil
    end
    if upgrade ~= nil then
        pawnTries[link] = nil
        return upgrade and true or false
    end
    local tries = (pawnTries[link] or 0) + 1
    pawnTries[link] = tries
    if tries > PAWN_MAX_TRIES then
        return nil
    end
    SchedulePawnRetry()
    return "pending"
end

-- Whether an item you can wear now would be better than what you wear:
-- Pawn's verdict if Pawn is installed, otherwise a higher item level than
-- the weakest item in its slots, or an empty slot.
local function IsUpgrade(itemID, link, level, wear)
    local getter = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local equipLoc = getter and select(4, getter(itemID))
    local slots = EQUIP_SLOTS[equipLoc]
    if not slots or wear ~= "now" then
        return false
    end
    local pawn = link and PawnSaysUpgrade(link)
    if pawn == "pending" then
        return true, "Pawn checking"
    elseif pawn ~= nil then
        return pawn, "Pawn"
    end
    if not level then
        return false
    end
    for _, inventorySlot in ipairs(slots) do
        local equipped = GetInventoryItemLink("player", inventorySlot)
        if inventorySlot == OFF_HAND_SLOT and equipLoc == "INVTYPE_WEAPON" and not equipped then
            -- An empty off hand only takes this one-hander if you can dual
            -- wield and are not holding a two-hander.
            if CanOffHandWeapon() then
                return true, "empty slot"
            end
        elseif inventorySlot == OFF_HAND_SLOT and equipLoc == "INVTYPE_WEAPON"
            and GetItemClass(GetInventoryItemID("player", inventorySlot)) ~= ITEM_CLASS_WEAPON then
            -- A shield or off-hand item there: not compared.
        elseif not equipped then
            return true, "empty slot"
        else
            local equippedLevel = GetItemLevel(nil, equipped)
            if equippedLevel and level > equippedLevel then
                return true, "item level"
            end
        end
    end
    return false
end

local ENCHANTING_SKILL_LINE = 333
local ENCHANTING_SPELL = 7411

-- Enchanting skill Classic asks for to disenchant green gear, by item
-- level. Blue gear needs at least 25 and purple gear from level 56 needs
-- 225. Items past the table are not checked; the game refuses those itself.
local SKILL_BANDS = {
    { maxLevel = 20, skill = 1 },
    { maxLevel = 25, skill = 25 },
    { maxLevel = 30, skill = 50 },
    { maxLevel = 35, skill = 75 },
    { maxLevel = 40, skill = 100 },
    { maxLevel = 45, skill = 125 },
    { maxLevel = 50, skill = 150 },
    { maxLevel = 55, skill = 175 },
    { maxLevel = 60, skill = 200 },
    { maxLevel = 65, skill = 225 },
    { maxLevel = 99, skill = 225 },
}

local function RequiredSkill(level, quality)
    if not level then
        return nil
    end
    for _, band in ipairs(SKILL_BANDS) do
        if level <= band.maxLevel then
            local skill = band.skill
            if quality == ITEM_QUALITY_EPIC and level >= 56 then
                skill = math.max(skill, 225)
            elseif quality and quality > ITEM_QUALITY_UNCOMMON then
                skill = math.max(skill, 25)
            end
            return skill
        end
    end
    return nil
end

-- Your Enchanting skill, or nil when it cannot be read (nothing is ruled
-- out then).
local function GetEnchantingSkill()
    if GetProfessions and GetProfessionInfo then
        local professions = { GetProfessions() }
        for i = 1, select("#", GetProfessions()) do
            if professions[i] then
                local _, _, rank, _, _, _, skillLine = GetProfessionInfo(professions[i])
                if skillLine == ENCHANTING_SKILL_LINE then
                    return rank
                end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local enchanting = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ENCHANTING_SPELL))
            or (GetSpellInfo and GetSpellInfo(ENCHANTING_SPELL)) or "Enchanting"
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank = GetSkillLineInfo(i)
            if not isHeader and name == enchanting then
                return rank
            end
        end
    end
    return nil
end

local function SkillTooLow(level, quality, skill)
    local required = RequiredSkill(level, quality)
    return skill ~= nil and required ~= nil and skill < required
end

-- Items that free a slot first, then the one worth least at a vendor.
local function IsBetterTarget(candidate, best)
    if not best then
        return true
    end
    if candidate.freesSlot ~= best.freesSlot then
        return candidate.freesSlot
    end
    return candidate.value < best.value
end

-- Every item you could disenchant, split into safe ones (soulbound gear you
-- can never wear, only good for materials) and the rest, with the one of
-- each to offer. Disenchanting frees the item's slot, but the materials take
-- a new slot unless they stack with what you carry. With room to spare
-- (more free slots than the yellow warning) every candidate counts; with
-- bags getting full only items whose every possible material has room for a full
-- result in your stacks count. Upgrades over what you wear are held back
-- and listed instead.
local function FindDisenchants(bags)
    local result = { known = Tally.KnowsDisenchant(), count = 0, safeCount = 0, upgrades = {} }
    if not TallyDB or not result.known then
        return result
    end
    result.tight = bags.free <= (TallyDB.bagWarning or 0)
    local skill = GetEnchantingSkill()

    local held = {}
    local candidates = {}
    for bag = 0, LastBagIndex() do
        for slot = 1, GetNumSlots(bag) do
            local itemID, count, quality, locked, link = GetBagSlotItem(bag, slot)
            if itemID then
                held[itemID] = held[itemID] or { count = 0, stacks = 0 }
                held[itemID].count = held[itemID].count + count
                held[itemID].stacks = held[itemID].stacks + 1
                if not locked and IsDisenchantCandidate(itemID, quality, bag, slot)
                    and not SkillTooLow(GetItemLevel(itemID, link), quality, skill) then
                    local wear = WearState(bag, slot, itemID)
                    local candidate = {
                        bag = bag,
                        slot = slot,
                        itemID = itemID,
                        quality = quality,
                        link = link or GetItemName(itemID),
                        level = GetItemLevel(itemID, link),
                        value = GetSellPrice(itemID) or 0,
                        safe = wear == "never",
                    }
                    local upgrade, reason
                    if TallyDB.keepUpgrades then
                        upgrade, reason = IsUpgrade(itemID, link, candidate.level, wear)
                    end
                    if upgrade then
                        candidate.reason = reason
                        result.upgrades[#result.upgrades + 1] = candidate
                    else
                        candidates[#candidates + 1] = candidate
                    end
                end
            end
        end
    end

    for _, candidate in ipairs(candidates) do
        -- A slot is only freed for sure when every possible result fits in
        -- the stacks you carry.
        local materials = PossibleMaterials(GetItemClass(candidate.itemID), candidate.quality, candidate.level)
        candidate.material = materials and materials[1][1]
        candidate.freesSlot = materials ~= nil
        for _, entry in ipairs(materials or {}) do
            local material, kind = entry[1], entry[2]
            local stacks = held[material]
            local room = stacks and stacks.stacks * GetMaxStack(material, kind) - stacks.count or 0
            if room < MATERIAL_YIELD[kind] then
                candidate.freesSlot = false
            end
        end
        if candidate.freesSlot or not result.tight then
            result.count = result.count + 1
            if candidate.safe then
                result.safeCount = result.safeCount + 1
                if IsBetterTarget(candidate, result.safeTarget) then
                    result.safeTarget = candidate
                end
            elseif IsBetterTarget(candidate, result.unsafeTarget) then
                result.unsafeTarget = candidate
            end
        end
    end
    return result
end

-- Rechecks the offered item as it is clicked: still in its slot, still
-- offered, not an upgrade and, for a plain click, still gear you can never
-- wear. Returns the macro for the disenchant button, or nil.
function Tally.PrepareDisenchant(target, requireSafe)
    if GetCursorInfo() then
        Print("put down what you are holding first.")
        return nil
    end
    local itemID, _, quality, locked, link = GetBagSlotItem(target.bag, target.slot)
    -- The full link, so another copy with a different random enchant does
    -- not pass for the item that was offered.
    if itemID ~= target.itemID or (link and link ~= target.link) or locked then
        Print("that item moved, nothing disenchanted.")
        return nil
    end
    if not IsDisenchantCandidate(itemID, quality, target.bag, target.slot) then
        Print("%s is no longer offered, nothing disenchanted.", target.link)
        return nil
    end
    if SkillTooLow(target.level, quality, GetEnchantingSkill()) then
        Print("%s needs more Enchanting skill, nothing disenchanted.", target.link)
        return nil
    end
    local wear = WearState(target.bag, target.slot, itemID)
    if requireSafe and wear ~= "never" then
        Print("%s is gear you can wear: shift-click to disenchant it.", target.link)
        return nil
    end
    if TallyDB.keepUpgrades then
        local upgrade, reason = IsUpgrade(itemID, link, target.level, wear)
        if upgrade and reason == "Pawn checking" then
            Print("Pawn has not rated %s yet, nothing disenchanted.", target.link)
            return nil
        elseif upgrade then
            Print("%s is better than what you wear, nothing disenchanted.", target.link)
            return nil
        end
    end
    local spell = Tally.GetDisenchantSpellName()
    if not spell then
        return nil
    end
    return string.format("/cast %s\n/use %d %d", spell, target.bag, target.slot)
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
    local separateProfession = TallyDB and TallyDB.professionBags

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
            -- Herb, enchanting, soul and other profession bags only take
            -- their own kind of item, so they may have room when your bags
            -- are full. Quivers and ammo pouches show on the ammo counter.
            local isProfessionBag = family ~= 0 and not isReagentBag and not isAmmoBag
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
                professionBag = isProfessionBag,
                separate = (isReagentBag and separateReagents) or (isProfessionBag and separateProfession) or false,
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
    Tally.disenchant = FindDisenchants(bags)
    Debug("bags %d/%d free, ammo %d (shown: %s), disenchant %d", bags.free, bags.total, ammo.count,
        tostring(ammo.shown), Tally.disenchant.count)
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
        local note = entry.ammoBag and " (ammo)" or entry.separate and " (own counter)"
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
    local disenchant = Tally.disenchant
    if disenchant.known then
        Print("disenchant: %d %s%s", disenchant.count, disenchant.count == 1 and "item" or "items",
            disenchant.tight and " that free a slot" or "")
    end
end

local function PrintHelp()
    Print("commands:")
    print("  /tally  - open Settings > AddOns > Tally")
    print("  /tally status  - print bag slots and ammo in chat")
    print("  /tally unlock  - move the counters outside Edit Mode")
    print("  /tally lock  - lock the counters")
    print("  /tally reset  - put the counters back in the bottom-right corner")
    print("  /tally keep  - list the items never offered for deletion or disenchanting")
    print("  /tally keep <item>  - add or remove an item (shift-click it into chat)")
    print("  /tally keep clear  - forget all kept items")
    print("  /tally debug  - toggle debug output")
end

local function HandleKeep(arg)
    if not arg then
        if Tally.GetKeptCount() == 0 then
            Print("no kept items. Right-click the bag or disenchant counter to always keep the item it offers.")
            return
        end
        Print("never offered for deletion or disenchanting:")
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
frame:RegisterEvent("SPELLS_CHANGED")
pcall(frame.RegisterEvent, frame, "SKILL_LINES_CHANGED")
-- The disenchant button is secure: it is put away as combat starts and
-- brought back after.
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if ns.display and ns.display.UpdateDisenchantButton then
            ns.display.UpdateDisenchantButton(event == "PLAYER_REGEN_DISABLED")
        end
    else
        Tally.RequestUpdate()
    end
end)
