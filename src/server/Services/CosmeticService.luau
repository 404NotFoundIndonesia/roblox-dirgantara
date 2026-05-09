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

function CosmeticService.init(_: Player)
end

function CosmeticService.cleanup(_: Player)
end

return CosmeticService
