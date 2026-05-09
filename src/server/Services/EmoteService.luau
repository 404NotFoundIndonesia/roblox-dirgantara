--[[
    EmoteService.luau
    ───────────────────
    Stub — full implementation in TASKS.md Phase 12 (T-075 / T-076).

    BindableEvents exposed for DailyTaskService:
        EmoteService.EmoteUsedNearPlayer — Fire(player, { amount = 1 })
]]

local EmoteService = {}

-- ─── BindableEvents ───────────────────────────────────────────────────────────

local _emoteNearPlayerEvent = Instance.new("BindableEvent")
_emoteNearPlayerEvent.Name  = "EmoteUsedNearPlayer"
EmoteService.EmoteUsedNearPlayer = _emoteNearPlayerEvent

-- ─── Service lifecycle ────────────────────────────────────────────────────────

function EmoteService.init(_: Player)
end

function EmoteService.cleanup(_: Player)
end

return EmoteService
