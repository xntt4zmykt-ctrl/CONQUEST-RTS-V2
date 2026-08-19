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

-- Protection contre un RunContext stale dans un fichier Studio deja ouvert.
-- Un LocalScript non-Legacy place dans StarterPlayerScripts peut s'executer
-- sur place puis etre clone dans PlayerScripts, ce qui cree deux mondes, deux
-- HUD et deux gestionnaires de clic. Le meta Rojo impose Legacy pour les
-- nouvelles synchronisations ; ce garde neutralise aussi les anciennes places.
local localPlayer = Players.LocalPlayer
if not script:IsDescendantOf(localPlayer) then
	warn("[CONQUEST UI] copie StarterPlayerScripts ignoree ; seule la copie PlayerScripts peut demarrer.")
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))
local BuildingDefs = require(Shared:WaitForChild("BuildingDefs"))

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
local VisualDirector = require(script.VisualDirector)

local player = localPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Rojo/Play Solo peut relancer le LocalScript sans nettoyer immédiatement
-- l'ancienne interface. Roblox suffixe parfois les doublons (`_1`, `_2`) :
-- chercher uniquement le nom exact laissait donc un vieux backdrop noir actif.
for _, child in playerGui:GetChildren() do
	if not child:IsA("ScreenGui") then
		continue
	end
	local hasOldMenu = child.Name == "ConquestRTS" or child:FindFirstChild("MainMenu", true) ~= nil
	if hasOldMenu then
		warn(`[CONQUEST UI] removing stale interface {child:GetFullName()}`)
		child:Destroy()
	end
end

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

local function hideTransientInterfaces()
	-- Filet de securite : masque aussi les anciennes versions du menu si elles
	-- viennent d'un ScreenGui suffixe que le nettoyage initial n'a pas vu.
	for _, gui in playerGui:GetChildren() do
		for _, node in gui:GetDescendants() do
			if node.Name == "MainMenu" or node.Name == "Intro" or node.Name == "Countdown" then
				if node:IsA("CanvasGroup") then
					node.GroupTransparency = 1
				end
				if node:IsA("GuiObject") then
					node.Visible = false
				end
			end
		end
	end
end

local TERRAIN_NAMES = {
	[Config.TERRAIN.OCEAN] = "Ocean",
	[Config.TERRAIN.BEACH] = "Littoral",
	[Config.TERRAIN.PLAINS] = "Plaines",
	[Config.TERRAIN.SAVANNA] = "Savane",
	[Config.TERRAIN.FOREST] = "Foret",
	[Config.TERRAIN.HILLS] = "Collines",
	[Config.TERRAIN.HIGHLAND] = "Hautes terres",
	[Config.TERRAIN.MOUNTAIN] = "Montagne",
	[Config.TERRAIN.PEAK] = "Sommet enneige",
}

-- La direction visuelle vit cote client : elle reste identique en Play Solo,
-- sur serveur publie et apres une reconstruction de carte.
VisualDirector.apply()

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

	-- Ne jamais poser l'avatar au centre exact de la capitale : son modele 3D
	-- occupe cette position et la camera epaule se retrouverait dans les murs.
	-- On cherche une tuile libre de la couronne proche, toujours dans le petit
	-- territoire de depart, puis on retombe sur la capitale en dernier recours.
	local spawnTile = capital
	local cx, cy = MapGen.fromIndex(capital)
	for radius = 3, 7 do
		local found = false
		for dy = -radius, radius do
			for dx = -radius, radius do
				if math.max(math.abs(dx), math.abs(dy)) ~= radius then
					continue
				end
				local x, y = cx + dx, cy + dy
				if not MapGen.inBounds(x, y) then
					continue
				end
				local candidate = MapGen.toIndex(x, y)
				local occupied = overlay and overlay:buildingAt(candidate) ~= nil
				if w:ownerAt(candidate) == mySlot and not occupied then
					spawnTile = candidate
					found = true
					break
				end
			end
			if found then
				break
			end
		end
		if found then
			break
		end
	end

	root.CFrame = WorldSpace.spawnCFrame(w.terrain, spawnTile)
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

local function pointerPosition(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return UserInputService:GetMouseLocation()
	end
	return Vector2.new(input.Position.X, input.Position.Y)
end

--[[
	Un clic sur le monde n'a pas de sens en soi : son effet depend entierement
	du mode arme dans le HUD. C'est le seul endroit ou cette traduction a lieu.
]]
local function executeTerritoryAction(action: string, index: number)
	local w = world
	if not w then
		return
	end

	local targetSlot = w:ownerAt(index)

	if action == "build" then
		Remotes.get("BuildOrder"):FireServer(index, hud.buildKind)
		return
	end

	if action == "upgrade" then
		Remotes.get("UpgradeBuildingOrder"):FireServer(index)
		return
	end

	if action == "boat" then
		Remotes.get("BoatOrder"):FireServer(index)
		return
	end

	if action == "nuke" then
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
	camera:punch(0.16)
	-- Le serveur derive lui-meme la faction depuis la tuile exacte. Envoyer un
	-- slot calcule par le buffer client pouvait cibler une ancienne faction si
	-- un delta de conquete arrivait au meme moment que le clic.
	Remotes.get("AttackOrder"):FireServer(index)
	hud:recordTutorial("attack")
end

local function inspectTerritory(index: number)
	local w = world
	if not w then
		return
	end

	local targetSlot = w:ownerAt(index)
	local terrainKind = buffer.readu8(w.terrain, index)
	local buildingName: string? = nil
	local buildingKind: number? = nil
	local buildingLevel: number? = nil
	local buildingRoutes: number? = nil
	local o = overlay
	if o then
		local kind, _, level, routes = o:buildingAt(index)
		buildingKind = kind
		buildingLevel = level
		buildingRoutes = routes
		local def = if kind then BuildingDefs.get(kind) else nil
		buildingName = if def then def.name else nil
	end

	hud:selectTerritory(
		index,
		targetSlot,
		TERRAIN_NAMES[terrainKind] or "Terrain",
		buildingName,
		buildingKind,
		buildingLevel,
		buildingRoutes
	)
	local fx = effects
	if fx then
		local color = if targetSlot == 0 then Theme.color.textMuted else Theme.factionColor(targetSlot)
		fx:selectTile(index, color)
	end
end

local function onTileClicked(index: number)
	-- La fiche de territoire ne s'ouvre qu'en mode Attaquer, le seul ou le clic
	-- sert aussi a inspecter. Dans les autres modes le clic EST un ordre :
	-- ouvrir la fiche fermerait la palette et empecherait de poser plusieurs
	-- batiments a la suite.
	if hud.mode == "attack" then
		inspectTerritory(index)
	end
	executeTerritoryAction(hud.mode, index)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pressOrigin = pointerPosition(input)
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

	local endPos = pointerPosition(input)
	if (endPos - origin).Magnitude > CLICK_DRAG_THRESHOLD then
		return
	end

	local w = world
	if w and deployed and worldReady and camera.mode == "overview" then
		local index = camera:tileAtScreen(endPos, w.root)
		if index then
			onTileClicked(index)
		else
			warn(`[CONQUEST ATTACK] aucun terrain sous x={math.floor(endPos.X)} y={math.floor(endPos.Y)}`)
		end
	else
		warn(`[CONQUEST ATTACK] clic bloque world={w ~= nil} deployed={deployed} ready={worldReady} camera={camera.mode}`)
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

hud.onTerritoryAction = function(action: string, index: number)
	executeTerritoryAction(action, index)
end

hud.onTerritoryClosed = function()
	local fx = effects
	if fx then
		fx:clearSelection()
	end
end

menu.onDeploy = function(nationId: number, modeId: string)
	myNation = nationId
	deployed = true
	hideTransientInterfaces()
	-- Verrou de securite : le menu ne doit jamais pouvoir recouvrir la partie,
	-- meme si un tween ou un callback UI est interrompu.
	menu.root.Visible = false
	menu.root.GroupTransparency = 1
	intro:show(nationId)
	Remotes.get("JoinRequest"):FireServer(nationId, modeId)
end

--=============================================================================
-- Reseau
--=============================================================================

Remotes.get("MapInit").OnClientEvent:Connect(function(seed: number, slot: number, initialRoster, capital: number?, profile)
	hideTransientInterfaces()
	menu.root.Visible = false
	menu.root.GroupTransparency = 1
	for _, child in screenGui:GetChildren() do
		if child.Name == "MainMenu" then
			(child :: any).Visible = false
			(child :: any).GroupTransparency = 1
		end
	end
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
	hud:setProfile(profile)
	hud:selectFaction(nil)
	hud.territoryPanel.Visible = false
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
				if #gains > 0 or #losses > 0 then
					camera:punch(math.min(0.32, changed / 160))
				end
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
	for _, entry in deltas do
		if entry.slot == mySlot and entry.kind == Config.BUILDING.CITY then
			hud:recordTutorial("build")
		end
		if worldReady and entry.slot == mySlot and entry.kind ~= 0 then
			camera:punch(0.22)
		end
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
		victory:show(match.winner, match.winnerName, hud.ranked, roster, mySlot, match.summary, hud.profile)
		victory:setCountdown(match.restartIn or 0)
	elseif matchPhase == "ended" then
		matchPhase = "playing"
		victory:hide()
	end
end)

Remotes.get("ProfileUpdate").OnClientEvent:Connect(function(profile)
	hud:setProfile(profile)
	victory:setProfile(profile)
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
	camera:punch(math.clamp(radius / 8, 0.65, 1.35))
end)

Remotes.get("Sfx").OnClientEvent:Connect(function(name: string)
	SoundManager.play(name)
	if name == "boatLaunch" then
		camera:punch(0.2)
	elseif name == "buildPlace" then
		camera:punch(0.14)
	end
end)

-- Watchdog temporaire : si le menu et le HUD sont visibles ensemble, le bug
-- est immediatement identifiable dans Output avec les valeurs reelles de la
-- scene, au lieu de devoir deviner quel fondu est reste bloque.
local menuLeakReported = false
RunService.Heartbeat:Connect(function()
	local menuVisible = menu.root.Visible
	local hudVisible = hud.root.Visible
	if menuVisible and hudVisible then
		if deployed then
			hideTransientInterfaces()
			menu.root.Visible = false
			menu.root.GroupTransparency = 1
		end
		if not menuLeakReported then
			menuLeakReported = true
			warn(`[CONQUEST UI] MENU LEAK: menuVisible={menuVisible} group={menu.root.GroupTransparency} background={menu.root.BackgroundTransparency} hudVisible={hudVisible}`)
		end
	elseif not menuVisible then
		menuLeakReported = false
	end
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
		w:step(dt)

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
					hideTransientInterfaces()
					hud.root.Visible = true
					hud:startOnboarding()
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
					end, mySlot, hud.era, hud.gold, function(index)
						local currentOverlay = overlay
						if currentOverlay then
							return currentOverlay:buildingAt(index)
						end
						return nil, nil
					end, function(index, slot, range)
						local currentOverlay = overlay
						return currentOverlay ~= nil and currentOverlay:hasCityNear(index, slot, range)
					end)
				p:update(tile, valid)
			else
				p:update(nil, false)
			end
		end

		-- Le joueur voit la case et la validite AVANT de cliquer. Le serveur
		-- reste autoritaire sur les regles fines (contact terrestre, budget,
		-- alliances), mais les erreurs evidentes sont lisibles immediatement.
		local fx = effects
		if fx and hud.root.Visible and hud.mode ~= "build" and camera.mode == "overview" then
			local mouse = UserInputService:GetMouseLocation()
			local tile = camera:tileAtScreen(mouse, w.root)
			if tile then
				local owner = w:ownerAt(tile)
				local land = w:isLand(tile)
				local valid = false
				local color = Theme.color.danger
				if hud.mode == "attack" then
					valid = land and owner ~= mySlot
					color = if owner == 0 then Theme.color.accent else Theme.factionColor(owner)
				elseif hud.mode == "boat" then
					valid = land and owner ~= mySlot and MapGen.isCoastal(w.terrain, tile)
					color = Theme.color.info
				elseif hud.mode == "nuke" then
					valid = land and owner ~= 0 and owner ~= mySlot
					color = Theme.color.nuclear
				end
				fx:previewTile(tile, if valid then color else Theme.color.danger, valid)
			else
				fx:clearActionPreview()
			end
		elseif fx then
			fx:clearActionPreview()
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
