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
local Eras = __require("Eras")

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
local Effects, PlacementPreview, BuildingModels, Overlay, RadialMenu, FactionLabels
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
	RadialMenu = __require("RadialMenu")
	FactionLabels = __require("FactionLabels")
	Overlay = __require("Overlay")
	WorldRenderer = __require("WorldRenderer")
	WorldCamera = __require("WorldCamera")
	Minimap = __require("Minimap")
end)

if failures > 0 then
	print("\27[31mChargement impossible : le reste du banc est ignore.\27[0m")
	os.exit(1)
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

--[[
	Salon : le menu annonce la partie qui tourne vraiment.

	Le bandeau ne s'affiche que sur le mode en cours, et son texte change avec la
	phase. Rien ne planterait s'il se posait sur la mauvaise carte ou s'il
	restait affiche apres la fin — il annoncerait juste une partie qui n'existe
	pas, ce qu'aucune erreur ne signale.
]]
check("salon : la carte en direct suit la partie du serveur", function()
	local first = GameModes.LIST[1]

	-- Sans annonce du serveur, la carte ne promet aucune partie.
	menu:setLobby(nil)
	assert(string.find(menu.liveTitle.Text, "Aucune") ~= nil, `sans donnee : "{menu.liveTitle.Text}"`)

	-- En attente : c'est le remplissage qui compte.
	menu:setLobby({ mode = first.id, phase = "waiting", players = 7, maxPlayers = 48, timeLeft = 900 })
	assert(string.find(menu.liveMeta.Text, "7/48") ~= nil, `en attente : "{menu.liveMeta.Text}"`)

	-- En jeu : c'est le temps restant. Rejoindre a deux minutes de la fin n'a
	-- pas le meme sens qu'a vingt.
	menu:setLobby({ mode = first.id, phase = "playing", players = 12, maxPlayers = 48, timeLeft = 125 })
	assert(string.find(menu.liveMeta.Text, "2 min 05") ~= nil, `en jeu : "{menu.liveMeta.Text}"`)

	menu:setLobby({ mode = first.id, phase = "ended", players = 3, maxPlayers = 48, timeLeft = 0 })
	assert(string.find(menu.liveTitle.Text, "termin") ~= nil, `fin : "{menu.liveTitle.Text}"`)
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

check("tous les modes et tous les batiments", function()
	for _, mode in { "attack", "boat", "build", "nuke" } do
		hud:setMode(mode)
	end
	-- Les classes de construction ont disparu avec la palette : armer un
	-- batiment se fait par sa case ou son raccourci, sans onglet intermediaire.
	for _, def in BuildingDefs.BUILDABLE do
		hud:setBuildKind(def.id)
	end
	hud:refreshPalettes()
end)

check("identite, ere, diplomatie et classement", function()
	hud:setIdentity(1, "Valoria", 2, 3)

	local stats = {}
	local roster = {}
	for slot = 1, 12 do
		-- Valeurs choisies pour tomber sur des formes compactes reconnaissables :
		-- 5501 -> "5.50K", 39800 -> "39.8K", 5020000 -> "5.02M". Un formatage
		-- casse se voit alors immediatement, au lieu de passer pour un chiffre
		-- plausible.
		stats[slot] = {
			troops = 5500 + slot,
			tiles = 500 - slot * 10,
			gold = 5020000,
			maxTroops = 39800,
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
	--[[
		Le prix reel suit le batiment arme, dans l'aide contextuelle.

		C'etait la seule information que la palette apportait en propre. En la
		supprimant sans verifier ceci, on aurait retire du jeu la reponse a
		"combien ca coute" sans que rien ne le signale.
	]]
	hud:setBuildKind(Config.BUILDING.CITY)
	assert(
		string.find(hud.hintLabel.Text, "243 or") ~= nil,
		`le prix reel n'apparait pas dans l'aide : "{hud.hintLabel.Text}"`
	)

	--[[
		Tous les chiffres du bandeau passent par Format.

		C'est la seule chose qui garantit que le classement, les etiquettes de
		la carte et le bandeau racontent la meme histoire. Un `tostring` oublie
		afficherait 5501 la ou la carte annonce 5.50K, et rien n'echouerait.
	]]
	assert(hud.troopsLabel.Text == "5.50K", `armee affichee "{hud.troopsLabel.Text}" au lieu de "5.50K"`)
	assert(hud.popCapLabel.Text == "39.8K", `capacite affichee "{hud.popCapLabel.Text}" au lieu de "39.8K"`)
	assert(string.find(hud.goldLabel.Text, "5.02M") ~= nil, `or affiche "{hud.goldLabel.Text}" au lieu de "5.02M"`)
	assert(string.find(hud.growthLabel.Text, "%d") ~= nil, "la croissance de population n'affiche aucun chiffre")

	--[[
		Le tri des factions survit au retrait du classement maison.

		Plus aucun panneau ne l'affiche — la liste native de Roblox s'en charge —
		mais `ranked` reste la source de la selection de faction et de la fiche
		diplomatique. Le supprimer avec le panneau aurait casse les deux sans
		lever la moindre erreur.
	]]
	assert(#hud.ranked > 0, "le classement des factions n'est plus calcule")
	for i = 2, #hud.ranked do
		assert(
			hud.ranked[i - 1].tiles >= hud.ranked[i].tiles,
			"les factions ne sont plus triees par territoire decroissant"
		)
	end

	-- N97 : leftover truncate. Premier update 12 slots, second un seul
	-- vivant → #ranked == 1, sinon une ligne fantome (VictoryScreen /
	-- selectFaction). Restaure le 12-slot avant la diplomatie.
	hud:update({ [3] = stats[3] }, { [3] = roster[3] })
	assert(#hud.ranked == 1, "leftover ranked non truncate")
	assert(hud.ranked[1].slot == 3, "ranked ne vise plus le slot vivant")
	hud:update(stats, roster)

	hud:setDiplomacy({
		allies = { [2] = true },
		incoming = { [3] = true },
		outgoing = { [4] = true },
		embargoes = { [5] = true },
		traitors = { [6] = true },
		marks = { [2] = 7 }, -- l'allie designe la nation 7 comme cible
	})
	--[[
		La diplomatie reste joignable apres le retrait du classement.

		C'est le vrai risque du retrait : alliance, embargo et rupture vivaient
		toutes DANS une ligne du classement. Supprimer le panneau sans redonner
		un toit a la fiche les rendait injoignables — sans erreur, sans trace,
		juste une mecanique entiere devenue morte.
	]]
	hud:selectFaction(2)
	assert(hud.diploDrawer.Visible, "la fiche diplomatique ne s'ouvre pas sur la nation selectionnee")
	assert(hud.diploCard.Visible, "le contenu de la fiche diplomatique reste masque")
	assert(hud.activeSheet == "diplomacy", `sous-menu actif "{tostring(hud.activeSheet)}" au lieu de "diplomacy"`)
	assert(string.find(hud.diploTitle.Text, "Nation2") ~= nil, `la fiche vise "{hud.diploTitle.Text}"`)

	-- Au moins une action doit etre proposee : une fiche sans bouton serait un
	-- panneau qui s'ouvre pour ne rien permettre.
	local offered = 0
	for _, b in hud.diploButtons do
		if b.Visible then
			offered += 1
		end
	end
	assert(offered > 0, "la fiche diplomatique n'offre aucune action")

	hud:selectFaction(nil)
	assert(not hud.diploDrawer.Visible, "la fiche reste ouverte apres deselection")

	-- La nation 7 est designee comme cible par l'allie : la fiche doit le dire,
	-- c'est l'information qui declenche une rupture avant la frappe.
	hud:selectFaction(7)
	assert(string.find(hud.diploStatus.Text, "\u{2691}") ~= nil, "la marque de cible n'apparait pas sur la fiche")
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

	--[[
		Chaque message porte sa croix de rejet : une demande d'alliance qu'on
		ne veut pas traiter ne doit pas rester a l'ecran jusqu'a expiration.
		Apres le rejet, le groupe est oublie — le meme message peut revenir
		sans heriter du compteur precedent.

		Le harnais execute task.delay immediatement : sans le court-circuiter,
		chaque message expirerait avant meme le retour de notify.
	]]
	local realDelay = task.delay
	task.delay = function() end
	hud:notify("a degager", "alert")
	local group = hud.feedGroups["a degager"]
	assert(group ~= nil, "le message ne rejoint pas le fil")
	local afterAdd = #hud.feedEntries
	local cross = group.entry:FindFirstChild("Dismiss")
	assert(cross ~= nil, "le message n'a pas sa croix de rejet")
	cross.Activated:Fire()
	assert(hud.feedGroups["a degager"] == nil, "le message rejete reste indexe")
	assert(#hud.feedEntries == afterAdd - 1, "le message rejete reste dans le fil")
	hud:notify("a degager", "alert")
	assert(hud.feedGroups["a degager"].count == 1, "le compteur survit au rejet")
	task.delay = realDelay
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

	--[[
		Construire n'ouvre plus RIEN.

		Sa palette a ete retiree : elle offrait une troisieme facon de choisir un
		batiment, apres la rangee du panneau de controle et la page "Batir" du
		menu radial, en occupant un tiers de l'ecran en permanence.
	]]
	-- On part d'un ecran propre : armer Construire ne FERME plus rien puisqu'il
	-- n'ouvre plus rien, donc une feuille laissee ouverte par l'etape precedente
	-- resterait la et fausserait le compte.
	hud:openSheet(nil)
	hud:setMode("build")
	assert(hud.sheets.build == nil, "la palette de construction existe encore")
	assert(openCount() == 0, `{openCount()} sous-menus ouverts apres Construire`)

	hud:setMode("nuke")
	assert(hud.sheets.nuke.Visible, "l'arsenal ne s'ouvre pas")
	assert(openCount() == 1, `{openCount()} sous-menus ouverts apres Frappe`)

	-- Armer deux fois le meme mode ne doit pas refermer sa feuille.
	hud:setMode("nuke")
	assert(hud.sheets.nuke.Visible, "rearmer un mode referme sa feuille")

	-- Un mode sans feuille ne laisse rien d'ouvert.
	hud:setMode("attack")
	assert(openCount() == 0, `{openCount()} sous-menus ouverts en mode Attaquer`)

	-- La fiche de profil ferme tout le reste, et son engrenage la referme.
	hud:openSheet("profile")
	assert(openCount() == 1, "la fiche de profil n'est pas exclusive")
	hud:openSheet("profile", true)
	assert(openCount() == 0, "l'engrenage ne referme pas la fiche de profil")

	-- Selectionner un territoire prend la place de toute autre feuille.
	hud:setMode("build")
	hud:selectTerritory(4242, 0, "Plaines", nil)
	assert(hud.territoryPanel.Visible, "la fiche de territoire ne s'ouvre pas")
	assert(openCount() == 1, `{openCount()} sous-menus ouverts avec la fiche de territoire`)
	hud:setMode("attack")
end)

check("messages rapides : catalogue, designation de cible et envoi", function()
	local sent = {}
	hud.onQuickChat = function(id, targetSlot)
		table.insert(sent, { id = id, target = targetSlot })
	end

	local function buttonWithText(text)
		for _, child in hud.chatBody:GetChildren() do
			if child:IsA("TextButton") and child.Text == text then
				return child
			end
		end
		return nil
	end

	hud:openSheet("chat")
	assert(hud.sheets.chat.Visible, "la feuille de messages ne s'ouvre pas")

	-- Un message sans cible part immediatement.
	hud.chatCategory = "social"
	hud:refreshChatSheet()
	local gg = buttonWithText("Bien joue !")
	assert(gg, "le message social n'est pas dans le catalogue affiche")
	gg.Activated:Fire()
	assert(#sent == 1 and sent[1].id == "social_gg" and sent[1].target == nil, "le message sans cible n'est pas parti")
	assert(not hud.sheets.chat.Visible, "la feuille ne se referme pas apres l'envoi")

	-- Un message avec cible demande une designation en deux temps.
	hud:openSheet("chat")
	hud.chatCategory = "attaque"
	hud:refreshChatSheet()
	local attack = buttonWithText("Attaquez ... !")
	assert(attack, "l'appel a l'attaque n'est pas affiche")
	attack.Activated:Fire()
	assert(hud.chatPending ~= nil, "la designation de cible ne s'ouvre pas")

	-- Choisir la nation 3 dans la liste des cibles.
	local target = buttonWithText("Nation3")
	assert(target, "la nation cible n'est pas listee")
	hud.chatSentAt = 0 -- neutralise l'anti-spam local pour le test
	target.Activated:Fire()
	assert(
		#sent == 2 and sent[2].id == "attack_target" and sent[2].target == 3,
		"le message cible n'est pas parti avec sa cible"
	)
end)

--[[
	Disposition CONQUEST.

	Le banc ne juge pas l'apparence — mais il peut verifier ou vivent les
	choses, et c'est exactement ce qui casse quand on deplace une interface :
	un panneau reste rattache a un parent disparu, ou un element cense etre
	permanent se retrouve derriere un sous-menu que plus personne n'ouvre. Rien
	de tout cela ne leve d'erreur, et tout cela se voit en jeu.
]]
check("disposition : panneau de controle en bas, aucun classement maison", function()
	--[[
		1. Aucun classement maison, sous aucune forme.

		Le jeu publie deja son classement dans la liste native de Roblox, celle
		qu'on ouvre avec Tab. En afficher un second demandait au joueur lequel
		des deux dit vrai — et obligeait a maintenir deux chemins de mise a jour
		pour la meme information.

		On verifie l'absence par le contenu de l'arbre et pas seulement par un
		champ a nil : un panneau construit puis oublie resterait affiche a
		l'ecran sans qu'aucun champ ne le trahisse.
	]]
	hud:openSheet(nil)
	assert(hud.sheets.nations == nil, "le classement est encore un sous-menu")
	assert(rawget(hud, "leaderPanel") == nil, "le panneau de classement est encore construit")
	assert(rawget(hud, "leaderRows") == nil, "les lignes de classement existent encore")
	for _, node in hud.root:GetDescendants() do
		assert(node.Name ~= "Leaderboard", "le panneau de classement est encore dans l'arbre")
	end

	--- 2. Le bas d'ecran n'appartient qu'au panneau de controle. ------------
	-- La rangee de modes, elle, ne doit exister que sur tactile : ici le banc
	-- simule un bureau, elle ne doit donc pas etre construite.
	assert(hud.controlPanel ~= nil, "le panneau de controle n'est pas construit")
	assert(
		hud.controlPanel.AnchorPoint.X == 0.5 and hud.controlPanel.AnchorPoint.Y == 1,
		"le panneau de controle n'est pas ancre en bas"
	)
	assert(hud.layers.bottom == nil, "le calque bas existe encore")
	assert(next(hud.modeButtons) == nil, "la rangee de modes existe encore")
	for _, node in hud.root:GetDescendants() do
		assert(node.Name ~= "CommandBar", "la barre basse est encore construite")
		assert(node.Name ~= "Modes", "la rangee de modes est encore construite")
	end

	--[[
		3. L'engagement vit dans le panneau de controle.

		On remonte la chaine de parents au lieu de compter les niveaux : la
		version precedente supposait une profondeur exacte, et un simple
		regroupement interne — ajouter un rail autour du remplissage — la faisait
		echouer alors que rien n'avait bouge a l'ecran.
	]]
	local function descendsFrom(node, ancestor): boolean
		local current = node
		for _ = 1, 8 do
			if current == nil then
				return false
			end
			if current == ancestor then
				return true
			end
			current = current.Parent
		end
		return false
	end
	assert(
		descendsFrom(hud.ratioFill, hud.controlPanel),
		"le curseur d'engagement n'est pas dans le panneau de controle"
	)
	assert(
		descendsFrom(hud.ratioKnob, hud.controlPanel),
		"la bille du curseur n'est pas dans le panneau de controle"
	)
	-- Le libelle vit dans sa propre puce, a gauche du rail : c'est la forme du
	-- CONQUEST — la puce dit combien part, le curseur decide.
	assert(hud.ratioReadout.Parent.Name == "RatioChip", "le libelle d'engagement n'est pas dans sa puce")
	assert(hud.ratioReadout.Parent.Parent == hud.controlPanel, "la puce d'engagement n'est pas dans le panneau")
	assert(hud.troopsLabel.Parent == hud.troopsFill.Parent, "le compteur d'armee n'est pas pose sur sa jauge")
	--[[
		Le libelle d'engagement dit DEUX choses : la part, et ce qu'elle vaut.

		L'ancienne assertion ne cherchait que le pourcentage. Elle serait donc
		restee verte si le nombre de troupes reellement engagees avait disparu —
		or c'est lui qu'on regarde avant de lancer une offensive, pas la part.
	]]
	hud:setRatio(0.5)
	local readout = hud.ratioReadout.Text
	assert(string.find(readout, "50%%") ~= nil, `engagement sans pourcentage : "{readout}"`)
	assert(string.find(readout, "%(") ~= nil, `engagement sans troupes engagees : "{readout}"`)

	--- 4. Coin haut droit : chrono, ere, sorties. ---------------------------
	assert(hud.timerLabel.Parent == hud.sessionBar, "le chrono n'est pas dans la barre de session")
	hud:setMatch({ phase = "playing", stage = "combat", timeLeft = 25, restartIn = 0 })
	assert(hud.timerLabel.Text == "00:25", `chrono affiche "{hud.timerLabel.Text}" au lieu de "00:25"`)

	--[[
		5. Rangee de batiments : raccourci, icone, compteur, et l'etat de verrou.

		Le raccourci affiche est la partie qui peut mentir en silence — il reste
		dessine que la touche fasse quelque chose ou non. On verifie donc qu'il
		existe pour chaque case ET que la case reagit au clic, faute de quoi le
		HUD annoncerait un geste qui n'aboutit nulle part.
	]]
	for _, def in BuildingDefs.BUILDABLE do
		local parts = hud.parkSlots[def.id]
		assert(parts ~= nil, `aucune case pour {def.name}`)
		assert(parts.key.Text ~= "", `la case de {def.name} n'affiche pas son raccourci`)
	end

	-- Un batiment verrouille par l'ere reste VISIBLE mais grise : le masquer
	-- ferait changer la longueur de la rangee en cours de partie, et le joueur
	-- perdrait la position qu'il vient d'apprendre.
	--[[
		Le grisage doit atteindre les DEUX sortes de glyphe.

		Trois batiments portent une image televersee, cinq portent encore un
		glyphe de repli. Une image se grise par ImageTransparency, un texte par
		TextTransparency — ecrire la mauvaise propriete ne leve aucune erreur, le
		glyphe reste simplement allume alors qu'il est verrouille. Sans cette
		lecture par type, la moitie de la rangee pourrait cesser de reagir sans
		que rien ne le signale.
	]]
	local function glyphDim(parts): number
		if parts.glyph:IsA("ImageLabel") then
			return parts.glyph.ImageTransparency or 0
		end
		return parts.glyph.TextTransparency or 0
	end

	hud.gold = 1000000
	hud.era = 1
	hud:refreshParkSlots()
	local locked, unlocked, images = 0, 0, 0
	for id, parts in hud.parkSlots do
		assert(parts.button.Visible ~= false, "une case verrouillee est masquee au lieu d'etre grisee")
		if parts.glyph:IsA("ImageLabel") then
			images += 1
			assert(parts.glyph.Image ~= "", `l'icone de {id} est vide`)
		end
		if hud.era >= Eras.requiredFor(id) then
			unlocked += 1
		else
			locked += 1
			assert(glyphDim(parts) > 0, `{id} est verrouille mais s'affiche en pleine lumiere`)
		end
	end
	assert(locked > 0 and unlocked > 0, "l'ere 1 ne separe plus les batiments verrouilles des autres")
	assert(images > 0, "aucune case n'utilise d'icone televersee")

	-- Et le verrou se leve quand l'ere avance, sinon il resterait ferme toute
	-- la partie sur un batiment pourtant debloque.
	hud.era = 5
	hud:refreshParkSlots()
	for _, parts in hud.parkSlots do
		assert(glyphDim(parts) == 0, "un batiment debloque et payable reste grise")
	end

	-- Trop cher grise aussi, mais differemment de verrouille : les deux ne
	-- disent pas la meme chose au joueur.
	hud.gold = 0
	hud:refreshParkSlots()
	for _, parts in hud.parkSlots do
		assert(glyphDim(parts) > 0, "un batiment hors budget s'affiche comme disponible")
	end
	hud.gold = 1000000

	--- 5b. Parc de batiments : une pastille par type constructible. ----------
	hud:setBuildingCounts({ [Config.BUILDING.CITY] = 3 })
	assert(hud.parkPills[Config.BUILDING.CITY].Text == "3", "le compteur de villes n'est pas repercute")
	assert(hud.parkPills[Config.BUILDING.SILO].Text == "0", "un type absent n'affiche pas zero")
	for _, def in BuildingDefs.BUILDABLE do
		assert(hud.parkPills[def.id] ~= nil, `aucune pastille pour {def.name}`)
	end

	--- 6. Le prix du palier suivant a sa propre colonne. --------------------
	-- Colle au bout du nom, il sortait du bouton des que l'ere s'appelait
	-- "Thermonucleaire" — et c'est le prix qui declenche le clic.
	local era, progress = hud.era, hud.eraProgress
	hud.era, hud.eraProgress = 4, 1
	hud:refreshEraPanel()
	assert(string.find(hud.eraPrice.Text, "or") ~= nil, "le prix du palier suivant n'est pas affiche")
	assert(string.find(hud.eraName.Text, "or") == nil, "le prix est encore colle au nom de l'ere")
	hud.era, hud.eraProgress = era, progress
	hud:refreshEraPanel()
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

check("hover spawn isolation : lisiere rouge, disque isole vert (N58)", function()
	local SpawnHint = __require("SpawnHint")
	local Theme = __require("Theme")
	local OCEAN = Config.TERRAIN.OCEAN
	local owner = world.owner

	local land: number? = nil
	local ocean: number? = nil
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(terrain, index) == OCEAN then
			if not ocean then
				ocean = index
			end
		else
			if not land then
				land = index
			end
		end
		if land and ocean then
			break
		end
	end
	assert(land ~= nil, "aucune terre")
	assert(ocean ~= nil, "aucun ocean")
	assert(SpawnHint.looksClaimable(terrain, owner, land), "disque isole encore rouge")
	assert(not SpawnHint.looksClaimable(terrain, owner, ocean), "ocean colore comme spawn")

	-- Peint tout le terre comme un empire sauf une lisiere (meme recette N55).
	local occupier = 1
	local pocket: number? = nil
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(terrain, index) ~= OCEAN then
			buffer.writeu8(owner, index, occupier)
		end
	end
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(terrain, index) ~= OCEAN then
			local x, y = MapGen.fromIndex(index)
			local adj = false
			for dx = -1, 1 do
				for dy = -1, 1 do
					if dx ~= 0 or dy ~= 0 then
						local nx, ny = x + dx, y + dy
						if MapGen.inBounds(nx, ny) then
							local ni = MapGen.toIndex(nx, ny)
							if buffer.readu8(terrain, ni) ~= OCEAN and buffer.readu8(owner, ni) == occupier then
								adj = true
							end
						end
					end
				end
			end
			if adj then
				buffer.writeu8(owner, index, 0)
				pocket = index
				break
			end
		end
	end
	assert(pocket ~= nil, "lisiere introuvable")
	assert(not SpawnHint.looksClaimable(terrain, owner, pocket), "lisiere encore verte")
	effects:previewTile(pocket, Theme.color.danger, false)
	effects:clearActionPreview()

	-- Restaure le buffer owner du monde (tout NEUTRAL) pour les checks suivants.
	for index = 0, Config.TILE_COUNT - 1 do
		buffer.writeu8(owner, index, 0)
	end
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

	--[[
		On se place dans le cas d'une usine posee EN COURS DE PARTIE.

		A la connexion, `animateFrom` bloque volontairement les chantiers : voir
		trente voies ramper en meme temps a l'arrivee serait absurde. Le banc
		venant de creer la couche, il tombe par defaut dans ce cas-la — et
		testerait donc precisement la situation ou l'animation ne doit PAS
		exister.
	]]
	overlay.animateFrom = 0

	-- Une usine est une gare : elle trace une voie vers chaque gare a portee.
	factoryEntry.links = { cityIndex, cityIndex + 300, cityIndex + 700 }
	overlay:applyBuildingDelta({ factoryEntry })
	local _, _, _, routeCount = overlay:buildingAt(factoryEntry.index)
	assert(routeCount == 3, `l'usine annonce {routeCount} routes au lieu de 3`)
	local built, sample = routesOf(factoryEntry.index)
	assert(built == 3, `{built} routes tracees au lieu de 3`)
	--[[
		Le trace suit la grille : chaque segment est strictement horizontal ou
		vertical, jamais en biais.

		C'est la seule propriete qui distingue une voie alignee d'une courbe, et
		elle est invisible a la lecture du code de rendu — une erreur de calcul
		produirait des diagonales parfaitement plausibles que personne ne
		remarquerait avant de lancer le jeu.
	]]
	assert(sample and #sample.path >= 2, "la route logistique n'a pas de trace")
	for i = 1, #sample.path - 1 do
		local a, b = sample.path[i], sample.path[i + 1]
		local dx = math.abs(b.X - a.X)
		local dz = math.abs(b.Z - a.Z)
		assert(
			dx < 0.001 or dz < 0.001,
			`segment {i} de la route part en diagonale (dx={dx}, dz={dz})`
		)
	end

	--[[
		La voie se construit progressivement, elle n'apparait pas d'un bloc.

		Rien ne leverait d'erreur si le chantier disparaissait : la route
		s'afficherait simplement finie des la premiere image, et personne ne
		verrait la difference sans comparer deux parties cote a cote.

		On mesure la longueur cumulee des chaussees, qui doit croitre puis se
		stabiliser — c'est la seule trace observable de l'animation.
	]]
	local function pavedLength(): number
		local total = 0
		for _, route in overlay.routes do
			if route.factory == factoryEntry.index then
				for _, part in route.model:GetChildren() do
					if part.Name == "Road" and part.Size then
						total += part.Size.Z
					end
				end
			end
		end
		return total
	end

	local atStart = pavedLength()
	overlay:stepInterpolation(0.2)
	local partway = pavedLength()
	assert(
		partway > atStart,
		`la voie ne s'allonge pas : {atStart} puis {partway}`
	)

	-- Au bout d'un temps largement suffisant, elle est finie et le chantier est
	-- libere — sinon il resterait a tourner pour rien a chaque image.
	for _ = 1, 30 do
		overlay:stepInterpolation(0.2)
	end
	local finished = pavedLength()
	assert(finished > partway, "la voie ne se termine jamais")
	for _, route in overlay.routes do
		if route.factory == factoryEntry.index then
			assert(route.construction == nil, "le chantier tourne encore apres la fin de la voie")
		end
	end

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

--[[
	Silhouettes procédurales : le niveau doit se voir.

	Ville, port et usine se stackent — cliquer a cote d'un exemplaire existant le
	fait monter d'un palier au lieu d'en poser un second, et son rendement suit.
	Tant que le modele ignorait ce niveau, deux batiments de rendement tres
	different etaient identiques a l'ecran, et le chiffre flottant au-dessus
	restait le seul indice sur une carte ou l'on lit d'abord les formes.

	Aucune erreur ne serait levee si la regle disparaissait : le batiment
	s'afficherait, simplement toujours au meme gabarit.
]]
check("modeles procéduraux : le palier change la silhouette", function()
	local Building = __require("BuildingModels")

	local function summit(kind: number, level: number): (number, number)
		local model = Building.create(kind, Color3.fromRGB(200, 60, 60), Vector3.new(0, 0, 0), level)
		local top, parts = 0, 0
		for _, part in model:GetChildren() do
			if part.Size then
				parts += 1
				local height = part.Position.Y + part.Size.Y / 2
				if height > top then
					top = height
				end
			end
		end
		return top, parts
	end

	for _, kind in { Config.BUILDING.CITY, Config.BUILDING.FACTORY, Config.BUILDING.PORT } do
		local lowTop, lowParts = summit(kind, 1)
		local highTop, highParts = summit(kind, 3)
		local def = BuildingDefs.get(kind)
		local name = if def then def.name else tostring(kind)

		assert(lowParts > 0, `{name} : le modele de niveau 1 ne produit aucune Part`)
		assert(
			highTop > lowTop + 0.5,
			`{name} : niveau 3 culmine a {highTop} contre {lowTop} au niveau 1 — le palier ne se voit pas`
		)

		--[[
			Le budget de Parts est une contrainte reelle, pas une preference.

			Le module l'annonce en tete : une partie compte plusieurs dizaines de
			batiments, et le terrain en consomme deja des milliers. Un modele qui
			double de complexite au niveau 3 ferait tomber les images sur mobile
			exactement quand la partie devient interessante.
		]]
		assert(highParts <= 18, `{name} : {highParts} Parts au niveau 3, budget depasse`)

		-- L'etiquette flottante doit suivre : sinon elle se plante au milieu du
		-- batiment qui vient de grandir.
		assert(
			Building.heightOf(kind, 3) > Building.heightOf(kind, 1),
			`{name} : la hauteur de reference ne suit pas le palier`
		)
	end
end)

check("apercu de placement pour chaque batiment", function()
	for _, def in BuildingDefs.BUILDABLE do
		preview:setKind(def.id)
		preview:update(1000, "exact")
		preview:update(1200, "snap")
		preview:update(1300, "upgrade")
		preview:update(1400, "invalid")
		preview:update(nil, "invalid")
	end
	preview:hide()
end)

--[[
	Accrochage du placement.

	C'est le comportement qui remplace le refus sur clic invalide, et c'est aussi
	celui qui a le plus de facons de casser en silence : le fantome et le serveur
	executent le meme module, mais avec deux contextes differents. Si l'un des
	deux ment sur la propriete d'une tuile ou sur un batiment pose, le joueur voit
	un fantome vert la ou le serveur refusera.
]]
check("accrochage du placement et bascule en amelioration", function()
	-- On cherche une zone de terre continue assez large pour y travailler.
	local origin: number? = nil
	for index = 0, Config.TILE_COUNT - 1 do
		local x, y = index % Config.MAP_WIDTH, index // Config.MAP_WIDTH
		if x > 12 and x < Config.MAP_WIDTH - 12 and y > 12 and y < Config.MAP_HEIGHT - 12 then
			local solid = true
			for dy = -8, 8 do
				for dx = -8, 8 do
					local n = (y + dy) * Config.MAP_WIDTH + (x + dx)
					if buffer.readu8(terrain, n) == Config.TERRAIN.OCEAN then
						solid = false
						break
					end
				end
				if not solid then
					break
				end
			end
			if solid then
				origin = index
				break
			end
		end
	end
	assert(origin ~= nil, "aucune zone de terre continue pour tester le placement")

	local ox, oy = (origin :: number) % Config.MAP_WIDTH, (origin :: number) // Config.MAP_WIDTH
	local MINE = 1

	local owned: { [number]: true } = {}
	for dy = -8, 8 do
		for dx = -8, 8 do
			owned[(oy + dy) * Config.MAP_WIDTH + (ox + dx)] = true
		end
	end

	local placed: { [number]: { kind: number, slot: number, level: number } } = {}
	local function ownerAt(index: number): number
		return if owned[index] then MINE else 0
	end
	local function buildingAt(index: number): (number?, number?, number?)
		local b = placed[index]
		if not b then
			return nil, nil, nil
		end
		return b.kind, b.slot, b.level
	end

	local counts: { [number]: number } = {}
	local function resolve(index: number, kind: number)
		return preview:resolve(index, kind, ownerAt, buildingAt, MINE, 9, 1000000, counts, 1)
	end

	preview:setKind(Config.BUILDING.CITY)

	-- 1. Terrain libre : le fantome se pose exactement sous le curseur.
	local landing, status = resolve(origin :: number, Config.BUILDING.CITY)
	assert(status == "exact", `terrain libre : statut {status} au lieu de "exact"`)
	assert(landing == origin, "terrain libre : le fantome n'est pas sous le curseur")

	-- 2. Tuile occupee par un autre type : le clic est reporte a cote au lieu
	-- d'etre refuse. C'est tout le changement de comportement.
	placed[origin :: number] = { kind = Config.BUILDING.DEFENSE, slot = MINE, level = 1 }
	counts[Config.BUILDING.DEFENSE] = 1
	landing, status = resolve(origin :: number, Config.BUILDING.CITY)
	assert(status == "snap", `tuile occupee : statut {status} au lieu de "snap"`)
	assert(landing ~= origin, "tuile occupee : le clic n'a pas ete reporte")

	-- 3. Le report respecte l'espacement minimal, tous types confondus.
	local lx, ly = landing % Config.MAP_WIDTH, landing // Config.MAP_WIDTH
	local dx, dy = lx - ox, ly - oy
	assert(
		dx * dx + dy * dy >= Config.BUILD_MIN_SPACING * Config.BUILD_MIN_SPACING,
		"le report ignore l'espacement minimal entre batiments"
	)

	-- 4. Une ville a portee bascule le clic en amelioration : un seul bouton par
	-- type, aucun mode a choisir pour le joueur.
	placed[landing] = { kind = Config.BUILDING.CITY, slot = MINE, level = 1 }
	counts[Config.BUILDING.CITY] = 1
	local upgradeTile, upgradeStatus = resolve(landing, Config.BUILDING.CITY)
	assert(upgradeStatus == "upgrade", `ville existante : statut {upgradeStatus} au lieu de "upgrade"`)
	assert(upgradeTile == landing, "l'amelioration ne vise pas la ville cliquee")

	-- 5. Une ville au niveau maximum ne bascule plus : on repose a cote.
	placed[landing].level = BuildingDefs.maxLevel(Config.BUILDING.CITY)
	local _, maxedStatus = resolve(landing, Config.BUILDING.CITY)
	assert(maxedStatus ~= "upgrade", "une ville au niveau maximum propose encore une amelioration")

	-- 6. Hors territoire : c'est le seul refus de position qui subsiste, et il
	-- correspond a une autre intention, pas a une erreur de visee.
	local foreign = (oy - 12) * Config.MAP_WIDTH + ox
	local _, foreignStatus = resolve(foreign, Config.BUILDING.CITY)
	assert(foreignStatus == "invalid", "un clic hors territoire est accepte")

	-- 7. Sans or, aucun placement : la seule autre raison de refus.
	local _, brokeStatus = preview:resolve(origin :: number, Config.BUILDING.CITY, ownerAt, buildingAt, MINE, 9, 0, counts, 1)
	assert(brokeStatus == "invalid", "un placement est propose sans l'or necessaire")

	preview:hide()
end)

--[[
	Menu radial.

	Il porte desormais toutes les actions de jeu, et il n'a aucune trace a
	l'ecran tant qu'il est ferme : une panne y est parfaitement silencieuse
	jusqu'au moment ou un joueur clique droit et ne voit rien.
]]
check("menu radial : pages, contexte et sorties", function()
	local menu = RadialMenu.new(screenGui)
	assert(not menu:isOpen(), "le menu est ouvert avant qu'on le demande")

	local actions: { string } = {}
	local builds: { number } = {}
	menu.onAction = function(action: string, tile: number)
		table.insert(actions, `{action}@{tile}`)
	end
	menu.onBuild = function(kind: number, tile: number)
		table.insert(builds, kind)
	end

	--- Sur une case etrangere : attaquer est possible, batir non. ------------
	menu:open(400, 300, { tile = 1234, ownerSlot = 2, mySlot = 1, era = 5, nukesUnlocked = true })
	assert(menu:isOpen(), "le menu ne s'ouvre pas")

	local function petalNamed(label: string)
		for _, p in menu.petals do
			if p.button.Visible and p.label.Text == label then
				return p
			end
		end
		return nil
	end

	local attack = petalNamed("Attaquer")
	local build = petalNamed("Batir")
	assert(attack and build, "l'anneau racine n'expose pas Attaquer et Batir")
	assert(not attack.button:GetAttribute("Disabled"), "Attaquer est grise sur un territoire ennemi")
	assert(build.button:GetAttribute("Disabled"), "Batir est propose sur un territoire ennemi")

	--- Sur son propre territoire, l'inverse. --------------------------------
	menu:open(400, 300, { tile = 77, ownerSlot = 1, mySlot = 1, era = 5, nukesUnlocked = true })
	attack = petalNamed("Attaquer")
	build = petalNamed("Batir")
	assert(attack and build, "l'anneau racine a change de contenu selon le proprietaire")
	assert(attack.button:GetAttribute("Disabled"), "Attaquer est propose sur son propre territoire")
	assert(not build.button:GetAttribute("Disabled"), "Batir est grise sur son propre territoire")

	--- Batir ouvre la page des batiments sans fermer le menu ni perdre la case.
	build.button.Activated:Fire()
	assert(menu:isOpen(), "choisir Batir a ferme le menu")
	assert(menu.page == "build", "la page des batiments ne s'ouvre pas")
	assert(menu.context.tile == 77, "la case visee est perdue en changeant de page")

	local shown = 0
	for _, p in menu.petals do
		if p.button.Visible then
			shown += 1
		end
	end
	assert(shown == #BuildingDefs.BUILDABLE, `{shown} batiments affiches sur {#BuildingDefs.BUILDABLE}`)

	--- Le moyeu revient en arriere au lieu de tout fermer. -------------------
	menu.hub.Activated:Fire()
	assert(menu:isOpen() and menu.page == "root", "le moyeu ferme le menu au lieu de revenir a l'anneau")

	--- Une action sort la valeur puis referme. ------------------------------
	menu:open(400, 300, { tile = 512, ownerSlot = 3, mySlot = 1, era = 5, nukesUnlocked = true })
	local strike = petalNamed("Frapper")
	assert(strike and not strike.button:GetAttribute("Disabled"), "Frapper est indisponible malgre l'ere atomique")
	strike.button.Activated:Fire()
	assert(actions[#actions] == "nuke@512", `sortie inattendue : {actions[#actions]}`)
	assert(not menu:isOpen(), "le menu reste ouvert apres une action")

	--- Un petale grise ne declenche rien. -----------------------------------
	menu:open(400, 300, { tile = 900, ownerSlot = 1, mySlot = 1, era = 1, nukesUnlocked = false })
	local before = #actions
	local blocked = petalNamed("Attaquer")
	assert(blocked, "Attaquer a disparu de l'anneau")
	blocked.button.Activated:Fire()
	assert(#actions == before, "un petale grise a quand meme declenche son action")
	assert(menu:isOpen(), "un petale grise a ferme le menu")

	--- L'ere verrouille les batiments avances. ------------------------------
	petalNamed("Batir").button.Activated:Fire()
	local locked = false
	for _, p in menu.petals do
		if p.button.Visible and p.button:GetAttribute("Disabled") then
			locked = true
			break
		end
	end
	assert(locked, "aucun batiment n'est verrouille a l'ere 1")

	--- Ouvert dans un coin, l'anneau reste entierement a l'ecran. -----------
	menu:open(0, 0, { tile = 5, ownerSlot = 0, mySlot = 1, era = 3, nukesUnlocked = false })
	assert(
		menu.ring.Position.X.Offset > 0 and menu.ring.Position.Y.Offset > 0,
		"le menu ouvert dans un coin deborde de l'ecran"
	)

	--- Un clic a cote referme. ----------------------------------------------
	menu.veil.Activated:Fire()
	assert(not menu:isOpen(), "cliquer a cote ne ferme pas le menu")

	menu:destroy()
end)

--[[
	Etiquettes de faction posees sur la carte.

	Elles n'existent que dans le monde 3D, donc rien a l'ecran ne signale une
	panne : un barycentre faux pose simplement le nom d'un pays au milieu de la
	mer, et un formatage casse affiche 87500 la ou on attend 87.5K.
]]
check("etiquettes de faction : centre, contenu et disparition", function()
	local labels = FactionLabels.new(world.root, terrain)

	-- Deux factions, l'une a gauche de la carte, l'autre a droite.
	local owner = buffer.create(Config.TILE_COUNT)
	local leftTiles, rightTiles = 0, 0
	for y = 40, 70 do
		for x = 20, 50 do
			buffer.writeu8(owner, y * Config.MAP_WIDTH + x, 1)
			leftTiles += 1
		end
		for x = 180, 200 do
			buffer.writeu8(owner, y * Config.MAP_WIDTH + x, 2)
			rightTiles += 1
		end
	end

	local stats = {
		[1] = { troops = 87500 },
		[2] = { troops = 1290000 },
	}
	local roster = {
		[1] = { name = "Valoria" },
		[2] = { name = "Ostrave" },
	}

	labels:refresh(owner, stats, roster)

	local first = labels.labels[1]
	local second = labels.labels[2]
	assert(first and second, "une faction possedant du territoire n'a pas d'etiquette")

	assert(first.name.Text == "Valoria", `nom incorrect : {first.name.Text}`)
	assert(first.troops.Text == "87.5K", `troupes affichees "{first.troops.Text}" au lieu de "87.5K"`)
	assert(second.troops.Text == "1.29M", `troupes affichees "{second.troops.Text}" au lieu de "1.29M"`)

	--[[
		Le barycentre tombe bien dans le territoire.

		C'est la seule verification qui attrape une erreur d'echantillonnage : un
		barycentre calcule sur la mauvaise dimension resterait un point
		parfaitement valide, juste pose au mauvais endroit.
	]]
	assert(
		first.anchor.CFrame.X < second.anchor.CFrame.X,
		"les deux etiquettes ne sont pas dans l'ordre est-ouest de leurs territoires"
	)

	-- La grande faction porte un nom plus large que la petite.
	assert(
		first.billboard.Size.X.Scale > second.billboard.Size.X.Scale,
		"la taille de l'etiquette ne suit pas la taille de l'empire"
	)

	-- Une faction effacee de la carte perd son etiquette au lieu de la laisser
	-- flotter sur un territoire qui ne lui appartient plus.
	local emptied = buffer.create(Config.TILE_COUNT)
    for y = 40, 70 do
        for x = 180, 200 do
            buffer.writeu8(emptied, y * Config.MAP_WIDTH + x, 2)
        end
    end
	labels:refresh(emptied, stats, roster)
	assert(labels.labels[1] == nil, "une faction sans territoire garde son etiquette")
	assert(labels.labels[2] ~= nil, "une faction encore vivante a perdu son etiquette")

	-- N96 : owner tout NEUTRAL → plus d'ancres (leftover hash interdit).
	local barren = buffer.create(Config.TILE_COUNT)
	labels:refresh(barren, stats, roster)
	assert(labels.labels[1] == nil and labels.labels[2] == nil, "etiquette fantome apres carte neutre")

	labels:clear()
	assert(next(labels.labels) == nil, "les etiquettes ne sont pas liberees")
end)

--[[
	Le "+X or" d'une livraison.

	Toute la chaine existait deja et fonctionnait cote serveur — mesure sur une
	partie : 669 colis arrives. Ce qui manquait etait a l'affichage, et rien ne
	pouvait le voir : un popup trop discret s'affiche sans erreur.
]]
check("livraison : le gain s'affiche sur la gare", function()
	overlay:setLocalSlot(1)

	local function popups(): number
		local n = 0
		for _, node in overlay.root:GetChildren() do
			if node.Name == "GoldPopup" then
				n += 1
			end
		end
		return n
	end

	local before = popups()
	overlay:onTradeEvent("arrival", 3000, 0, 1, 1240)
	assert(popups() == before + 1, "l'arrivee d'un colis n'affiche rien")

	-- Le chiffre est formate comme partout ailleurs, et porte son unite.
	local latest
	for _, node in overlay.root:GetChildren() do
		if node.Name == "GoldPopup" then
			latest = node
		end
	end
	local board = latest:FindFirstChild("Board")
	local label = board and board:FindFirstChildWhichIsA("TextLabel")
	assert(label ~= nil, "le popup n'a pas de texte")
	assert(label.Text == "+1.24K or", `le popup affiche "{label.Text}" au lieu de "+1.24K or"`)

	--[[
		Notre livraison se lit plus fort que celle du voisin.

		Sept cents colis arrivent en dix minutes sur une carte peuplee. Les
		afficher tous pareil noyait le seul chiffre qui compte pour le joueur.
	]]
	local mineSize = board.Size.Y.Offset
	overlay:onTradeEvent("arrival", 3100, 0, 2, 1240)
	local other
	for _, node in overlay.root:GetChildren() do
		if node.Name == "GoldPopup" and node ~= latest then
			other = node
		end
	end
	local otherBoard = other and other:FindFirstChild("Board")
	assert(otherBoard ~= nil, "la livraison d'un rival n'affiche rien")
	assert(
		otherBoard.Size.Y.Offset < mineSize,
		"la livraison d'un rival s'affiche aussi fort que la notre"
	)
end)

check("navires, missiles et interpolation", function()
	overlay:applyUnits({
		{ id = 1, slot = 1, x = 10, y = 10, troops = 100, kind = 1, retreating = true },
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
	-- N98 : extra missile mute, pas remplace. Navire : extra reste nil
	-- (retraite N56 via retreatTinted).
	assert(overlay.units[1].extra == nil, "un navire ne doit pas porter extra")
	local extra = overlay.units[3].extra
	assert(extra ~= nil and extra.tx == 60 and extra.ty == 60, "extra missile initial absent")
	overlay:applyUnits({
		{ id = 1, slot = 1, x = 10, y = 10, troops = 100, kind = 1, retreating = true },
		{ id = 2, slot = 2, x = 20, y = 30, troops = 0, kind = 2 },
		{ id = 4, slot = 3, x = 30, y = 30, troops = 0, kind = 3 },
	}, {
		{ id = 3, slot = 1, x = 40, y = 40, tx = 80, ty = 90, kind = 1 },
	})
	assert(overlay.units[3].extra.tx == 80 and overlay.units[3].extra.ty == 90, "extra missile non mute")
	assert(rawequal(extra, overlay.units[3].extra), "record extra missile remplace")
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

	-- N95 : prise sur une faction puis delta vide → leftover truncate.
	-- Coloniser du neutre ne classe rien ; occuper en 2 puis capturer en 1
	-- produit un gain. Le second applyDelta (payload vide) doit renvoyer
	-- les memes pools a # == 0, sinon un splash fantome rejouerait la tuile.
	local occupy = buffer.create(5)
	buffer.writeu32(occupy, 0, 2100)
	buffer.writeu8(occupy, 4, 2)
	world:applyDelta(occupy, 1)
	local capture = buffer.create(5)
	buffer.writeu32(capture, 0, 2100)
	buffer.writeu8(capture, 4, 1)
	local _, g2, l2, o2 = world:applyDelta(capture, 1)
	assert(#g2 == 1 and g2[1] == 2100, "prise locale non classee en gain")
	assert(#l2 == 0 and #o2 == 0, "prise locale mal classee")
	local empty = buffer.create(0)
	local changed0, g3, l3, o3 = world:applyDelta(empty, 1)
	assert(changed0 == 0, "delta vide count")
	assert(#g3 == 0 and #l3 == 0 and #o3 == 0, "leftover applyDelta non truncate")
	assert(rawequal(g2, g3) and rawequal(l2, l3) and rawequal(o2, o3), "pools applyDelta non recycles")

	world:stepRebuilds()
end)

check("camera strategique", function()
	local camera = WorldCamera.new()
	camera:setMode("overview")
	camera:setDistance(300, true)
	camera:focusTile(5000, true)
	camera:step(1 / 60)

	--[[
		Panoramique libre au clic du milieu, le geste CONQUEST.
		Les faux InputObject sont de simples tables : le code ne lit que
		UserInputType, Position et Delta.
	]]
	local uis = game:GetService("UserInputService")
	local anchor = camera.targetFocus
	uis.InputBegan:Fire(
		{ UserInputType = Enum.UserInputType.MouseButton3, Position = Vector3.new(400, 300, 0), Delta = Vector3.zero },
		false
	)
	uis.InputChanged:Fire({
		UserInputType = Enum.UserInputType.MouseMovement,
		Position = Vector3.new(460, 330, 0),
		Delta = Vector3.new(60, 30, 0),
	})
	assert(camera.targetFocus ~= anchor, "le glissement au clic du milieu ne deplace pas la camera")
	uis.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton3, Position = Vector3.new(460, 330, 0), Delta = Vector3.zero })
	local afterRelease = camera.targetFocus
	uis.InputChanged:Fire({
		UserInputType = Enum.UserInputType.MouseMovement,
		Position = Vector3.new(500, 350, 0),
		Delta = Vector3.new(40, 20, 0),
	})
	assert(camera.targetFocus == afterRelease, "la camera bouge encore apres le relachement")

	camera:toggleMode()
	camera:step(1 / 60)
	camera:toggleMode()
	camera:tileAtScreen(Vector2.new(100, 100), world.root)
end)

--[[
	Gestes tactiles de la camera.

	Sans ce banc, un signe inverse ou un nil dans le pincement ne se verrait que
	sur un vrai telephone, entre les mains d'un joueur. Les faux InputObject sont
	de simples tables : le code ne lit que UserInputType et Position.
]]
check("camera tactile : panoramique, pincement et torsion", function()
	local uis = game:GetService("UserInputService")
	local camera = WorldCamera.new()
	camera:setMode("overview")
	camera:setDistance(300, true)
	camera:focusTile(5000, true)

	local function touch(x: number, y: number)
		return { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(x, y, 0), Delta = Vector3.zero }
	end

	--- Un doigt sous le seuil : c'est un tap, la mire ne bouge pas. -----------
	local fingerA = touch(100, 100)
	uis.InputBegan:Fire(fingerA, false)
	assert(camera.touchCount == 1, "le doigt n'est pas enregistre")
	local anchor = camera.targetFocus
	fingerA.Position = Vector3.new(104, 103, 0)
	uis.InputChanged:Fire(fingerA)
	assert(camera.targetFocus == anchor, "un micro-glissement a deplace la camera")

	--- Au-dela du seuil : panoramique, avec rattrapage depuis l'origine. ------
	fingerA.Position = Vector3.new(160, 140, 0)
	uis.InputChanged:Fire(fingerA)
	assert(camera.targetFocus ~= anchor, "le glissement ne deplace pas la camera")

	--- Deuxieme doigt : l'ecartement pilote le zoom. ---------------------------
	local fingerB = touch(300, 100)
	uis.InputBegan:Fire(fingerB, false)
	assert(camera.touchCount == 2, "le second doigt n'est pas enregistre")
	local before = camera.targetDistance
	fingerA.Position = Vector3.new(60, 140, 0) -- ecartement +80 px
	uis.InputChanged:Fire(fingerA)
	assert(camera.targetDistance < before, "ecarter les doigts ne rapproche pas la camera")

	--- La torsion fait tourner la carte. ---------------------------------------
	local yawBefore = camera.targetYaw
	fingerB.Position = Vector3.new(300, 180, 0)
	uis.InputChanged:Fire(fingerB)
	assert(camera.targetYaw ~= yawBefore, "la torsion ne fait pas tourner la carte")

	--- Retrait des doigts : l'etat se nettoie. ---------------------------------
	uis.InputEnded:Fire(fingerB)
	assert(camera.touchCount == 1 and camera.pinch == nil, "le pincement survit au retrait d'un doigt")
	uis.InputEnded:Fire(fingerA)
	assert(camera.touchCount == 0, "les doigts ne sont pas liberes")

	--- Un doigt ignore par l'interface ne pilote pas la camera. ----------------
	local ignored = touch(50, 50)
	uis.InputBegan:Fire(ignored, true)
	assert(camera.touchCount == 0, "un touch consomme par l'interface pilote quand meme la camera")

	camera:step(1 / 60)
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

--[[
	Barre d'action tactile.

	Le banc simule un poste de travail : la barre ne doit donc PAS exister tant
	que personne ne la force — c'est le contrat de la disposition CONQUEST. On
	la construit ensuite a la main pour verifier qu'elle arme les modes comme le
	clavier, qu'elle decale les feuilles du bas, et qu'elle ne se duplique pas.

	Placee en dernier : elle peuple volontairement `modeButtons`, que le test de
	disposition verifie vide — l'ordre des verifications fait donc partie du
	contrat.
]]
check("barre tactile : modes, recentrage et feuilles decalees", function()
	assert(hud.touchBar == nil, "la barre tactile existe sur un appareil a clavier")
	assert(next(hud.modeButtons) == nil, "des boutons de mode existent sans tactile")

	-- La palette de construction ayant disparu, l'arsenal sert de temoin : c'est
	-- desormais la feuille du bas qui doit remonter au-dessus de la barre.
	local sheetOffsetBefore = hud.sheets.nuke.Position.Y.Offset

	hud.touchOnly = true
	hud:buildTouchBar()
	assert(hud.touchBar ~= nil, "la barre tactile ne se construit pas")
	assert(next(hud.modeButtons) ~= nil, "les modes n'ont pas de bouton tactile")

	--- Armer un mode depuis la barre produit le meme etat que le clavier. -----
	hud.modeButtons.boat.Activated:Fire()
	assert(hud.mode == "boat", "le bouton Debarquer n'arme pas le mode")
	assert(hud.modeButtons.boat:GetAttribute("Selected"), "le mode actif n'est pas mis en evidence")
	assert(not hud.modeButtons.attack:GetAttribute("Selected"), "l'ancien mode reste mis en evidence")

	--- Le bouton Capitale appelle le rappel branche par le client. -------------
	local recalled = 0
	hud.onRecenter = function()
		recalled += 1
	end
	hud.touchHome.Activated:Fire()
	assert(recalled == 1, "le bouton Capitale ne declenche pas le recentrage")

	--- Les feuilles du bas passent au-dessus de la barre. ----------------------
	assert(
		hud.sheets.nuke.Position.Y.Offset < sheetOffsetBefore,
		"la palette de construction reste sous la barre tactile"
	)

	--- Une seconde construction ne duplique rien. ------------------------------
	local bar = hud.touchBar
	hud:buildTouchBar()
	assert(hud.touchBar == bar, "la barre tactile se construit en double")

	hud:setMode("attack")
end)

--=============================================================================
-- Rapport
--=============================================================================

print("")
if failures == 0 then
	print("\27[32mTous les ecrans se construisent et s'executent sans erreur.\27[0m")
else
	print(`\27[31m{failures} defaillance(s) client.\27[0m`)
	os.exit(1)
end
