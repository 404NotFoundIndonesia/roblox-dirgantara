--[[
    AudioController.luau
    ─────────────────────
    Client-side Kegelapan visuals and audio crossfade. Covers T-040.

    Listens to:
        Kegelapan_ZoneState_S2C { zoneId, entered }   — zone enter / exit
        Kegelapan_DimState_S2C  { dimmed, [userId] }  — self or nearby player dim

    Sound setup (Studio)
    ────────────────────
    Add Sound instances directly under SoundService:
        "Ambient"          — normal background music
        "KegelapanTension" — atonal drone played in darkness zones

    Character light dimming
    ────────────────────────
    Any PointLight or SurfaceLight parented anywhere inside a player's character
    model will be dimmed when that player activates self-dim, and restored on
    toggle-off or character respawn.
]]

local Lighting          = game:GetService("Lighting")
local Players           = game:GetService("Players")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local LocalPlayer = Players.LocalPlayer

local AudioController = {}

-- ─── Audio crossfade ──────────────────────────────────────────────────────────

local FADE_TIME = 1.5   -- seconds

local function findSound(name: string): Sound?
	return SoundService:FindFirstChild(name) :: Sound?
end

local function crossfadeTo(targetName: string, fadeName: string)
	local target = findSound(targetName)
	local fade   = findSound(fadeName)

	if target then
		target.Volume = 0
		target:Play()
		TweenService:Create(target, TweenInfo.new(FADE_TIME), { Volume = 1 }):Play()
	end

	if fade then
		local fadeTween = TweenService:Create(fade, TweenInfo.new(FADE_TIME), { Volume = 0 })
		fadeTween:Play()
		fadeTween.Completed:Once(function()
			if fade.Volume == 0 then
				fade:Stop()
			end
		end)
	end
end

-- ─── ColorCorrectionEffect ────────────────────────────────────────────────────

local DARKNESS_SATURATION = -0.7
local DARKNESS_BRIGHTNESS = -0.3
local DARKNESS_CONTRAST   =  0.2
local NORMAL_SATURATION   =  0
local NORMAL_BRIGHTNESS   =  0
local NORMAL_CONTRAST     =  0

local _colorEffect: ColorCorrectionEffect? = nil
local _colorTween:  Tween?                 = nil

local function getColorEffect(): ColorCorrectionEffect
	if not _colorEffect then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name       = "KegelapanColorCorrection"
		effect.Saturation = NORMAL_SATURATION
		effect.Brightness = NORMAL_BRIGHTNESS
		effect.Contrast   = NORMAL_CONTRAST
		effect.Parent     = Lighting
		_colorEffect      = effect
	end
	return _colorEffect :: ColorCorrectionEffect
end

local function tweenColor(saturation: number, brightness: number, contrast: number)
	if _colorTween then
		_colorTween:Cancel()
	end
	local effect = getColorEffect()
	_colorTween = TweenService:Create(effect, TweenInfo.new(FADE_TIME), {
		Saturation = saturation,
		Brightness = brightness,
		Contrast   = contrast,
	})
	_colorTween:Play()
end

-- ─── Character light dimming ──────────────────────────────────────────────────

local DIM_BRIGHTNESS = 0

type LightRecord = { light: Instance, original: number }

local _savedLights: { [number]: { LightRecord } } = {}

local function dimCharacter(userId: number, char: Model, dimmed: boolean)
	if dimmed then
		local records: { LightRecord } = {}
		for _, desc in char:GetDescendants() do
			if desc:IsA("PointLight") or desc:IsA("SurfaceLight") then
				local light = desc :: PointLight
				table.insert(records, { light = desc, original = light.Brightness })
				TweenService:Create(desc, TweenInfo.new(FADE_TIME), { Brightness = DIM_BRIGHTNESS }):Play()
			end
		end
		_savedLights[userId] = records
	else
		local records = _savedLights[userId]
		if records then
			for _, rec in records do
				if rec.light and rec.light.Parent then
					TweenService:Create(rec.light, TweenInfo.new(FADE_TIME), { Brightness = rec.original }):Play()
				end
			end
		end
		_savedLights[userId] = nil
	end
end

-- ─── Zone state ───────────────────────────────────────────────────────────────

local _activeZoneCount = 0

local function onZoneState(payload: any)
	if type(payload) ~= "table" then return end
	local entered = payload.entered == true

	if entered then
		_activeZoneCount += 1
		if _activeZoneCount == 1 then
			crossfadeTo("KegelapanTension", "Ambient")
			tweenColor(DARKNESS_SATURATION, DARKNESS_BRIGHTNESS, DARKNESS_CONTRAST)
		end
	else
		_activeZoneCount = math.max(0, _activeZoneCount - 1)
		if _activeZoneCount == 0 then
			crossfadeTo("Ambient", "KegelapanTension")
			tweenColor(NORMAL_SATURATION, NORMAL_BRIGHTNESS, NORMAL_CONTRAST)
		end
	end
end

-- ─── Dim state ────────────────────────────────────────────────────────────────

local function onDimState(payload: any)
	if type(payload) ~= "table" then return end
	local dimmed       = payload.dimmed == true
	local targetUserId = payload.userId

	if type(targetUserId) == "number" then
		-- Nearby player toggled dim
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target then return end
		local char = target.Character
		if not char then return end
		dimCharacter(targetUserId, char, dimmed)
	else
		-- Local player's own state
		local char = LocalPlayer.Character
		if not char then return end
		dimCharacter(LocalPlayer.UserId, char, dimmed)
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

local _connections: { RBXScriptConnection } = {}

function AudioController.start()
	local c1 = Remotes.Kegelapan_ZoneState_S2C.OnClientEvent:Connect(onZoneState)
	local c2 = Remotes.Kegelapan_DimState_S2C.OnClientEvent:Connect(onDimState)
	table.insert(_connections, c1)
	table.insert(_connections, c2)

	-- Clear saved lights on respawn so stale records don't persist
	local c3 = LocalPlayer.CharacterAdded:Connect(function()
		_savedLights[LocalPlayer.UserId] = nil
	end)
	table.insert(_connections, c3)
end

function AudioController.stop()
	for _, conn in _connections do
		conn:Disconnect()
	end
	table.clear(_connections)

	if _colorEffect then
		_colorEffect:Destroy()
		_colorEffect = nil
	end

	_activeZoneCount = 0
	table.clear(_savedLights)
end

return AudioController
