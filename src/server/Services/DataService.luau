--[[
    DataService.luau
    ────────────────
    Player data load / save, daily reset, auto-save loop, and global DataStore
    helpers. All DataStore calls are wrapped with RetryAsync.

    Public API
    ──────────
    DataService.init(player)                            -- called by server bootstrap
    DataService.cleanup(player)                         -- called on PlayerRemoving
    DataService.get(player) -> PlayerData?              -- in-memory read
    DataService.save(player)                            -- force write to DataStore
    DataService.readGlobal(storeName, key) -> any       -- non-player DataStore read
    DataService.writeGlobal(storeName, key, value)      -- non-player DataStore write
    DataService.writeLeaderboard(userId, score)         -- OrderedDataStore write
    DataService.readLeaderboardTop(count) -> { any }    -- top-N leaderboard read
    DataService.DailyReset: BindableEvent               -- fires after daily reset is applied
]]

local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local Types      = require(Shared.Types)
local Constants  = require(Shared.Constants)
local RetryAsync = require(Shared.RetryAsync)

local DataService = {}

-- ─── BindableEvent ────────────────────────────────────────────────────────────

local _dailyResetEvent = Instance.new("BindableEvent")
_dailyResetEvent.Name  = "DailyReset"
DataService.DailyReset = _dailyResetEvent   -- DailyTaskService subscribes to this

local _playerLoadedEvent = Instance.new("BindableEvent")
_playerLoadedEvent.Name  = "PlayerLoaded"
DataService.PlayerLoaded = _playerLoadedEvent   -- fires after data is loaded; used by DailyTaskService for login streak

-- ─── DataStore handles ────────────────────────────────────────────────────────

local _playerStore:  GlobalDataStore  = DataStoreService:GetDataStore(Constants.DS_PLAYER_DATA)
local _ikatanStore:  GlobalDataStore  = DataStoreService:GetDataStore(Constants.DS_IKATAN_GRAPH)
local _seasonStore:  GlobalDataStore  = DataStoreService:GetDataStore(Constants.DS_SEASON_CONFIG)
local _spiritStore:  GlobalDataStore  = DataStoreService:GetDataStore(Constants.DS_DAILY_SPIRIT)
local _purchaseStore: GlobalDataStore = DataStoreService:GetDataStore(Constants.DS_PURCHASE_HIST)
local _grantsStore:  GlobalDataStore  = DataStoreService:GetDataStore(Constants.DS_PENDING_GRANTS)
local _leaderStore:  OrderedDataStore = DataStoreService:GetOrderedDataStore(Constants.DS_LEADERBOARD)

-- Lookup table for readGlobal / writeGlobal
local _globalStores: { [string]: GlobalDataStore } = {
	[Constants.DS_IKATAN_GRAPH]   = _ikatanStore,
	[Constants.DS_SEASON_CONFIG]  = _seasonStore,
	[Constants.DS_DAILY_SPIRIT]   = _spiritStore,
	[Constants.DS_PURCHASE_HIST]  = _purchaseStore,
	[Constants.DS_PENDING_GRANTS] = _grantsStore,
}

-- ─── Per-player state ─────────────────────────────────────────────────────────

local _cache:           { [number]: Types.PlayerData } = {}
local _autoSaveThreads: { [number]: thread }           = {}

-- ─── Default data factory ─────────────────────────────────────────────────────

local function makeDefaultData(): Types.PlayerData
	local now = os.time()
	return {
		schemaVersion = Constants.SCHEMA_VERSION,
		createdAt     = now,
		lastLogin     = now,

		cahaya      = 50,
		cahayaHati  = 0,
		koinMusim   = 0,
		bintangHati = 0,

		wingLevel      = 1,
		awanXP         = 0,
		skysPeakCycles = 0,

		dailyCahayaCollected  = 0,
		dailyResetTimestamp   = 0,   -- 0 forces a daily reset on first login
		loginStreak           = 0,
		lastStreakDate         = "",
		graceDaysRemaining    = 0,
		dailySpiritsTouched   = {},

		taskState = {
			date                    = "",
			tasks                   = {},
			completedIndices        = {},
			milestoneRewardsClaimed = {},
		},

		weeklyState = {
			weekNumber    = 0,
			fullClearDays = 0,
			rewardClaimed = false,
		},

		monthlyState = {
			month               = "",
			weeklyMilestonesMet = 0,
			rewardClaimed       = false,
		},

		freedSpiritIds = {},
		galeriRohOrder = {},

		ikatanList            = {},
		ikatanGiftsGivenToday = 0,

		ownedItems        = {},
		fragmentInventory = {},
		equippedItems     = {
			emoteSlots = {} :: { string },
		},
		openedChests = {},

		activeSeasonId           = "",
		seasonPassOwned          = false,
		seasonPassPlusOwned      = false,
		freedSeasonSpiritIds     = {},
		seasonQuestProgress      = {},
		dailyChestBonusUsedToday = false,

		starterPackClaimed = false,
		uiScale            = Constants.UI_SCALE_DEFAULT,
	}
end

-- ─── Daily reset helpers ──────────────────────────────────────────────────────

-- Returns the Unix timestamp of today's midnight in UTC+7, expressed as UTC.
local function getUTC7MidnightTimestamp(): number
	local now       = os.time()
	local localNow  = now + Constants.DAILY_RESET_UTC_OFFSET
	local localMidnight = math.floor(localNow / 86400) * 86400
	return localMidnight - Constants.DAILY_RESET_UTC_OFFSET
end

local PREMIUM_DAILY_CAHAYA_BONUS = 10

local function applyDailyReset(data: Types.PlayerData, player: Player)
	data.dailyCahayaCollected   = 0
	data.ikatanGiftsGivenToday  = 0
	data.dailyChestBonusUsedToday = false
	data.dailySpiritsTouched    = {}
	data.dailyResetTimestamp    = getUTC7MidnightTimestamp()
	-- T-117: Roblox Premium members receive a bonus Cahaya on each daily reset.
	if player.MembershipType == Enum.MembershipType.Premium then
		data.cahaya += PREMIUM_DAILY_CAHAYA_BONUS
	end
	_dailyResetEvent:Fire(player)
end

-- ─── Load (private) ───────────────────────────────────────────────────────────

local function load(player: Player)
	local userId = player.UserId
	local key    = tostring(userId)

	local ok, raw = RetryAsync.run(function(): any
		return _playerStore:GetAsync(key)
	end, Constants.DS_MAX_RETRIES, Constants.DS_RETRY_DELAY)

	local data: Types.PlayerData

	if not ok then
		-- All retries failed — load blank-state; do NOT overwrite DataStore on exit
		warn("[DataService] Load failed for", player.Name, "— using blank-state, save is locked")
		data = makeDefaultData()
		data.dataLoadFailed = true
	elseif raw == nil then
		-- First-ever join; no record in DataStore yet
		data = makeDefaultData()
	else
		data = raw :: Types.PlayerData
	end

	-- Apply daily reset if the stored timestamp is from a previous UTC+7 day
	local midnight = getUTC7MidnightTimestamp()
	if data.dailyResetTimestamp < midnight then
		applyDailyReset(data, player)
	end

	data.lastLogin  = os.time()
	_cache[userId]  = data
end

-- ─── Save ─────────────────────────────────────────────────────────────────────

function DataService.save(player: Player)
	local userId   = player.UserId
	local data     = _cache[userId]
	if not data then return end

	-- Never overwrite the DataStore with blank-state; real data may still be there
	if data.dataLoadFailed then
		warn("[DataService] Save skipped for", player.Name, "— dataLoadFailed is set")
		return
	end

	local key      = tostring(userId)
	local snapshot = data   -- table reference; serialised at UpdateAsync call time

	local ok, _ = RetryAsync.run(function()
		_playerStore:UpdateAsync(key, function(_: any): any
			return snapshot
		end)
	end, Constants.DS_MAX_RETRIES, Constants.DS_RETRY_DELAY)

	if not ok then
		warn("[DataService] Save failed for", player.Name)
	end
end

-- ─── Auto-save loop ───────────────────────────────────────────────────────────

local function startAutoSave(player: Player)
	local userId = player.UserId
	local thread = task.spawn(function()
		while _cache[userId] ~= nil do
			task.wait(Constants.AUTO_SAVE_INTERVAL)
			if _cache[userId] ~= nil then
				DataService.save(player)
			end
		end
	end)
	_autoSaveThreads[userId] = thread
end

local function stopAutoSave(userId: number)
	local thread = _autoSaveThreads[userId]
	if thread then
		task.cancel(thread)
		_autoSaveThreads[userId] = nil
	end
end

-- ─── Public player API ────────────────────────────────────────────────────────

-- Returns the live in-memory PlayerData for the given player, or nil if not loaded.
function DataService.get(player: Player): Types.PlayerData?
	return _cache[player.UserId]
end

function DataService.init(player: Player)
	load(player)
	startAutoSave(player)
	-- T-116: apply purchases queued while the player was offline.
	local monetSvc = require(script.Parent.MonetizationService)
	;(monetSvc :: any).applyPendingGrants(player)
	_playerLoadedEvent:Fire(player)
end

function DataService.cleanup(player: Player)
	local userId = player.UserId
	stopAutoSave(userId)
	DataService.save(player)
	_cache[userId] = nil
end

-- ─── Global DataStore helpers (T-017) ─────────────────────────────────────────

-- Read from any named non-player DataStore using retryAsync.
function DataService.readGlobal(storeName: string, key: string): any
	local store = _globalStores[storeName]
	if not store then
		warn("[DataService] readGlobal: unknown store '" .. storeName .. "'")
		return nil
	end
	local ok, result = RetryAsync.run(function(): any
		return store:GetAsync(key)
	end, Constants.DS_MAX_RETRIES, Constants.DS_RETRY_DELAY)
	return if ok then result else nil
end

-- Write to any named non-player DataStore using retryAsync + UpdateAsync.
function DataService.writeGlobal(storeName: string, key: string, value: any)
	local store = _globalStores[storeName]
	if not store then
		warn("[DataService] writeGlobal: unknown store '" .. storeName .. "'")
		return
	end
	local ok, _ = RetryAsync.run(function()
		store:UpdateAsync(key, function(_: any): any
			return value
		end)
	end, Constants.DS_MAX_RETRIES, Constants.DS_RETRY_DELAY)
	if not ok then
		warn("[DataService] writeGlobal failed — store:", storeName, "key:", key)
	end
end

-- Write a numeric score to the OrderedDataStore leaderboard.
function DataService.writeLeaderboard(userId: number, score: number)
	local ok, _ = RetryAsync.run(function()
		_leaderStore:SetAsync(tostring(userId), score)
	end, Constants.DS_MAX_RETRIES, Constants.DS_RETRY_DELAY)
	if not ok then
		warn("[DataService] writeLeaderboard failed for userId", userId)
	end
end

-- Read the top-N entries from the leaderboard OrderedDataStore.
function DataService.readLeaderboardTop(count: number): { any }
	local ok, pages = RetryAsync.run(function(): any
		return _leaderStore:GetSortedAsync(false, count)
	end, Constants.DS_MAX_RETRIES, Constants.DS_RETRY_DELAY)

	if not ok or pages == nil then
		return {}
	end

	local entries: { any } = {}
	local pageData = (pages :: DataStorePages):GetCurrentPage()
	for _, entry in pageData do
		table.insert(entries, entry)
	end
	return entries
end

-- ─── Settings_SetUIScale handler (T-092) ─────────────────────────────────────

local _Remotes = require(Shared.Remotes)

_Remotes.Settings_SetUIScale.OnServerEvent:Connect(function(player: Player, payload: any)
	local scale = payload and payload.scale
	if type(scale) ~= "number" then return end
	scale = math.clamp(scale, Constants.UI_SCALE_MIN, Constants.UI_SCALE_MAX)
	local data = DataService.get(player)
	if not data then return end
	data.uiScale = scale
end)

return DataService
