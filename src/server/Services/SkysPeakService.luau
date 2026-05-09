--[[
    SkysPeakService.luau
    ──────────────────────
    Stub — full implementation in TASKS.md Phase 14 (T-086 through T-089).

    BindableEvents exposed for DailyTaskService:
        SkysPeakService.SkysPeakReached — Fire(player)
]]

local SkysPeakService = {}

-- ─── BindableEvents ───────────────────────────────────────────────────────────

local _skysPeakReachedEvent = Instance.new("BindableEvent")
_skysPeakReachedEvent.Name  = "SkysPeakReached"
SkysPeakService.SkysPeakReached = _skysPeakReachedEvent

-- ─── Service lifecycle ────────────────────────────────────────────────────────

function SkysPeakService.init(_: Player)
end

function SkysPeakService.cleanup(_: Player)
end

-- Stub for SkysPeakService.isRunActive used by WingService
function SkysPeakService.isRunActive(_: Player): boolean
	return false
end

return SkysPeakService
