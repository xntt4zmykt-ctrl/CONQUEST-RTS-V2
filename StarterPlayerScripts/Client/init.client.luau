--!strict
-- Point d'entree client : interface, camera 2D (pan/zoom) et saisie des ordres.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
-- Meme logique que cote serveur : ce fichier est le LocalScript "Client", les
-- modules voisins en sont les enfants.
local MapRenderer = require(script.MapRenderer)
local HUD = require(script.HUD)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ConquestRTS"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Fond opaque : la carte est du pur 2D pour l'instant, le monde 3D derriere
-- n'a rien a montrer.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local viewport = Instance.new("Frame")
viewport.Name = "Viewport"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundTransparency = 1
viewport.ClipsDescendants = true
viewport.Parent = backdrop

local renderer: MapRenderer.MapRenderer? = nil
local mySlot = 0
local roster: { [number]: { name: string, isBot: boolean } } = {}
local stats: { [number]: { troops: number, tiles: number } } = {}

local hud = HUD.new(screenGui)

--=============================================================================
-- Camera 2D
--=============================================================================

local MIN_ZOOM, MAX_ZOOM = 1.5, 24
local zoom = 4
local panOffset = Vector2.zero
local dragging = false
local dragStart = Vector2.zero
local panStart = Vector2.zero

local function applyCamera()
	local r = renderer
	if not r then
		return
	end
	r.label.Size = UDim2.fromOffset(Config.MAP_WIDTH * zoom, Config.MAP_HEIGHT * zoom)
	r.label.Position = UDim2.new(0.5, panOffset.X, 0.5, panOffset.Y)
end

local function zoomAt(delta: number, focus: Vector2)
	local r = renderer
	if not r then
		return
	end

	local oldZoom = zoom
	zoom = math.clamp(zoom * (1 + delta * 0.18), MIN_ZOOM, MAX_ZOOM)
	if zoom == oldZoom then
		return
	end

	-- Zoom centre sur le curseur : on corrige le pan pour que la tuile sous la
	-- souris reste sous la souris. Sans ca, naviguer sur une grande carte est
	-- insupportable.
	local center = r.label.AbsolutePosition + r.label.AbsoluteSize / 2
	local toFocus = focus - center
	local scale = zoom / oldZoom
	panOffset += toFocus - toFocus * scale

	applyCamera()
end

--=============================================================================
-- Saisie
--=============================================================================

local CLICK_DRAG_THRESHOLD = 6 -- px : au-dela, c'est un pan, pas un clic

local function onTileClicked(index: number)
	local r = renderer
	if not r then
		return
	end

	local targetSlot = r:ownerAt(index)
	if targetSlot == mySlot then
		hud:setStatus("Ce territoire est deja a toi.")
		return
	end

	-- On n'envoie qu'une intention : le serveur decide si le contact existe.
	Remotes.get("AttackOrder"):FireServer(targetSlot)

	local name = if targetSlot == Config.NEUTRAL_SLOT
		then "territoire neutre"
		else (roster[targetSlot] and roster[targetSlot].name or "faction inconnue")
	hud:setStatus(`Offensive lancee sur {name}`)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		panStart = panOffset
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		local mouse = UserInputService:GetMouseLocation()
		zoomAt(input.Position.Z, mouse)
	elseif
		dragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then
		local current = Vector2.new(input.Position.X, input.Position.Y)
		panOffset = panStart + (current - dragStart)
		applyCamera()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if not dragging then
		return
	end
	dragging = false

	local endPos = Vector2.new(input.Position.X, input.Position.Y)
	if (endPos - dragStart).Magnitude > CLICK_DRAG_THRESHOLD then
		return -- c'etait un deplacement de camera
	end

	local r = renderer
	if r then
		local index = r:tileAtScreen(endPos)
		if index then
			onTileClicked(index)
		end
	end
end)

hud.onRatioChanged = function(ratio: number)
	Remotes.get("SetAttackRatio"):FireServer(ratio)
end

--=============================================================================
-- Reseau
--=============================================================================

Remotes.get("MapInit").OnClientEvent:Connect(function(seed: number, slot: number, initialRoster)
	mySlot = slot
	roster = initialRoster

	if renderer then
		renderer.label:Destroy()
	end
	renderer = MapRenderer.new(seed, viewport)
	applyCamera()

	hud:setIdentity(slot, roster[slot] and roster[slot].name or player.DisplayName)
	hud:setStatus("Clique sur un territoire voisin pour l'attaquer.")
end)

Remotes.get("RosterUpdate").OnClientEvent:Connect(function(newRoster)
	roster = newRoster
end)

Remotes.get("StateDelta").OnClientEvent:Connect(function(delta: buffer?, newStats)
	stats = newStats
	if delta and renderer then
		renderer:applyDelta(delta)
	end
end)

RunService.RenderStepped:Connect(function()
	local r = renderer
	if r then
		r:flush()
	end
	hud:update(mySlot, stats, roster)
end)
