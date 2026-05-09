--[[
    init.client.luau
    ────────────────
    Client bootstrap. Boots all controllers in the order defined in PRD §1.3.
    Waits for character load before starting gameplay controllers.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- ─── Shared modules ───────────────────────────────────────────────────────────
local Shared   = ReplicatedStorage:WaitForChild("Shared")
local _Remotes = require(Shared.Remotes)   -- ensures Remotes folder is found

-- ─── Controllers ──────────────────────────────────────────────────────────────
local Controllers = script.Controllers

-- InputController and UIController start immediately (no character needed)
local InputController      = require(Controllers.InputController)
local UIController         = require(Controllers.UIController)

-- Gameplay controllers start after character is available
local FlightController     = require(Controllers.FlightController)
local CameraController     = require(Controllers.CameraController)
local AudioController      = require(Controllers.AudioController)
local CosmeticController   = require(Controllers.CosmeticController)
local InstrumentController = require(Controllers.InstrumentController)
local EmoteController      = require(Controllers.EmoteController)

-- ─── Startup order ────────────────────────────────────────────────────────────

-- Phase 1: start UI/input immediately
InputController.start()
UIController.start()

-- Phase 2: wait for character, then start gameplay controllers
local function onCharacterAdded(_character: Model)
	FlightController.start()
	CameraController.start()
	AudioController.start()
	CosmeticController.start()
	InstrumentController.start()
	EmoteController.start()
end

if LocalPlayer.Character then
	-- Character already exists (Studio play-test)
	task.spawn(onCharacterAdded, LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
