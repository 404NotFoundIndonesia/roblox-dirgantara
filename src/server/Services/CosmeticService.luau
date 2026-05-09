--[[
    CosmeticService.luau
    ────────────────────
    Cosmetic inventory management. Full visual equip/unequip logic in Phase 13.

    Public API (partial — expanded in Phase 13)
    ──────────────────────────────────────────
    CosmeticService.init(player)
    CosmeticService.cleanup(player)
    CosmeticService.grantItem(player, itemId)  -- add itemId to ownedItems
]]

-- Lazy-require DataService to avoid load-order cycles
local _DataService: any = nil
local function getDS(): any
	if not _DataService then
		_DataService = require(script.Parent.DataService)
	end
	return _DataService
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared   = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes   = require(Shared.Remotes)
local Types     = require(Shared.Types)

local CosmeticService = {}

-- Grant ownership of itemId to player. Idempotent — safe to call if already owned.
function CosmeticService.grantItem(player: Player, itemId: string)
	local data = getDS().get(player)
	if not data then
		return
	end
	data.ownedItems[itemId] = true
end

-- Add one fragment of itemId. Auto-crafts to grantItem when count reaches 3 (T-082, Phase 13).
function CosmeticService.grantFragment(player: Player, itemId: string)
	local data = getDS().get(player)
	if not data then
		return
	end
	data.fragmentInventory[itemId] = (data.fragmentInventory[itemId] or 0) + 1
	if data.fragmentInventory[itemId] >= 3 then
		data.fragmentInventory[itemId] = 0
		CosmeticService.grantItem(player, itemId)
	end
end

-- ─── T-079: Emote slot equip handler ─────────────────────────────────────────
-- Handles Cosmetic_EquipRequest for "emoteSlot_N" slots.
-- Phase 13 (T-081) will replace this with a full handler covering all slots.

Remotes.Cosmetic_EquipRequest.OnServerEvent:Connect(function(player: Player, payload: any)
	local slot   = payload and payload.slot
	local itemId = payload and payload.itemId
	if type(slot) ~= "string" then return end

	local data = getDS().get(player) :: Types.PlayerData?
	if not data then return end

	-- Emote slot assignment
	local slotNum = tonumber(string.match(slot, "^emoteSlot_(%d+)$"))
	if not slotNum then return end   -- non-emote slots handled in Phase 13 T-081

	slotNum = math.floor(slotNum)
	if slotNum < 1 or slotNum > Constants.EMOTE_SLOT_COUNT then
		Remotes.Cosmetic_EquipResult_S2C:FireClient(player, {
			success = false,
			loadout = data.equippedItems,
		})
		return
	end

	-- Validate ownership when assigning a specific item
	if type(itemId) == "string" and itemId ~= "" then
		if not data.ownedItems[itemId] then
			Remotes.Cosmetic_EquipResult_S2C:FireClient(player, {
				success = false,
				loadout = data.equippedItems,
			})
			return
		end
	end

	-- Pad emoteSlots to 8 entries if needed
	while #data.equippedItems.emoteSlots < Constants.EMOTE_SLOT_COUNT do
		table.insert(data.equippedItems.emoteSlots, "")
	end

	data.equippedItems.emoteSlots[slotNum] =
		(type(itemId) == "string") and itemId or ""

	Remotes.Cosmetic_EquipResult_S2C:FireClient(player, {
		success = true,
		loadout = data.equippedItems,
	})
end)

function CosmeticService.init(_: Player)
end

function CosmeticService.cleanup(_: Player)
end

return CosmeticService
