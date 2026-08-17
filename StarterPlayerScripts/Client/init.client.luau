--!strict
--[[
	Point d'entree client : monde 3D, camera, saisie des ordres, reseau.

	Le client n'est jamais autoritaire. Chaque clic est traduit en intention et
	envoyee au serveur, qui repond par une notification en cas de refus. Aucune
	regle de jeu n'est evaluee ici — au pire l'interface propose une action que
	le serveur rejettera, jamais l'inverse.

	Le joueur a deux facons d'habiter la carte : la vue strategique en survol
	(par defaut) et son propre avatar, pose sur sa capitale. La touche F bascule
	entre les deux.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))

-- Ce fichier est le LocalScript "Client" ; les modules voisins en sont les
-- enfants, pas les freres.
local WorldRenderer = require(script.WorldRenderer)
local WorldCamera = require(script.WorldCamera)
local Overlay = require(script.Overlay)
local Effects = require(script.Effects)
local PlacementPreview = require(script.PlacementPreview)
local MainMenu = require(script.MainMenu)
local Intro = require(script.Intro)
local Minimap = require(script.Minimap)
local VictoryScreen = require(script.VictoryScreen)
local SoundManager = require(script.SoundManager)
local HUD = require(script.HUD)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--=============================================================================
-- Interface
--=============================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ConquestRTS"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local hud = HUD.new(screenGui)
local victory = VictoryScreen.new(screenGui)
local intro = Intro.new(screenGui)
local menu = MainMenu.new(screenGui)

-- L'interface de jeu reste masquee tant que le joueur n'est pas deploye.
hud.root.Visible = false

local world: WorldRenderer.WorldRenderer? = nil
local overlay: Overlay.Overlay? = nil
local effects: Effects.Effects? = nil
local preview: PlacementPreview.PlacementPreview? = nil
local minimap: Minimap.Minimap? = nil
local camera = WorldCamera.new()

local mySlot = 0
-- Tuile de sa propre capitale : point de repere du recentrage et lieu de spawn.
local myCapital: number? = nil
local roster = {}
local stats = {}
local matchPhase = "playing"
local myNation = 1
local deployed = false
local worldReady = false

--=============================================================================
-- Ambiance
--=============================================================================
-- Reglee ici plutot que dans le fichier de projet : le client est le seul a
-- savoir qu'on regarde une carte vue du ciel et pas un niveau au sol.

Lighting.Ambient = Color3.fromRGB(92, 100, 116)
Lighting.OutdoorAmbient = Color3.fromRGB(112, 122, 140)
Lighting.Brightness = 2.4
Lighting.ClockTime = 15.2
Lighting.GeographicLatitude = 20
Lighting.FogEnd = 4000

--=============================================================================
-- Avatar
--=============================================================================

--[[
	Pose le personnage sur sa capitale.

	Le serveur decide ou, mais c'est le client qui doit le faire au bon moment :
	le personnage peut apparaitre avant ou apres la construction du monde, et le
	deposer avant que le sol existe le fait tomber dans le vide.
]]
local function placeCharacterAtCapital()
	local w = world
	local capital = myCapital
	if not w or not capital then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	root.CFrame = WorldSpace.spawnCFrame(w.terrain, capital)
end

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.2)
	placeCharacterAtCapital()
end)

--=============================================================================
-- Saisie
--=============================================================================

local CLICK_DRAG_THRESHOLD = 8 -- px : au-dela, c'etait un deplacement de vue
local pressOrigin: Vector2? = nil

--[[
	Un clic sur le monde n'a pas de sens en soi : son effet depend entierement
	du mode arme dans le HUD. C'est le seul endroit ou cette traduction a lieu.
]]
local function onTileClicked(index: number)
	local w = world
	if not w then
		return
	end

	local targetSlot = w:ownerAt(index)
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
	-- diplomatique, pour negocier avec un voisin sans le chercher dans le
	-- classement.
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
		pressOrigin = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local origin = pressOrigin
	pressOrigin = nil
	if not origin or processed then
		return
	end

	local endPos = Vector2.new(input.Position.X, input.Position.Y)
	if (endPos - origin).Magnitude > CLICK_DRAG_THRESHOLD then
		return
	end

	local w = world
	if w and deployed and worldReady and camera.mode == "overview" then
		local index = camera:tileAtScreen(endPos, w.root)
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

	-- Retour a sa capitale. Sur un monde de 1024 studs, se reperer est la
	-- premiere friction, et celle qui fatigue le plus.
	if input.KeyCode == Enum.KeyCode.Space and myCapital then
		camera:focusTile(myCapital)
		return
	end

	-- Bascule survol / avatar.
	if input.KeyCode == Enum.KeyCode.F then
		camera:toggleMode()
		if camera.mode == "avatar" then
			placeCharacterAtCapital()
			hud:notify("Vue avatar — F pour revenir au survol.", "info")
		else
			hud:notify("Vue strategique.", "info")
		end
		return
	end

	-- Defilement par les bords : pratique a la souris, genant au clavier.
	if input.KeyCode == Enum.KeyCode.G then
		camera.edgePan = not camera.edgePan
		hud:notify(
			if camera.edgePan then "Defilement par les bords active." else "Defilement par les bords desactive.",
			"info"
		)
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

hud.onResearch = function()
	Remotes.get("ResearchOrder"):FireServer()
end

hud.onBuildKindChanged = function(kind: number)
	local p = preview
	if p and hud.mode == "build" then
		p:setKind(kind)
	end
end

hud.onModeChanged = function(mode: string)
	local p = preview
	if not p then
		return
	end
	if mode == "build" then
		p:setKind(hud.buildKind)
	else
		p:hide()
	end
end

menu.onDeploy = function(nationId: number, modeId: string)
	myNation = nationId
	deployed = true
	intro:show(nationId)
	Remotes.get("JoinRequest"):FireServer(nationId, modeId)
end

--=============================================================================
-- Reseau
--=============================================================================

Remotes.get("MapInit").OnClientEvent:Connect(function(seed: number, slot: number, initialRoster, capital: number?)
	mySlot = slot
	roster = initialRoster
	myCapital = capital
	matchPhase = "playing"

	if world then
		world:destroy()
	end
	if minimap then
		minimap:destroy()
		minimap = nil
	end
	victory:hide()

	-- Relance de partie : on remontre l'ecran de chargement. Sans lui, le
	-- joueur voit le monde se reconstruire par morceaux sous le compte a
	-- rebours, ce qui ressemble a un bug.
	if deployed then
		intro:show(myNation)
	end

	worldReady = false

	local built = WorldRenderer.new(seed)
	world = built
	overlay = Overlay.new(built.root, built.terrain)
	effects = Effects.new(built.root, built.terrain)
	preview = PlacementPreview.new(built.root, built.terrain)
	minimap = Minimap.new(screenGui, built.terrain, function(index: number)
		camera:focusTile(index)
	end)

	camera:setMode("overview")
	camera:setDistance(260, true)
	if capital then
		camera:focusTile(capital, true)
	end

	-- Le monde se construit sur quelques dizaines de frames : on repose
	-- l'avatar une fois le sol susceptible d'exister sous lui.
	task.delay(1.5, placeCharacterAtCapital)

	local entry = roster[slot]
	hud:setIdentity(
		slot,
		if entry then entry.name else player.DisplayName,
		if entry then entry.doctrine else 1,
		if entry then entry.betrayals else 0
	)
	hud:selectFaction(nil)
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

	if delta then
		local w = world
		if w then
			local changed, gains, losses, others = w:applyDelta(delta, mySlot)
			-- Un seul son par vague de captures, pas un par tuile : le bridage
			-- du SoundManager fait le reste.
			if changed > 0 then
				SoundManager.play("tileCapture")
			end

			local fx = effects
			if fx then
				if #gains > 0 then
					fx:conquestWave(gains, Theme.factionColor(mySlot), true)
				end
				if #losses > 0 then
					fx:lossWave(losses, #losses)
				end
				-- Les prises entre tierces factions restent discretes : elles
				-- situent le conflit sans voler la vedette aux siennes.
				if #others > 0 then
					fx:conquestWave(others, Theme.color.textFaint, false)
				end
			end
		end
		local m = minimap
		if m then
			m:applyDelta(delta)
		end
	end

	hud:update(stats, roster)
end)

Remotes.get("BuildingDelta").OnClientEvent:Connect(function(deltas)
	local o = overlay
	if o then
		o:applyBuildingDelta(deltas)
	end
end)

Remotes.get("UnitSnapshot").OnClientEvent:Connect(function(boats, missiles)
	local o = overlay
	if o then
		o:applyUnits(boats, missiles)
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
	local o = overlay
	if o then
		o:explosion(x, y, radius)
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
	camera:step(dt)

	local w = world
	if w then
		-- Les reconstructions de terrain sont etalees : pendant une grande
		-- offensive, des dizaines de chunks changent dans le meme tick.
		w:stepRebuilds()

		-- Le monde apparait chunk par chunk : on suit cette file pour alimenter
		-- la barre de chargement, puis on lance le compte a rebours une fois le
		-- dernier chunk pose.
		if not worldReady then
			local progress = w:initialProgress()
			intro:setProgress(progress)

			if progress >= 1 then
				worldReady = true
				intro:hide()
				intro:runCountdown(Intro.COUNTDOWN_SECONDS, function()
					hud.root.Visible = true
					hud:showDoctrineModal()
				end)
			end
		end

		-- Apercu de construction : suit le curseur tant que le mode est arme.
		local p = preview
		if p and hud.mode == "build" and camera.mode == "overview" then
			local mouse = UserInputService:GetMouseLocation()
			local tile = camera:tileAtScreen(mouse, w.root)
			if tile then
				local valid = p:isValid(tile, hud.buildKind, function(index)
					return w:ownerAt(index)
				end, mySlot, hud.era, hud.gold)
				p:update(tile, valid)
			else
				p:update(nil, false)
			end
		end
	end

	local o = overlay
	if o then
		o:stepInterpolation(dt)
	end

	local m = minimap
	if m then
		m:flush()
		m:setFocus(camera.focus)
	end
end)
