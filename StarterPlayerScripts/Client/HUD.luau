--!strict
--[[
	Interface de commandement, calee sur la disposition CONQUEST
	 :

	  haut gauche     la carte d'identite : nation, doctrine, territoire
	  haut droit      la session : chrono, recherche, reglages
	  bas centre      le panneau de controle : cadence, armee, or, engagement
	  bas droit       le fil des evenements

	Le panneau de controle est le coeur de l'interface — deux lignes qui
	repondent a "de quoi je dispose, la, maintenant" :

	  ligne 1   ce qui rentre : cadence de population, armee sur capacite, or
	  ligne 2   ce qui part : le curseur d'engagement et le chiffre envoye

	Le centre de l'ecran ne porte rien en permanence : c'est la seule regle de
	disposition qui compte, parce que le centre EST le jeu.

	Tout le reste s'ouvre a la demande, et **un seul sous-menu a la fois** —
	c'est la regle qui empeche l'interface de redevenir un empilement de douze
	panneaux dont aucun ne sait se fermer.

	Le HUD ne connait ni le reseau ni la carte. Il expose des callbacks que
	init.client branche sur les remotes, et un mode courant que le controleur de
	saisie interroge.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))
local Doctrines = require(Shared:WaitForChild("Doctrines"))
local BuildingDefs = require(Shared:WaitForChild("BuildingDefs"))
local Eras = require(Shared:WaitForChild("Eras"))
local Format = require(Shared:WaitForChild("Format"))
local QuickChat = require(Shared:WaitForChild("QuickChat"))
local SoundManager = require(script.Parent.SoundManager)

local C = Theme.color
local S = Theme.space
local F = Theme.font
local T = Theme.textSize

local HUD = {}
HUD.__index = HUD

-- Le fil de notifications ne doit jamais depasser cette hauteur : au-dela il
-- recouvre la carte, qui est l'element le plus important de l'ecran.
local MAX_FEED_ENTRIES = 3
local FEED_ENTRY_HEIGHT = 21

--[[
	Geometrie, disposition CONQUEST.

	Les hauteurs sont derivees, jamais recopiees : le panneau de controle, les
	feuilles et la barre tactile s'empilent depuis la meme reference, donc
	changer CONTROL_HEIGHT deplace la pile entiere sans laisser un panneau en
	arriere.
]]

-- Panneau de controle, bas centre : deux lignes de commande et le parc.
--[[
	Largeur DERIVEE de la rangee de batiments, jamais choisie.

	Elle etait figee a 500 px pour une rangee qui n'en occupe que 428 : le
	panneau trainait donc 72 px de vide a droite, et la comparaison cote a cote
	avec la reference le montrait immediatement — leurs cases remplissent leur
	panneau, les notres flottaient dedans.

	Deriver la largeur du contenu rend ce vide impossible, et un batiment ajoute
	ou retire elargit le panneau au lieu de deregler la rangee.
]]
-- Case de la rangee de batiments. Resserree apres comparaison cote a cote : la
-- reference tient dix cases dans la largeur ou nous en mettions huit, et ses
-- cases sont sensiblement plus courtes que les notres.
--[[
	Densite : le defaut qui faisait "cheap", et il ne tenait pas aux couleurs.

	Mesure cote a cote : notre panneau faisait 396 x 106 px, le leur est deux
	fois plus large que haut a contenu comparable. Leurs cases sont NETTEMENT
	plus larges que hautes ; les notres etaient presque carrees, ce qui les
	faisait lire comme une grille de tuiles au lieu d'une bande d'outils.

	Une interface de strategie parait soignee quand elle est dense. Chaque pixel
	d'air en trop la fait paraitre amateur, quelle que soit la qualite du reste.
]]
local SLOT_WIDTH = 44
local SLOT_HEIGHT = 26
-- Meme taille d'icone que la reference (`w-4` = 16 px). A 26 px de haut, une
-- icone de 18 ne laissait plus de place au raccourci en exposant.
local SLOT_ICON = 16

-- Marge du panneau et interligne. Resserres avec les cases : garder 8 px
-- d'interligne autour de rangees plus courtes aurait annule le gain.
local PANEL_PAD = 6
local ROW_GAP = 3
local CONTROL_WIDTH = #BuildingDefs.BUILDABLE * SLOT_WIDTH
	+ (#BuildingDefs.BUILDABLE - 1) * Theme.space.xs
	+ PANEL_PAD * 2
--[[
	Hauteur DERIVEE des trois rangees, jamais recopiee.

	Elle etait ecrite en dur a 96. En passant la rangee de batiments de 28 a
	40 px pour y loger le raccourci, elle debordait du panneau — sans aucune
	erreur, puisque rien ne verifie qu'un enfant tient dans son parent. Le
	calcul rend ce genre de decalage impossible.
]]
local CONTROL_HEIGHT = PANEL_PAD * 2 + 24 * 2 + ROW_GAP * 2 + SLOT_HEIGHT
local CONTROL_ROW_H = 24 -- `h-6` de la reference
-- `px-1.5` : le libelle est pose SUR la jauge, nom a gauche et valeur a droite.
local GAUGE_PAD = 6

-- Curseur d'engagement : un filet mince, et une bille qui le deborde.
local SLIDER_RAIL = 6
local SLIDER_KNOB = 14
-- Ligne de basse que les feuilles a la demande ne franchissent jamais :
-- panneau de controle + respiration.
local DECK_BOTTOM = S.sm + CONTROL_HEIGHT + S.sm

-- Carte d'identite, coin haut gauche.
local IDENTITY_WIDTH = 210
local IDENTITY_HEIGHT = 46

-- Barre de session, coin haut droit, et la pile qu'elle amorce.
local SESSION_WIDTH = 168
local SESSION_HEIGHT = 30
local SESSION_ERA_HEIGHT = 26
local SESSION_BOTTOM = S.md + SESSION_HEIGHT + S.xs + SESSION_ERA_HEIGHT + 16

local SIDE_SHEET_WIDTH = 290
local SHEET_WIDTH = 620
-- Les feuilles s'ouvrent juste au-dessus du panneau de controle.
local SHEET_BOTTOM = DECK_BOTTOM

--[[
	Nombre de tuiles de terre, denominateur du pourcentage de domination.

	Valeur de repli seulement : `setLandCount` la remplace par le compte exact
	des que le monde est genere. Le client possede le meme terrain que le
	serveur, il n'a donc aucune raison de se contenter d'une estimation — et le
	ratio que garantit MapGen n'est qu'une moyenne, l'ecart reel sur une graine
	donnee se voit des la premiere decimale.

	Le repli existe quand meme : le classement peut s'afficher avant que la
	carte soit construite, et diviser par zero mettrait "inf %" dans la colonne.
]]
local FALLBACK_LAND_TILES = math.floor(Config.TILE_COUNT * Config.LAND_RATIO)

local TUTORIAL_STEPS = {
	{ key = "doctrine", title = "Choisis ta doctrine", hint = "Elle definit ton style pour toute la campagne." },
	{ key = "colonize", title = "Etends tes frontieres", hint = "Capture 20 territoires neutres." },
	{ key = "build", title = "Fonde une ville", hint = "Mode Construire, puis clique sur ton territoire." },
	{ key = "attack", title = "Lance une offensive", hint = "Selectionne une nation voisine et engage tes troupes." },
	{ key = "era", title = "Atteins l'ere industrielle", hint = "Developpe ton economie puis finance la recherche." },
}

-- Aides contextuelles et couleurs d'accent de chaque mode. Declarees avec les
-- constantes : la barre tactile, construite dans HUD.new, en a besoin avant
-- les mutateurs qui les utilisent aussi.
local HINTS: { [string]: string } = {
	attack = "Clique sur un territoire voisin pour lancer l'offensive.",
	boat = "Clique sur une cote ennemie ou neutre pour y debarquer.",
	build = "Clique sur ton territoire pour poser le batiment choisi.",
	nuke = "Clique sur la cible de la frappe. Elle sera visible de tous.",
}

local MODE_COLORS: { [string]: Color3 } = {
	attack = C.accent,
	boat = C.info,
	build = C.ally,
	nuke = C.nuclear,
}

export type Mode = "attack" | "build" | "boat" | "nuke"

type RankRow = { slot: number, tiles: number, troops: number, gold: number }
type Ranking = { RankRow }

export type HUD = typeof(setmetatable({} :: any, HUD))

--=============================================================================
-- Composants
--=============================================================================

local function button(parent: GuiObject, text: string, size: number): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = C.surfaceRaised
	b.BorderSizePixel = 0
	b.FontFace = F.bold
	b.TextSize = size
	b.TextColor3 = C.textMuted
	b.Text = text
	b.AutoButtonColor = false
	b.Parent = parent
	Theme.corner(b, Theme.radius.sm)
	local edge = Theme.stroke(b, C.line, 1)
	edge.Name = "Edge"
	edge.Transparency = 0.42

	-- Retour au survol fait main : AutoButtonColor assombrit brutalement et
	-- ignore la couleur d'etat qu'on pose nous-memes sur les boutons actifs.
	b:SetAttribute("BaseColor", C.surfaceRaised)
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Selected") then
			return
		end
		TweenService:Create(b, Theme.motion.instant, { BackgroundColor3 = C.surfaceHover }):Play()
	end)
	b.MouseLeave:Connect(function()
		if b:GetAttribute("Selected") then
			return
		end
		local base = b:GetAttribute("BaseColor") :: Color3
		TweenService:Create(b, Theme.motion.instant, { BackgroundColor3 = base }):Play()
	end)
	b.Activated:Connect(function()
		SoundManager.play("uiClick")
	end)

	return b
end

local function setSelected(b: TextButton, selected: boolean, accent: Color3?)
	b:SetAttribute("Selected", selected)
	local selectedColor = accent or C.accentSoft
	local target = if selected then selectedColor else (b:GetAttribute("BaseColor") :: Color3)
	TweenService:Create(b, Theme.motion.quick, { BackgroundColor3 = target }):Play()
	b.TextColor3 = if selected then C.text else C.textMuted
	local edge = b:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Color = if selected then (accent or C.accent) else C.line
		edge.Transparency = if selected then 0.02 else 0.42
		edge.Thickness = if selected then 1.5 else 1
	end
end

--[[
	Pastille compacte : un glyphe, un chiffre, un contour fin.

	Le contour remplace le fond plein parce qu'il en faut une dizaine cote a
	cote sur la meme ligne : dix rectangles pleins forment un bloc opaque, dix
	contours restent une rangee ou chaque element se compte.
]]
--[[
	Pastille "icone + compteur".

	Les dimensions ne sont pas choisies : elles sont relevees sur le jeu de
	reference, dont la feuille de style les fixe a `w-12 h-7` (48x28 px) avec
	une icone `w-4 h-4` (16 px), une bordure de 1 px et un rayon de 6 px. Nos
	35x18 precedents etaient une estimation, et c'est exactement le genre
	d'ecart qui fait qu'une interface parait bricolee sans qu'on sache dire
	pourquoi.

	Reste un ecart qu'aucune mesure ne comblera : leur glyphe est une image
	dessinee, le notre un caractere unicode. Voir PILL_ICON.
]]
local PILL_WIDTH = 48
local PILL_HEIGHT = 28

local PILL_ICON = 16
local PILL_PAD = 4

local function pill(parent: GuiObject, symbol: string, tint: Color3): (Frame, TextLabel)
	local chip = Instance.new("Frame")
	chip.Name = "Pill"
	chip.BackgroundColor3 = C.surfaceRaised
	chip.BackgroundTransparency = 0.45
	chip.BorderSizePixel = 0
	chip.Parent = parent
	Theme.corner(chip, Theme.radius.sm)
	Theme.stroke(chip, tint, 1)

	local glyph = Theme.label(chip, symbol, T.small, tint)
	glyph.Position = UDim2.fromOffset(PILL_PAD, 0)
	glyph.Size = UDim2.new(0, PILL_ICON, 1, 0)
	glyph.TextXAlignment = Enum.TextXAlignment.Center

	local value = Theme.label(chip, "0", T.small, C.textFaint)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -PILL_PAD, 0, 0)
	value.Size = UDim2.new(1, -(PILL_ICON + PILL_PAD * 2), 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.FontFace = F.medium

	return chip, value
end

--=============================================================================
-- Construction
--=============================================================================

function HUD.new(parent: ScreenGui): HUD
	local self = setmetatable({}, HUD) :: any

	self.mode = "attack"
	self.buildKind = Config.BUILDING.CITY
	self.nukeKind = Config.NUKE.ATOM
	self.mySlot = 0
	self.doctrineId = Doctrines.DEFAULT_ID
	self.ratio = Config.DEFAULT_ATTACK_RATIO
	self.gold = 0
	self.troops = 0
	self.era = 1
	self.eraProgress = 0
	self.modeButtons = {}
	self.buildPrices = {}
	self.nukeButtons = {}
	self.diploButtons = {}
	self.parkPills = {}
	self.parkSlots = {}
	self.buildingCounts = {}
	self.troopGrowth = 0
	self.diplomacy = { allies = {}, incoming = {}, outgoing = {}, embargoes = {}, traitors = {}, marks = {} }
	self.roster = {}
	self.ranked = {}
	self.feedEntries = {}
	self.feedCounter = 0
	self.feedGroups = {}
	self.landTiles = FALLBACK_LAND_TILES
	self.tutorialStep = 0
	self.tutorialStartTiles = 0
	self.selectedTerritory = nil
	self.profile = { xp = 0, level = 1, matches = 0, wins = 0, betrayals = 0 }

	-- Registre des sous-menus. Un seul peut etre ouvert : c'est la regle qui
	-- empeche l'interface de redevenir un empilement.
	self.sheets = {}
	self.sheetButtons = {}
	self.activeSheet = nil

	local root = Instance.new("Frame")
	root.Name = "HUD"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = parent
	self.root = root

	self:buildLayers()

	self:buildDiplomacySheet()
	self:buildControlPanel()
	self:buildIdentityPanel()
	self:buildSessionBar()
	self:buildHint()
	self:buildMissionStrip()
	self:buildFeed()
	self:buildProfileSheet()
	self:buildArsenalSheet()
	self:buildChatSheet()
	self:buildTerritorySheet()
	self:buildDoctrineModal()

	-- La barre d'action n'existe que la ou elle sert : appareil tactile sans
	-- clavier. Elle se construit apres les feuilles, qu'elle decale vers le haut.
	self.touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	self:buildTouchBar()

	self:setRatio(self.ratio)
	self:setMode("attack")

	return self
end

--=============================================================================
-- Calques
--=============================================================================

--[[
	Trois calques et une couche modale, et rien d'autre a la racine.

	L'arborescence comptait douze enfants directs empiles a plat : rien ne
	disait, en lisant l'Explorer, lequel etait toujours affiche et lequel
	n'apparaissait qu'a la demande — il fallait ouvrir chaque panneau pour le
	savoir.

	Les calques sont transparents et occupent tout l'ecran, donc chaque panneau
	garde exactement le positionnement qu'il avait : ranger ne deplace rien. Ce
	qu'on y gagne est ailleurs — la structure dit maintenant ce qu'elle fait, et
	un calque entier peut etre masque, decale ou fondu d'un seul geste.

	Il n'y a plus de calque bas : la disposition CONQUEST ne laisse plus rien
	de permanent en bas d'ecran, et un calque vide aurait juste laisse croire
	que quelque chose y vit encore.

	L'ordre de dessin suit l'ordre de declaration : les sous-menus passent
	au-dessus des barres, la modale au-dessus de tout.
]]
function HUD.buildLayers(self: HUD)
	local function layer(name: string, order: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.ZIndex = order
		frame.Parent = self.root
		return frame
	end

	self.layers = {
		-- Statut permanent : les trois grappes du haut et le bandeau d'objectif.
		top = layer("Top", 1),
		-- Fil de notifications, seul calque a se vider tout seul.
		feed = layer("Feed", 2),
		-- Les quatre sous-menus. Un seul visible a la fois, voir openSheet.
		sheets = layer("Sheets", 3),
		-- Choix de doctrine : bloque le reste tant qu'il est ouvert.
		modal = layer("Modal", 4),
	}
end

--=============================================================================
-- Sous-menus
--=============================================================================

function HUD.registerSheet(self: HUD, id: string, frame: Frame)
	frame.Visible = false
	self.sheets[id] = frame
end

--[[
	Ouvre un sous-menu et ferme tous les autres. Passer `nil` ferme tout.

	`toggle` n'est vrai que pour les boutons d'ouverture : un bouton qui ouvre
	doit aussi savoir refermer, sinon le joueur cherche la croix. Le reste du
	code force l'ouverture — armer le mode Construire deux fois de suite doit
	laisser la palette ouverte, pas la refermer.
]]
function HUD.openSheet(self: HUD, id: string?, toggle: boolean?)
	if toggle and id and self.activeSheet == id then
		id = nil
	end

	self.activeSheet = id

	for sheetId, frame in self.sheets do
		frame.Visible = sheetId == id
	end
	for sheetId, b in self.sheetButtons do
		setSelected(b, sheetId == id)
	end

	-- Fermer la fiche de territoire annule la selection : la surbrillance sur
	-- la carte ne doit jamais survivre au panneau qui l'explique.
	if id ~= "territory" and self.selectedTerritory and self.onTerritoryClosed then
		self.selectedTerritory = nil
		self.onTerritoryClosed()
	end
end

--=============================================================================
-- 1. Diplomatie
--=============================================================================

--[[
	Fiche diplomatique autonome.

	Elle vivait depliee dans une ligne du classement maison, qui a ete retire :
	la liste native de Roblox donne deja le classement, et en afficher un second
	revenait a demander au joueur lequel des deux dit vrai.

	Mais le classement portait aussi TOUTE la diplomatie — alliance, embargo,
	rupture. Le supprimer sans lui redonner un toit rendait ces trois actions
	injoignables, ce qui aurait vide de son sens la mecanique la plus
	differenciante du jeu. La fiche est donc devenue un panneau a part entiere,
	que `selectFaction` ouvre sur la nation visee : le geste d'entree change (on
	clique un territoire au lieu d'une ligne), la suite est identique.
]]
function HUD.buildDiplomacySheet(self: HUD)
	local drawer = Theme.glassPanel("Diplomatie", self.layers.sheets)
	drawer.AnchorPoint = Vector2.new(0.5, 1)
	drawer.Position = UDim2.new(0.5, 0, 1, -S.md)
	drawer.Size = UDim2.fromOffset(340, 118)
	drawer.Visible = false
	self.diploDrawer = drawer
	self:registerSheet("diplomacy", drawer)

	local card = Instance.new("Frame")
	card.Name = "DiplomacyCard"
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromScale(1, 1)
	card.Visible = false
	card.Parent = drawer
	self.diploCard = card

	local cardTitle = Theme.label(card, "", T.small, C.text)
	cardTitle.Position = UDim2.fromOffset(S.sm, S.xs)
	cardTitle.Size = UDim2.new(1, -S.sm * 2, 0, 13)
	cardTitle.TextTruncate = Enum.TextTruncate.AtEnd
	self.diploTitle = cardTitle

	local cardStatus = Theme.label(card, "", T.tiny, C.textMuted)
	cardStatus.Position = UDim2.fromOffset(S.sm, 18)
	cardStatus.Size = UDim2.new(1, -S.sm * 2, 0, 12)
	cardStatus.FontFace = F.medium
	cardStatus.TextTruncate = Enum.TextTruncate.AtEnd
	self.diploStatus = cardStatus

	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.Position = UDim2.fromOffset(S.sm, 34)
	actions.Size = UDim2.new(1, -S.sm * 2, 0, 76)
	actions.Parent = card
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -3, 0, 24)
	grid.CellPadding = UDim2.fromOffset(4, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = actions

	local actionDefs = {
		{ id = "request", text = "Alliance", color = C.ally, order = 1 },
		{ id = "accept", text = "Accepter", color = C.ally, order = 2 },
		{ id = "break", text = "Rompre", color = C.danger, order = 3 },
		{ id = "embargo", text = "Embargo", color = C.warning, order = 4 },
		{ id = "unembargo", text = "Lever", color = C.info, order = 5 },
		{ id = "extend", text = "Prolonger", color = C.ally, order = 6 },
		{ id = "donateGold", text = "Don or", color = C.warning, order = 7 },
		{ id = "donateTroops", text = "Don troupes", color = C.info, order = 8 },
		{ id = "markTarget", text = "\u{2691} Cible", color = C.danger, order = 9 },
	}

	for _, action in actionDefs do
		local b = button(actions, action.text, T.tiny)
		b.LayoutOrder = action.order
		b.Visible = false
		b.TextColor3 = action.color
		b.Activated:Connect(function()
			local target = self.selectedSlot
			if target and self.onDiplomacyAction then
				self.onDiplomacyAction(action.id, target)
			end
		end)
		self.diploButtons[action.id] = b
	end
end

--=============================================================================
-- 2. Panneau de controle — bas centre
--=============================================================================

--[[
	Deux lignes qui repondent a "de quoi je dispose, la, maintenant", et une
	troisieme qui compte le parc.

	Ligne 1 : ce qui rentre — cadence de population, armee sur capacite, or.
	Ligne 2 : ce qui part — le curseur d'engagement et le chiffre envoye.
	Ligne 3 : ce que j'ai — une pastille comptee par type de batiment.

	C'est la forme CONQUEST : le joueur y pose les yeux entre deux
	ordres, sans jamais quitter le bas de l'ecran ou sa main est deja. Les
	puces sont des contours colores plutot que des fonds pleins : trois blocs
	opaques cote a cote feraient un semafor, trois contours restent des puces.
]]
function HUD.buildControlPanel(self: HUD)
	local panel = Theme.glassPanel("ControlPanel", self.layers.top)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -S.sm)
	panel.Size = UDim2.fromOffset(CONTROL_WIDTH, CONTROL_HEIGHT)
	self.controlPanel = panel
	Theme.accentBar(panel, C.accent)

	local row1Y = PANEL_PAD
	local row2Y = PANEL_PAD + CONTROL_ROW_H + ROW_GAP
	local row3Y = row2Y + CONTROL_ROW_H + ROW_GAP

	--- Cadence de population -------------------------------------------------
	-- Le stock de troupes ne dit pas si l'empire monte ou s'effondre ; la
	-- pente, oui. C'est elle qui previent qu'une offensive coute plus qu'elle
	-- ne rapporte, plusieurs dizaines de secondes avant le compteur.
	local rateChip = Instance.new("Frame")
	rateChip.Name = "RateChip"
	rateChip.Position = UDim2.fromOffset(PANEL_PAD, row1Y)
	rateChip.Size = UDim2.fromOffset(86, CONTROL_ROW_H)
	rateChip.BackgroundColor3 = C.surfaceRaised
	rateChip.BackgroundTransparency = 0.4
	rateChip.BorderSizePixel = 0
	rateChip.Parent = panel
	Theme.corner(rateChip, Theme.radius.sm)
	self.growthChipEdge = Theme.stroke(rateChip, C.ally, 1)

	-- Un chevron monochrome plutot qu'un emoji : il rend la puce lisible comme
	-- une PENTE et non comme un stock, et il s'affiche dans toutes les polices.
	local rateMark = Theme.label(rateChip, "\u{25B2}", T.tiny, C.ally)
	rateMark.Position = UDim2.fromOffset(8, 0)
	rateMark.Size = UDim2.fromOffset(12, CONTROL_ROW_H)
	rateMark.TextXAlignment = Enum.TextXAlignment.Center

	local rate = Theme.label(rateChip, "+0/s", T.small, C.ally)
	rate.Position = UDim2.fromOffset(20, 0)
	rate.Size = UDim2.new(1, -26, 1, 0)
	rate.TextXAlignment = Enum.TextXAlignment.Center
	self.growthLabel = rate

	--- Jauge d'armee ----------------------------------------------------------
	-- Troupes sur capacite, avec l'armee engagee posee a la suite : le joueur
	-- lit d'un coup ce qui defend encore et ce qui est deja parti.
	local troopTrack = Instance.new("Frame")
	troopTrack.Name = "Troops"
	troopTrack.Position = UDim2.fromOffset(S.sm + 86 + S.xs, row1Y)
	troopTrack.Size = UDim2.fromOffset(CONTROL_WIDTH - S.sm * 2 - 86 - 108 - S.xs * 2, CONTROL_ROW_H)
	troopTrack.BackgroundColor3 = C.glass
	troopTrack.BackgroundTransparency = 0.4
	troopTrack.BorderSizePixel = 0
	troopTrack.ClipsDescendants = true
	troopTrack.Parent = panel
	Theme.corner(troopTrack, Theme.radius.sm)
	Theme.stroke(troopTrack, C.line, 1)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.info
	fill.BorderSizePixel = 0
	fill.Parent = troopTrack
	self.troopsFill = fill

	local committed = Instance.new("Frame")
	committed.Name = "Committed"
	committed.Size = UDim2.fromScale(0, 1)
	committed.BackgroundColor3 = C.accent
	committed.BorderSizePixel = 0
	committed.Parent = troopTrack
	self.committedFill = committed

	--[[
		"armee / capacite" se lit d'un bloc, centre sur la jauge.

		Nos deux nombres etaient pousses aux extremites opposees de la barre.
		C'est lisible, mais ce n'est pas la meme information : deux valeurs
		eloignees se comparent mal, alors qu'un "4.18K / 12.1K" centre se lit
		comme un rapport. La reference les colle, et le symbole de troupes se
		pose juste apres — c'est lui qui dit de quoi on parle.
	]]
	local troops = Theme.label(troopTrack, "0", T.body, C.text)
	troops.AnchorPoint = Vector2.new(1, 0)
	troops.Position = UDim2.new(0.5, -9, 0, 0)
	troops.Size = UDim2.fromOffset(90, CONTROL_ROW_H)
	troops.TextXAlignment = Enum.TextXAlignment.Right
	troops.ZIndex = 2
	self.troopsLabel = troops

	local separator = Theme.label(troopTrack, "/", T.body, C.textMuted)
	separator.AnchorPoint = Vector2.new(0.5, 0)
	separator.Position = UDim2.new(0.5, 0, 0, 0)
	separator.Size = UDim2.fromOffset(10, CONTROL_ROW_H)
	separator.TextXAlignment = Enum.TextXAlignment.Center
	separator.ZIndex = 2

	local cap = Theme.label(troopTrack, "0", T.body, C.textMuted)
	cap.Position = UDim2.new(0.5, 9, 0, 0)
	cap.Size = UDim2.fromOffset(90, CONTROL_ROW_H)
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.FontFace = F.medium
	cap.ZIndex = 2
	self.popCapLabel = cap

	--[[
		Pas de pictogramme dans la jauge.

		La reference en met un ; le notre etait un emoji, que Gotham ne porte pas
		— il s'affichait en carre noir sur la barre bleue. Un glyphe manquant est
		strictement pire que pas de glyphe : il ressemble a un bug. On y
		reviendra quand les icones seront des images.
	]]

	--- Or ---------------------------------------------------------------------
	local purse = Instance.new("Frame")
	purse.Name = "Purse"
	purse.AnchorPoint = Vector2.new(1, 0)
	purse.Position = UDim2.new(1, -S.sm, 0, row1Y)
	purse.Size = UDim2.fromOffset(108, CONTROL_ROW_H)
	purse.BackgroundColor3 = C.surfaceRaised
	purse.BackgroundTransparency = 0.4
	purse.BorderSizePixel = 0
	purse.Parent = panel
	Theme.corner(purse, Theme.radius.sm)
	Theme.stroke(purse, C.gold, 1)

	local coin = Theme.label(purse, "\u{25C9}", T.small, C.gold)
	coin.Position = UDim2.fromOffset(6, 0)
	coin.Size = UDim2.new(0, 14, 1, 0)
	coin.TextXAlignment = Enum.TextXAlignment.Center

	local gold = Theme.label(purse, "0", T.small, C.gold)
	gold.Position = UDim2.fromOffset(22, 0)
	gold.Size = UDim2.new(1, -28, 1, 0)
	gold.TextTruncate = Enum.TextTruncate.AtEnd
	self.goldLabel = gold

	local goldScale = Instance.new("UIScale")
	goldScale.Parent = gold
	self.goldScale = goldScale

	--- Engagement : la puce dit combien part, le curseur decide ---------------
	--[[
		L'engagement s'annonce SANS cadre.

		Un cadre autour de ce chiffre le mettait au meme rang que l'or et la
		croissance, qui en ont un. Or ce n'est pas une ressource : c'est le
		libelle du curseur pose juste a cote. Sans cadre, l'oeil relie
		immediatement le chiffre au reglage qui le produit.
	]]
	local ratioChip = Instance.new("Frame")
	ratioChip.Name = "RatioChip"
	ratioChip.Position = UDim2.fromOffset(PANEL_PAD, row2Y)
	ratioChip.Size = UDim2.fromOffset(128, CONTROL_ROW_H)
	ratioChip.BackgroundTransparency = 1
	ratioChip.Parent = panel

	local blade = Theme.label(ratioChip, "\u{2694}", T.small, C.textMuted)
	blade.Size = UDim2.fromOffset(18, CONTROL_ROW_H)
	blade.TextXAlignment = Enum.TextXAlignment.Center

	local readout = Theme.label(ratioChip, "", T.small, C.text)
	readout.Position = UDim2.fromOffset(20, 0)
	readout.Size = UDim2.new(1, -20, 1, 0)
	readout.TextXAlignment = Enum.TextXAlignment.Left
	readout.FontFace = F.bold
	self.ratioReadout = readout

	self:buildEngagementSlider(panel, row2Y)

	--- Parc de batiments -------------------------------------------------------
	self:buildParkRow(panel, row3Y)

	--- Etat des fronts, pose au-dessus du panneau ------------------------------
	-- Sans cadre : il est vide la plupart du temps et ne doit pas reserver de
	-- place en permanence.
	local front = Theme.label(self.layers.top, "AUCUN FRONT ACTIF", T.tiny, C.textFaint)
	front.AnchorPoint = Vector2.new(0.5, 1)
	front.Position = UDim2.new(0.5, 0, 1, -(S.sm + CONTROL_HEIGHT + 2))
	front.Size = UDim2.fromOffset(320, 14)
	front.TextXAlignment = Enum.TextXAlignment.Center
	front.TextTruncate = Enum.TextTruncate.AtEnd
	self.frontStatus = front
end

--=============================================================================
-- 3. Carte d'identite — coin haut gauche
--=============================================================================

--[[
	Qui je suis dans cette partie : la nation et sa couleur, la doctrine qui
	dit de quel genre de commandant il s'agit, et le territoire tenu.

	Le classement complet est la liste native de Roblox : l'afficher une
	seconde fois ici demanderait au joueur lequel des deux dit vrai.
]]
function HUD.buildIdentityPanel(self: HUD)
	local panel = Theme.glassPanel("Identity", self.layers.top)
	panel.Position = UDim2.fromOffset(S.md, S.md)
	panel.Size = UDim2.fromOffset(IDENTITY_WIDTH, IDENTITY_HEIGHT)
	self.identityPanel = panel

	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Position = UDim2.fromOffset(S.sm, S.sm)
	stripe.Size = UDim2.fromOffset(3, IDENTITY_HEIGHT - S.sm * 2)
	stripe.BackgroundColor3 = C.textFaint
	stripe.BorderSizePixel = 0
	stripe.Parent = panel
	Theme.corner(stripe, 2)
	self.identityStripe = stripe

	local name = Theme.label(panel, "CONQUEST RTS", T.body, C.text)
	name.Position = UDim2.fromOffset(S.sm + 9, S.sm + 1)
	name.Size = UDim2.fromOffset(IDENTITY_WIDTH - S.sm * 2 - 9, 16)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	self.nameLabel = name

	-- Le gris sous le nom dit de quel genre de commandant il s'agit. La
	-- doctrine est ce qui s'en rapproche le plus chez nous, et elle porte deja
	-- le marqueur de trahison.
	local sub = Theme.label(panel, "", T.tiny, C.textMuted)
	sub.Position = UDim2.fromOffset(S.sm + 9, S.sm + 18)
	sub.Size = UDim2.fromOffset(108, 12)
	sub.FontFace = F.medium
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	self.identitySub = sub

	local tiles = Theme.label(panel, "0 tuiles", T.tiny, C.textFaint)
	tiles.AnchorPoint = Vector2.new(1, 0)
	tiles.Position = UDim2.new(1, -S.sm, 0, S.sm + 18)
	tiles.Size = UDim2.fromOffset(82, 12)
	tiles.TextXAlignment = Enum.TextXAlignment.Right
	tiles.FontFace = F.medium
	tiles.TextTruncate = Enum.TextTruncate.AtEnd
	self.tilesLabel = tiles
end

--[[
	Une pastille par type de batiment, comptee.

	Elle repond a une question qu'aucun autre element ne couvre : "j'ai combien
	de silos, deja ?" — sans quoi il faut survoler la carte pour recompter.

	Piege : le HUD ne peut pas deduire ces nombres tout seul. Le serveur ne
	replique qu'un total tous types confondus, et le detail par type vit dans
	Overlay, que le HUD ne connait pas. Les compteurs restent donc a zero tant
	que personne n'appelle setBuildingCounts.
]]
--[[
	Rangee de batiments : un bouton par type, avec son raccourci.

	Trois informations dans une case de 48x40, et chacune repond a une question
	differente : le chiffre en exposant dit COMMENT le poser au clavier, l'icone
	dit QUOI, le compteur dit COMBIEN on en a deja.

	Le chiffre en exposant n'est pas decoratif — c'est le raccourci reel. Les
	touches 1 a 4 servaient aux modes ; les modes vivent desormais dans le menu
	radial, donc les chiffres reviennent aux batiments, comme dans le jeu de
	reference. Un raccourci affiche est un raccourci qu'on apprend sans le
	chercher.

	Un batiment verrouille par l'ere reste VISIBLE mais grise. Le masquer
	donnerait une rangee dont la longueur change en cours de partie, et le joueur
	perdrait la position qu'il vient d'apprendre.
]]
function HUD.buildParkRow(self: HUD, parent: GuiObject, offsetY: number)
	local row = Instance.new("Frame")
	row.Name = "Park"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(PANEL_PAD, offsetY)
	row.Size = UDim2.fromOffset(CONTROL_WIDTH - PANEL_PAD * 2, SLOT_HEIGHT)
	row.Parent = parent
	Theme.list(row, Enum.FillDirection.Horizontal, S.xs)

	for order, def in BuildingDefs.BUILDABLE do
		local slot = Instance.new("TextButton")
		slot.Name = `Slot{def.id}`
		slot.LayoutOrder = order
		slot.Size = UDim2.fromOffset(SLOT_WIDTH, SLOT_HEIGHT)
		slot.BackgroundColor3 = C.surfaceRaised
		slot.BackgroundTransparency = 0.45
		slot.BorderSizePixel = 0
		slot.AutoButtonColor = false
		slot.Text = ""
		slot.Parent = row
		Theme.corner(slot, Theme.radius.sm)
		Theme.stroke(slot, C.line, 1)

		--[[
			Le raccourci se SUPERPOSE, il ne prend pas de ligne.

			Il occupait une bande en haut de la case, ce qui poussait l'icone et
			le compteur vers le bas et obligeait a une case haute. Pose en
			exposant dans le coin, il ne coute plus aucune hauteur — c'est ce qui
			permet de passer de 40 a 34 px sans rien serrer.
		]]
		local key = Theme.label(slot, tostring(order % 10), T.tiny, C.textFaint)
		key.Position = UDim2.fromOffset(3, 0)
		key.Size = UDim2.fromOffset(9, 9)
		key.TextXAlignment = Enum.TextXAlignment.Left

		--[[
			Icone et compteur forment un COUPLE, centre dans la case.

			Ils etaient plaques aux deux bords opposes, ce qui les faisait lire
			comme deux informations sans rapport separees par du vide. Colles, on
			lit "trois usines" d'un seul coup d'oeil — c'est la disposition de la
			reference, et c'est aussi ce qui permet de reduire la case.
		]]
		--[[
			Une image si le batiment en a une, son glyphe sinon.

			Tous n'ont pas encore leur icone televersee. Le repli n'est donc pas
			une precaution theorique : cinq des huit cases affichent encore une
			forme geometrique aujourd'hui. Les deux chemins doivent se teinter de
			la meme facon, sinon la moitie de la rangee cesserait de reagir aux
			verrous sans qu'aucune erreur ne le dise.

			Le couple icone/compteur est centre sur la HAUTEUR de la case, pas
			colle a son bas : c'est ce qui l'equilibre maintenant que le
			raccourci ne mange plus de place en haut.
		]]
		local glyph: any
		if def.icon then
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.Image = def.icon
			-- Les icones sont blanches : la teinte vient d'ici, pas du fichier.
			image.ImageColor3 = C.text
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = slot
			glyph = image
		else
			glyph = Theme.label(slot, def.symbol, T.body, C.text)
			glyph.TextXAlignment = Enum.TextXAlignment.Right
		end
		glyph.Name = "Glyph"
		glyph.AnchorPoint = Vector2.new(1, 0.5)
		glyph.Position = UDim2.new(0.5, 2, 0.5, 3)
		glyph.Size = UDim2.fromOffset(SLOT_ICON, SLOT_ICON)

		local value = Theme.label(slot, "0", T.small, C.textFaint)
		value.AnchorPoint = Vector2.new(0, 0.5)
		value.Position = UDim2.new(0.5, 5, 0.5, 3)
		value.Size = UDim2.fromOffset(18, 18)
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.FontFace = F.bold

		slot.Activated:Connect(function()
			self:setBuildKind(def.id)
		end)

		self.parkPills[def.id] = value
		self.parkSlots[def.id] = { button = slot, glyph = glyph, key = key }
	end

	self:refreshParkSlots()
end

--[[
	Grise les batiments que l'ere n'a pas encore ouverts.

	Appele a la construction et a chaque changement d'ere : sans le second appel,
	un batiment debloque en cours de partie resterait grise jusqu'a la fin, et
	le joueur croirait ne pas y avoir droit.
]]
function HUD.refreshParkSlots(self: HUD)
	for id, parts in self.parkSlots do
		local def = BuildingDefs.get(id)
		local unlocked = self.era >= Eras.requiredFor(id)
		--[[
			Deux raisons distinctes de griser, et elles ne disent pas la meme
			chose : verrouille par l'ere veut dire "pas encore", trop cher veut
			dire "pas maintenant". On les distingue par l'intensite plutot que
			par la couleur — la rangee doit rester lisible d'un balayage.
		]]
		local price = self.buildPrices[id] or (if def then def.cost else math.huge)
		local affordable = unlocked and self.gold >= price
		local dim = if not unlocked then 0.6 elseif not affordable then 0.35 else 0

		parts.button.BackgroundTransparency = if unlocked then 0.45 else 0.75
		--[[
			Une image se grise par ImageTransparency, un texte par
			TextTransparency. Ecrire la mauvaise propriete ne leve rien : le
			glyphe reste simplement en pleine lumiere alors qu'il est verrouille.
		]]
		if parts.glyph:IsA("ImageLabel") then
			parts.glyph.ImageTransparency = dim
		else
			parts.glyph.TextTransparency = dim
		end
		parts.key.TextTransparency = math.max(dim, 0.15)
		setSelected(parts.button, id == self.buildKind)

		local count = self.parkPills[id]
		if count then
			count.TextTransparency = dim
		end
	end
end

--=============================================================================
-- 3. Session — coin haut droit
--=============================================================================

--[[
	Le coin qui ne parle pas de la carte : le temps qui reste, l'ere en cours,
	et les deux sorties.

	Le bandeau d'ere EST le bouton de recherche. Quand le palier suivant est
	financable il change de couleur et annonce son prix ; il n'y a ni panneau
	separe ni clic pour savoir ou on en est.
]]
function HUD.buildSessionBar(self: HUD)
	local bar = Theme.glassPanel("Session", self.layers.top)
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.new(1, -S.md, 0, S.md)
	bar.Size = UDim2.fromOffset(SESSION_WIDTH, SESSION_HEIGHT)
	self.sessionBar = bar

	local timer = Theme.label(bar, "00:00", T.body, C.text)
	timer.AnchorPoint = Vector2.new(0, 0.5)
	timer.Position = UDim2.new(0, S.sm + 2, 0.5, 0)
	timer.Size = UDim2.fromOffset(56, 18)
	timer.FontFace = F.display
	self.timerLabel = timer

	local settings = button(bar, "\u{2699}", T.small)
	settings.AnchorPoint = Vector2.new(1, 0.5)
	settings.Position = UDim2.new(1, -(S.sm + 26), 0.5, 0)
	settings.Size = UDim2.fromOffset(22, 20)
	settings.Activated:Connect(function()
		self:openSheet("profile", true)
	end)
	self.sheetButtons.profile = settings

	--[[
		Messages rapides.

		Le free-chat ne coordonne pas une alliance multilingue ; des messages
		predefinis, si. Le bouton vit dans la barre de session, a portee de
		pouce du classement ou l'on designe les cibles.
	]]
	local chat = button(bar, "\u{1F4AC}", T.small)
	chat.AnchorPoint = Vector2.new(1, 0.5)
	chat.Position = UDim2.new(1, -(S.sm + 52), 0.5, 0)
	chat.Size = UDim2.fromOffset(22, 20)
	chat.Activated:Connect(function()
		self:openSheet("chat", true)
	end)
	self.sheetButtons.chat = chat

	--[[
		Sortie.

		Aucun callback n'est branche cote init.client pour l'instant, et un
		bouton qui quitte pour de vrai sans que personne l'ait demande serait la
		pire chose a poser ici. Il expose donc `onLeave` et, a defaut, dit ou se
		trouve la vraie sortie plutot que de ne rien faire en silence.

		Le glyphe est une fleche et non le symbole d'alimentation du jeu de
		reference : Gotham ne le porte pas, et un caractere absent s'affiche en
		carre vide dans Roblox.
	]]
	local leave = button(bar, "\u{2190}", T.small)
	leave.AnchorPoint = Vector2.new(1, 0.5)
	leave.Position = UDim2.new(1, -S.sm, 0.5, 0)
	leave.Size = UDim2.fromOffset(22, 20)
	leave.TextColor3 = C.danger
	leave.Activated:Connect(function()
		if self.onLeave then
			self.onLeave()
		else
			self:notify("Quitte la campagne depuis le menu Roblox.", "info")
		end
	end)

	--- Ere ------------------------------------------------------------------
	local era = button(self.layers.top, "", T.small)
	era.Name = "EraBanner"
	era.AnchorPoint = Vector2.new(1, 0)
	era.Position = UDim2.new(1, -S.md, 0, S.md + SESSION_HEIGHT + S.xs)
	era.Size = UDim2.fromOffset(SESSION_WIDTH, SESSION_ERA_HEIGHT)
	era.TextXAlignment = Enum.TextXAlignment.Left
	era.Activated:Connect(function()
		if self.onResearch then
			self.onResearch()
		end
	end)
	self.eraButton = era

	-- Le prix a sa propre colonne, a droite, plutot que d'etre colle au bout du
	-- nom : "THERMONUCLEAIRE" est assez long pour pousser le prix hors du
	-- bouton, et c'est justement le prix qui declenche le clic.
	local eraName = Theme.label(era, "", T.tiny, C.text)
	eraName.Position = UDim2.fromOffset(S.sm, 3)
	eraName.Size = UDim2.new(1, -S.sm * 2 - 54, 0, 13)
	eraName.TextTruncate = Enum.TextTruncate.AtEnd
	self.eraName = eraName

	local eraPrice = Theme.label(era, "", T.tiny, C.gold)
	eraPrice.AnchorPoint = Vector2.new(1, 0)
	eraPrice.Position = UDim2.new(1, -S.sm, 0, 3)
	eraPrice.Size = UDim2.fromOffset(52, 13)
	eraPrice.TextXAlignment = Enum.TextXAlignment.Right
	self.eraPrice = eraPrice

	local eraTrack = Instance.new("Frame")
	eraTrack.Position = UDim2.fromOffset(S.sm, 19)
	eraTrack.Size = UDim2.new(1, -S.sm * 2, 0, 3)
	eraTrack.BackgroundColor3 = C.glass
	eraTrack.BorderSizePixel = 0
	eraTrack.Parent = era
	Theme.corner(eraTrack, Theme.radius.pill)

	local eraFill = Instance.new("Frame")
	eraFill.Size = UDim2.fromScale(0, 1)
	eraFill.BackgroundColor3 = C.info
	eraFill.BorderSizePixel = 0
	eraFill.Parent = eraTrack
	Theme.corner(eraFill, Theme.radius.pill)
	self.eraFill = eraFill

	-- La phase ne dure que quelques dizaines de secondes en debut de partie :
	-- elle n'a pas besoin d'un cadre, juste d'une ligne qui reste vide le reste
	-- du temps.
	local phase = Theme.label(self.layers.top, "", T.tiny, C.textMuted)
	phase.AnchorPoint = Vector2.new(1, 0)
	phase.Position = UDim2.new(1, -S.md, 0, S.md + SESSION_HEIGHT + S.xs + SESSION_ERA_HEIGHT + 3)
	phase.Size = UDim2.fromOffset(180, 13)
	phase.TextXAlignment = Enum.TextXAlignment.Right
	phase.FontFace = F.medium
	phase.TextTruncate = Enum.TextTruncate.AtEnd
	self.phaseLabel = phase
end

--=============================================================================
-- Bandeau d'objectifs
--=============================================================================

--[[
	Une bande fine en haut-centre, qui disparait des que le briefing est
	termine. L'ancien panneau restait a l'ecran toute la partie.
]]
function HUD.buildMissionStrip(self: HUD)
	local strip = Theme.panel("Mission", self.layers.top)
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, S.md)
	strip.Size = UDim2.fromOffset(360, 26)
	strip.Visible = false
	self.missionStrip = strip

	local title = Theme.label(strip, "", T.small, C.text)
	title.Position = UDim2.fromOffset(S.md, 3)
	title.Size = UDim2.fromOffset(180, 13)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	self.missionTitle = title

	local hint = Theme.label(strip, "", T.tiny, C.textFaint)
	hint.Position = UDim2.fromOffset(S.md, 15)
	hint.Size = UDim2.fromOffset(300, 12)
	hint.FontFace = F.medium
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	self.missionHint = hint

	local counter = Theme.label(strip, "0 / 5", T.tiny, C.textMuted)
	counter.AnchorPoint = Vector2.new(1, 0)
	counter.Position = UDim2.new(1, -S.md, 0, 4)
	counter.Size = UDim2.fromOffset(40, 12)
	counter.TextXAlignment = Enum.TextXAlignment.Right
	self.missionCounter = counter

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0)
	track.Position = UDim2.new(1, -S.md, 0, 19)
	track.Size = UDim2.fromOffset(60, 3)
	track.BackgroundColor3 = C.glass
	track.BorderSizePixel = 0
	track.Parent = strip
	Theme.corner(track, Theme.radius.pill)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	Theme.corner(fill, Theme.radius.pill)
	self.missionFill = fill
end

--=============================================================================
-- Fil de notifications
--=============================================================================

function HUD.buildFeed(self: HUD)
	local feed = Instance.new("Frame")
	feed.Name = "Stream"
	feed.AnchorPoint = Vector2.new(1, 1)
	feed.Position = UDim2.new(1, -S.md, 1, -S.sm)
	feed.Size = UDim2.fromOffset(300, MAX_FEED_ENTRIES * (FEED_ENTRY_HEIGHT + S.xs))
	feed.BackgroundTransparency = 1
	feed.ClipsDescendants = true
	feed.Parent = self.layers.feed
	self.feed = feed

	local layout = Theme.list(feed, Enum.FillDirection.Vertical, S.xs)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
end

local FEED_COLORS: { [string]: Color3 } = {
	good = C.ally,
	bad = C.danger,
	alert = C.warning,
	info = C.info,
}

local FEED_SOUNDS: { [string]: string } = {
	bad = "uiError",
	alert = "uiSelect",
}

--[[
	Ajoute un message au fil.

	Le fil est plafonne en nombre d'entrees, pas seulement en duree : pendant
	une phase agitee les messages arrivent bien plus vite qu'ils n'expirent, et
	un simple minuteur laissait le fil recouvrir tout l'ecran.
]]
function HUD.notify(self: HUD, text: string, kind: string)
	-- Un meme message repete remonte en compteur au lieu de s'empiler.
	local existing = self.feedGroups[text]
	if existing and existing.entry.Parent then
		existing.count += 1
		existing.entry.Text = `{text}   x{existing.count}`
		return
	end

	-- Retrait partage par l'expiration, le plafond d'entrees et la croix :
	-- trois chemins, un seul endroit qui nettoie les deux index.
	-- V124 : Parent = nil + push feedFree si encore parente. Pas de
	-- Destroy. Un delay fantome (reparente) ne double-push pas.
	local function removeEntry(target: TextLabel)
		if not target.Parent then
			return
		end
		local index = table.find(self.feedEntries, target)
		if index then
			-- V103 : Dismiss / expiration gardent table.remove(index)
			-- (retrait au milieu, pas overflow FIFO). Ne PAS y mettre
			-- le decalage prefixe.
			table.remove(self.feedEntries, index)
		end
		for key, group in self.feedGroups do
			if group.entry == target then
				self.feedGroups[key] = nil
				break
			end
		end
		target.Parent = nil
		local pool = self.feedFree
		if pool then
			pool[#pool + 1] = target
		end
	end

	-- V124 : free-list feedFree PAR HUD (pas ringFree / textFree /
	-- dismissFree). Recette feel N167 inline — ne PAS merger ee71 /
	-- 6cec. Leftover Parent = nil, pas Destroy du TextLabel. Pop O(1)
	-- depuis la fin. Parent = self.feed (pas overlay.root). Pas
	-- Theme.corner / Theme.stroke au reuse (UICorner deja enfant).
	-- Recolor UIStroke existant. Recreer Dismiss si Destroy par delay
	-- / croix (Name Dismiss, Disconnect Activated). V103 decalage
	-- prefixe conserve. Dismiss table.remove(index) conserve.
	-- MAX_FEED_ENTRIES=3 inchange. Groupement feedGroups inchange.
	-- Delay 4.5 inchange. LayoutOrder ~= born : un delay ne fond pas
	-- le message reparente (plafond V103 recycle avant 4.5 s). Lazy-
	-- init feedFree ici (pas HUD.new). Distinct de V123 (BuildRing
	-- ringFree, BuildingModels). Distinct de V120 (floatingText
	-- textFree, Effects). Distinct de V122 (conquestPulse pulseFree).
	-- Distinct de V125 (selectTile SelectedTerritory, Effects).
	-- Distinct de V126 (clearSelection Parent=nil, Effects).
	-- Pas reentrant. Evenement fil, pas 60 Hz. Ne pas nil les slots
	-- du pool. Ne pas geler Size flame (V74).
	local feedFree = self.feedFree
	if not feedFree then
		feedFree = {}
		self.feedFree = feedFree
	end
	local nFeed = #feedFree
	local entry: TextLabel
	local reused = nFeed > 0
	if reused then
		entry = feedFree[nFeed] :: TextLabel
		feedFree[nFeed] = nil
	else
		entry = Instance.new("TextLabel")
		entry.BorderSizePixel = 0
		entry.FontFace = F.bold
		entry.TextSize = T.small
		entry.TextTruncate = Enum.TextTruncate.AtEnd
	end
	local born = self.feedCounter
	entry.Size = UDim2.new(1, 0, 0, FEED_ENTRY_HEIGHT)
	entry.BackgroundColor3 = C.surface
	entry.BackgroundTransparency = 0.14
	entry.TextTransparency = 0
	entry.TextColor3 = FEED_COLORS[kind] or C.text
	entry.Text = text
	entry.LayoutOrder = born
	entry.Parent = self.feed
	if reused then
		local stroke = entry:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = FEED_COLORS[kind] or C.line
		end
	else
		Theme.corner(entry, Theme.radius.sm)
		Theme.stroke(entry, FEED_COLORS[kind] or C.line, 1)
	end

	-- Le texte s'arrete avant la croix, sinon les longs messages passent
	-- dessous et l'un des deux devient illisible.
	if not entry:FindFirstChildWhichIsA("UIPadding") then
		local inset = Instance.new("UIPadding")
		inset.PaddingRight = UDim.new(0, 20)
		inset.Parent = entry
	end

	--[[
		Croix de rejet. Un message qui reste — une demande d'alliance qu'on ne
		veut pas traiter tout de suite — ne doit pas devenir un element
		permanent : le joueur le degage, le minuteur le degage, mais l'un des
		deux doit toujours pouvoir le faire tout de suite.

		Le delay Destroy la croix : au reuse, la recreer si absente.
	]]
	if not entry:FindFirstChild("Dismiss") then
		local dismiss = Instance.new("TextButton")
		dismiss.Name = "Dismiss"
		dismiss.AnchorPoint = Vector2.new(1, 0.5)
		dismiss.Position = UDim2.new(1, -3, 0.5, 0)
		dismiss.Size = UDim2.fromOffset(14, 14)
		dismiss.BackgroundTransparency = 1
		dismiss.FontFace = F.bold
		dismiss.TextSize = T.small
		dismiss.TextColor3 = C.textFaint
		dismiss.Text = "\u{00D7}"
		dismiss.ZIndex = 2
		dismiss.Parent = entry
		dismiss.Activated:Connect(function()
			removeEntry(entry)
		end)
	end

	local sound = FEED_SOUNDS[kind]
	if sound then
		SoundManager.play(sound)
	end

	self.feedCounter += 1
	table.insert(self.feedEntries, entry)
	self.feedGroups[text] = { entry = entry, count = 1 }

	-- V103 : decalage prefixe in-place. Plus de table.remove(1) a
	-- chaque overflow. n = 3 (MAX_FEED_ENTRIES). oldest lu AVANT le
	-- shift ; nil du dernier ; PUIS removeEntry (table.find rate, pas
	-- de double-retrait, Parent=nil + feedGroups nil, V124). Recette feel N153
	-- inline — ne PAS merger ee71. Pas de feedHead (N112/V101 est
	-- WorldRenderer). Croix Dismiss garde table.remove(index) (retrait
	-- au milieu). Groupement / LayoutOrder / task.delay(4.5) inchanges.
	-- Distinct de V101/V102 (dirtyQueue, WorldRenderer — autre fichier).
	-- Distinct de feel N106 (recycle Ground/Border — fermee V112).
	-- Overlay Blast recyclee (V113). Overlay BlastSmoke recyclee (V114).
	-- Overlay Shockwave recyclee (V115). Overlay DeliveryPulse recyclee
	-- (V116). Overlay LandingSplash recyclee (V117). Overlay LaunchWake
	-- recyclee (V118). Overlay goldPopup recyclee (V119). Effects
	-- floatingText recyclee (V120). Effects tileFlash recyclee
	-- (V121). Effects conquestPulse recyclee (V122). BuildingModels
	-- BuildRing recyclee (V123). HUD notify recyclee (V124).
	-- MAX_FEED_ENTRIES=3
	-- inchange. Pas reentrant. FactoryOutput / SiloWarning fermees (V104).
	-- Feux navire fermes (V105). Wake Transparency fermee (V106).
	-- Flag pitch fermee (V107). CapitalFlag fermee (V108).
	-- PortCraneBoom fermee (V109). PortCraneCable fermee (V110).
	-- Flame Size phase fermee (V111).
	while #self.feedEntries > MAX_FEED_ENTRIES do
		local entries = self.feedEntries
		local n = #entries
		local oldest = entries[1]
		for i = 1, n - 1 do
			entries[i] = entries[i + 1]
		end
		entries[n] = nil
		if oldest then
			removeEntry(oldest)
		end
	end

	task.delay(4.5, function()
		if not entry.Parent then
			return
		end
		-- V124 : LayoutOrder change au reuse. Un delay ne doit pas
		-- fondre le message reparente (plafond V103 recycle avant 4.5 s).
		if entry.LayoutOrder ~= born then
			return
		end
		-- Le fondu ne touche que l'etiquette : la croix part d'elle-meme,
		-- sinon elle resterait visible sur un message deja efface.
		local cross = entry:FindFirstChild("Dismiss")
		if cross then
			cross:Destroy()
		end
		local tween = TweenService:Create(
			entry,
			Theme.motion.smooth,
			{ BackgroundTransparency = 1, TextTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		removeEntry(entry)
	end)
end

--=============================================================================
-- Engagement et aide contextuelle
--=============================================================================

--[[
	Curseur d'engagement, seconde ligne du panneau de controle.

	C'est la decision tactique centrale du jeu, donc elle merite un vrai
	curseur continu plutot que des paliers : le joueur doit pouvoir doser
	precisement ce qu'il risque. La puce a sa gauche dit en chiffres absolus
	combien de troupes partent ; le rail, lui, sert de poignee. L'etiquette de
	la puce est un TextLabel, donc inerte : glisser dessus glisse bien le
	curseur. Y poser un bouton avalerait le geste.
]]
function HUD.buildEngagementSlider(self: HUD, parent: GuiObject, offsetY: number)
	local track = Instance.new("TextButton")
	track.Name = "EngagementTrack"
	track.Text = ""
	track.AutoButtonColor = false
	track.Position = UDim2.fromOffset(S.sm + 128 + S.xs, offsetY)
	track.Size = UDim2.fromOffset(CONTROL_WIDTH - S.sm * 2 - 128 - S.xs, CONTROL_ROW_H)
	--[[
		Rail fin et bille ronde, comme la reference.

		Le rail ne fait plus toute la hauteur de la ligne : c'est un filet mince
		centre verticalement, ce qui laisse la bille depasser au-dessus et en
		dessous. Une bille qui deborde se saisit a l'oeil et au doigt ; un
		curseur enferme dans son rail ne dit pas qu'il se deplace.

		D'ou la disparition de ClipsDescendants : c'est lui qui rendait la bille
		impossible. Il etait la pour contenir le remplissage — les coins arrondis
		du rail s'en chargent aussi bien.
	]]
	--[[
		Le rail est un FILET, pas une gouttiere.

		La zone cliquable garde la hauteur d'une ligne — il faut pouvoir attraper
		le curseur au doigt — mais elle est desormais invisible. Seul le filet se
		voit. Auparavant la zone entiere etait peinte : on obtenait une grosse
		barre grise qui pesait autant a l'oeil que la jauge d'armee au-dessus,
		alors qu'elle ne porte qu'un reglage.
	]]
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Parent = parent

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.AnchorPoint = Vector2.new(0.5, 0.5)
	rail.Position = UDim2.fromScale(0.5, 0.5)
	rail.Size = UDim2.new(1, 0, 0, SLIDER_RAIL)
	rail.BackgroundColor3 = C.surfaceBright
	rail.BackgroundTransparency = 0.4
	rail.BorderSizePixel = 0
	rail.Parent = track
	Theme.corner(rail, Theme.radius.pill)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(Config.DEFAULT_ATTACK_RATIO, 1)
	fill.BackgroundColor3 = C.accent
	fill.BorderSizePixel = 0
	fill.Parent = rail
	Theme.corner(fill, Theme.radius.pill)
	self.ratioFill = fill

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(Config.DEFAULT_ATTACK_RATIO, 0.5)
	knob.Size = UDim2.fromOffset(SLIDER_KNOB, SLIDER_KNOB)
	knob.BackgroundColor3 = C.accent
	knob.BorderSizePixel = 0
	knob.ZIndex = 3
	knob.Parent = track
	Theme.corner(knob, Theme.radius.pill)
	self.ratioKnob = knob

	local function ratioFromInput(inputX: number)
		local origin = track.AbsolutePosition.X
		local size = track.AbsoluteSize.X
		if size <= 0 then
			return
		end
		local ratio = math.clamp((inputX - origin) / size, 0.05, 1)
		self:setRatio(ratio)
		if self.onRatioChanged then
			self.onRatioChanged(ratio)
		end
	end

	local dragging = false

	track.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			SoundManager.play("uiClick")
			ratioFromInput(input.Position.X)
		end
	end)

	-- Le suivi se fait au niveau global : sans ca, sortir du rail pendant le
	-- glissement fige la valeur au lieu de continuer a suivre le doigt.
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			ratioFromInput(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
end

--[[
	Aide contextuelle du mode arme.

	La rangee de boutons de mode qui l'accompagnait est supprimee : le menu
	radial du clic droit propose les memes actions **sur la case visee**, ce qui
	economise l'aller-retour vers le bas de l'ecran. Restait la phrase, qui elle
	n'a pas d'equivalent — le menu radial ne dit pas ce qu'on attend du clic
	suivant, une fois qu'il s'est referme.

	Elle flotte au-dessus du panneau de controle, sans cadre : elle est vide la
	plupart du temps et ne doit pas reserver de place en permanence.
]]
function HUD.buildHint(self: HUD)
	local hint = Theme.label(self.layers.top, "", T.tiny, C.textFaint)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -(S.sm + CONTROL_HEIGHT + 18))
	hint.Size = UDim2.fromOffset(520, 12)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.FontFace = F.medium
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	self.hintLabel = hint
end

--=============================================================================
-- Barre d'action tactile
--=============================================================================

--[[
	Le bas de l'ecran n'appartient qu'au panneau de controle — sur desktop, ou
	le clic droit ouvre le menu radial et le clavier arme les modes. Sur mobile
	ni l'un ni l'autre n'existe : l'appui long ouvre bien le radial, mais chaque
	action couterait alors deux gestes, et poser cinq batiments d'affilee — le
	geste le plus repete du jeu — deviendrait une corvee.

	Les quatre modes et le retour a la capitale tiennent donc dans une barre
	posee juste au-dessus du panneau, construite UNIQUEMENT sur appareil tactile
	sans clavier. Le test de disposition continue de garantir que le bureau
	reste vierge : sans tactile, rien n'est construit.

	Les feuilles ancreees en bas remontent d'autant : une palette ouverte ne
	doit jamais recouvrir les boutons qui commandent le mode actif.
]]
local TOUCH_BAR_HEIGHT = 44

function HUD.buildTouchBar(self: HUD)
	if self.touchBar or not self.touchOnly then
		return
	end

	local bar = Theme.panel("TouchBar", self.layers.top)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -(S.sm + CONTROL_HEIGHT + S.xs))
	bar.Size = UDim2.fromOffset(452, TOUCH_BAR_HEIGHT)
	Theme.padding(bar, S.xs)
	Theme.list(bar, Enum.FillDirection.Horizontal, S.xs)
	self.touchBar = bar

	local modes: { { id: Mode, label: string } } = {
		{ id = "attack", label = "Attaquer" },
		{ id = "boat", label = "Debarquer" },
		{ id = "build", label = "Construire" },
		{ id = "nuke", label = "Nucleaire" },
	}
	for order, entry in modes do
		local b = button(bar, entry.label, T.small)
		b.LayoutOrder = order
		b.Size = UDim2.new(0, 96, 1, 0)
		b.Activated:Connect(function()
			self:setMode(entry.id)
		end)
		self.modeButtons[entry.id] = b
	end

	-- Meme role que la touche Espace : sur un monde de 1024 studs, le retour a
	-- sa capitale est le repere principal du joueur.
	local home = button(bar, "Capitale", T.small)
	home.LayoutOrder = #modes + 1
	home.Size = UDim2.new(0, 84, 1, 0)
	home.Activated:Connect(function()
		if self.onRecenter then
			self.onRecenter()
		end
	end)
	self.touchHome = home

	-- Les feuilles du bas se decalent au-dessus de la barre.
	for _, sheet in self.sheets do
		if sheet.AnchorPoint.Y == 1 then
			sheet.Position = UDim2.new(0.5, 0, 1, -(SHEET_BOTTOM + TOUCH_BAR_HEIGHT + S.sm))
		end
	end

	-- Le mode deja arme se reflete immediatement sur les nouveaux boutons, sans
	-- rejouer setMode : armer Construire ici rouvrirait la palette sans raison.
	for id, b in self.modeButtons do
		setSelected(b, id == self.mode, MODE_COLORS[id])
	end
end

--=============================================================================
-- Sous-menu : Profil
--=============================================================================

function HUD.buildProfileSheet(self: HUD)
	local sheet = Theme.panel("Profile", self.layers.sheets)
	sheet.AnchorPoint = Vector2.new(1, 0)
	sheet.Position = UDim2.new(1, -S.md, 0, SESSION_BOTTOM + S.sm)
	sheet.Size = UDim2.fromOffset(SIDE_SHEET_WIDTH, 96)
	self:registerSheet("profile", sheet)

	local role = Theme.label(sheet, "COMMANDANT  \u{00B7}  NIVEAU 1", T.small, C.text)
	role.Position = UDim2.fromOffset(S.md, S.sm)
	role.Size = UDim2.new(1, -S.md * 2, 0, 14)
	self.roleLabel = role

	local stats = Theme.label(sheet, "", T.tiny, C.textMuted)
	stats.Position = UDim2.fromOffset(S.md, 28)
	stats.Size = UDim2.new(1, -S.md * 2, 0, 40)
	stats.FontFace = F.medium
	stats.TextWrapped = true
	stats.TextYAlignment = Enum.TextYAlignment.Top
	self.profileStats = stats

	local close = button(sheet, "Fermer", T.tiny)
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -S.md, 1, -S.sm)
	close.Size = UDim2.fromOffset(64, 22)
	close.Activated:Connect(function()
		self:openSheet(nil)
	end)
end

--=============================================================================
-- Sous-menu : Construire
--=============================================================================

--=============================================================================
-- Sous-menu : Arsenal
--=============================================================================

function HUD.buildArsenalSheet(self: HUD)
	local sheet = Theme.panel("Arsenal", self.layers.sheets)
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -SHEET_BOTTOM)
	sheet.Size = UDim2.fromOffset(SHEET_WIDTH, 112)
	self:registerSheet("nuke", sheet)
	self.nukePalette = sheet

	local title = Theme.label(sheet, "ARSENAL", T.tiny, C.textFaint)
	title.Position = UDim2.fromOffset(S.md, S.sm)
	title.Size = UDim2.new(1, -S.md * 2, 0, 12)

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(S.md, 26)
	list.Size = UDim2.new(1, -S.md * 2, 1, -34)
	list.Parent = sheet
	Theme.list(list, Enum.FillDirection.Horizontal, S.sm)

	for kind = 1, #Config.NUKE_STATS do
		local stats = Config.NUKE_STATS[kind]
		local card = button(list, "", T.small)
		card.LayoutOrder = kind
		card.Size = UDim2.fromOffset(190, 74)

		local glyph = Theme.label(card, "\u{2622}", 18, C.nuclear)
		glyph.Position = UDim2.fromOffset(S.sm, S.sm)
		glyph.Size = UDim2.fromOffset(22, 22)

		local name = Theme.label(card, stats.name, T.small, C.text)
		name.Position = UDim2.fromOffset(S.sm + 26, 10)
		name.Size = UDim2.new(1, -S.sm - 26, 0, 14)

		-- Le MIRV ne decrit pas un rayon mais une pluie d'ogives : c'est cette
		-- saturation que le joueur achete, pas un cratere.
		local detailText = if stats.warheads
			then `{stats.warheads} ogives, rayon {stats.warheadRadius}`
			else `Rayon {stats.radius} tuiles`
		local detail = Theme.label(card, detailText, T.tiny, C.textFaint)
		detail.Position = UDim2.fromOffset(S.sm + 26, 26)
		detail.Size = UDim2.new(1, -S.sm - 26, 0, 12)
		detail.FontFace = F.medium

		local price = Theme.label(card, `{stats.cost} or`, T.tiny, C.gold)
		price.AnchorPoint = Vector2.new(0, 1)
		price.Position = UDim2.new(0, S.sm, 1, -S.sm)
		price.Size = UDim2.new(1, -S.sm * 2, 0, 12)
		price.FontFace = F.bold

		card.Activated:Connect(function()
			self.nukeKind = kind
			self:setMode("nuke")
		end)
		self.nukeButtons[kind] = card
	end
end

--=============================================================================
-- Sous-menu : Messages rapides
--=============================================================================

--[[
	Le catalogue predefini, regle CONQUEST : pas de texte libre, donc pas
	d'insulte ni de barriere de langue. Deux temps seulement — on choisit un
	message, et s'il exige une cible, on la designe dans la liste des nations.
]]
function HUD.buildChatSheet(self: HUD)
	local sheet = Theme.panel("Messages", self.layers.sheets)
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -SHEET_BOTTOM)
	sheet.Size = UDim2.fromOffset(SHEET_WIDTH, 150)
	self:registerSheet("chat", sheet)

	local title = Theme.label(sheet, "MESSAGES", T.tiny, C.textFaint)
	title.Position = UDim2.fromOffset(S.md, S.sm)
	title.Size = UDim2.new(1, -S.md * 2, 0, 12)

	-- Onglets de categories, a gauche.
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(S.md, 26)
	tabs.Size = UDim2.fromOffset(86, 116)
	tabs.Parent = sheet
	Theme.list(tabs, Enum.FillDirection.Vertical, S.xs)

	self.chatTabs = {}
	for i, category in QuickChat.CATEGORIES do
		local tab = button(tabs, category.name, T.tiny)
		tab.LayoutOrder = i
		tab.Size = UDim2.new(1, 0, 0, 18)
		tab.Activated:Connect(function()
			self.chatCategory = category.id
			self.chatPending = nil
			self:refreshChatSheet()
		end)
		self.chatTabs[category.id] = tab
	end

	-- Zone des messages, a droite : reconstruite a chaque changement
	-- d'onglet, elle est trop simple pour meriter un recyclage.
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(S.md + 94, 26)
	body.Size = UDim2.new(1, -S.md * 2 - 94, 1, -34)
	body.Parent = sheet
	self.chatBody = body

	self.chatCategory = QuickChat.CATEGORIES[1].id
	self.chatPending = nil
	self.chatSentAt = 0
	self:refreshChatSheet()
end

function HUD.refreshChatSheet(self: HUD)
	for _, child in self.chatBody:GetChildren() do
		child:Destroy()
	end
	for id, tab in self.chatTabs do
		setSelected(tab, id == self.chatCategory)
	end

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -3, 0, 24)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = self.chatBody

	-- Deuxieme temps : la designation de la cible du message choisi.
	local pending = self.chatPending
	if pending then
		local back = button(self.chatBody, "\u{2190} Retour", T.tiny)
		back.LayoutOrder = 0
		back.Activated:Connect(function()
			self.chatPending = nil
			self:refreshChatSheet()
		end)

		local order = 0
		for slot, entry in self.roster do
			if slot ~= self.mySlot then
				order += 1
				local b = button(self.chatBody, entry.name, T.tiny)
				b.LayoutOrder = order
				b.TextColor3 = Theme.factionColor(slot)
				b.Activated:Connect(function()
					self:sendQuickChat(pending, slot)
				end)
			end
		end
		return
	end

	local order = 0
	for _, entry in QuickChat.MESSAGES do
		if entry.category == self.chatCategory then
			order += 1
			-- Le trou de la cible se lit "..." dans le catalogue : le joueur
			-- sait qu'il devra la designer au clic.
			local label = string.gsub(entry.text, "{target}", "...")
			local b = button(self.chatBody, label, T.tiny)
			b.LayoutOrder = order
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.Activated:Connect(function()
				if entry.needsTarget then
					self.chatPending = entry
					self:refreshChatSheet()
				else
					self:sendQuickChat(entry, nil)
				end
			end)
		end
	end
end

function HUD.sendQuickChat(self: HUD, entry: QuickChat.Message, targetSlot: number?)
	-- Garde-fou local : le serveur reste autoritaire sur l'anti-spam, mais le
	-- joueur merite un retour immediat plutot qu'un silence.
	if os.clock() - self.chatSentAt < QuickChat.COOLDOWN / Config.TICK_RATE then
		self:notify("Patiente un instant avant de renvoyer un message.", "info")
		return
	end
	self.chatSentAt = os.clock()
	self.chatPending = nil
	self:openSheet(nil)
	if self.onQuickChat then
		self.onQuickChat(entry.id, targetSlot)
	end
end

--=============================================================================
-- Sous-menu : Territoire
--=============================================================================

function HUD.buildTerritorySheet(self: HUD)
	local sheet = Theme.panel("Territory", self.layers.sheets)
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -SHEET_BOTTOM)
	sheet.Size = UDim2.fromOffset(SHEET_WIDTH, 88)
	self:registerSheet("territory", sheet)
	self.territoryPanel = sheet

	local owner = Theme.label(sheet, "", T.small, C.text)
	owner.Position = UDim2.fromOffset(S.md, S.sm)
	owner.Size = UDim2.fromOffset(280, 14)
	owner.TextTruncate = Enum.TextTruncate.AtEnd
	self.territoryOwner = owner

	local details = Theme.label(sheet, "", T.tiny, C.textMuted)
	details.Position = UDim2.fromOffset(S.md, 26)
	details.Size = UDim2.fromOffset(400, 30)
	details.FontFace = F.medium
	details.TextWrapped = true
	details.TextYAlignment = Enum.TextYAlignment.Top
	self.territoryDetails = details

	local close = button(sheet, "\u{2715}", T.tiny)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -S.sm, 0, S.sm - 2)
	close.Size = UDim2.fromOffset(20, 18)
	close.Activated:Connect(function()
		self:openSheet(nil)
	end)

	local actions = Instance.new("Frame")
	actions.AnchorPoint = Vector2.new(1, 1)
	actions.Position = UDim2.new(1, -S.md, 1, -S.sm)
	actions.Size = UDim2.fromOffset(316, 26)
	actions.BackgroundTransparency = 1
	actions.Parent = sheet
	Theme.list(actions, Enum.FillDirection.Horizontal, S.xs)

	self.territoryButtons = {}

	local actionDefs = {
		{ id = "attack", text = "Attaquer", order = 1 },
		{ id = "boat", text = "Debarquer", order = 2 },
		{ id = "build", text = "Construire", order = 3 },
		{ id = "nuke", text = "Frappe", order = 4 },
	}

	for _, action in actionDefs do
		local b = button(actions, action.text, T.tiny)
		b.LayoutOrder = action.order
		b.Size = UDim2.fromOffset(76, 26)
		b.Activated:Connect(function()
			if b:GetAttribute("Disabled") then
				SoundManager.play("uiError")
				return
			end
			local selected = self.selectedTerritory
			if selected and self.onTerritoryAction then
				self.onTerritoryAction(action.id, selected.index)
			end
		end)
		self.territoryButtons[action.id] = b
	end
end

--=============================================================================
-- Choix de doctrine
--=============================================================================

function HUD.buildDoctrineModal(self: HUD)
	local modal = Instance.new("Frame")
	modal.Name = "DoctrineModal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = C.void
	modal.BackgroundTransparency = 0.2
	modal.BorderSizePixel = 0
	modal.ZIndex = 20
	modal.Visible = false
	modal.Parent = self.layers.modal
	self.doctrineModal = modal

	local box = Theme.panel("Box", modal)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(620, 300)
	box.ZIndex = 21

	local title = Theme.label(box, "CHOISIS TA DOCTRINE", 22, C.text)
	title.Position = UDim2.fromOffset(S.xl, S.lg)
	title.Size = UDim2.new(1, -S.xl * 2, 0, 26)
	title.FontFace = F.display
	title.ZIndex = 22

	local subtitle = Theme.label(box, "Un engagement definitif pour toute la partie.", T.small, C.textMuted)
	subtitle.Position = UDim2.fromOffset(S.xl, S.lg + 26)
	subtitle.Size = UDim2.new(1, -S.xl * 2, 0, 16)
	subtitle.FontFace = F.medium
	subtitle.ZIndex = 22

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(S.xl, 82)
	row.Size = UDim2.new(1, -S.xl * 2, 0, 190)
	row.ZIndex = 22
	row.Parent = box
	Theme.list(row, Enum.FillDirection.Horizontal, S.sm)

	for i, doctrine in Doctrines.LIST do
		local card = button(row, "", T.small)
		card.LayoutOrder = i
		card.Size = UDim2.fromOffset(132, 190)
		card.ZIndex = 22

		local symbol = Theme.label(card, doctrine.symbol, 30, C.text)
		symbol.Position = UDim2.fromOffset(0, S.lg)
		symbol.Size = UDim2.new(1, 0, 0, 36)
		symbol.TextXAlignment = Enum.TextXAlignment.Center
		symbol.ZIndex = 23

		local name = Theme.label(card, doctrine.name, T.title, C.text)
		name.Position = UDim2.fromOffset(0, 60)
		name.Size = UDim2.new(1, 0, 0, 20)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.ZIndex = 23

		local tagline = Theme.label(card, doctrine.tagline, T.tiny, C.textMuted)
		tagline.Position = UDim2.fromOffset(S.sm, 86)
		tagline.Size = UDim2.new(1, -S.sm * 2, 0, 92)
		tagline.TextXAlignment = Enum.TextXAlignment.Center
		tagline.TextYAlignment = Enum.TextYAlignment.Top
		tagline.TextWrapped = true
		tagline.FontFace = F.medium
		tagline.ZIndex = 23

		card.Activated:Connect(function()
			if self.onDoctrineChosen then
				self.onDoctrineChosen(doctrine.id)
			end
			modal.Visible = false
			self:recordTutorial("doctrine")
		end)
	end
end

function HUD.showDoctrineModal(self: HUD)
	self.doctrineModal.Visible = true
end

--=============================================================================
-- Onboarding
--=============================================================================

function HUD.startOnboarding(self: HUD)
	self.tutorialStep = 1
	self.tutorialStartTiles = 0
	self.missionStrip.Visible = true
	self:refreshOnboarding()
end

function HUD.refreshOnboarding(self: HUD)
	local step = TUTORIAL_STEPS[self.tutorialStep]

	if not step then
		self.missionTitle.Text = "Briefing termine"
		self.missionTitle.TextColor3 = C.ally
		self.missionHint.Text = "Tu es libre de construire ton empire comme tu veux."
		self.missionFill.Size = UDim2.fromScale(1, 1)
		self.missionFill.BackgroundColor3 = C.ally
		self.missionCounter.Text = `{#TUTORIAL_STEPS} / {#TUTORIAL_STEPS}`
		-- Le bandeau s'efface de lui-meme : un objectif accompli ne doit pas
		-- continuer a occuper l'ecran.
		task.delay(4, function()
			if self.tutorialStep > #TUTORIAL_STEPS then
				self.missionStrip.Visible = false
			end
		end)
		return
	end

	self.missionStrip.Visible = true
	self.missionTitle.Text = step.title
	self.missionTitle.TextColor3 = C.text
	self.missionHint.Text = step.hint
	self.missionFill.Size = UDim2.fromScale((self.tutorialStep - 1) / #TUTORIAL_STEPS, 1)
	self.missionFill.BackgroundColor3 = C.accent
	self.missionCounter.Text = `{self.tutorialStep - 1} / {#TUTORIAL_STEPS}`
end

function HUD.recordTutorial(self: HUD, action: string)
	local step = TUTORIAL_STEPS[self.tutorialStep]
	if not step or step.key ~= action then
		return
	end
	self.tutorialStep += 1
	SoundManager.play("uiSelect")
	self:refreshOnboarding()
end

function HUD.setProfile(self: HUD, profile)
	if not profile then
		return
	end
	self.profile = profile
	self.roleLabel.Text = `COMMANDANT  \u{00B7}  NIVEAU {profile.level or 1}`
	self.profileStats.Text = `{profile.xp or 0} XP  \u{00B7}  {profile.matches or 0} campagnes  \u{00B7}  {profile.wins or 0} victoires\n{profile.betrayals or 0} trahison(s) inscrite(s) a ton nom`
	if profile.lastGain and profile.lastGain > 0 then
		self:notify(`Progression de campagne : +{profile.lastGain} XP`, "good")
	end
end

--=============================================================================
-- Territoire
--=============================================================================

function HUD.selectTerritory(
	self: HUD,
	index: number,
	ownerSlot: number,
	terrainName: string,
	buildingName: string?,
	buildingKind: number?,
	buildingLevel: number?,
	buildingRoutes: number?
)
	local level = buildingLevel or 1
	self.selectedTerritory = {
		index = index,
		owner = ownerSlot,
		buildingKind = buildingKind,
		buildingLevel = level,
	}
	self:openSheet("territory")
	self.territoryPanel.Visible = true

	local ownerName = if ownerSlot == 0
		then "Territoire neutre"
		elseif ownerSlot == self.mySlot
		then "Ton territoire"
		elseif self.roster[ownerSlot] then self.roster[ownerSlot].name else `Faction #{ownerSlot}`
	self.territoryOwner.Text = ownerName
	self.territoryOwner.TextColor3 = if ownerSlot == 0
		then C.textMuted
		elseif ownerSlot == self.mySlot
		then Theme.factionColor(self.mySlot)
		else Theme.factionColor(ownerSlot)

	local displayBuildingName = if buildingKind == Config.BUILDING.CITY
		then Config.CITY_LEVELS[level].name
		else buildingName
	local showsLevel = buildingKind ~= nil and BuildingDefs.isUpgradable(buildingKind)
	local building = if displayBuildingName and displayBuildingName ~= ""
		then `  \u{00B7}  {displayBuildingName}{if showsLevel then ` niv. {level}` else ""}`
		else ""
	local detailLine = `Case tactique #{index}`

	--[[
		Amelioration, tous types confondus.

		La ville garde ses paliers nommes ; le port et l'usine ont un niveau
		generique dont le prix est celui du batiment suivant du meme type — que le
		serveur nous envoie deja dans `buildPrices`. Aucun calcul de cout n'est
		duplique ici : il n'y a qu'une seule source de verite.
	]]
	local mine = ownerSlot == self.mySlot and buildingKind ~= nil
	local upgradable = mine and buildingKind ~= nil and BuildingDefs.isUpgradable(buildingKind)
	local maxLevel = if buildingKind then BuildingDefs.maxLevel(buildingKind) else 1
	local atMax = upgradable and level >= maxLevel
	local upgradePrice = math.huge
	local upgradeReady = false

	local nextCity = if buildingKind == Config.BUILDING.CITY then Config.CITY_LEVELS[level + 1] else nil
	if nextCity then
		local currentCity = Config.CITY_LEVELS[level]
		local doctrine = Doctrines.get(self.doctrineId)
		upgradePrice = math.floor((currentCity.upgradeCost or math.huge) * doctrine.buildCost)
		upgradeReady = self.era >= nextCity.requiredEra
		detailLine = `Vers {nextCity.name} : {upgradePrice} or \u{00B7} +{nextCity.popCapBonus - currentCity.popCapBonus} capacite`
	elseif buildingKind == Config.BUILDING.CITY then
		detailLine = "Megapole achevee \u{00B7} niveau maximum"
	elseif upgradable and not atMax and buildingKind then
		upgradePrice = self.buildPrices[buildingKind] or math.huge
		upgradeReady = true
		detailLine = `Niveau {level}/{maxLevel} \u{00B7} passer au niveau {level + 1} : {upgradePrice} or`
	elseif buildingKind == Config.BUILDING.FACTORY then
		local routes = buildingRoutes or 0
		detailLine = if routes > 0
			then `Reseau de {routes} liaison{if routes > 1 then "s" else ""} \u{00B7} villes, ports et usines a portee`
			else `Aucune gare a moins de {Config.RAIL_RANGE} cases \u{00B7} production arretee`
	end
	self.territoryDetails.Text = `{terrainName}{building}\n{detailLine}`

	local canUpgrade = upgradable and not atMax and upgradeReady
	local enabled = {
		attack = ownerSlot ~= self.mySlot,
		build = (ownerSlot == self.mySlot and buildingKind == nil) or canUpgrade,
		boat = ownerSlot ~= self.mySlot,
		nuke = ownerSlot ~= 0 and ownerSlot ~= self.mySlot and self.era >= Eras.requiredForNuke(Config.NUKE.ATOM),
	}
	for id, action in self.territoryButtons do
		local available = enabled[id] == true
		if id == "build" then
			action.Text = if mine and upgradable
				then (if atMax then "Niveau max" elseif canUpgrade then "Ameliorer" else "Verrouille")
				elseif mine then "Occupe"
				else "Construire"
		end
		action:SetAttribute("Disabled", not available)
		action.BackgroundTransparency = if available then 0 else 0.6
		action.TextTransparency = if available then 0 else 0.55
	end
end

--=============================================================================
-- Etat
--=============================================================================

function HUD.setRatio(self: HUD, ratio: number)
	self.ratio = ratio
	self.ratioFill.Size = UDim2.fromScale(ratio, 1)
	self.ratioKnob.Position = UDim2.fromScale(ratio, 0.5)
	self:refreshRatioReadout()
end

function HUD.refreshRatioReadout(self: HUD)
	local committed = math.floor(self.troops * self.ratio)
	-- "16% (669)" : la part decide, le nombre entre parentheses est ce qu'elle
	-- represente reellement. C'est le second qu'on regarde avant de lancer.
	self.ratioReadout.Text = `{math.floor(self.ratio * 100)}% ({Format.compact(committed)})`
end

--[[
	Parc de batiments possede, par type.

	Le HUD ne peut pas le compter : ces nombres vivent dans Overlay, qui suit
	les batiments poses sur la carte. C'est donc a l'appelant de les fournir —
	et tant que personne ne le fait, les pastilles affichent zero plutot que de
	mentir sur une valeur inventee.
]]
function HUD.setBuildingCounts(self: HUD, counts: { [number]: number })
	self.buildingCounts = counts
	for id, label in self.parkPills do
		label.Text = tostring(counts[id] or 0)
		label.TextColor3 = if (counts[id] or 0) > 0 then C.text else C.textFaint
	end
	self:refreshParkSlots()
end

--[[
	Arme un batiment et bascule en mode Construire.

	Deux entrees menent ici — la palette et le menu radial — et elles doivent
	produire exactement le meme etat. Quand la selection vivait dans le
	gestionnaire de clic de la palette, la seconde entree ne pouvait que le
	recopier, et une divergence n'aurait rien casse visiblement : le mode aurait
	simplement cesse de suivre le batiment choisi.
]]
function HUD.setBuildKind(self: HUD, kind: number)
	self.buildKind = kind
	self:setMode("build")
	if self.onBuildKindChanged then
		self.onBuildKindChanged(kind)
	end
end

--[[
	Fixe le denominateur exact du pourcentage de domination.

	Appele une fois par le client, des que le terrain est genere. Sans lui la
	colonne reste sur une estimation qui derive selon la graine.
]]
function HUD.setLandCount(self: HUD, tiles: number)
	if tiles and tiles > 0 then
		self.landTiles = tiles
	end
end

function HUD.setMode(self: HUD, mode: Mode)
	self.mode = mode

	for id, b in self.modeButtons do
		setSelected(b, id == mode, MODE_COLORS[id])
	end

	self.hintLabel.Text = HINTS[mode] or ""

	-- Le mode arme decide du sous-menu : construire ouvre la palette, frapper
	-- ouvre l'arsenal, et les modes qui n'ont rien a choisir ne laissent rien
	-- d'ouvert derriere eux.
	if mode == "build" then
		--[[
			L'aide contextuelle porte desormais le PRIX.

			C'etait la seule information que la palette apportait en propre. En la
			mettant ici, elle apparait exactement au moment ou elle sert — quand
			on vient d'armer un batiment — au lieu d'attendre dans un panneau
			ouvert en permanence.
		]]
		local def = BuildingDefs.get(self.buildKind)
		if def then
			local price = self.buildPrices[self.buildKind] or def.cost
			self.hintLabel.Text = `{def.name}  \u{00B7}  {price} or  \u{00B7}  {def.description}`
		end
		self:refreshParkSlots()
	elseif mode == "nuke" then
		self:openSheet("nuke")
		self:refreshPalettes()
		local needed = Eras.requiredForNuke(Config.NUKE.ATOM)
		if self.era < needed then
			self.hintLabel.Text = `Arsenal verrouille : necessite l'ere {Eras.get(needed).name}.`
		end
	elseif self.activeSheet == "nuke" then
		self:openSheet(nil)
	end

	if self.onModeChanged then
		self.onModeChanged(mode)
	end
end

--[[
	Ce qu'on ne peut pas payer est grise.

	Ne concerne plus que l'arsenal : la palette de construction a ete retiree.
	Elle offrait une TROISIEME facon de choisir un batiment, apres la rangee du
	panneau de controle et la page "Batir" du menu radial — trois chemins vers
	le meme geste, dont un occupait un tiers de l'ecran en permanence.

	Ce qu'elle apportait seule, c'etait le PRIX. Il vit desormais dans l'aide
	contextuelle au moment ou l'on arme un batiment, et l'inabordable se lit sur
	la rangee elle-meme (voir refreshParkSlots).
]]
function HUD.refreshPalettes(self: HUD)
	for kind, b in self.nukeButtons do
		local stats = Config.NUKE_STATS[kind]
		local affordable = self.gold >= stats.cost and self.era >= Eras.requiredForNuke(kind)
		setSelected(b, kind == self.nukeKind, C.nuclear)
		b.BackgroundTransparency = if kind == self.nukeKind or affordable then 0 else 0.55
	end
end

--[[
	Le bandeau d'ere du coin haut droit annonce toujours le prochain palier et
	son prix : c'est l'information qui oriente toute la partie economique, elle
	ne doit jamais demander un clic pour etre lue.
]]
function HUD.refreshEraPanel(self: HUD)
	local era = Eras.get(self.era)

	if self.era >= Eras.MAX_ID then
		self.eraName.Text = `{era.symbol} APOGEE`
		self.eraPrice.Text = ""
		self.eraFill.Size = UDim2.fromScale(1, 1)
		self.eraFill.BackgroundColor3 = C.nuclear
		setSelected(self.eraButton, false)
		return
	end

	local nextEra = Eras.get(self.era + 1)
	local ready = self.eraProgress >= 1

	self.eraName.Text = if ready
		then `\u{2192} {string.upper(nextEra.name)}`
		else `{era.symbol} {string.upper(era.name)}`
	self.eraPrice.Text = if ready then `{nextEra.cost} or` else ""
	self.eraFill.Size = UDim2.fromScale(math.clamp(self.eraProgress, 0, 1), 1)
	self.eraFill.BackgroundColor3 = if ready then C.nuclear else C.info
	setSelected(self.eraButton, ready, C.nuclear)
end

function HUD.setIdentity(self: HUD, slot: number, name: string, doctrineId: number, betrayals: number)
	self.mySlot = slot
	self.doctrineId = doctrineId
	local color = Theme.factionColor(slot)
	self.nameLabel.Text = string.upper(name)
	self.nameLabel.TextColor3 = color
	self.identityStripe.BackgroundColor3 = color

	-- Le nom de la doctrine tient dans le gris qui suit le nom, la ou le jeu de
	-- reference met le type de joueur : c'est bien ce qu'elle est chez nous, un
	-- genre de commandant. Le glyphe seul ne disait rien a qui n'a pas retenu
	-- la modale du debut de partie.
	local doctrine = Doctrines.get(doctrineId)
	self.identitySub.Text = if betrayals > 0
		then `{doctrine.name}  \u{26A0}{betrayals}`
		else doctrine.name
	self.identitySub.TextColor3 = if betrayals > 0 then C.warning else C.textMuted
end

function HUD.setMatch(self: HUD, match: Types.MatchInfo)
	-- Minutes sur deux chiffres : sous la barre des dix minutes, un "9:59" qui
	-- devient "10:00" fait sauter tout le groupe d'un caractere a chaque
	-- passage de palier. Le zero de tete fige la largeur.
	local minutes = math.floor(match.timeLeft / 60)
	local seconds = math.floor(match.timeLeft % 60)
	self.timerLabel.Text = string.format("%02d:%02d", minutes, seconds)

	if match.stage == "preparation" then
		self.phaseLabel.Text = `PREPARATION  {math.ceil(match.combatIn or 0)} s`
		self.phaseLabel.TextColor3 = C.ally
		self.timerLabel.TextColor3 = C.text
	elseif match.stage == "ended" then
		self.phaseLabel.Text = "CAMPAGNE TERMINEE"
		self.phaseLabel.TextColor3 = C.gold
	else
		self.phaseLabel.Text = ""
		-- Derniere minute : le chrono vire au rouge, prioritaire sur la teinte
		-- nucleaire — c'est l'echeance qui compte desormais, plus l'ere.
		self.timerLabel.TextColor3 = if match.timeLeft <= 60
			then C.danger
			elseif self.era >= 4 then C.nuclear
			else C.text
	end
end

--=============================================================================
-- Diplomatie
--=============================================================================

function HUD.setDiplomacy(self: HUD, diplomacy: Types.Diplomacy)
	local hadIncoming = next(self.diplomacy.incoming) ~= nil
	-- Un client d'une version anterieure peut recevoir une vue sans marques :
	-- normaliser plutot que planter sur une table absente.
	diplomacy.marks = diplomacy.marks or {}
	self.diplomacy = diplomacy

	-- Une proposition d'alliance recue est une sollicitation directe : elle
	-- merite un son et un message, pas juste un bouton qui apparait.
	if not hadIncoming and next(diplomacy.incoming) ~= nil then
		SoundManager.play("allianceFormed")
		self:notify("Une nation te propose une alliance.", "info")
	end

	self:refreshDiplomacyPanel()
end

-- Aucun sous-menu a ouvrir : le classement est permanent, la fiche se deplie
-- simplement dans sa ligne.
function HUD.selectFaction(self: HUD, slot: number?)
	self.selectedSlot = if slot ~= self.mySlot then slot else nil
	self:refreshDiplomacyPanel()
end

--[[
	Ouvre la fiche diplomatique sur la nation selectionnee.

	Un seul exemplaire pour toutes les nations : c'est le contenu qui change, pas
	le cadre. Selectionner personne la referme.
]]
function HUD.refreshDiplomacyPanel(self: HUD)
	local slot = self.selectedSlot
	local entry = if slot then self.roster[slot] else nil

	if not entry or not slot then
		self.diploDrawer.Visible = false
		self.diploCard.Visible = false
		if self.activeSheet == "diplomacy" then
			self:openSheet(nil)
		end
		return
	end

	self:openSheet("diplomacy")
	self.diploCard.Visible = true

	self.diploTitle.Text = entry.name
	self.diploTitle.TextColor3 = Theme.factionColor(slot)

	local d = self.diplomacy
	local allied = d.allies[slot] == true
	local incoming = d.incoming[slot] == true
	local outgoing = d.outgoing[slot] == true
	local embargoed = d.embargoes[slot] == true

	local status = if allied
		then "Allie"
		elseif incoming then "Te propose une alliance"
		elseif outgoing then "Proposition envoyee"
		else "Neutre"
	if entry.betrayals > 0 then
		status ..= `  \u{26A0} {entry.betrayals} trahison(s)`
	end
	if embargoed then
		status ..= "  \u{2716} embargo"
	end
	if d.traitors[slot] then
		status ..= "  Traître (actif)"
	end

	-- Marquages de cible visibles sur cette faction : les miens et ceux de mes
	-- allies. Savoir qu'on est designe est aussi une information — elle invite
	-- a rompre l'alliance avant la frappe.
	local markers: { string } = {}
	for marker, target in d.marks do
		if target == slot then
			local name = if marker == self.mySlot
				then "moi"
				elseif self.roster[marker] then self.roster[marker].name
				else "?"
			table.insert(markers, name)
		end
	end
	if #markers > 0 then
		status ..= `  \u{2691} cible de {table.concat(markers, ", ")}`
	end

	self.diploStatus.Text = status
	self.diploStatus.TextColor3 = if allied then C.ally elseif entry.betrayals > 0 then C.warning else C.textMuted

	self.diploButtons.request.Visible = not allied and not incoming and not outgoing
	self.diploButtons.accept.Visible = incoming
	self.diploButtons["break"].Visible = allied
	self.diploButtons.embargo.Visible = not embargoed
	self.diploButtons.unembargo.Visible = embargoed
	-- Gestes d'alliance active : prolongation du pacte et dons, uniquement
	-- entre allies. Le montant du don est fixe cote serveur (part du tresor).
	self.diploButtons.extend.Visible = allied
	self.diploButtons.donateGold.Visible = allied
	self.diploButtons.donateTroops.Visible = allied
	-- Designer un allie comme cible n'a aucun sens : la marque sert a
	-- coordonner une frappe, pas a decorer un pacte.
	self.diploButtons.markTarget.Visible = not allied
end

-- V54 : HUD.update hoist rankByTiles (recette V53 closure module).
-- Distinct de V50 (records ranked) et de V31 (playerStatsForReplicate).
-- Non reentrant. Meme loi : tuiles desc, tie-break troupes desc.
-- Ne PAS retoucher self.ranked / inner records (V50 deja).
-- Pas de RemoteFunction. VictoryScreen / Overlay / init.client non touches.
local function rankByTiles(a: RankRow, b: RankRow): boolean
	if a.tiles == b.tiles then
		return a.troops > b.troops
	end
	return a.tiles > b.tiles
end

--=============================================================================
-- Rafraichissement par tick
--=============================================================================

function HUD.update(self: HUD, stats: Types.Stats, roster: Types.Roster)
	self.roster = roster

	local mine = stats[self.mySlot]
	if mine then
		local previousTroops = self.troops
		local previousGold = self.gold
		self.troops = mine.troops
		self.troopsLabel.Text = Format.compact(mine.troops)
		self.popCapLabel.Text = Format.compact(mine.maxTroops)

		--[[
			Croissance de population, par seconde.

			Mesuree sur l'horloge et non sur le nombre d'appels : rien ne
			garantit que ce rafraichissement arrive au rythme du tick serveur,
			et une pente calculee sur un intervalle suppose aurait bouge au
			premier hoquet reseau. Le lissage evite le clignotement d'un chiffre
			qui varie de quelques unites d'un envoi a l'autre.
		]]
		local now = os.clock()
		local elapsed = now - (self.lastStatsAt or now)
		self.lastStatsAt = now
		if elapsed > 0 and previousTroops > 0 then
			local rate = (mine.troops - previousTroops) / elapsed
			self.troopGrowth = self.troopGrowth * 0.6 + rate * 0.4
		end
		local growth = math.floor(self.troopGrowth + 0.5)
		self.growthLabel.Text = if growth >= 0
			then `+{Format.compact(growth)}/s`
			else `-{Format.compact(-growth)}/s`
		local growthColor = if growth >= 0 then C.ally else C.warning
		self.growthLabel.TextColor3 = growthColor
		self.growthChipEdge.Color = growthColor

		local routes = mine.logisticsRoutes or 0
		local logisticsPerSecond = (mine.logisticsIncome or 0) * Config.TICK_RATE
		self.tilesLabel.Text = if routes > 0
			then `{Format.compact(mine.tiles)} tuiles  \u{00B7}  {routes} routes`
			else `{Format.compact(mine.tiles)} tuiles`
		self.goldLabel.Text = if routes > 0
			then `{Format.compact(mine.gold)}  +{string.format("%.1f", logisticsPerSecond)}/s`
			else Format.compact(mine.gold)

		if previousGold > 0 and mine.gold ~= previousGold then
			local gained = mine.gold > previousGold
			self.goldLabel.TextColor3 = if gained then C.ally else C.warning
			self.goldScale.Scale = 1
			TweenService:Create(self.goldScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = if gained then 1.1 else 0.94,
			}):Play()
			task.delay(0.16, function()
				TweenService:Create(self.goldScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				TweenService:Create(self.goldLabel, TweenInfo.new(0.25), { TextColor3 = C.gold }):Play()
			end)
		end
		if previousTroops > 0 and mine.troops > previousTroops * 1.08 then
			self.troopsLabel.TextColor3 = C.ally
			task.delay(0.22, function()
				TweenService:Create(self.troopsLabel, TweenInfo.new(0.3), { TextColor3 = C.text }):Play()
			end)
		end
		self.buildPrices = mine.buildPrices or self.buildPrices

		local fronts = mine.activeAttacks or 0
		local committed = mine.committedTroops or 0
		-- Le libelle flotte au-dessus du panneau sur 320 px : il doit tenir sans
		-- troncature, sinon c'est justement le chiffre engage qui saute.
		if fronts > 0 then
			self.frontStatus.Text =
				`{fronts} FRONT{if fronts > 1 then "S" else ""} \u{00B7} {Format.compact(committed)}`
			self.frontStatus.TextColor3 = C.accent
		elseif routes > 0 then
			self.frontStatus.Text = `{routes} ROUTE{if routes > 1 then "S" else ""} LOGISTIQUE{if routes > 1 then "S" else ""}`
			self.frontStatus.TextColor3 = C.ally
		else
			self.frontStatus.Text = "AUCUN FRONT ACTIF"
			self.frontStatus.TextColor3 = C.textFaint
		end

		local fillRatio = if mine.maxTroops > 0 then mine.troops / mine.maxTroops else 0
		local fillClamped = math.clamp(fillRatio, 0, 1)
		self.troopsFill.Size = UDim2.fromScale(fillClamped, 1)
		-- Plafond atteint : la population stagne, il faut depenser.
		-- Seuil d'alerte du plafond d'armee. La reference le fixe a 80 % ; le
		-- notre etait a 97 %, donc il ne prevenait qu'une fois le plafond
		-- pratiquement atteint — soit trop tard pour en faire quoi que ce soit.
		self.troopsFill.BackgroundColor3 = if fillRatio > Config.ARMY_LIMIT_WARNING then C.warning else C.info

		-- Les troupes engagees sont deja sorties du pool : elles se dessinent
		-- a la suite du remplissage, pour lire d'un coup ce qui defend encore
		-- et ce qui est deja parti.
		local committedRatio = if mine.maxTroops > 0 then committed / mine.maxTroops else 0
		self.committedFill.Position = UDim2.fromScale(fillClamped, 0)
		self.committedFill.Size = UDim2.fromScale(math.clamp(committedRatio, 0, 1 - fillClamped), 1)

		self:refreshRatioReadout()

		if self.gold ~= mine.gold then
			self.gold = mine.gold
			if self.mode == "build" or self.mode == "nuke" then
				self:refreshPalettes()
			end
		end

		if self.era ~= mine.era then
			self.era = mine.era
			self:refreshPalettes()
		end
		self.eraProgress = mine.eraProgress
		self:refreshEraPanel()

		local tutorial = TUTORIAL_STEPS[self.tutorialStep]
		if tutorial and tutorial.key == "colonize" and mine.tiles >= self.tutorialStartTiles + 20 then
			self:recordTutorial("colonize")
		elseif tutorial and tutorial.key == "era" and mine.era >= 2 then
			self:recordTutorial("era")
		end
	end

	-- Classement trie par territoire : c'est la mesure qui decide la victoire.
	-- V50 : recycle self.ranked + inner records (recette boatSnapBuf / V48).
	-- Distinct de V49 (hash barycentre) et de V31 (playerStatsForReplicate).
	-- Non reentrant. Truncate leftover AVANT table.sort (une ligne fantome
	-- apparaitrait dans VictoryScreen.show / #hud.ranked).
	-- Ne PAS table.insert. Ne PAS remplacer self.ranked.
	local ranked: Ranking = self.ranked
	local n = 0
	local maxTiles = 1
	for slot, s in stats do
		n += 1
		local rec = ranked[n]
		if rec == nil then
			ranked[n] = { slot = slot, tiles = s.tiles, troops = s.troops, gold = s.gold }
		else
			rec.slot = slot
			rec.tiles = s.tiles
			rec.troops = s.troops
			rec.gold = s.gold
		end
		if s.tiles > maxTiles then
			maxTiles = s.tiles
		end
	end
	for i = #ranked, n + 1, -1 do
		ranked[i] = nil
	end
	table.sort(ranked, rankByTiles)

	--[[
		Le classement maison a ete retire : la liste native de Roblox le donne
		deja, et en afficher deux revenait a demander lequel dit vrai.

		Le tri reste calcule ici. `self.ranked` sert au reste du client — il n'a
		jamais eu besoin d'un panneau pour exister, et le supprimer casserait la
		selection de faction comme la fiche diplomatique.
	]]

	self:refreshDiplomacyPanel()
end

return HUD
