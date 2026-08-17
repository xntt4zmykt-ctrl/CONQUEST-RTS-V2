--!strict
--[[
	Point d'entree client : camera 2D, saisie des ordres, branchement reseau.

	Le client n'est jamais autoritaire. Chaque clic est traduit en intention et
	envoyee au serveur, qui repond par une notification en cas de refus. Aucune
	regle de jeu n'est evaluee ici — au pire l'interface propose une action que
	le serveur rejettera, jamais l'inverse.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(Shared:WaitForChild("Theme"))
local MapGen = require(Shared:WaitForChild("MapGen"))

-- Ce fichier est le LocalScript "Client" ; les modules voisins en sont les
-- enfants, pas les freres.
local MapRenderer = require(script.MapRenderer)
local Overlay = require(script.Overlay)
local Minimap = require(script.Minimap)
local VictoryScreen = require(script.VictoryScreen)
local SoundManager = require(script.SoundManager)
local HUD = require(script.HUD)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--=============================================================================
-- Racine de l'interface
--=============================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ConquestRTS"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Theme.color.void
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local viewport = Instance.new("Frame")
viewport.Name = "Viewport"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundTransparency = 1
viewport.ClipsDescendants = true
viewport.Parent = backdrop

local renderer: MapRenderer.MapRenderer? = nil
local overlay: Overlay.Overlay? = nil
local minimap: Minimap.Minimap? = nil

local hud = HUD.new(screenGui)
local victory = VictoryScreen.new(screenGui)

local mySlot = 0
-- Tuile de sa propre capitale : point de repere pour le recentrage clavier.
local myCapital: number? = nil
local roster = {}
local stats = {}
local matchPhase = "playing"

--=============================================================================
-- Camera 2D
--=============================================================================
-- Le zoom et le pan visent une cible, et la position affichee la rejoint par
-- interpolation. Un deplacement instantane sur une carte de 40 000 tuiles est
-- desorientant : on perd le fil de ou on etait.

local MIN_ZOOM, MAX_ZOOM = 1.5, 26

local zoom = 4
local targetZoom = 4
local panOffset = Vector2.zero
local targetPan = Vector2.zero

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

	local previous = targetZoom
	targetZoom = math.clamp(targetZoom * (1 + delta * 0.2), MIN_ZOOM, MAX_ZOOM)
	if targetZoom == previous then
		return
	end

	-- Zoom centre sur le curseur : on corrige le pan pour que la tuile sous la
	-- souris reste sous la souris. Sans ca, naviguer sur une grande carte est
	-- insupportable.
	local center = r.label.AbsolutePosition + r.label.AbsoluteSize / 2
	local toFocus = focus - center
	targetPan += toFocus - toFocus * (targetZoom / previous)
end

-- Centre la vue sur une tuile : utilise par la minimap et au spawn.
local function focusTile(index: number, instant: boolean?)
	local x, y = MapGen.fromIndex(index)
	local centreX = (x + 0.5 - Config.MAP_WIDTH / 2) * targetZoom
	local centreY = (y + 0.5 - Config.MAP_HEIGHT / 2) * targetZoom
	targetPan = Vector2.new(-centreX, -centreY)
	if instant then
		panOffset = targetPan
		zoom = targetZoom
		applyCamera()
	end
end

--=============================================================================
-- Saisie
--=============================================================================

local CLICK_DRAG_THRESHOLD = 6 -- px : au-dela, c'est un pan, pas un clic

--[[
	Un clic sur la carte n'a pas de sens en soi : son effet depend entierement
	du mode arme dans le HUD. C'est le seul endroit ou cette traduction a lieu.
]]
local function onTileClicked(index: number)
	local r = renderer
	if not r then
		return
	end

	local targetSlot = r:ownerAt(index)
	local mode = hud.mode

	if mode == "build" then
		Remotes.get("BuildOrder"):FireServer(index, hud.buildKind)
		return
	end

	if mode == "boat" then
		Remotes.get("BoatOrder"):FireServer(index)
		return
	end

	if mode == "nuke" then
		Remotes.get("NukeOrder"):FireServer(index, hud.nukeKind)
		return
	end

	-- Mode attaque : le clic sert aussi a designer l'interlocuteur
	-- diplomatique, pour qu'on puisse negocier avec un voisin sans le chercher
	-- dans le classement.
	if targetSlot ~= 0 and targetSlot ~= mySlot then
		hud:selectFaction(targetSlot)
	end

	if targetSlot == mySlot then
		hud:notify("Ce territoire est deja a toi.", "info")
		return
	end

	SoundManager.play("attackLaunch")
	Remotes.get("AttackOrder"):FireServer(targetSlot)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		panStart = targetPan
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		zoomAt(input.Position.Z, UserInputService:GetMouseLocation())
	elseif
		dragging
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then
		local current = Vector2.new(input.Position.X, input.Position.Y)
		targetPan = panStart + (current - dragStart)
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

-- Raccourcis clavier : les modes sont les actions les plus repetees de la
-- partie, les atteindre a la souris a chaque fois casse le rythme.
local MODE_KEYS: { [Enum.KeyCode]: HUD.Mode } = {
	[Enum.KeyCode.One] = "attack",
	[Enum.KeyCode.Two] = "boat",
	[Enum.KeyCode.Three] = "build",
	[Enum.KeyCode.Four] = "nuke",
}

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end

	local mode = MODE_KEYS[input.KeyCode]
	if mode then
		hud:setMode(mode)
		return
	end

	-- Espace : retour a sa capitale. Sur une grande carte, se reperer est la
	-- premiere friction, et c'est celle qui fatigue le plus.
	if input.KeyCode == Enum.KeyCode.Space and myCapital then
		focusTile(myCapital)
	end
end)

--=============================================================================
-- Callbacks du HUD
--=============================================================================

hud.onRatioChanged = function(ratio: number)
	Remotes.get("SetAttackRatio"):FireServer(ratio)
end

hud.onDoctrineChosen = function(doctrineId: number)
	Remotes.get("ChooseDoctrine"):FireServer(doctrineId)
end

hud.onDiplomacyAction = function(action: string, targetSlot: number)
	Remotes.get("DiplomacyOrder"):FireServer(action, targetSlot)
end

--=============================================================================
-- Reseau
--=============================================================================

Remotes.get("MapInit").OnClientEvent:Connect(function(seed: number, slot: number, initialRoster, capital: number?)
	mySlot = slot
	roster = initialRoster
	myCapital = capital
	matchPhase = "playing"

	if renderer then
		renderer.label:Destroy()
	end
	if overlay then
		overlay:clear()
	end
	if minimap then
		minimap:destroy()
		minimap = nil
	end
	victory:hide()

	-- Le rendu peut echouer si le moteur ne fournit pas les EditableImage : il
	-- affiche alors sa propre banniere d'erreur, et on evite simplement de
	-- construire les calques par dessus.
	local created = MapRenderer.new(seed, viewport)
	renderer = created

	if created then
		overlay = Overlay.new(created.label)
		minimap = Minimap.new(screenGui, created.label, function(index: number)
			focusTile(index)
		end)

		targetZoom = 6
		zoom = 6
		if capital then
			focusTile(capital, true)
		else
			applyCamera()
		end
	else
		overlay = nil
	end

	local entry = roster[slot]
	hud:setIdentity(
		slot,
		if entry then entry.name else player.DisplayName,
		if entry then entry.doctrine else 1,
		if entry then entry.betrayals else 0
	)
	hud:selectFaction(nil)
	hud:showDoctrineModal()
end)

Remotes.get("RosterUpdate").OnClientEvent:Connect(function(newRoster)
	roster = newRoster
	local entry = roster[mySlot]
	if entry then
		hud:setIdentity(mySlot, entry.name, entry.doctrine, entry.betrayals)
	end
end)

Remotes.get("StateDelta").OnClientEvent:Connect(function(delta: buffer?, newStats)
	stats = newStats
	if delta and renderer then
		local changed = (renderer :: MapRenderer.MapRenderer):applyDelta(delta)
		-- Un seul son par vague de captures, pas un par tuile : le bridage du
		-- SoundManager fait le reste.
		if changed > 0 then
			SoundManager.play("tileCapture")
		end
	end
	hud:update(stats, roster)
end)

Remotes.get("BuildingDelta").OnClientEvent:Connect(function(deltas)
	if overlay then
		(overlay :: Overlay.Overlay):applyBuildingDelta(deltas)
	end
end)

Remotes.get("UnitSnapshot").OnClientEvent:Connect(function(boats, missiles)
	if overlay then
		(overlay :: Overlay.Overlay):applyUnits(boats, missiles)
	end
end)

Remotes.get("DiplomacyUpdate").OnClientEvent:Connect(function(diplomacy)
	hud:setDiplomacy(diplomacy)
end)

Remotes.get("MatchUpdate").OnClientEvent:Connect(function(match)
	hud:setMatch(match)

	if match.phase == "ended" then
		matchPhase = "ended"
		victory:show(match.winner, match.winnerName, hud.ranked, roster, mySlot)
		victory:setCountdown(match.restartIn or 0)
	elseif matchPhase == "ended" then
		matchPhase = "playing"
		victory:hide()
	end
end)

Remotes.get("Notify").OnClientEvent:Connect(function(text: string, kind: string)
	hud:notify(text, kind)
end)

Remotes.get("Explosion").OnClientEvent:Connect(function(x: number, y: number, radius: number)
	if overlay then
		(overlay :: Overlay.Overlay):explosion(x, y, radius)
	end
	SoundManager.play("nukeImpact")
end)

Remotes.get("Sfx").OnClientEvent:Connect(function(name: string)
	SoundManager.play(name)
end)

--=============================================================================
-- Boucle de rendu
--=============================================================================

RunService.RenderStepped:Connect(function(dt: number)
	-- Lissage exponentiel encadre : `1 - e^(-k*dt)` reste correct quel que
	-- soit le framerate, contrairement a un simple `dt * k` qui devient
	-- instable en dessous de 30 FPS.
	local alpha = 1 - math.exp(-14 * dt)
	local moved = false

	if math.abs(targetZoom - zoom) > 0.001 then
		zoom += (targetZoom - zoom) * alpha
		moved = true
	end
	if (targetPan - panOffset).Magnitude > 0.5 then
		panOffset += (targetPan - panOffset) * alpha
		moved = true
	end
	if moved then
		applyCamera()
	end

	local r = renderer
	if r then
		r:stepHeat(dt)
		r:flush()
	end

	local o = overlay
	if o then
		o:stepInterpolation(dt)
	end

	local m = minimap
	if m and r then
		m:sync(r.label, viewport)
	end
end)
