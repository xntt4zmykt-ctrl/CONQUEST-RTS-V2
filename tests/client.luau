--[[
	Banc d'essai client.

	Construit chaque module d'interface et rejoue le parcours complet d'une
	partie : menu, deploiement, chargement, jeu, fin de partie. Il ne verifie
	pas l'apparence — il verifie que **rien ne leve d'erreur**.

	C'est la classe de bug qui a le plus coute jusqu'ici : une propriete mal
	nommee ou une methode absente dans un module d'interface se presente au
	joueur comme un ecran noir muet, et n'apparait nulle part ailleurs.
]]

local Config = __require("Config")
local MapGen = __require("MapGen")
local Nations = __require("Nations")
local GameModes = __require("GameModes")
local BuildingDefs = __require("BuildingDefs")

local failures = 0

local function check(label, fn)
	local ok, err = pcall(fn)
	if ok then
		print(`  \27[32mOK\27[0m    {label}`)
	else
		failures += 1
		print(`  \27[31mECHEC\27[0m {label}`)
		print(`         {err}`)
	end
end

print("=== CONQUEST RTS — banc d'essai client ===")

--=============================================================================
-- Chargement des modules
--=============================================================================

local SoundManager, HUD, MainMenu, Intro, VictoryScreen
local Effects, PlacementPreview, BuildingModels, Overlay
local WorldRenderer, WorldCamera, Minimap

check("chargement des modules", function()
	SoundManager = __require("SoundManager")
	BuildingModels = __require("BuildingModels")
	HUD = __require("HUD")
	MainMenu = __require("MainMenu")
	Intro = __require("Intro")
	VictoryScreen = __require("VictoryScreen")
	Effects = __require("Effects")
	PlacementPreview = __require("PlacementPreview")
	Overlay = __require("Overlay")
	WorldRenderer = __require("WorldRenderer")
	WorldCamera = __require("WorldCamera")
	Minimap = __require("Minimap")
end)

if failures > 0 then
	print("\27[31mChargement impossible : le reste du banc est ignore.\27[0m")
	return
end

local screenGui = Instance.new("ScreenGui")
screenGui.Parent = testPlayerGui

local terrain = MapGen.generate(4242)

--=============================================================================
-- Ecrans
--=============================================================================

local menu, intro, hud, victory

check("construction du menu principal", function()
	menu = MainMenu.new(screenGui)
end)

check("selection de chaque nation et de chaque mode", function()
	for _, nation in Nations.LIST do
		menu:selectNation(nation.id)
	end
	for _, mode in GameModes.LIST do
		menu:selectMode(mode.id)
	end
end)

check("fermeture puis reouverture du menu", function()
	menu:close()
	menu:open()
	-- Le fondu ne doit jamais laisser le contenu definitivement invisible :
	-- c'est le bug qui produisait un ecran noir avec le menu par-dessus.
	assert(menu.root.GroupTransparency == 0, "le menu reste transparent apres reouverture")
	assert(menu.root.Visible ~= false, "le menu reste masque apres reouverture")
end)

check("construction de l'ecran de chargement", function()
	intro = Intro.new(screenGui)
end)

check("cycle complet de l'ecran de chargement", function()
	for _, nation in Nations.LIST do
		intro:show(nation.id)
		intro:setProgress(0)
		intro:setProgress(0.5)
		intro:setProgress(1)
		intro:hide()
	end
	-- Deuxieme partie : l'ecran doit se rallumer intact.
	intro:show(1)
	assert(intro.root.GroupTransparency == 0, "l'ecran de chargement reste transparent au reaffichage")
	intro:hide()
end)

check("construction du HUD", function()
	hud = HUD.new(screenGui)
end)

check("tous les modes et toutes les classes de construction", function()
	for _, mode in { "attack", "boat", "build", "nuke" } do
		hud:setMode(mode)
	end
	for _, class in BuildingDefs.CLASSES do
		hud:setBuildClass(class.id)
	end
	for _, def in BuildingDefs.BUILDABLE do
		hud.buildKind = def.id
		hud:refreshPalettes()
	end
end)

check("identite, ere, diplomatie et classement", function()
	hud:setIdentity(1, "Valoria", 2, 3)

	local stats = {}
	local roster = {}
	for slot = 1, 12 do
		stats[slot] = {
			troops = 1000 + slot,
			tiles = 500 - slot * 10,
			gold = 2000,
			maxTroops = 5000,
			era = math.min(5, 1 + slot % 5),
			eraProgress = slot / 12,
			activeAttacks = if slot == 1 then 2 else 0,
			committedTroops = if slot == 1 then 640 else 0,
			logisticsRoutes = if slot == 1 then 3 else 0,
			logisticsIncome = if slot == 1 then 1.2 else 0,
			buildPrices = { [Config.BUILDING.CITY] = 243 },
		}
		roster[slot] = { name = `Nation{slot}`, isBot = slot > 1, doctrine = 1, betrayals = slot % 3 }
	end

	hud:update(stats, roster)
	assert(string.find(hud.frontStatus.Text, "2 FRONTS") ~= nil, "les fronts actifs ne sont pas affiches")
	assert(string.find(hud.tilesLabel.Text, "3") ~= nil, "les routes logistiques ne sont pas affichees")
	assert(string.find(hud.goldLabel.Text, "+12.0/s") ~= nil, "le revenu logistique n'est pas affiche")
	assert(hud.buildPriceLabels[Config.BUILDING.CITY].Text == "243 or", "le vrai prix de construction n'est pas affiche")
	hud:setDiplomacy({
		allies = { [2] = true },
		incoming = { [3] = true },
		outgoing = { [4] = true },
		embargoes = { [5] = true },
		traitors = { [6] = true },
	})
	hud:selectFaction(2)
	hud:selectFaction(nil)

	for era = 1, 5 do
		hud.era = era
		hud:refreshEraPanel()
		hud:setMatch({ phase = "playing", timeLeft = 600, restartIn = 0 })
	end
end)

check("fil de notifications sature", function()
	for i = 1, 40 do
		hud:notify(`message {i}`, if i % 2 == 0 then "bad" else "info")
	end
	-- Le meme message repete doit se regrouper, pas s'empiler.
	for _ = 1, 5 do
		hud:notify("repetition", "info")
	end
end)

check("onboarding, profil et inspecteur de territoire", function()
	hud:setProfile({ xp = 640, level = 2, matches = 4, wins = 1, betrayals = 0 })
	hud:startOnboarding()
	for _, action in { "doctrine", "colonize", "build", "attack", "era" } do
		hud:recordTutorial(action)
	end
	assert(hud.missionCounter.Text == "5 / 5", "le briefing ne se termine pas")

	hud:selectTerritory(4242, 0, "Plaines", nil)
	hud:selectTerritory(4243, 1, "Foret", "Ville", Config.BUILDING.CITY, 1)
	assert(hud.territoryButtons.build.Text == "Ameliorer", "une ville ne propose pas son evolution")
	hud:selectTerritory(4243, 1, "Foret", "Ville", Config.BUILDING.CITY, 3)
	assert(hud.territoryButtons.build.Text == "Niveau max", "une megapole peut encore etre amelioree")
	hud:selectTerritory(4244, 2, "Littoral", "Port")
	assert(hud.territoryPanel.Visible, "la fiche de territoire ne s'affiche pas")
end)

check("un seul sous-menu ouvert a la fois", function()
	local function openCount()
		local open = 0
		for _, frame in hud.sheets do
			if frame.Visible then
				open += 1
			end
		end
		return open
	end

	-- Armer un mode ouvre sa feuille et referme celle d'avant.
	hud:setMode("build")
	assert(hud.sheets.build.Visible, "le mode Construire n'ouvre pas sa palette")
	assert(openCount() == 1, `{openCount()} sous-menus ouverts apres Construire`)

	hud:setMode("nuke")
	assert(hud.sheets.nuke.Visible and not hud.sheets.build.Visible, "l'arsenal ne remplace pas la palette")
	assert(openCount() == 1, `{openCount()} sous-menus ouverts apres Frappe`)

	-- Armer deux fois le meme mode ne doit pas refermer sa feuille.
	hud:setMode("nuke")
	assert(hud.sheets.nuke.Visible, "rearmer un mode referme sa feuille")

	-- Un mode sans feuille ne laisse rien d'ouvert.
	hud:setMode("attack")
	assert(openCount() == 0, `{openCount()} sous-menus ouverts en mode Attaquer`)

	-- Le classement ferme tout le reste, et son bouton le referme.
	hud:openSheet("nations")
	assert(openCount() == 1, "le classement n'est pas exclusif")
	hud:openSheet("nations", true)
	assert(openCount() == 0, "le bouton du classement ne le referme pas")

	-- Selectionner un territoire prend la place de toute autre feuille.
	hud:setMode("build")
	hud:selectTerritory(4242, 0, "Plaines", nil)
	assert(hud.territoryPanel.Visible and not hud.sheets.build.Visible, "la fiche de territoire n'est pas exclusive")
	assert(openCount() == 1, `{openCount()} sous-menus ouverts avec la fiche de territoire`)
	hud:setMode("attack")
end)

check("curseur d'engagement et doctrines", function()
	for _, ratio in { 0.05, 0.25, 0.5, 1 } do
		hud:setRatio(ratio)
	end
	hud:showDoctrineModal()
end)

check("ecran de victoire", function()
	victory = VictoryScreen.new(screenGui)
	local ranked = {}
	for slot = 1, 8 do
		table.insert(ranked, { slot = slot, tiles = 900 - slot * 50, troops = 1000 })
	end
	local roster = {}
	for slot = 1, 8 do
		roster[slot] = { name = `Nation{slot}`, isBot = false, doctrine = 1, betrayals = 0 }
	end
	-- Appele deux fois : une relance de partie ne doit pas dupliquer les lignes.
	local summary = {
		[1] = { troops = 1000, tiles = 850, gold = 200, maxTroops = 2000, era = 3, eraProgress = 0.5,
			capturedTiles = 240, lostTiles = 20, capitalsCaptured = 2, buildingsBuilt = 7, attacksLaunched = 8 },
	}
	victory:show(1, "Valoria", ranked, roster, 1, summary, { xp = 900, level = 3, matches = 8, wins = 2, betrayals = 0, lastGain = 180 })
	victory:hide()
	victory:show(2, "Kerensk", ranked, roster, 1)
	victory:setCountdown(12)
	victory:hide()
end)

--=============================================================================
-- Monde
--=============================================================================

local world, overlay, effects, preview

check("construction du monde 3D", function()
	world = WorldRenderer.new(4242)
	-- Vide toute la file de reconstruction, comme le ferait le chargement.
	local guard = 0
	while world:initialProgress() < 1 and guard < 5000 do
		world:stepRebuilds()
		guard += 1
	end
	assert(world:initialProgress() >= 1, "la construction initiale ne se termine jamais")
end)

check("calques d'entites, effets et apercu", function()
	overlay = Overlay.new(world.root, terrain)
	effects = Effects.new(world.root, terrain)
	preview = PlacementPreview.new(world.root, terrain)
	effects:selectTile(2000, Color3.fromRGB(45, 194, 177))
	effects:previewTile(2001, Color3.fromRGB(45, 194, 177), true)
	effects:previewTile(2002, Color3.fromRGB(231, 76, 60), false)
	effects:clearActionPreview()
	effects:clearSelection()
end)

check("pose et capture de chaque type de batiment", function()
	local deltas = {}
	local index = 0
	for _, def in BuildingDefs.LIST do
		index += 137
		table.insert(deltas, { index = index, kind = def.id, slot = 1, level = 1 })
	end
	overlay:applyBuildingDelta(deltas)
	local firstKind, firstSlot = overlay:buildingAt(deltas[1].index)
	assert(firstKind == deltas[1].kind and firstSlot == 1, "l'inspection du batiment est fausse")

	-- Une usine connectee cree une route monde et expose sa destination dans
	-- l'inspecteur. Le camion est ensuite anime par la boucle de frame.
	local cityIndex: number? = nil
	local factoryEntry = nil
	for _, entry in deltas do
		if entry.kind == Config.BUILDING.CITY then
			cityIndex = entry.index
		elseif entry.kind == Config.BUILDING.FACTORY then
			factoryEntry = entry
		end
	end
	assert(cityIndex ~= nil and factoryEntry ~= nil, "ville ou usine absente du catalogue")

	local function routesOf(index)
		local count = 0
		local sample = nil
		for _, route in overlay.routes do
			if route.factory == index then
				count += 1
				sample = route
			end
		end
		return count, sample
	end

	-- Une usine dessert TOUTES les villes a portee : trois villes, trois routes.
	factoryEntry.links = { cityIndex, cityIndex + 300, cityIndex + 700 }
	overlay:applyBuildingDelta({ factoryEntry })
	local _, _, _, routeCount = overlay:buildingAt(factoryEntry.index)
	assert(routeCount == 3, `l'usine annonce {routeCount} routes au lieu de 3`)
	local built, sample = routesOf(factoryEntry.index)
	assert(built == 3, `{built} routes tracees au lieu de 3`)
	assert(sample and #sample.path == 6, "la route logistique n'est pas courbee en segments")

	-- Perdre une ville doit retirer sa route, pas les laisser s'accumuler.
	factoryEntry.links = { cityIndex }
	overlay:applyBuildingDelta({ factoryEntry })
	assert(routesOf(factoryEntry.index) == 1, "les routes obsoletes ne sont pas effacees")
	overlay:stepInterpolation(1 / 60)

	-- Une ville qui evolue change reellement de silhouette et conserve son
	-- niveau dans l'inspecteur client.
	for _, entry in deltas do
		if entry.kind == Config.BUILDING.CITY then
			entry.level = 3
			overlay:applyBuildingDelta({ entry })
			local _, _, level = overlay:buildingAt(entry.index)
			assert(level == 3, "le niveau de ville n'est pas replique")
			break
		end
	end

	-- Recapture : le modele doit etre recolore, pas reconstruit.
	for _, entry in deltas do
		entry.slot = 2
	end
	overlay:applyBuildingDelta(deltas)

	-- Destruction
	for _, entry in deltas do
		entry.kind = 0
	end
	overlay:applyBuildingDelta(deltas)
	assert(next(overlay.routes) == nil, "une route detruite reste affichee")
end)

check("apercu de placement pour chaque batiment", function()
	for _, def in BuildingDefs.BUILDABLE do
		preview:setKind(def.id)
		preview:update(1000, true)
		preview:update(1200, false)
		preview:update(nil, false)
	end
	preview:hide()
end)

check("navires, missiles et interpolation", function()
	overlay:applyUnits({
		{ id = 1, slot = 1, x = 10, y = 10, troops = 100, kind = 1 },
		{ id = 2, slot = 2, x = 20, y = 30, troops = 0, kind = 2 },
		{ id = 4, slot = 3, x = 30, y = 30, troops = 0, kind = 3 },
	}, {
		{ id = 3, slot = 1, x = 40, y = 40, tx = 60, ty = 60, kind = 1 },
	})
	assert(#overlay.units[1].visual.pieces >= 15, "le navire de debarquement est encore un placeholder")
	assert(#overlay.units[2].visual.pieces >= 15, "le cargo est encore un placeholder")
	assert(#overlay.units[3].visual.pieces >= 8, "le missile est encore un placeholder")
	assert(overlay.units[1].visual.model.Name == "LandingShip", "mauvais modele de debarquement")
	assert(overlay.units[2].visual.model.Name == "MerchantShip", "mauvais modele de cargo")
	overlay:stepInterpolation(1 / 60)
	overlay:applyUnits({}, {})
	overlay:explosion(50, 50, 9)
end)

check("vagues de conquete", function()
	local wave = {}
	for i = 1, 200 do
		wave[i] = 1000 + i
	end
	effects:conquestWave(wave, Color3.fromRGB(255, 0, 0), true)
	effects:lossWave(wave, #wave)
	effects:conquestWave({ 5 }, Color3.fromRGB(0, 255, 0), false)
end)

check("deltas de terrain et conquetes classees", function()
	local delta = buffer.create(4 * 5)
	for i = 0, 3 do
		buffer.writeu32(delta, i * 5, 2000 + i)
		buffer.writeu8(delta, i * 5 + 4, 1)
	end
	local changed, gains, losses, others = world:applyDelta(delta, 1)
	assert(changed == 4, "le nombre de tuiles modifiees est faux")
	assert(gains ~= nil and losses ~= nil and others ~= nil, "conquetes non classees")
	world:stepRebuilds()
end)

check("camera strategique", function()
	local camera = WorldCamera.new()
	camera:setMode("overview")
	camera:setDistance(300, true)
	camera:focusTile(5000, true)
	camera:step(1 / 60)
	camera:toggleMode()
	camera:step(1 / 60)
	camera:toggleMode()
	camera:tileAtScreen(Vector2.new(100, 100), world.root)
end)

check("minimap", function()
	local minimap = Minimap.new(screenGui, terrain, function() end)
	if minimap then
		local delta = buffer.create(5)
		buffer.writeu32(delta, 0, 1234)
		buffer.writeu8(delta, 4, 3)
		minimap:applyDelta(delta)
		minimap:flush()
		minimap:setFocus(Vector3.new(0, 0, 0))
		minimap:destroy()
	end
end)

check("sons du catalogue", function()
	local Audio = __require("Audio")
	for name in Audio.SOUNDS do
		SoundManager.play(name)
	end
	SoundManager.playAt("nukeImpact", 40)
end)

--=============================================================================
-- Rapport
--=============================================================================

print("")
if failures == 0 then
	print("\27[32mTous les ecrans se construisent et s'executent sans erreur.\27[0m")
else
	print(`\27[31m{failures} defaillance(s) client.\27[0m`)
end
