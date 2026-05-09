--[[
    WingService.luau
    ────────────────
    Wing level progression, realm entry gate, join sync, and Awan XP/rank.
    Covers T-032 through T-035.

    Public API
    ──────────
    WingService.init(player)                          -- join sync: level + XP
    WingService.cleanup(player)                       -- clear per-player state
    WingService.canEnterRealm(player, realmId)        -- gate check; fires denial remote
    WingService.awardAwanXP(player, amount)           -- XP from any source; fires rank-up
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local Constants  = require(Shared.Constants)
local WingDefs   = require(Shared.WingDefs)
local RealmDefs  = require(Shared.RealmDefs)
local Remotes    = require(Shared.Remotes)

-- Lazy-require sibling services to avoid load-order cycles
local _DataService:     any = nil
local _FlightService:   any = nil
local _SkysPeakService: any = nil

local function getDS(): any
	if not _DataService then
		_DataService = require(script.Parent.DataService)
	end
	return _DataService
end

local function getFS(): any
	if not _FlightService then
		_FlightService = require(script.Parent.FlightService)
	end
	return _FlightService
end

local function getSPS(): any
	if not _SkysPeakService then
		_SkysPeakService = require(script.Parent.SkysPeakService)
	end
	return _SkysPeakService
end

local WingService = {}

-- ─── Per-player state ─────────────────────────────────────────────────────────

local _players:  { [number]: Player } = {}
local _lastRank: { [number]: string } = {}

-- ─── Awan rank helpers (T-035) ────────────────────────────────────────────────

-- Walk ranks ascending; return the highest bracket the player qualifies for.
local function computeRank(xp: number): string
	local name = Constants.AWAN_RANKS[1].name
	for _, entry in Constants.AWAN_RANKS do
		if xp >= entry.minXP then
			name = entry.name
		end
	end
	return name
end

-- ─── T-035: Awan XP award ────────────────────────────────────────────────────

function WingService.awardAwanXP(player: Player, amount: number)
	local userId = player.UserId
	local data   = getDS().get(player)
	if not data then return end

	data.awanXP += amount

	local newRank = computeRank(data.awanXP)
	_lastRank[userId] = newRank

	-- Fire on every XP change so the client can update its XP bar.
	-- A rank-up is signalled by the rank field changing; the client detects it by
	-- comparing the incoming rank to its cached value and shows the appropriate notification.
	Remotes.AwanXP_Update_S2C:FireClient(player, {
		xp   = data.awanXP,
		rank = newRank,
	})
end

-- ─── T-032: Upgrade remote ────────────────────────────────────────────────────

Remotes.Wing_UpgradeRequest.OnServerEvent:Connect(function(player: Player)
	local data = getDS().get(player)
	if not data then return end

	local currentLevel = data.wingLevel

	-- Validate: not already at max
	if currentLevel >= Constants.MAX_WING_LEVEL then
		Remotes.Wing_UpgradeResult_S2C:FireClient(player, {
			success       = false,
			newLevel      = currentLevel,
			newCahayaHati = data.cahayaHati,
		})
		return
	end

	local nextLevel = currentLevel + 1
	local nextDef   = WingDefs[nextLevel]
	if not nextDef then return end   -- safety: definition missing

	-- Validate: enough Cahaya Hati
	if data.cahayaHati < nextDef.cahayaHatiCost then
		Remotes.Wing_UpgradeResult_S2C:FireClient(player, {
			success       = false,
			newLevel      = currentLevel,
			newCahayaHati = data.cahayaHati,
		})
		return
	end

	-- Validate: no active Sky's Peak run
	local sps = getSPS()
	if sps.isRunActive and sps.isRunActive(player) then
		Remotes.Wing_UpgradeResult_S2C:FireClient(player, {
			success       = false,
			newLevel      = currentLevel,
			newCahayaHati = data.cahayaHati,
		})
		return
	end

	-- Apply upgrade
	data.cahayaHati -= nextDef.cahayaHatiCost
	data.wingLevel   = nextLevel

	-- Update FlightService charge max immediately
	getFS().setWingLevel(player, nextLevel)

	-- Award Awan XP: 50 × new level
	WingService.awardAwanXP(player, Constants.AWAN_XP_WING_PER_LEVEL * nextLevel)

	-- Sync wing level to client
	Remotes.Wing_LevelSync_S2C:FireClient(player, { level = nextLevel })

	-- Fire upgrade result
	Remotes.Wing_UpgradeResult_S2C:FireClient(player, {
		success       = true,
		newLevel      = nextLevel,
		newCahayaHati = data.cahayaHati,
	})
end)

-- ─── T-033: Realm entry gate ──────────────────────────────────────────────────

-- Returns true if the player meets the wing level requirement for the realm.
-- Fires Wing_GateDenied_S2C and returns false if not. The TeleportService layer
-- (Phase 20) is responsible for the actual kick-back to Hub when this returns false.
function WingService.canEnterRealm(player: Player, realmId: string): boolean
	local data     = getDS().get(player)
	local realmDef = RealmDefs[realmId]

	if not data or not realmDef then return false end

	if data.wingLevel < realmDef.minWingLevel then
		Remotes.Wing_GateDenied_S2C:FireClient(player, {
			requiredLevel = realmDef.minWingLevel,
		})
		return false
	end

	return true
end

-- ─── T-034: Join sync ────────────────────────────────────────────────────────

function WingService.init(player: Player)
	local userId = player.UserId
	_players[userId] = player

	local data = getDS().get(player)
	if not data then return end

	-- Initialise rank cache before first sync
	_lastRank[userId] = computeRank(data.awanXP)

	-- Sync wing level to FlightService so charge max is correct before gameplay starts
	getFS().setWingLevel(player, data.wingLevel)

	-- Send wing level + XP/rank to client
	task.defer(function()
		if not _players[userId] then return end
		Remotes.Wing_LevelSync_S2C:FireClient(player, { level = data.wingLevel })
		Remotes.AwanXP_Update_S2C:FireClient(player, {
			xp   = data.awanXP,
			rank = _lastRank[userId],
		})
	end)
end

function WingService.cleanup(player: Player)
	local userId = player.UserId
	_players[userId]  = nil
	_lastRank[userId] = nil
end

return WingService
