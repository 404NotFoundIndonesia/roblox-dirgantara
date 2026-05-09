--[[
    InventoryPanel.luau
    ─────────────────────
    Emote slot management panel (T-079).
    Full multi-category inventory browser added in Phase 15 (T-085).

    Public API
    ──────────
    InventoryPanel.openEmotes()                      -- open to emote slot view
    InventoryPanel.close()
    InventoryPanel.setSlots(slots: { string })       -- update slot display
    InventoryPanel.setOwnedEmotes(ids: { string })   -- called by EmoteController on sync
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local Remotes      = require(Shared.Remotes)
local CosmeticDefs = require(Shared.CosmeticDefs)
local Constants    = require(Shared.Constants)

local InventoryPanel = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local _gui:          ScreenGui?   = nil
local _slots:        { string }   = {}   -- current equipped emote slots (1-8)
local _ownedEmotes:  { string }   = {}   -- owned emote itemIds

-- Drag state (PC drag-to-slot)
local _dragEmoteId:  string       = ""
local _dragGhost:    Frame?       = nil
local _dragConn:     RBXScriptConnection? = nil

-- Two-tap state (mobile / fallback)
local _selectedEmote: string      = ""

-- References into the live GUI
local _slotButtons:  { TextButton } = {}
local _emoteTiles:   { [string]: TextButton } = {}

local _isMobile = UserInputService:IsTouchEnabled()
               and not UserInputService:IsKeyboardEnabled()

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function getEmoteName(emoteId: string): string
	if emoteId == "" then return "" end
	local def = (CosmeticDefs :: any)[emoteId] :: any
	return if def then (def.nameKey or emoteId) else emoteId
end

local function roundify(inst: Instance, radius: number?)
	local c           = Instance.new("UICorner")
	c.CornerRadius    = UDim.new(0, radius or 8)
	c.Parent          = inst
end

local function makeLabel(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local l                  = Instance.new("TextLabel")
	l.Size                   = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text                   = text
	l.TextSize               = size
	l.Font                   = Enum.Font.GothamMedium
	l.TextColor3             = color
	l.TextWrapped            = true
	l.TextXAlignment         = Enum.TextXAlignment.Center
	l.TextYAlignment         = Enum.TextYAlignment.Center
	l.Parent                 = parent
	return l
end

-- ─── Assign emote to slot (fires remote, updates local display) ───────────────

local function assignToSlot(slotIndex: number, emoteId: string)
	if slotIndex < 1 or slotIndex > Constants.EMOTE_SLOT_COUNT then return end

	_slots[slotIndex] = emoteId

	-- Update slot button label
	local btn = _slotButtons[slotIndex]
	if btn then
		local lbl = btn:FindFirstChildOfClass("TextLabel") :: TextLabel?
		if lbl then
			lbl.Text = if emoteId ~= "" then string.sub(getEmoteName(emoteId), 1, 8) else tostring(slotIndex)
		end
		btn.BackgroundColor3 = if emoteId ~= ""
			then Color3.fromRGB(60, 120, 200)
			else Color3.fromRGB(45, 45, 60)
	end

	Remotes.Cosmetic_EquipRequest:FireServer({
		slot   = "emoteSlot_" .. slotIndex,
		itemId = emoteId,
	})
end

-- ─── Slot button interaction ──────────────────────────────────────────────────

local function onSlotClicked(slotIndex: number)
	if _selectedEmote ~= "" then
		-- Two-tap: assign selected emote to this slot
		assignToSlot(slotIndex, _selectedEmote)
		_selectedEmote = ""
		-- Clear highlight on all tiles
		for _, tile in _emoteTiles do
			tile.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
		end
	end
end

-- ─── Drag-to-slot (PC) ───────────────────────────────────────────────────────

local function startDrag(emoteId: string, startPos: Vector2)
	_dragEmoteId = emoteId

	-- Ghost frame that follows cursor
	local ghost              = Instance.new("Frame")
	ghost.Name               = "DragGhost"
	ghost.Size               = UDim2.fromOffset(80, 32)
	ghost.AnchorPoint        = Vector2.new(0.5, 0.5)
	ghost.Position           = UDim2.fromOffset(startPos.X, startPos.Y)
	ghost.BackgroundColor3   = Color3.fromRGB(80, 140, 220)
	ghost.BackgroundTransparency = 0.3
	ghost.ZIndex             = 50
	ghost.Parent             = _gui
	roundify(ghost, 6)
	makeLabel(ghost, string.sub(getEmoteName(emoteId), 1, 10), 11, Color3.new(1,1,1))

	_dragGhost = ghost

	-- Track mouse movement
	_dragConn = UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			ghost.Position = UDim2.fromOffset(input.Position.X, input.Position.Y)
		end
	end)
end

local function endDrag(dropPos: Vector2)
	if _dragConn then
		_dragConn:Disconnect()
		_dragConn = nil
	end
	if _dragGhost then
		_dragGhost:Destroy()
		_dragGhost = nil
	end

	if _dragEmoteId == "" then return end

	-- Check which slot button is under the drop position
	local guiService = game:GetService("GuiService")
	local objects    = guiService:GetGuiObjectsAtPosition(dropPos.X, dropPos.Y)
	for _, obj in objects do
		for slotIdx, btn in _slotButtons do
			if obj == btn then
				assignToSlot(slotIdx, _dragEmoteId)
				break
			end
		end
	end

	_dragEmoteId = ""
end

-- ─── Build GUI ────────────────────────────────────────────────────────────────

local function buildPanel()
	if _gui then
		_gui:Destroy()
		_gui         = nil
		_slotButtons = {}
		_emoteTiles  = {}
	end

	local gui            = Instance.new("ScreenGui")
	gui.Name             = "InventoryPanel_Emotes"
	gui.ResetOnSpawn     = false
	gui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder     = 25
	gui.Parent           = PlayerGui
	_gui = gui

	-- Panel frame (centred)
	local panel             = Instance.new("Frame")
	panel.AnchorPoint       = Vector2.new(0.5, 0.5)
	panel.Size              = UDim2.fromOffset(480, 420)
	panel.Position          = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3  = Color3.fromRGB(28, 28, 38)
	panel.BackgroundTransparency = 0.1
	panel.Parent            = gui
	roundify(panel, 12)

	-- Title
	local title             = Instance.new("TextLabel")
	title.Size              = UDim2.new(1, -44, 0, 36)
	title.Position          = UDim2.fromOffset(12, 8)
	title.BackgroundTransparency = 1
	title.Text              = "EMOTE SLOTS"
	title.TextSize          = 18
	title.Font              = Enum.Font.GothamBold
	title.TextColor3        = Color3.new(1, 1, 1)
	title.TextXAlignment    = Enum.TextXAlignment.Left
	title.Parent            = panel

	-- Close button
	local closeBtn          = Instance.new("TextButton")
	closeBtn.Size           = UDim2.fromOffset(32, 32)
	closeBtn.Position       = UDim2.new(1, -40, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.Text           = "✕"
	closeBtn.TextSize       = 16
	closeBtn.Font           = Enum.Font.GothamBold
	closeBtn.TextColor3     = Color3.new(1, 1, 1)
	closeBtn.Parent         = panel
	roundify(closeBtn, 6)
	closeBtn.MouseButton1Click:Connect(function()
		InventoryPanel.close()
	end)

	-- ── Slot row (top) ────────────────────────────────────────────────────────

	local slotHeader        = Instance.new("TextLabel")
	slotHeader.Size         = UDim2.new(1, -24, 0, 20)
	slotHeader.Position     = UDim2.fromOffset(12, 52)
	slotHeader.BackgroundTransparency = 1
	slotHeader.Text         = "Equipped Slots  (tap slot after selecting emote)"
	slotHeader.TextSize     = 12
	slotHeader.Font         = Enum.Font.GothamMedium
	slotHeader.TextColor3   = Color3.fromRGB(160, 160, 180)
	slotHeader.TextXAlignment = Enum.TextXAlignment.Left
	slotHeader.Parent       = panel

	local slotRow           = Instance.new("Frame")
	slotRow.Size            = UDim2.new(1, -24, 0, 52)
	slotRow.Position        = UDim2.fromOffset(12, 76)
	slotRow.BackgroundTransparency = 1
	slotRow.Parent          = panel

	local slotLayout              = Instance.new("UIListLayout")
	slotLayout.FillDirection      = Enum.FillDirection.Horizontal
	slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	slotLayout.VerticalAlignment  = Enum.VerticalAlignment.Center
	slotLayout.Padding            = UDim.new(0, 4)
	slotLayout.Parent             = slotRow

	for i = 1, Constants.EMOTE_SLOT_COUNT do
		local emoteId = _slots[i] or ""

		local btn             = Instance.new("TextButton")
		btn.Name              = "Slot_" .. i
		btn.Size              = UDim2.fromOffset(52, 48)
		btn.BackgroundColor3  = if emoteId ~= ""
			then Color3.fromRGB(60, 120, 200)
			else Color3.fromRGB(45, 45, 60)
		btn.Text              = ""
		btn.Parent            = slotRow
		roundify(btn, 6)

		local lbl = makeLabel(btn,
			if emoteId ~= "" then string.sub(getEmoteName(emoteId), 1, 8) else tostring(i),
			10, Color3.new(1, 1, 1))
		lbl.TextWrapped = true

		local slotIdx = i
		btn.MouseButton1Click:Connect(function()
			onSlotClicked(slotIdx)
		end)

		_slotButtons[i] = btn
	end

	-- ── Emote list (scrollable) ───────────────────────────────────────────────

	local listHeader        = Instance.new("TextLabel")
	listHeader.Size         = UDim2.new(1, -24, 0, 20)
	listHeader.Position     = UDim2.fromOffset(12, 140)
	listHeader.BackgroundTransparency = 1
	listHeader.Text         = if _isMobile
		then "Tap emote → tap slot to assign"
		else "Click to select, then click slot  |  Drag to slot"
	listHeader.TextSize     = 12
	listHeader.Font         = Enum.Font.GothamMedium
	listHeader.TextColor3   = Color3.fromRGB(160, 160, 180)
	listHeader.TextXAlignment = Enum.TextXAlignment.Left
	listHeader.Parent       = panel

	local scroll            = Instance.new("ScrollingFrame")
	scroll.Size             = UDim2.new(1, -24, 0, 226)
	scroll.Position         = UDim2.fromOffset(12, 166)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 140)
	scroll.CanvasSize       = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent           = panel

	local grid              = Instance.new("UIGridLayout")
	grid.CellSize           = UDim2.fromOffset(108, 52)
	grid.CellPadding        = UDim2.fromOffset(6, 6)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent             = scroll

	local padding           = Instance.new("UIPadding")
	padding.PaddingTop      = UDim.new(0, 4)
	padding.PaddingLeft     = UDim.new(0, 4)
	padding.Parent          = scroll

	_emoteTiles = {}
	for _, emoteId in _ownedEmotes do
		local tile             = Instance.new("TextButton")
		tile.Name              = emoteId
		tile.Size              = UDim2.fromOffset(108, 52)
		tile.BackgroundColor3  = Color3.fromRGB(38, 38, 52)
		tile.Text              = ""
		tile.Parent            = scroll
		roundify(tile, 6)

		makeLabel(tile, string.sub(getEmoteName(emoteId), 1, 14), 11, Color3.new(1,1,1))

		local capturedId = emoteId

		-- Click/tap → select (two-tap flow)
		tile.MouseButton1Click:Connect(function()
			_selectedEmote = capturedId

			-- Highlight selected, clear others
			for id, t in _emoteTiles do
				t.BackgroundColor3 = if id == capturedId
					then Color3.fromRGB(70, 140, 220)
					else Color3.fromRGB(38, 38, 52)
			end
		end)

		-- PC drag-to-slot
		if not _isMobile then
			tile.MouseButton1Down:Connect(function()
				local mousePos = UserInputService:GetMouseLocation()
				startDrag(capturedId, mousePos)
			end)

			tile.MouseButton1Up:Connect(function()
				if _dragEmoteId ~= "" then
					local dropPos = UserInputService:GetMouseLocation()
					endDrag(dropPos)
				end
			end)
		end

		_emoteTiles[emoteId] = tile
	end

	-- Global mouse-up handler to end drag if released outside a tile
	if not _isMobile then
		local conn: RBXScriptConnection
		conn = UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				if _dragEmoteId ~= "" then
					endDrag(UserInputService:GetMouseLocation())
				end
				conn:Disconnect()
			end
		end)
	end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function InventoryPanel.setSlots(slots: { string })
	_slots = {}
	for i = 1, Constants.EMOTE_SLOT_COUNT do
		_slots[i] = slots[i] or ""
	end

	-- Refresh slot buttons if panel is open
	for i, btn in _slotButtons do
		local emoteId = _slots[i] or ""
		local lbl = btn:FindFirstChildOfClass("TextLabel") :: TextLabel?
		if lbl then
			lbl.Text = if emoteId ~= "" then string.sub(getEmoteName(emoteId), 1, 8) else tostring(i)
		end
		btn.BackgroundColor3 = if emoteId ~= ""
			then Color3.fromRGB(60, 120, 200)
			else Color3.fromRGB(45, 45, 60)
	end
end

function InventoryPanel.setOwnedEmotes(ids: { string })
	_ownedEmotes = ids
end

function InventoryPanel.openEmotes()
	buildPanel()
end

function InventoryPanel.open()
	InventoryPanel.openEmotes()
end

function InventoryPanel.close()
	if _dragConn then
		_dragConn:Disconnect()
		_dragConn = nil
	end
	if _dragGhost then
		_dragGhost:Destroy()
		_dragGhost = nil
	end
	if _gui then
		_gui:Destroy()
		_gui         = nil
		_slotButtons = {}
		_emoteTiles  = {}
	end
	_dragEmoteId   = ""
	_selectedEmote = ""
end

return InventoryPanel
