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
local Doctrines = require(Shared:WaitForChild("Doctrines"))
local Eras = require(Shared:WaitForChild("Eras"))

-- Ce fichier est le LocalScript "Client" ; les modules voisins en sont les
-- enfants, pas les freres.
local WorldRenderer = require(script.WorldRenderer)
local WorldCamera = require(script.WorldCamera)
local Overlay = require(script.Overlay)
local Effects = require(script.Effects)
local PlacementPreview = require(script.PlacementPreview)
local RadialMenu = require(script.RadialMenu)
local FactionLabels = require(script.FactionLabels)
local MainMenu = require(script.MainMenu)
local Intro = require(script.Intro)
local Minimap = require(script.Minimap)
local VictoryScreen = require(script.VictoryScreen)
local SoundManager = require(script.SoundManager)
local HUD = require(script.HUD)
local VisualDirector = require(script.VisualDirector)

local player = localPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Sequence d'intention : idempotence cote serveur (dernier argument optionnel).
local clientSequence = 0
local function nextSequence(): number
	clientSequence += 1
	return clientSequence
end

local function fireOrder(remoteName: string, ...: any)
	local packed = table.pack(...)
	packed.n += 1
	packed[packed.n] = nextSequence()
	Remotes.get(remoteName):FireServer(table.unpack(packed, 1, packed.n))
end

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
-- Le menu affiche l'identite Roblox du joueur : drapeau choisi + pseudo.
menu:setPlayer(player.DisplayName)

-- L'interface de jeu reste masquee tant que le joueur n'est pas deploye.
hud.root.Visible = false

local world: WorldRenderer.WorldRenderer? = nil
local overlay: Overlay.Overlay? = nil
local effects: Effects.Effects? = nil
local preview: PlacementPreview.PlacementPreview? = nil
local factionLabels: FactionLabels.FactionLabels? = nil
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

-- Duree d'appui au doigt qui vaut clic droit. Assez long pour ne pas se
-- declencher sur un tap, assez court pour ne pas donner l'impression que rien
-- ne repond.
local LONG_PRESS_SECONDS = 0.35
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
		fireOrder("BuildOrder", index, hud.buildKind)
		return
	end

	if action == "upgrade" then
		fireOrder("UpgradeBuildingOrder", index)
		return
	end

	if action == "boat" then
		fireOrder("BoatOrder", index)
		return
	end

	if action == "nuke" then
		fireOrder("NukeOrder", index, hud.nukeKind)
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
	fireOrder("AttackOrder", index)
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

--[[
	Menu radial : clic droit sur une case, regle CONQUEST.

	Il double les modes plutot que de les remplacer. Le clic gauche continue
	d'appliquer le mode arme — c'est le geste rapide, celui qu'on repete pour
	poser cinq batiments d'affilee — et le clic droit ouvre le menu sur la case
	visee pour choisir explicitement, sans avoir a se souvenir du mode courant.

	Un menu contextuel connait sa cible : il grise ce qui n'a pas de sens ici,
	la ou une barre permanente reste generique et laisse decouvrir l'erreur
	apres coup.
]]
local radial = RadialMenu.new(screenGui)

radial.onAction = function(action: string, tile: number)
	if action == "inspect" then
		inspectTerritory(tile)
		return
	end
	if action == "retreat" then
		fireOrder("RetreatOrder", tile)
		return
	end
	hud:setMode(action :: any)
	inspectTerritory(tile)
	executeTerritoryAction(action, tile)
end

radial.onBuild = function(kind: number, tile: number)
	hud:setBuildKind(kind)
	hud:setMode("build")
	executeTerritoryAction("build", tile)
end

local function openRadial(position: Vector2)
	local w = world
	if not w or not deployed or not worldReady or camera.mode ~= "overview" then
		return
	end
	local tile = camera:tileAtScreen(position, w.root)
	if not tile then
		return
	end
	-- La retraite ne se propose que sur une case dont le proprietaire subit
	-- deja une de nos offensives.
	local owner = w:ownerAt(tile)
	local attacking = false
	local mine = stats and stats[mySlot]
	if mine and mine.attackTargets then
		for _, target in mine.attackTargets do
			if target == owner then
				attacking = true
				break
			end
		end
	end
	radial:open(position.X, position.Y, {
		tile = tile,
		ownerSlot = owner,
		mySlot = mySlot,
		era = hud.era,
		nukesUnlocked = hud.era >= Eras.requiredForNuke(Config.NUKE.ATOM),
		attacking = attacking,
	})
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		openRadial(pointerPosition(input))
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pressOrigin = pointerPosition(input)
		-- Appui long au doigt : l'equivalent tactile du clic droit. Sans lui le
		-- menu serait reserve a la souris, sur une plateforme majoritairement
		-- mobile.
		if input.UserInputType == Enum.UserInputType.Touch then
			local origin = pressOrigin
			task.delay(LONG_PRESS_SECONDS, function()
				-- Un geste a deux doigts (zoom, rotation) ne doit jamais ouvrir
				-- le menu radial : le premier doigt est immobile, mais il
				-- participe a un pilotage de la vue, pas a un appui long.
				if pressOrigin == origin and origin and camera.touchCount <= 1 then
					pressOrigin = nil
					openRadial(origin)
				end
			end)
		end
	end
end)

--[[
	Un doigt qui glisse annule le tap ET l'appui long.

	La camera tactile transforme ce meme glissement en panoramique : sans cette
	annulation, l'appui long se declencherait en plein deplacement de vue et le
	menu radial s'ouvrirait sous le doigt du joueur a chaque panoramique lent.
]]
UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local origin = pressOrigin
	if not origin then
		return
	end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if (pos - origin).Magnitude > CLICK_DRAG_THRESHOLD then
		pressOrigin = nil
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
--[[
	Les chiffres arment un BATIMENT, plus un mode.

	Les modes vivent dans le menu radial depuis qu'il existe ; garder les
	chiffres pour eux revenait a doubler un geste deja disponible et a priver
	les batiments du raccourci que le HUD affiche desormais en exposant sur
	chaque case. Un raccourci ecrit a l'ecran et qui ne fait rien est pire que
	pas de raccourci du tout.
]]
local BUILD_KEYS: { [Enum.KeyCode]: number } = {}
do
	local digits = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
		Enum.KeyCode.Seven,
		Enum.KeyCode.Eight,
		Enum.KeyCode.Nine,
	}
	for order, def in BuildingDefs.BUILDABLE do
		local key = digits[order]
		if key then
			BUILD_KEYS[key] = def.id
		end
	end
end

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

	-- Le batiment passe avant le mode : `setBuildKind` bascule deja en mode
	-- Construire, donc les deux gestes n'en font qu'un.
	local kind = BUILD_KEYS[input.KeyCode]
	if kind then
		hud:setBuildKind(kind)
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
		return
	end

	-- Messages rapides : la coordination d'alliance ne doit jamais demander
	-- plus d'une touche.
	if input.KeyCode == Enum.KeyCode.C then
		hud:openSheet("chat", true)
	end
end)

--=============================================================================
-- Callbacks du HUD
--=============================================================================

hud.onRatioChanged = function(ratio: number)
	fireOrder("SetAttackRatio", ratio)
end

-- Bouton "Capitale" de la barre tactile : meme effet que la touche Espace.
hud.onRecenter = function()
	if myCapital then
		camera:focusTile(myCapital)
	end
end

hud.onDoctrineChosen = function(doctrineId: number)
	fireOrder("ChooseDoctrine", doctrineId)
end

hud.onDiplomacyAction = function(action: string, targetSlot: number)
	fireOrder("DiplomacyOrder", action, targetSlot)
end

hud.onQuickChat = function(messageId: string, targetSlot: number?)
	fireOrder("QuickChat", messageId, targetSlot)
end

hud.onResearch = function()
	fireOrder("ResearchOrder")
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

Remotes.get("MapInit").OnClientEvent:Connect(function(
	seed: number,
	slot: number,
	initialRoster,
	capital: number?,
	profile,
	mapMeta
)
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
	if overlay then
		overlay:setLocalSlot(slot)
	end
	roster = initialRoster
	myCapital = capital
	matchPhase = "playing"
	clientSequence = 0

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

	-- Verifie le contrat de generation avant d'afficher la carte.
	if typeof(mapMeta) == "table" then
		local localTerrain = MapGen.generate(seed)
		local localHash = MapGen.terrainHash(localTerrain)
		if mapMeta.terrainHash ~= localHash
			or mapMeta.mapId ~= Config.MAP_ID
			or mapMeta.mapVersion ~= Config.MAP_VERSION
			or mapMeta.generatorVersion ~= Config.GENERATOR_VERSION
		then
			warn(
				`[CONQUEST RTS] desync carte : serveur hash={mapMeta.terrainHash} local={localHash} — demande de snapshot`
			)
			hud:notify("Carte desynchronisee — resynchronisation…", "bad")
			Remotes.get("RequestSnapshot"):FireServer()
		end
	end

	if Config.RENDER_MODE ~= "Blocks" then
		warn(`[CONQUEST RTS] RENDER_MODE={Config.RENDER_MODE} ignore — Blocks est le seul chemin de production`)
	end

	local built = WorldRenderer.new(seed)
	world = built
	overlay = Overlay.new(built.root, built.terrain)
	-- Aussi pose ici : l'identite peut arriver AVANT que le monde soit
	-- construit, auquel cas la couche n'existait pas encore pour la recevoir.
	overlay:setLocalSlot(mySlot)
	effects = Effects.new(built.root, built.terrain)
	preview = PlacementPreview.new(built.root, built.terrain)
	factionLabels = FactionLabels.new(built.root, built.terrain)

	-- Le pourcentage de domination a besoin du vrai nombre de tuiles de terre.
	-- Le client possede le meme terrain que le serveur : il le compte lui-meme
	-- plutot que de se fier au ratio moyen de MapGen, qui derive selon la graine.
	hud:setLandCount(MapGen.countLand(built.terrain))
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

Remotes.get("OwnerSnapshot").OnClientEvent:Connect(function(owner: buffer, tick: number, _structureHash: number)
	local w = world
	if not w or typeof(owner) ~= "buffer" then
		return
	end
	w:applyOwnerSnapshot(owner)
	hud:notify(`Resynchronisation appliquee (tick {tick}).`, "good")
end)

Remotes.get("IntentReject").OnClientEvent:Connect(function(reason: string, detail: string?)
	local text = detail or reason
	if reason == "RateLimited" then
		hud:notify(text or "Trop d'ordres — ralentis.", "bad")
	elseif reason == "DuplicateSequence" or reason == "StaleSequence" then
		-- Silent : replay reseau, pas une erreur joueur.
		return
	elseif reason == "NotPlaying" then
		hud:notify("La partie n'a pas commence.", "info")
	else
		hud:notify(text or "Ordre refuse.", "bad")
	end
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

	--[[
		Nom et armee de chaque faction, poses sur son territoire.

		On se branche sur la replication du HUD plutot que sur la boucle
		d'images : ces deux valeurs ne changent qu'a l'arrivee d'un lot de stats,
		et les recalculer entre deux lots ne pourrait produire que le meme
		resultat. Le module se limite lui-meme a un balayage par seconde.
	]]
	local labels = factionLabels
	local w = world
	if labels and w then
		labels:step(w.owner, stats, roster)
	end

	--[[
		Compteurs de parc du bandeau.

		Le detail par type de batiment n'est pas replique — `PlayerStats` ne
		transporte qu'un total. Mais le client connait deja chaque batiment de la
		carte, puisqu'il les dessine : le decompte se lit dans la couche
		d'entites, qui le maintient a l'incrementale a chaque delta. Repliquer
		neuf compteurs par joueur et par tick pour une information qu'on possede
		deja serait du gaspillage pur.
	]]
	local o = overlay
	if o then
		hud:setBuildingCounts(o:buildingCounts(mySlot))
	end
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
	-- Le menu suit la meme diffusion : il annonce le salon en cours tant que le
	-- joueur n'a pas encore rejoint.
	if menu then
		menu:setLobby(match)
	end

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

--[[
	Butin de mise a mort : le "+X or" qui recompense la conquete.

	Il reutilise l'affichage des livraisons plutot que d'en inventer un second :
	le joueur a deja appris ce que veut dire un chiffre dore qui monte, et deux
	langages visuels pour la meme idee seraient deux fois plus a apprendre.
]]
Remotes.get("Plunder").OnClientEvent:Connect(function(tile: number, slot: number, gold: number)
	local o = overlay
	if not o then
		return
	end
	o:goldPopup(tile, gold)
	if slot == mySlot then
		SoundManager.play("capitalFallen")
	end
end)

Remotes.get("TradeEvent").OnClientEvent:Connect(function(action: string, a: number, b: number, slot: number, value: number)
	local o = overlay
	if o then
		o:onTradeEvent(action, a, b, slot, value)
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

		--[[
			Apercu de construction.

			Le fantome ne suit pas le curseur : il suit **le resultat**. Le meme
			resolveur que le serveur decide de la tuile, donc le fantome saute
			visiblement sur la case libre voisine quand le clic est reporte, et
			passe en bleu quand il s'agit d'une amelioration.
		]]
		local p = preview
		if p and hud.mode == "build" and camera.mode == "overview" then
			local mouse = UserInputService:GetMouseLocation()
			local tile = camera:tileAtScreen(mouse, w.root)
			if tile then
				local o = overlay
				local landing, status = p:resolve(
					tile,
					hud.buildKind,
					function(index)
						return w:ownerAt(index)
					end,
					function(index)
						if o then
							local kind, slot, level = o:buildingAt(index)
							return kind, slot, level
						end
						return nil, nil, nil
					end,
					mySlot,
					hud.era,
					hud.gold,
					if o then o:buildingCounts(mySlot) else {},
					Doctrines.get(hud.doctrineId).buildCost
				)
				p:update(landing, status)
			else
				p:update(nil, "invalid")
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
