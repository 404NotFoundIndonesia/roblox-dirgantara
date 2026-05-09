--[[
    InstrumentService.luau
    ────────────────────────
    Stub — full implementation in TASKS.md Phase 11 (T-070 / T-071).

    BindableEvents exposed for DailyTaskService:
        InstrumentService.InstrumentPlayed  — Fire(player, { amount: seconds })
        InstrumentService.HarmoniActive     — Fire(player, { playerCount, duration })
]]

local InstrumentService = {}

-- ─── BindableEvents ───────────────────────────────────────────────────────────

local _instrumentPlayedEvent = Instance.new("BindableEvent")
_instrumentPlayedEvent.Name  = "InstrumentPlayed"
InstrumentService.InstrumentPlayed = _instrumentPlayedEvent

local _harmoniActiveEvent = Instance.new("BindableEvent")
_harmoniActiveEvent.Name  = "HarmoniActive"
InstrumentService.HarmoniActive = _harmoniActiveEvent

-- ─── Service lifecycle ────────────────────────────────────────────────────────

function InstrumentService.init(_: Player)
end

function InstrumentService.cleanup(_: Player)
end

return InstrumentService
