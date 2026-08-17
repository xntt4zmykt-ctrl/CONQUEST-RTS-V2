--!strict
--[[
	Interface de commandement.

	Principe directeur : a tout instant le joueur doit pouvoir repondre a trois
	questions sans reflechir — combien j'ai de troupes, qui est en train de
	gagner, et qu'est-ce que mon prochain clic va faire. Tout le reste est
	secondaire et peut etre replie.

	Le HUD ne connait pas le reseau : il expose des callbacks que init.client
	branche sur les remotes. Il ne connait pas non plus la carte : il expose un
	mode courant que le controleur de saisie interroge.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Doctrines = require(Shared:WaitForChild("Doctrines"))
local BuildingDefs = require(Shared:WaitForChild("BuildingDefs"))

local HUD = {}
HUD.__index = HUD

local RATIOS = { 0.1, 0.25, 0.5, 1.0 }

-- Le fil de notifications ne doit jamais depasser cette hauteur : au-dela il
-- recouvre la carte, qui est l'element le plus important de l'ecran.
local MAX_FEED_ENTRIES = 5
local FEED_ENTRY_HEIGHT = 24
local BOLD = Font.fromEnum(Enum.Font.GothamBold)
local REGULAR = Font.fromEnum(Enum.Font.Gotham)
local UI = Config.UI

export type Mode = "attack" | "build" | "boat" | "nuke"

type Ranking = { { slot: number, tiles: number, troops: number } }

export type HUD = typeof(setmetatable(
	{} :: {
		root: Frame,
		mode: Mode,
		buildKind: number,
		nukeKind: number,
		mySlot: number,
		ratio: number,
		selectedSlot: number?,
		gold: number,

		troopsLabel: TextLabel,
		goldLabel: TextLabel,
		tilesLabel: TextLabel,
		nameLabel: TextLabel,
		timerLabel: TextLabel,
		hintLabel: TextLabel,
		modeButtons: { [string]: TextButton },
		ratioButtons: { [number]: TextButton },
		buildPalette: Frame,
		buildButtons: { [number]: TextButton },
		nukePalette: Frame,
		leaderRows: { [number]: TextButton },
		diploPanel: Frame,
		diploTitle: TextLabel,
		diploButtons: { [string]: TextButton },
		feed: Frame,
		feedEntries: { TextLabel },
		feedCounter: number,
		doctrineModal: Frame,

		diplomacy: Types.Diplomacy,
		roster: Types.Roster,
		ranked: Ranking,

		onRatioChanged: ((number) -> ())?,
		onDoctrineChosen: ((number) -> ())?,
		onDiplomacyAction: ((string, number) -> ())?,
		onModeChanged: ((Mode) -> ())?,
	},
	HUD
))

--=============================================================================
-- Petits constructeurs
--=============================================================================

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: GuiObject, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = 0.4
	s.Parent = parent
end

local function panel(name: string, parent: GuiObject): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = UI.PANEL
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, 12)
	stroke(frame, UI.STROKE, 1.5)
	return frame
end

local function label(parent: GuiObject, text: string, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = BOLD
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent: GuiObject, text: string, size: number): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = UI.PANEL_LIGHT
	b.BorderSizePixel = 0
	b.FontFace = BOLD
	b.TextSize = size
	b.TextColor3 = UI.TEXT_DIM
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 8)
	return b
end

local function colorFor(slot: number): Color3
	if slot <= 0 then
		return Color3.fromRGB(200, 200, 200)
	end
	return Config.PLAYER_COLORS[((slot - 1) % #Config.PLAYER_COLORS) + 1]
end

--=============================================================================
-- Construction de l'interface
--=============================================================================

function HUD.new(parent: ScreenGui): HUD
	local self = setmetatable({}, HUD) :: HUD

	self.mode = "attack"
	self.buildKind = Config.BUILDING.CITY
	self.nukeKind = Config.NUKE.ATOM
	self.mySlot = 0
	self.ratio = Config.DEFAULT_ATTACK_RATIO
	self.gold = 0
	self.modeButtons = {}
	self.ratioButtons = {}
	self.buildButtons = {}
	self.leaderRows = {}
	self.diploButtons = {}
	self.diplomacy = { allies = {}, incoming = {}, outgoing = {}, embargoes = {}, traitors = {} }
	self.roster = {}
	self.ranked = {}
	self.feedEntries = {}
	self.feedCounter = 0

	local root = Instance.new("Frame")
	root.Name = "HUD"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = parent
	self.root = root

	self:buildTopBar()
	self:buildCommandBar()
	self:buildBuildPalette()
	self:buildNukePalette()
	self:buildLeaderboard()
	self:buildDiplomacyPanel()
	self:buildFeed()
	self:buildDoctrineModal()

	self:setRatio(self.ratio)
	self:setMode("attack")

	return self
end

function HUD.buildTopBar(self: HUD)
	local top = panel("TopBar", self.root)
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 12)
	top.Size = UDim2.fromOffset(340, 52)

	local name = label(top, Config.GAME_NAME, 17, UI.TEXT)
	name.Position = UDim2.fromOffset(14, 6)
	name.Size = UDim2.new(1, -28, 0, 20)
	self.nameLabel = name

	local timer = label(top, "25:00", 14, UI.TEXT_DIM)
	timer.Position = UDim2.fromOffset(14, 27)
	timer.Size = UDim2.new(1, -28, 0, 18)
	timer.FontFace = REGULAR
	self.timerLabel = timer
end

function HUD.buildCommandBar(self: HUD)
	local bar = panel("CommandBar", self.root)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(520, 148)

	-- Ligne 1 : ressources. Les troupes sont le chiffre le plus gros de tout
	-- l'ecran, parce que c'est la seule valeur consultee en permanence.
	local troops = label(bar, "0", 30, UI.TEXT)
	troops.Position = UDim2.fromOffset(18, 8)
	troops.Size = UDim2.fromOffset(220, 34)
	self.troopsLabel = troops

	local gold = label(bar, "0", 18, UI.GOLD)
	gold.AnchorPoint = Vector2.new(1, 0)
	gold.Position = UDim2.new(1, -18, 0, 10)
	gold.Size = UDim2.fromOffset(160, 22)
	gold.TextXAlignment = Enum.TextXAlignment.Right
	self.goldLabel = gold

	local tiles = label(bar, "0 territoires", 13, UI.TEXT_DIM)
	tiles.AnchorPoint = Vector2.new(1, 0)
	tiles.Position = UDim2.new(1, -18, 0, 32)
	tiles.Size = UDim2.fromOffset(160, 18)
	tiles.TextXAlignment = Enum.TextXAlignment.Right
	tiles.FontFace = REGULAR
	self.tilesLabel = tiles

	-- Ligne 2 : curseur d'engagement.
	local ratioRow = Instance.new("Frame")
	ratioRow.BackgroundTransparency = 1
	ratioRow.Position = UDim2.fromOffset(18, 48)
	ratioRow.Size = UDim2.new(1, -36, 0, 28)
	ratioRow.Parent = bar

	local ratioLayout = Instance.new("UIListLayout")
	ratioLayout.FillDirection = Enum.FillDirection.Horizontal
	ratioLayout.Padding = UDim.new(0, 6)
	ratioLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ratioLayout.Parent = ratioRow

	for i, value in RATIOS do
		local b = button(ratioRow, `{math.floor(value * 100)}%`, 15)
		b.LayoutOrder = i
		b.Size = UDim2.new(0.25, -5, 1, 0)
		b.Activated:Connect(function()
			self:setRatio(value)
			if self.onRatioChanged then
				self.onRatioChanged(value)
			end
		end)
		self.ratioButtons[i] = b
	end

	-- Ligne 3 : mode d'action. C'est ce qui determine l'effet du prochain clic
	-- sur la carte, donc le mode actif est marque en couleur d'accent.
	local modeRow = Instance.new("Frame")
	modeRow.BackgroundTransparency = 1
	modeRow.Position = UDim2.fromOffset(18, 82)
	modeRow.Size = UDim2.new(1, -36, 0, 30)
	modeRow.Parent = bar

	local modeLayout = Instance.new("UIListLayout")
	modeLayout.FillDirection = Enum.FillDirection.Horizontal
	modeLayout.Padding = UDim.new(0, 6)
	modeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	modeLayout.Parent = modeRow

	local modes: { { id: Mode, text: string } } = {
		{ id = "attack", text = "Attaquer" },
		{ id = "boat", text = "Debarquer" },
		{ id = "build", text = "Construire" },
		{ id = "nuke", text = "Nucleaire" },
	}

	for i, entry in modes do
		local b = button(modeRow, entry.text, 13)
		b.LayoutOrder = i
		b.Size = UDim2.new(0.25, -5, 1, 0)
		b.Activated:Connect(function()
			self:setMode(entry.id)
		end)
		self.modeButtons[entry.id] = b
	end

	local hint = label(bar, "", 12, UI.TEXT_DIM)
	hint.Position = UDim2.fromOffset(18, 118)
	hint.Size = UDim2.new(1, -36, 0, 18)
	hint.FontFace = REGULAR
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	self.hintLabel = hint
end

function HUD.buildBuildPalette(self: HUD)
	local palette = panel("BuildPalette", self.root)
	palette.AnchorPoint = Vector2.new(0, 1)
	palette.Position = UDim2.new(0, 14, 1, -14)
	palette.Size = UDim2.fromOffset(198, 30 + #BuildingDefs.LIST * 40)
	palette.Visible = false
	self.buildPalette = palette

	local title = label(palette, "CONSTRUIRE", 12, UI.TEXT_DIM)
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 16)

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(10, 28)
	list.Size = UDim2.new(1, -20, 1, -38)
	list.Parent = palette

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for i, def in BuildingDefs.LIST do
		local b = button(list, "", 13)
		b.LayoutOrder = i
		b.Size = UDim2.new(1, 0, 0, 35)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Text = `  {def.symbol}  {def.name}`

		local price = label(b, tostring(def.cost), 12, UI.GOLD)
		price.AnchorPoint = Vector2.new(1, 0.5)
		price.Position = UDim2.new(1, -10, 0.5, 0)
		price.Size = UDim2.fromOffset(50, 16)
		price.TextXAlignment = Enum.TextXAlignment.Right

		b.Activated:Connect(function()
			self.buildKind = def.id
			self:setMode("build")
			self:refreshBuildPalette()
		end)

		self.buildButtons[def.id] = b
	end
end

function HUD.buildNukePalette(self: HUD)
	local palette = panel("NukePalette", self.root)
	palette.AnchorPoint = Vector2.new(0, 1)
	palette.Position = UDim2.new(0, 14, 1, -14)
	palette.Size = UDim2.fromOffset(198, 110)
	palette.Visible = false
	self.nukePalette = palette

	local title = label(palette, "ARSENAL", 12, UI.TEXT_DIM)
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 16)

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(10, 28)
	list.Size = UDim2.new(1, -20, 1, -38)
	list.Parent = palette

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for kind, stats in Config.NUKE_STATS do
		local b = button(list, `  {stats.name}`, 13)
		b.LayoutOrder = kind
		b.Size = UDim2.new(1, 0, 0, 32)
		b.TextXAlignment = Enum.TextXAlignment.Left

		local price = label(b, tostring(stats.cost), 12, UI.GOLD)
		price.AnchorPoint = Vector2.new(1, 0.5)
		price.Position = UDim2.new(1, -10, 0.5, 0)
		price.Size = UDim2.fromOffset(50, 16)
		price.TextXAlignment = Enum.TextXAlignment.Right

		b.Activated:Connect(function()
			self.nukeKind = kind
			self:setMode("nuke")
		end)
	end
end

function HUD.buildLeaderboard(self: HUD)
	local board = panel("Leaderboard", self.root)
	board.AnchorPoint = Vector2.new(1, 0)
	board.Position = UDim2.new(1, -14, 0, 12)
	board.Size = UDim2.fromOffset(226, 256)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = board

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = board

	for i = 1, 11 do
		local row = Instance.new("TextButton")
		row.LayoutOrder = i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 20)
		row.FontFace = BOLD
		row.TextSize = 12
		row.TextColor3 = UI.TEXT_DIM
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.Text = ""
		row.AutoButtonColor = false
		row.Parent = board
		self.leaderRows[i] = row
	end
end

function HUD.buildDiplomacyPanel(self: HUD)
	local p = panel("Diplomacy", self.root)
	p.AnchorPoint = Vector2.new(1, 0)
	p.Position = UDim2.new(1, -14, 0, 276)
	p.Size = UDim2.fromOffset(226, 152)
	p.Visible = false
	self.diploPanel = p

	local title = label(p, "", 14, UI.TEXT)
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 20)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	self.diploTitle = title

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(10, 32)
	list.Size = UDim2.new(1, -20, 1, -42)
	list.Parent = p

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local actions = {
		{ id = "request", text = "Proposer une alliance", order = 1 },
		{ id = "accept", text = "Accepter l'alliance", order = 2 },
		{ id = "break", text = "Rompre le pacte", order = 3 },
		{ id = "embargo", text = "Declarer un embargo", order = 4 },
		{ id = "unembargo", text = "Lever l'embargo", order = 5 },
	}

	for _, action in actions do
		local b = button(list, action.text, 12)
		b.LayoutOrder = action.order
		b.Size = UDim2.new(1, 0, 0, 26)
		b.Visible = false
		b.Activated:Connect(function()
			local target = self.selectedSlot
			if target and self.onDiplomacyAction then
				self.onDiplomacyAction(action.id, target)
			end
		end)
		self.diploButtons[action.id] = b
	end
end

function HUD.buildFeed(self: HUD)
	local feed = Instance.new("Frame")
	feed.Name = "Feed"
	feed.AnchorPoint = Vector2.new(0.5, 0)
	feed.Position = UDim2.new(0.5, 0, 0, 72)
	-- Hauteur bornee au nombre maximal de messages, et decoupage actif : le
	-- fil ne doit jamais pouvoir grandir jusqu'a manger la carte.
	feed.Size = UDim2.fromOffset(420, MAX_FEED_ENTRIES * (FEED_ENTRY_HEIGHT + 4))
	feed.BackgroundTransparency = 1
	feed.ClipsDescendants = true
	feed.Parent = self.root
	self.feed = feed
	self.feedEntries = {}

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = feed
end

--[[
	Le choix de doctrine est le premier ecran de la partie. Il est modal et
	bloquant visuellement, mais pas fonctionnellement : un joueur qui l'ignore
	garde la doctrine par defaut et peut jouer immediatement.
]]
function HUD.buildDoctrineModal(self: HUD)
	local modal = Instance.new("Frame")
	modal.Name = "DoctrineModal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
	modal.BackgroundTransparency = 0.25
	modal.BorderSizePixel = 0
	modal.ZIndex = 20
	modal.Parent = self.root
	self.doctrineModal = modal

	local box = panel("Box", modal)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(560, 300)
	box.ZIndex = 21

	local title = label(box, "CHOISIS TA DOCTRINE", 20, UI.TEXT)
	title.Position = UDim2.fromOffset(20, 16)
	title.Size = UDim2.new(1, -40, 0, 26)
	title.ZIndex = 22

	local subtitle = label(box, "Un engagement definitif pour toute la partie.", 13, UI.TEXT_DIM)
	subtitle.Position = UDim2.fromOffset(20, 42)
	subtitle.Size = UDim2.new(1, -40, 0, 18)
	subtitle.FontFace = REGULAR
	subtitle.ZIndex = 22

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(20, 74)
	row.Size = UDim2.new(1, -40, 0, 200)
	row.ZIndex = 22
	row.Parent = box

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	for i, doctrine in Doctrines.LIST do
		local card = button(row, "", 13)
		card.LayoutOrder = i
		card.Size = UDim2.new(0.25, -8, 1, 0)
		card.Text = ""
		card.ZIndex = 22

		local symbol = label(card, doctrine.symbol, 30, UI.TEXT)
		symbol.Position = UDim2.fromOffset(0, 16)
		symbol.Size = UDim2.new(1, 0, 0, 36)
		symbol.TextXAlignment = Enum.TextXAlignment.Center
		symbol.ZIndex = 23

		local name = label(card, doctrine.name, 15, UI.TEXT)
		name.Position = UDim2.fromOffset(0, 58)
		name.Size = UDim2.new(1, 0, 0, 20)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.ZIndex = 23

		local tagline = label(card, doctrine.tagline, 11, UI.TEXT_DIM)
		tagline.Position = UDim2.fromOffset(8, 84)
		tagline.Size = UDim2.new(1, -16, 0, 80)
		tagline.TextXAlignment = Enum.TextXAlignment.Center
		tagline.TextYAlignment = Enum.TextYAlignment.Top
		tagline.TextWrapped = true
		tagline.FontFace = REGULAR
		tagline.ZIndex = 23

		card.Activated:Connect(function()
			if self.onDoctrineChosen then
				self.onDoctrineChosen(doctrine.id)
			end
			modal.Visible = false
		end)
	end
end

--=============================================================================
-- Etat de l'interface
--=============================================================================

function HUD.setRatio(self: HUD, ratio: number)
	self.ratio = ratio
	for i, b in self.ratioButtons do
		local selected = math.abs(RATIOS[i] - ratio) < 1e-3
		b.BackgroundColor3 = if selected then UI.ACCENT else UI.PANEL_LIGHT
		b.TextColor3 = if selected then UI.TEXT else UI.TEXT_DIM
	end
end

local HINTS: { [string]: string } = {
	attack = "Clique sur un territoire voisin pour lancer l'offensive.",
	boat = "Clique sur une cote ennemie ou neutre pour y debarquer.",
	build = "Clique sur ton territoire pour poser le batiment choisi.",
	nuke = "Clique sur la cible de la frappe. Elle sera visible de tous.",
}

function HUD.setMode(self: HUD, mode: Mode)
	self.mode = mode

	for id, b in self.modeButtons do
		local selected = id == mode
		b.BackgroundColor3 = if selected then UI.ACCENT else UI.PANEL_LIGHT
		b.TextColor3 = if selected then UI.TEXT else UI.TEXT_DIM
	end

	self.buildPalette.Visible = mode == "build"
	self.nukePalette.Visible = mode == "nuke"
	self.hintLabel.Text = HINTS[mode] or ""

	if mode == "build" then
		self:refreshBuildPalette()
	end

	if self.onModeChanged then
		self.onModeChanged(mode)
	end
end

-- Le batiment selectionne est mis en avant, et ceux qu'on ne peut pas payer
-- sont grises : le joueur voit son budget sans avoir a comparer des chiffres.
function HUD.refreshBuildPalette(self: HUD)
	for id, b in self.buildButtons do
		local def = BuildingDefs.get(id)
		local affordable = def ~= nil and self.gold >= def.cost
		local selected = id == self.buildKind

		b.BackgroundColor3 = if selected then UI.ACCENT else UI.PANEL_LIGHT
		if selected then
			b.TextColor3 = UI.TEXT
		else
			b.TextColor3 = if affordable then UI.TEXT_DIM else Color3.fromRGB(95, 105, 120)
		end
	end
end

function HUD.setIdentity(self: HUD, slot: number, name: string)
	self.mySlot = slot
	self.nameLabel.Text = name
	self.nameLabel.TextColor3 = colorFor(slot)
end

function HUD.showDoctrineModal(self: HUD)
	self.doctrineModal.Visible = true
end

--=============================================================================
-- Flux de notifications
--=============================================================================

local FEED_COLORS: { [string]: Color3 } = {
	good = Color3.fromRGB(120, 230, 160),
	bad = Color3.fromRGB(255, 120, 110),
	alert = Color3.fromRGB(255, 200, 90),
	info = Color3.fromRGB(180, 200, 230),
}

--[[
	Ajoute un message au fil.

	Le fil est plafonne en nombre d'entrees, pas seulement en duree : pendant
	une phase agitee (offensives multiples, frappes nucleaires), les messages
	arrivent bien plus vite qu'ils n'expirent, et un simple minuteur laissait le
	fil recouvrir tout l'ecran. Au-dela du plafond, le plus ancien saute
	immediatement.
]]
function HUD.notify(self: HUD, text: string, kind: string)
	-- Un meme message repete (une offensive relancee en boucle) remonte au lieu
	-- de s'empiler a l'identique.
	local last = self.feedEntries[#self.feedEntries]
	if last and last.Parent and last:GetAttribute("Body") == text then
		local repeats = (last:GetAttribute("Repeats") or 1) + 1
		last:SetAttribute("Repeats", repeats)
		last.Text = `{text}  x{repeats}`
		return
	end

	local entry = Instance.new("TextLabel")
	entry.Size = UDim2.new(1, 0, 0, FEED_ENTRY_HEIGHT)
	entry.BackgroundColor3 = UI.PANEL
	entry.BackgroundTransparency = 0.15
	entry.BorderSizePixel = 0
	entry.FontFace = BOLD
	entry.TextSize = 13
	entry.TextColor3 = FEED_COLORS[kind] or UI.TEXT
	entry.Text = text
	entry.TextTruncate = Enum.TextTruncate.AtEnd
	entry.LayoutOrder = self.feedCounter
	entry:SetAttribute("Body", text)
	entry.Parent = self.feed
	corner(entry, 6)

	self.feedCounter += 1
	table.insert(self.feedEntries, entry)

	while #self.feedEntries > MAX_FEED_ENTRIES do
		local oldest = table.remove(self.feedEntries, 1)
		if oldest then
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
		local tween = TweenService:Create(
			entry,
			TweenInfo.new(0.5),
			{ BackgroundTransparency = 1, TextTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		entry:Destroy()
	end)
end

--=============================================================================
-- Rafraichissement
--=============================================================================

function HUD.setDiplomacy(self: HUD, diplomacy: Types.Diplomacy)
	self.diplomacy = diplomacy
	self:refreshDiplomacyPanel()
end

function HUD.selectFaction(self: HUD, slot: number?)
	self.selectedSlot = if slot ~= self.mySlot then slot else nil
	self:refreshDiplomacyPanel()
end

function HUD.refreshDiplomacyPanel(self: HUD)
	local slot = self.selectedSlot
	if not slot or slot <= 0 then
		self.diploPanel.Visible = false
		return
	end

	local entry = self.roster[slot]
	if not entry then
		self.diploPanel.Visible = false
		return
	end

	self.diploPanel.Visible = true
	self.diploTitle.Text = entry.name
	self.diploTitle.TextColor3 = colorFor(slot)

	local d = self.diplomacy
	local allied = d.allies[slot] == true
	local incoming = d.incoming[slot] == true
	local outgoing = d.outgoing[slot] == true
	local embargoed = d.embargoes[slot] == true

	self.diploButtons.request.Visible = not allied and not incoming and not outgoing
	self.diploButtons.accept.Visible = incoming
	self.diploButtons["break"].Visible = allied
	self.diploButtons.embargo.Visible = not embargoed
	self.diploButtons.unembargo.Visible = embargoed
end

function HUD.setMatch(self: HUD, match: Types.MatchInfo)
	local minutes = math.floor(match.timeLeft / 60)
	local seconds = math.floor(match.timeLeft % 60)
	local suffix = if match.nukesUnlocked then "  \u{2622} arsenal actif" else ""
	self.timerLabel.Text = string.format("%d:%02d%s", minutes, seconds, suffix)
	self.timerLabel.TextColor3 = if match.nukesUnlocked then UI.GOLD else UI.TEXT_DIM
end

function HUD.update(self: HUD, stats: Types.Stats, roster: Types.Roster)
	self.roster = roster

	local mine = stats[self.mySlot]
	if mine then
		self.troopsLabel.Text = `{mine.troops}`
		self.tilesLabel.Text = `{mine.tiles} territoires`
		self.goldLabel.Text = `{mine.gold} or`

		if self.gold ~= mine.gold then
			self.gold = mine.gold
			if self.mode == "build" then
				self:refreshBuildPalette()
			end
		end
	end

	-- Classement trie par territoire : c'est la mesure qui compte pour la
	-- victoire, donc c'est elle qu'on affiche.
	local ranked: Ranking = {}
	for slot, s in stats do
		table.insert(ranked, { slot = slot, tiles = s.tiles, troops = s.troops })
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
			row.Text = ""
			row.Visible = false
			continue
		end

		row.Visible = true
		local info = roster[item.slot]
		local name = if info then info.name else `#{item.slot}`

		-- Marqueurs sociaux : l'allie et le traitre doivent se reperer d'un
		-- coup d'oeil, sans ouvrir de panneau.
		local marks = ""
		if self.diplomacy.allies[item.slot] then
			marks ..= " \u{1F91D}"
		end
		if self.diplomacy.traitors[item.slot] then
			marks ..= " \u{26A0}"
		end
		if info and info.betrayals > 0 then
			marks ..= ` ({info.betrayals})`
		end

		local prefix = if item.slot == self.mySlot then "\u{25B8} " else ""
		row.Text = `{prefix}{i}. {name}{marks}  {item.tiles}`
		row.TextColor3 = colorFor(item.slot)

	end

	-- Chaque ligne n'est reliee qu'une fois, mais la faction qu'elle designe
	-- change a chaque tri : le clic lit donc le classement courant stocke sur
	-- l'objet, jamais une copie capturee a la connexion.
	for i, row in self.leaderRows do
		if not row:GetAttribute("Bound") then
			row:SetAttribute("Bound", true)
			row.Activated:Connect(function()
				local item = self.ranked[i]
				if item then
					self:selectFaction(item.slot)
				end
			end)
		end
	end
end

return HUD
