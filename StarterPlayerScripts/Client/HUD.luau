--!strict
--[[
	Interface de commandement.

	**Trois elements permanents, jamais plus.**

	  1. la barre haute — qui je suis, ou en est la partie
	  2. la barre basse — mes ressources et ma prochaine action
	  3. la minimap (voir Minimap.luau)

	Tout le reste s'ouvre a la demande, et **un seul sous-menu a la fois**.

	Cette regle remplace une accumulation de douze panneaux simultanes, chacun
	ajoute isolement pour repondre a une demande et aucun capable de se fermer.
	Pris un par un ils etaient corrects ; c'est leur simultaneite qui etouffait
	la carte, c'est-a-dire le jeu lui-meme.

	Deux fusions font l'essentiel du travail :
	  - classement et diplomatie ne font plus qu'un panneau : on ouvre le
	    classement, on clique une nation, sa fiche se deplie sur place avec ses
	    actions. Le lien entre "qui est fort" et "que faire avec lui" devient
	    un seul geste au lieu de deux panneaux cote a cote.
	  - les palettes de construction et d'arsenal partagent une seule feuille,
	    au lieu de se disputer le meme coin d'ecran.

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
local LEADER_ROWS = 10

--[[
	Geometrie des trois elements permanents.

	Tout ce qui est **informatif** vit dans la barre haute ; la barre basse ne
	garde que ce sur quoi on agit. C'est ce partage qui permet de la reduire de
	720x92 a 470x64 et de rendre le centre de l'ecran a la carte, qui est le
	jeu.
]]
local TOP_BAR_WIDTH = 664
local TOP_BAR_HEIGHT = 38
local BOTTOM_BAR_WIDTH = 470
local BOTTOM_BAR_HEIGHT = 64
local SIDE_SHEET_WIDTH = 290
local SHEET_WIDTH = 620

local TUTORIAL_STEPS = {
	{ key = "doctrine", title = "Choisis ta doctrine", hint = "Elle definit ton style pour toute la campagne." },
	{ key = "colonize", title = "Etends tes frontieres", hint = "Capture 20 territoires neutres." },
	{ key = "build", title = "Fonde une ville", hint = "Mode Construire, puis clique sur ton territoire." },
	{ key = "attack", title = "Lance une offensive", hint = "Selectionne une nation voisine et engage tes troupes." },
	{ key = "era", title = "Atteins l'ere industrielle", hint = "Developpe ton economie puis finance la recherche." },
}

export type Mode = "attack" | "build" | "boat" | "nuke"

type Ranking = { { slot: number, tiles: number, troops: number } }

type LeaderRow = {
	button: TextButton,
	bar: Frame,
	name: TextLabel,
	value: TextLabel,
	details: Frame,
}

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

-- Separateur vertical entre deux groupes d'une meme barre.
local function divider(parent: GuiObject, height: number, offsetX: number)
	local line = Instance.new("Frame")
	line.Name = "Divider"
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, offsetX, 0.5, 0)
	line.Size = UDim2.fromOffset(1, height)
	line.BackgroundColor3 = C.line
	line.BorderSizePixel = 0
	line.Parent = parent
	return line
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
	self.buildButtons = {}
	self.buildPriceLabels = {}
	self.buildPrices = {}
	self.nukeButtons = {}
	self.leaderRows = {}
	self.diploButtons = {}
	self.diplomacy = { allies = {}, incoming = {}, outgoing = {}, embargoes = {}, traitors = {} }
	self.roster = {}
	self.ranked = {}
	self.feedEntries = {}
	self.feedCounter = 0
	self.feedGroups = {}
	self.buildClass = BuildingDefs.CLASSES[1].id
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

	self:buildTopBar()
	self:buildMissionStrip()
	self:buildFeed()
	self:buildBottomBar()
	self:buildNationsSheet()
	self:buildProfileSheet()
	self:buildBuildSheet()
	self:buildArsenalSheet()
	self:buildTerritorySheet()
	self:buildDoctrineModal()

	self:setRatio(self.ratio)
	self:setMode("attack")

	return self
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
-- 1. Barre haute
--=============================================================================

--[[
	Une seule ligne pour tout ce qui repond a "qui suis-je, ou en est la
	partie". Elle remplace trois panneaux distincts (identite, ere, chrono) qui
	occupaient tout le coin superieur gauche.
]]
function HUD.buildTopBar(self: HUD)
	local bar = Theme.panel("TopBar", self.root)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, S.md)
	bar.Size = UDim2.fromOffset(TOP_BAR_WIDTH, TOP_BAR_HEIGHT)

	--- Identite -------------------------------------------------------------
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.AnchorPoint = Vector2.new(0, 0.5)
	stripe.Position = UDim2.new(0, S.md, 0.5, 0)
	stripe.Size = UDim2.fromOffset(4, 20)
	stripe.BackgroundColor3 = C.textFaint
	stripe.BorderSizePixel = 0
	stripe.Parent = bar
	Theme.corner(stripe, 2)
	self.identityStripe = stripe

	local name = Theme.label(bar, "CONQUEST RTS", T.body, C.text)
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, S.md + 10, 0.5, 0)
	name.Size = UDim2.fromOffset(112, 18)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	self.nameLabel = name

	-- Doctrine et reputation en un seul glyphe : l'information reste, le
	-- panneau qui la portait disparait.
	local sub = Theme.label(bar, "", T.small, C.textMuted)
	sub.AnchorPoint = Vector2.new(0, 0.5)
	sub.Position = UDim2.new(0, S.md + 124, 0.5, 0)
	sub.Size = UDim2.fromOffset(40, 16)
	sub.FontFace = F.medium
	self.identitySub = sub

	divider(bar, 18, 172)

	--- Chrono ---------------------------------------------------------------
	local timer = Theme.label(bar, "25:00", T.body, C.text)
	timer.AnchorPoint = Vector2.new(0, 0.5)
	timer.Position = UDim2.new(0, 186, 0.5, 0)
	timer.Size = UDim2.fromOffset(52, 18)
	timer.FontFace = F.display
	self.timerLabel = timer

	local phase = Theme.label(bar, "", T.tiny, C.textMuted)
	phase.AnchorPoint = Vector2.new(0, 0.5)
	phase.Position = UDim2.new(0, 240, 0.5, 0)
	phase.Size = UDim2.fromOffset(112, 14)
	phase.FontFace = F.medium
	phase.TextTruncate = Enum.TextTruncate.AtEnd
	self.phaseLabel = phase

	divider(bar, 18, 356)

	--- Territoire et fronts -------------------------------------------------
	-- Deux chiffres qu'on consulte sans jamais cliquer dessus : leur place est
	-- ici, pas dans la barre d'action.
	local tiles = Theme.label(bar, "0 territoires", T.tiny, C.textMuted)
	tiles.Position = UDim2.fromOffset(368, 6)
	tiles.Size = UDim2.fromOffset(124, 12)
	tiles.FontFace = F.medium
	tiles.TextTruncate = Enum.TextTruncate.AtEnd
	self.tilesLabel = tiles

	local front = Theme.label(bar, "AUCUN FRONT ACTIF", T.tiny, C.textFaint)
	front.Position = UDim2.fromOffset(368, 20)
	front.Size = UDim2.fromOffset(124, 12)
	front.FontFace = F.bold
	front.TextTruncate = Enum.TextTruncate.AtEnd
	self.frontStatus = front

	divider(bar, 18, 500)

	--- Ere ------------------------------------------------------------------
	-- Le bandeau d'ere EST le bouton de recherche : quand le palier suivant est
	-- finançable il change de couleur et annonce son prix. Aucun panneau
	-- separe, aucun clic pour savoir ou on en est.
	local era = button(bar, "", T.small)
	era.AnchorPoint = Vector2.new(0, 0.5)
	era.Position = UDim2.new(0, 512, 0.5, 0)
	era.Size = UDim2.fromOffset(76, 26)
	era.TextXAlignment = Enum.TextXAlignment.Left
	era.Activated:Connect(function()
		if self.onResearch then
			self.onResearch()
		end
	end)
	self.eraButton = era

	local eraName = Theme.label(era, "", T.tiny, C.text)
	eraName.Position = UDim2.fromOffset(S.sm, 3)
	eraName.Size = UDim2.new(1, -S.sm * 2, 0, 13)
	eraName.TextTruncate = Enum.TextTruncate.AtEnd
	self.eraName = eraName

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

	--- Ouvertures de sous-menus --------------------------------------------
	local nations = button(bar, "\u{2261}", T.body)
	nations.AnchorPoint = Vector2.new(1, 0.5)
	nations.Position = UDim2.new(1, -(S.md + 32), 0.5, 0)
	nations.Size = UDim2.fromOffset(28, 26)
	nations.Activated:Connect(function()
		self:openSheet("nations", true)
	end)
	self.sheetButtons.nations = nations

	local profile = button(bar, "\u{25CF}", T.small)
	profile.AnchorPoint = Vector2.new(1, 0.5)
	profile.Position = UDim2.new(1, -S.md, 0.5, 0)
	profile.Size = UDim2.fromOffset(28, 26)
	profile.Activated:Connect(function()
		self:openSheet("profile", true)
	end)
	self.sheetButtons.profile = profile
end

--=============================================================================
-- Bandeau d'objectifs
--=============================================================================

--[[
	Une bande fine sous la barre haute, qui disparait des que le briefing est
	termine. L'ancien panneau restait a l'ecran toute la partie.
]]
function HUD.buildMissionStrip(self: HUD)
	local strip = Theme.panel("Mission", self.root)
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, S.md + TOP_BAR_HEIGHT + S.sm)
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
	feed.Name = "Feed"
	feed.AnchorPoint = Vector2.new(0.5, 0)
	feed.Position = UDim2.new(0.5, 0, 0, S.md + TOP_BAR_HEIGHT + S.sm + 30)
	feed.Size = UDim2.fromOffset(340, MAX_FEED_ENTRIES * (FEED_ENTRY_HEIGHT + S.xs))
	feed.BackgroundTransparency = 1
	feed.ClipsDescendants = true
	feed.Parent = self.root
	self.feed = feed

	local layout = Theme.list(feed, Enum.FillDirection.Vertical, S.xs)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
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

	local entry = Instance.new("TextLabel")
	entry.Size = UDim2.new(1, 0, 0, FEED_ENTRY_HEIGHT)
	entry.BackgroundColor3 = C.surface
	entry.BackgroundTransparency = 0.14
	entry.BorderSizePixel = 0
	entry.FontFace = F.bold
	entry.TextSize = T.small
	entry.TextColor3 = FEED_COLORS[kind] or C.text
	entry.Text = text
	entry.TextTruncate = Enum.TextTruncate.AtEnd
	entry.LayoutOrder = self.feedCounter
	entry.Parent = self.feed
	Theme.corner(entry, Theme.radius.sm)
	Theme.stroke(entry, FEED_COLORS[kind] or C.line, 1)

	local sound = FEED_SOUNDS[kind]
	if sound then
		SoundManager.play(sound)
	end

	self.feedCounter += 1
	table.insert(self.feedEntries, entry)
	self.feedGroups[text] = { entry = entry, count = 1 }

	while #self.feedEntries > MAX_FEED_ENTRIES do
		local oldest = table.remove(self.feedEntries, 1)
		if oldest then
			self.feedGroups[oldest.Text] = nil
			oldest:Destroy()
		end
	end

	task.delay(4.5, function()
		if not entry.Parent then
			return
		end
		local index = table.find(self.feedEntries, entry)
		if index then
			table.remove(self.feedEntries, index)
		end
		self.feedGroups[text] = nil
		local tween = TweenService:Create(
			entry,
			Theme.motion.smooth,
			{ BackgroundTransparency = 1, TextTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		entry:Destroy()
	end)
end

--=============================================================================
-- 2. Barre basse
--=============================================================================

--[[
	Ressources a gauche, engagement au centre, actions a droite.

	Le compteur de troupes reste le plus gros chiffre de l'ecran : c'est la
	seule valeur consultee en permanence, et la seule que la refonte n'a pas
	reduite.
]]
function HUD.buildBottomBar(self: HUD)
	local bar = Theme.panel("CommandBar", self.root)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -S.md)
	bar.Size = UDim2.fromOffset(BOTTOM_BAR_WIDTH, BOTTOM_BAR_HEIGHT)

	--- Ressources vives -----------------------------------------------------
	-- Les troupes restent le plus gros chiffre de l'ecran : c'est la seule
	-- valeur consultee en permanence, et la seule que la compaction n'a pas
	-- reduite.
	local troops = Theme.label(bar, "0", T.hero, C.text)
	troops.Position = UDim2.fromOffset(S.md, 6)
	troops.Size = UDim2.fromOffset(104, 28)
	troops.FontFace = F.display
	self.troopsLabel = troops

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(S.md, 35)
	track.Size = UDim2.fromOffset(104, 3)
	track.BackgroundColor3 = C.glass
	track.BorderSizePixel = 0
	track.Parent = bar
	Theme.corner(track, Theme.radius.pill)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.info
	fill.BorderSizePixel = 0
	fill.Parent = track
	Theme.corner(fill, Theme.radius.pill)
	self.troopsFill = fill

	local gold = Theme.label(bar, "0", T.small, C.gold)
	gold.Position = UDim2.fromOffset(S.md, 42)
	gold.Size = UDim2.fromOffset(104, 14)
	gold.FontFace = F.bold
	self.goldLabel = gold

	local goldScale = Instance.new("UIScale")
	goldScale.Parent = gold
	self.goldScale = goldScale

	divider(bar, 40, 128)

	--- Engagement -----------------------------------------------------------
	self:buildEngagementSlider(bar)

	--- Actions --------------------------------------------------------------
	self:buildModeRow(bar)
end

--[[
	Curseur d'engagement.

	C'est la decision tactique centrale du jeu, donc elle merite un vrai
	curseur continu plutot que des paliers : le joueur doit pouvoir doser
	precisement ce qu'il risque, et voir en chiffres absolus combien de troupes
	partent.
]]
function HUD.buildEngagementSlider(self: HUD, parent: GuiObject)
	local left = 140
	local width = 108

	local readout = Theme.label(parent, "", T.tiny, C.textMuted)
	readout.Position = UDim2.fromOffset(left, 14)
	readout.Size = UDim2.fromOffset(width, 12)
	readout.FontFace = F.medium
	readout.TextTruncate = Enum.TextTruncate.AtEnd
	self.ratioReadout = readout

	local track = Instance.new("TextButton")
	track.Name = "EngagementTrack"
	track.Text = ""
	track.AutoButtonColor = false
	track.Position = UDim2.fromOffset(left, 32)
	track.Size = UDim2.fromOffset(width, 10)
	track.BackgroundColor3 = C.glass
	track.BorderSizePixel = 0
	track.Parent = parent
	Theme.corner(track, Theme.radius.pill)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(Config.DEFAULT_ATTACK_RATIO, 1)
	fill.BackgroundColor3 = C.accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	Theme.corner(fill, Theme.radius.pill)
	self.ratioFill = fill

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(Config.DEFAULT_ATTACK_RATIO, 0.5)
	knob.Size = UDim2.fromOffset(13, 13)
	knob.BackgroundColor3 = C.text
	knob.BorderSizePixel = 0
	knob.Parent = track
	Theme.corner(knob, Theme.radius.pill)
	Theme.stroke(knob, C.accent, 2)
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

function HUD.buildModeRow(self: HUD, parent: GuiObject)
	local row = Instance.new("Frame")
	row.Name = "Modes"
	row.AnchorPoint = Vector2.new(1, 0.5)
	row.Position = UDim2.new(1, -S.md, 0.5, 0)
	row.Size = UDim2.fromOffset(212, 48)
	row.BackgroundTransparency = 1
	row.Parent = parent
	Theme.list(row, Enum.FillDirection.Horizontal, S.sm)

	local modes: { { id: Mode, text: string, key: string } } = {
		{ id = "attack", text = "ATTAQUER", key = "1" },
		{ id = "boat", text = "DEBARQUER", key = "2" },
		{ id = "build", text = "CONSTRUIRE", key = "3" },
		{ id = "nuke", text = "FRAPPE", key = "4" },
	}

	for i, entry in modes do
		local b = button(row, entry.text, T.tiny)
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(50, 48)
		b.TextYAlignment = Enum.TextYAlignment.Bottom
		b.TextWrapped = true

		-- Rappel du raccourci clavier : c'est ainsi qu'on fait passer un joueur
		-- de la souris au clavier sans tutoriel.
		local key = Theme.label(b, entry.key, T.tiny, C.textFaint)
		key.AnchorPoint = Vector2.new(1, 0)
		key.Position = UDim2.new(1, -4, 0, 3)
		key.Size = UDim2.fromOffset(10, 12)
		key.TextXAlignment = Enum.TextXAlignment.Right

		b.Activated:Connect(function()
			self:setMode(entry.id)
		end)
		self.modeButtons[entry.id] = b
	end

	-- L'aide contextuelle flotte SOUS la barre : elle change a chaque mode et
	-- n'a pas a reserver de la hauteur en permanence.
	local hint = Theme.label(self.root, "", T.tiny, C.textFaint)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -(S.md + BOTTOM_BAR_HEIGHT + 3))
	hint.Size = UDim2.fromOffset(520, 12)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.FontFace = F.medium
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	self.hintLabel = hint
end

--=============================================================================
-- Sous-menu : Nations (classement et diplomatie fusionnes)
--=============================================================================

--[[
	Le classement et la diplomatie ne font plus qu'un.

	On ouvre le classement, on clique une nation, et sa fiche se deplie **sur
	place** — drapeau, reputation, boutons d'alliance. Le lien entre "qui est
	fort" et "que faire avec lui" devient un seul geste, au lieu de deux
	panneaux qui se regardaient en chiens de faience.
]]
function HUD.buildNationsSheet(self: HUD)
	local sheet = Theme.panel("Nations", self.root)
	sheet.AnchorPoint = Vector2.new(1, 0)
	sheet.Position = UDim2.new(1, -S.md, 0, S.md + TOP_BAR_HEIGHT + S.sm)
	sheet.Size = UDim2.fromOffset(SIDE_SHEET_WIDTH, 34 + LEADER_ROWS * 20 + 150)
	self:registerSheet("nations", sheet)
	self.diploPanel = sheet

	local title = Theme.label(sheet, "DOMINATION", T.tiny, C.textFaint)
	title.Position = UDim2.fromOffset(S.md, S.sm)
	title.Size = UDim2.new(1, -S.md * 2, 0, 12)

	local close = button(sheet, "\u{2715}", T.tiny)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -S.sm, 0, S.sm - 2)
	close.Size = UDim2.fromOffset(20, 18)
	close.Activated:Connect(function()
		self:openSheet(nil)
	end)

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(S.sm, 26)
	list.Size = UDim2.new(1, -S.sm * 2, 1, -34)
	list.Parent = sheet
	Theme.list(list, Enum.FillDirection.Vertical, 2)

	for i = 1, LEADER_ROWS do
		local holder = Instance.new("Frame")
		holder.LayoutOrder = i
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 0, 20)
		holder.Parent = list

		local row = Instance.new("TextButton")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 20)
		row.Text = ""
		row.AutoButtonColor = false
		row.Parent = holder

		-- Barre de fond proportionnelle au territoire : on lit le rapport de
		-- force sans avoir a comparer des nombres.
		local bar = Instance.new("Frame")
		bar.Name = "Share"
		bar.Size = UDim2.fromScale(0, 1)
		bar.BackgroundTransparency = 0.78
		bar.BorderSizePixel = 0
		bar.Parent = row
		Theme.corner(bar, Theme.radius.sm)

		local name = Theme.label(row, "", T.small, C.textMuted)
		name.Position = UDim2.fromOffset(S.sm, 0)
		name.Size = UDim2.new(1, -66, 1, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd

		local value = Theme.label(row, "", T.small, C.textFaint)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -S.sm, 0, 0)
		value.Size = UDim2.fromOffset(50, 20)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.FontFace = F.medium

		-- La fiche diplomatique de CETTE nation, repliee par defaut.
		local details = Instance.new("Frame")
		details.Name = "Details"
		details.Position = UDim2.fromOffset(0, 20)
		details.Size = UDim2.new(1, 0, 0, 66)
		details.BackgroundColor3 = C.surfaceRaised
		details.BorderSizePixel = 0
		details.Visible = false
		details.Parent = holder
		Theme.corner(details, Theme.radius.sm)

		row.MouseEnter:Connect(function()
			bar.BackgroundTransparency = 0.6
		end)
		row.MouseLeave:Connect(function()
			bar.BackgroundTransparency = 0.78
		end)
		row.Activated:Connect(function()
			local item = self.ranked[i]
			if item then
				SoundManager.play("uiSelect")
				self:selectFaction(item.slot)
			end
		end)

		self.leaderRows[i] = { button = row, bar = bar, name = name, value = value, details = details } :: LeaderRow
	end

	-- Contenu de la fiche : un seul exemplaire, reparente dans la ligne
	-- selectionnee. Dupliquer ces boutons dix fois serait du gaspillage et
	-- multiplierait les connexions a maintenir.
	local card = Instance.new("Frame")
	card.Name = "DiplomacyCard"
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromScale(1, 1)
	card.Visible = false
	card.Parent = sheet
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
	actions.Size = UDim2.new(1, -S.sm * 2, 0, 26)
	actions.Parent = card
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -2, 0, 24)
	grid.CellPadding = UDim2.fromOffset(4, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = actions

	local actionDefs = {
		{ id = "request", text = "Alliance", color = C.ally, order = 1 },
		{ id = "accept", text = "Accepter", color = C.ally, order = 2 },
		{ id = "break", text = "Rompre", color = C.danger, order = 3 },
		{ id = "embargo", text = "Embargo", color = C.warning, order = 4 },
		{ id = "unembargo", text = "Lever", color = C.info, order = 5 },
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
-- Sous-menu : Profil
--=============================================================================

function HUD.buildProfileSheet(self: HUD)
	local sheet = Theme.panel("Profile", self.root)
	sheet.AnchorPoint = Vector2.new(1, 0)
	sheet.Position = UDim2.new(1, -S.md, 0, S.md + TOP_BAR_HEIGHT + S.sm)
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

--[[
	Les trois classes sont des onglets d'une seule feuille, et non deux
	palettes concurrentes se disputant le meme coin d'ecran.

	Le classement par classe force une reponse a "je veux quoi maintenant" —
	de l'argent, de la force, ou de l'avance technologique — avant de choisir
	un batiment precis.
]]
function HUD.buildBuildSheet(self: HUD)
	local sheet = Theme.panel("BuildSheet", self.root)
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -(S.md + BOTTOM_BAR_HEIGHT + 18))
	sheet.Size = UDim2.fromOffset(SHEET_WIDTH, 148)
	self:registerSheet("build", sheet)
	self.buildPalette = sheet

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(S.md, S.sm)
	tabs.Size = UDim2.new(1, -S.md * 2, 0, 22)
	tabs.Parent = sheet
	Theme.list(tabs, Enum.FillDirection.Horizontal, S.xs)

	self.classTabs = {}
	self.classPages = {}

	local pages = Instance.new("Frame")
	pages.BackgroundTransparency = 1
	pages.Position = UDim2.fromOffset(S.md, 38)
	pages.Size = UDim2.new(1, -S.md * 2, 1, -46)
	pages.Parent = sheet

	for i, class in BuildingDefs.CLASSES do
		local tab = button(tabs, string.upper(class.name), T.tiny)
		tab.LayoutOrder = i
		tab.Size = UDim2.fromOffset(92, 22)
		tab.Activated:Connect(function()
			self:setBuildClass(class.id)
		end)
		self.classTabs[class.id] = tab

		local page = Instance.new("Frame")
		page.Name = class.id
		page.BackgroundTransparency = 1
		page.Size = UDim2.fromScale(1, 1)
		page.Visible = false
		page.Parent = pages
		Theme.list(page, Enum.FillDirection.Horizontal, S.sm)
		self.classPages[class.id] = page

		for order, def in BuildingDefs.BY_CLASS[class.id] do
			local card = button(page, "", T.small)
			card.LayoutOrder = order
			card.Size = UDim2.fromOffset(158, 96)

			local glyph = Theme.label(card, def.symbol, 18, C.text)
			glyph.Position = UDim2.fromOffset(S.sm, S.sm)
			glyph.Size = UDim2.fromOffset(22, 22)

			local name = Theme.label(card, def.name, T.small, C.text)
			name.Position = UDim2.fromOffset(S.sm, 34)
			name.Size = UDim2.new(1, -S.sm * 2, 0, 14)
			name.TextTruncate = Enum.TextTruncate.AtEnd

			local description = Theme.label(card, def.description, T.tiny, C.textFaint)
			description.Position = UDim2.fromOffset(S.sm, 50)
			description.Size = UDim2.new(1, -S.sm * 2, 0, 26)
			description.FontFace = F.medium
			description.TextWrapped = true
			description.TextYAlignment = Enum.TextYAlignment.Top

			local price = Theme.label(card, `{def.cost} or`, T.tiny, C.gold)
			price.AnchorPoint = Vector2.new(0, 1)
			price.Position = UDim2.new(0, S.sm, 1, -S.sm)
			price.Size = UDim2.new(1, -S.sm * 2, 0, 12)
			price.FontFace = F.bold
			self.buildPriceLabels[def.id] = price

			card.Activated:Connect(function()
				self.buildKind = def.id
				self:setMode("build")
				if self.onBuildKindChanged then
					self.onBuildKindChanged(def.id)
				end
			end)

			self.buildButtons[def.id] = card
		end
	end
end

--=============================================================================
-- Sous-menu : Arsenal
--=============================================================================

function HUD.buildArsenalSheet(self: HUD)
	local sheet = Theme.panel("Arsenal", self.root)
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -(S.md + BOTTOM_BAR_HEIGHT + 18))
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

	for kind = 1, 2 do
		local stats = Config.NUKE_STATS[kind]
		local card = button(list, "", T.small)
		card.LayoutOrder = kind
		card.Size = UDim2.fromOffset(220, 74)

		local glyph = Theme.label(card, "\u{2622}", 18, C.nuclear)
		glyph.Position = UDim2.fromOffset(S.sm, S.sm)
		glyph.Size = UDim2.fromOffset(22, 22)

		local name = Theme.label(card, stats.name, T.small, C.text)
		name.Position = UDim2.fromOffset(S.sm + 26, 10)
		name.Size = UDim2.new(1, -S.sm - 26, 0, 14)

		local detail = Theme.label(card, `Rayon {stats.radius} tuiles`, T.tiny, C.textFaint)
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
-- Sous-menu : Territoire
--=============================================================================

function HUD.buildTerritorySheet(self: HUD)
	local sheet = Theme.panel("Territory", self.root)
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -(S.md + BOTTOM_BAR_HEIGHT + 18))
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
	modal.Parent = self.root
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
	local building = if displayBuildingName and displayBuildingName ~= ""
		then `  \u{00B7}  {displayBuildingName}{if buildingKind == Config.BUILDING.CITY then ` niv. {level}` else ""}`
		else ""
	local detailLine = `Case tactique #{index}`
	local upgradePrice = math.huge
	local nextCity = if buildingKind == Config.BUILDING.CITY then Config.CITY_LEVELS[level + 1] else nil
	if nextCity then
		local currentCity = Config.CITY_LEVELS[level]
		local doctrine = Doctrines.get(self.doctrineId)
		upgradePrice = math.floor((currentCity.upgradeCost or math.huge) * doctrine.buildCost)
		detailLine = `Vers {nextCity.name} : {upgradePrice} or \u{00B7} +{nextCity.popCapBonus - currentCity.popCapBonus} capacite`
	elseif buildingKind == Config.BUILDING.CITY then
		detailLine = "Megapole achevee \u{00B7} niveau maximum"
	elseif buildingKind == Config.BUILDING.FACTORY then
		local routes = buildingRoutes or 0
		detailLine = if routes > 0
			then `{routes} route{if routes > 1 then "s" else ""} logistique{if routes > 1 then "s" else ""} \u{00B7} une par ville desservie`
			else `Aucune ville a moins de {Config.FACTORY_ROUTE_RANGE} cases \u{00B7} production arretee`
	end
	self.territoryDetails.Text = `{terrainName}{building}\n{detailLine}`

	local citySelected = ownerSlot == self.mySlot and buildingKind == Config.BUILDING.CITY
	local cityUpgradeable = citySelected and nextCity ~= nil and self.era >= nextCity.requiredEra
	local enabled = {
		attack = ownerSlot ~= self.mySlot,
		build = (ownerSlot == self.mySlot and buildingKind == nil) or cityUpgradeable,
		boat = ownerSlot ~= self.mySlot,
		nuke = ownerSlot ~= 0 and ownerSlot ~= self.mySlot and self.era >= Eras.requiredForNuke(Config.NUKE.ATOM),
	}
	for id, action in self.territoryButtons do
		local available = enabled[id] == true
		if id == "build" then
			action.Text = if citySelected
				then (if nextCity == nil then "Niveau max" elseif cityUpgradeable then "Ameliorer" else "Verrouille")
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
	self.ratioReadout.Text = `{math.floor(self.ratio * 100)} %  \u{2192}  {committed} troupes`
end

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
		self:openSheet("build")
		local def = BuildingDefs.get(self.buildKind)
		if def then
			self.hintLabel.Text = `{def.name}  \u{00B7}  {def.description}`
		end
		self:refreshPalettes()
	elseif mode == "nuke" then
		self:openSheet("nuke")
		self:refreshPalettes()
		local needed = Eras.requiredForNuke(Config.NUKE.ATOM)
		if self.era < needed then
			self.hintLabel.Text = `Arsenal verrouille : necessite l'ere {Eras.get(needed).name}.`
		end
	elseif self.activeSheet == "build" or self.activeSheet == "nuke" then
		self:openSheet(nil)
	end

	if self.onModeChanged then
		self.onModeChanged(mode)
	end
end

function HUD.setBuildClass(self: HUD, classId: string)
	self.buildClass = classId
	for id, tab in self.classTabs do
		setSelected(tab, id == classId)
	end
	for id, page in self.classPages do
		page.Visible = id == classId
	end
end

-- Ce qu'on ne peut pas payer est grise : le joueur lit son budget sans avoir a
-- comparer des chiffres.
function HUD.refreshPalettes(self: HUD)
	for id, b in self.buildButtons do
		local def = BuildingDefs.get(id)
		local unlocked = self.era >= Eras.requiredFor(id)
		local realPrice = self.buildPrices[id] or (if def then def.cost else math.huge)
		local affordable = def ~= nil and unlocked and self.gold >= realPrice
		local priceLabel = self.buildPriceLabels[id]
		if priceLabel then
			priceLabel.Text = if realPrice < math.huge then `{realPrice} or` else "\u{2014}"
			priceLabel.TextColor3 = if affordable then C.gold else C.textFaint
		end
		setSelected(b, id == self.buildKind)
		b.BackgroundTransparency = if id == self.buildKind or affordable then 0 else 0.55
	end

	for kind, b in self.nukeButtons do
		local stats = Config.NUKE_STATS[kind]
		local affordable = self.gold >= stats.cost and self.era >= Eras.requiredForNuke(kind)
		setSelected(b, kind == self.nukeKind, C.nuclear)
		b.BackgroundTransparency = if kind == self.nukeKind or affordable then 0 else 0.55
	end
end

--[[
	Le bandeau d'ere de la barre haute annonce toujours le prochain palier et
	son prix : c'est l'information qui oriente toute la partie economique, elle
	ne doit jamais demander un clic pour etre lue.
]]
function HUD.refreshEraPanel(self: HUD)
	local era = Eras.get(self.era)

	if self.era >= Eras.MAX_ID then
		self.eraName.Text = `{era.symbol} APOGEE`
		self.eraFill.Size = UDim2.fromScale(1, 1)
		self.eraFill.BackgroundColor3 = C.nuclear
		setSelected(self.eraButton, false)
		return
	end

	local nextEra = Eras.get(self.era + 1)
	local ready = self.eraProgress >= 1

	self.eraName.Text = if ready
		then `\u{2192} {string.upper(nextEra.name)}  {nextEra.cost} or`
		else `{era.symbol} {string.upper(era.name)}`
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

	local doctrine = Doctrines.get(doctrineId)
	self.identitySub.Text = if betrayals > 0 then `{doctrine.symbol} \u{26A0}{betrayals}` else doctrine.symbol
	self.identitySub.TextColor3 = if betrayals > 0 then C.warning else C.textMuted
end

function HUD.setMatch(self: HUD, match: Types.MatchInfo)
	local minutes = math.floor(match.timeLeft / 60)
	local seconds = math.floor(match.timeLeft % 60)
	self.timerLabel.Text = string.format("%d:%02d", minutes, seconds)

	if match.stage == "preparation" then
		self.phaseLabel.Text = `PREPARATION  {math.ceil(match.combatIn or 0)} s`
		self.phaseLabel.TextColor3 = C.ally
		self.timerLabel.TextColor3 = C.text
	elseif match.stage == "ended" then
		self.phaseLabel.Text = "CAMPAGNE TERMINEE"
		self.phaseLabel.TextColor3 = C.gold
	else
		self.phaseLabel.Text = ""
		self.timerLabel.TextColor3 = if self.era >= 4 then C.nuclear else C.text
	end
end

--=============================================================================
-- Diplomatie
--=============================================================================

function HUD.setDiplomacy(self: HUD, diplomacy: Types.Diplomacy)
	local hadIncoming = next(self.diplomacy.incoming) ~= nil
	self.diplomacy = diplomacy

	-- Une proposition d'alliance recue est une sollicitation directe : elle
	-- merite un son et un message, pas juste un bouton qui apparait.
	if not hadIncoming and next(diplomacy.incoming) ~= nil then
		SoundManager.play("allianceFormed")
		self:notify("Une nation te propose une alliance.", "info")
	end

	self:refreshDiplomacyPanel()
end

function HUD.selectFaction(self: HUD, slot: number?)
	self.selectedSlot = if slot ~= self.mySlot then slot else nil
	if self.selectedSlot then
		self:openSheet("nations")
	end
	self:refreshDiplomacyPanel()
end

--[[
	Deplie la fiche diplomatique dans la ligne de la nation selectionnee.

	La carte est un exemplaire unique qu'on reparente : dupliquer ces boutons
	pour chacune des dix lignes multiplierait les connexions a maintenir pour
	un panneau visible une ligne a la fois.
]]
function HUD.refreshDiplomacyPanel(self: HUD)
	local slot = self.selectedSlot
	local entry = if slot then self.roster[slot] else nil

	for i, row in self.leaderRows do
		local item = self.ranked[i]
		local isSelected = entry ~= nil and item ~= nil and item.slot == slot
		row.details.Visible = isSelected
		row.button.Parent.Size = UDim2.new(1, 0, 0, if isSelected then 88 else 20)
		if isSelected then
			self.diploCard.Parent = row.details
			self.diploCard.Visible = true
		end
	end

	if not entry or not slot then
		self.diploCard.Visible = false
		return
	end

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
	self.diploStatus.Text = status
	self.diploStatus.TextColor3 = if allied then C.ally elseif entry.betrayals > 0 then C.warning else C.textMuted

	self.diploButtons.request.Visible = not allied and not incoming and not outgoing
	self.diploButtons.accept.Visible = incoming
	self.diploButtons["break"].Visible = allied
	self.diploButtons.embargo.Visible = not embargoed
	self.diploButtons.unembargo.Visible = embargoed
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
		self.troopsLabel.Text = tostring(mine.troops)

		local routes = mine.logisticsRoutes or 0
		local logisticsPerSecond = (mine.logisticsIncome or 0) * Config.TICK_RATE
		self.tilesLabel.Text = if routes > 0
			then `{mine.tiles} territoires  \u{00B7}  {routes} routes`
			else `{mine.tiles} territoires`
		self.goldLabel.Text = if routes > 0
			then `{mine.gold}  +{string.format("%.1f", logisticsPerSecond)}/s`
			else tostring(mine.gold)

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
		if fronts > 0 then
			self.frontStatus.Text = `{fronts} FRONT{if fronts > 1 then "S" else ""} \u{00B7} {committed} ENGAGEES`
			self.frontStatus.TextColor3 = C.accent
		elseif routes > 0 then
			self.frontStatus.Text = `{routes} ROUTE{if routes > 1 then "S" else ""} LOGISTIQUE{if routes > 1 then "S" else ""}`
			self.frontStatus.TextColor3 = C.ally
		else
			self.frontStatus.Text = "AUCUN FRONT ACTIF"
			self.frontStatus.TextColor3 = C.textFaint
		end

		local fillRatio = if mine.maxTroops > 0 then mine.troops / mine.maxTroops else 0
		self.troopsFill.Size = UDim2.fromScale(math.clamp(fillRatio, 0, 1), 1)
		-- Plafond atteint : la population stagne, il faut depenser.
		self.troopsFill.BackgroundColor3 = if fillRatio > 0.97 then C.warning else C.info

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
	local ranked: Ranking = {}
	local maxTiles = 1
	for slot, s in stats do
		table.insert(ranked, { slot = slot, tiles = s.tiles, troops = s.troops })
		if s.tiles > maxTiles then
			maxTiles = s.tiles
		end
	end
	table.sort(ranked, function(a, b)
		if a.tiles == b.tiles then
			return a.troops > b.troops
		end
		return a.tiles > b.tiles
	end)
	self.ranked = ranked

	for i, row in self.leaderRows do
		local item = ranked[i]
		if not item then
			row.button.Parent.Visible = false
			continue
		end

		row.button.Parent.Visible = true
		local info = roster[item.slot]
		local color = Theme.factionColor(item.slot)

		-- Marqueurs sociaux : l'allie et le traitre doivent se reperer d'un
		-- coup d'oeil, sans ouvrir de fiche.
		local marks = ""
		if self.diplomacy.allies[item.slot] then
			marks ..= " \u{1F91D}"
		end
		if self.diplomacy.traitors[item.slot] then
			marks ..= " \u{26A0}"
		end

		local prefix = if item.slot == self.mySlot then "\u{25B8} " else ""
		row.name.Text = `{prefix}{if info then info.name else `#{item.slot}`}{marks}`
		row.name.TextColor3 = if item.slot == self.mySlot then C.text else color
		row.value.Text = tostring(item.tiles)
		row.bar.BackgroundColor3 = color
		row.bar.Size = UDim2.fromScale(item.tiles / maxTiles, 1)
	end

	self:refreshDiplomacyPanel()
end

return HUD
