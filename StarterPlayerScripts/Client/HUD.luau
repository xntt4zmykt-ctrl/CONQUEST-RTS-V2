--!strict
--[[
	Interface de commandement.

	Principe directeur : a tout instant le joueur doit pouvoir repondre a trois
	questions sans reflechir —
	  combien j'ai de troupes,
	  qui est en train de gagner,
	  qu'est-ce que mon prochain clic va faire.
	Tout le reste est secondaire et peut etre replie.

	Le HUD ne connait ni le reseau ni la carte. Il expose des callbacks que
	init.client branche sur les remotes, et un mode courant que le controleur de
	saisie interroge. Cette separation permet de retravailler entierement
	l'interface sans toucher a une ligne de simulation.
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
local SoundManager = require(script.Parent.SoundManager)

local C = Theme.color
local S = Theme.space
local F = Theme.font
local T = Theme.textSize

local HUD = {}
HUD.__index = HUD

-- Le fil de notifications ne doit jamais depasser cette hauteur : au-dela il
-- recouvre la carte, qui est l'element le plus important de l'ecran.
local MAX_FEED_ENTRIES = 5
local FEED_ENTRY_HEIGHT = 26
local LEADER_ROWS = 10

export type Mode = "attack" | "build" | "boat" | "nuke"

type Ranking = { { slot: number, tiles: number, troops: number } }

type LeaderRow = {
	button: TextButton,
	bar: Frame,
	name: TextLabel,
	value: TextLabel,
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
	local target = if selected then (accent or C.accent) else (b:GetAttribute("BaseColor") :: Color3)
	TweenService:Create(b, Theme.motion.quick, { BackgroundColor3 = target }):Play()
	b.TextColor3 = if selected then C.text else C.textMuted
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
	self.ratio = Config.DEFAULT_ATTACK_RATIO
	self.gold = 0
	self.troops = 0
	self.nukesUnlocked = false
	self.modeButtons = {}
	self.buildButtons = {}
	self.nukeButtons = {}
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

	self:buildIdentity()
	self:buildMatchBar()
	self:buildLeaderboard()
	self:buildDiplomacyPanel()
	self:buildCommandBar()
	self:buildPalettes()
	self:buildFeed()
	self:buildDoctrineModal()

	self:setRatio(self.ratio)
	self:setMode("attack")

	return self
end

--=============================================================================
-- Carte d'identite (haut gauche)
--=============================================================================

function HUD.buildIdentity(self: HUD)
	local card = Theme.panel("Identity", self.root)
	card.Position = UDim2.fromOffset(S.md, S.md)
	card.Size = UDim2.fromOffset(232, 62)

	-- Bandeau de couleur : le rappel permanent de "quelle couleur je suis" sur
	-- la carte. C'est l'information d'orientation la plus fondamentale.
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Size = UDim2.fromOffset(5, 40)
	stripe.Position = UDim2.fromOffset(S.md, 11)
	stripe.BorderSizePixel = 0
	stripe.BackgroundColor3 = C.textFaint
	stripe.Parent = card
	Theme.corner(stripe, Theme.radius.sm)
	self.identityStripe = stripe

	local name = Theme.label(card, "CONQUEST RTS", T.title, C.text)
	name.Position = UDim2.fromOffset(S.md + 14, 10)
	name.Size = UDim2.new(1, -(S.md * 2 + 14), 0, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	self.nameLabel = name

	local sub = Theme.label(card, "", T.small, C.textMuted)
	sub.Position = UDim2.fromOffset(S.md + 14, 31)
	sub.Size = UDim2.new(1, -(S.md * 2 + 14), 0, 18)
	sub.FontFace = F.medium
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	self.identitySub = sub
end

--=============================================================================
-- Bandeau de match (haut centre)
--=============================================================================

function HUD.buildMatchBar(self: HUD)
	local bar = Theme.panel("MatchBar", self.root)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, S.md)
	bar.Size = UDim2.fromOffset(196, 46)

	local timer = Theme.label(bar, "25:00", 22, C.text)
	timer.Position = UDim2.fromOffset(0, 6)
	timer.Size = UDim2.new(1, 0, 0, 24)
	timer.FontFace = F.display
	timer.TextXAlignment = Enum.TextXAlignment.Center
	self.timerLabel = timer

	local phase = Theme.label(bar, "", T.tiny, C.textMuted)
	phase.Position = UDim2.fromOffset(0, 28)
	phase.Size = UDim2.new(1, 0, 0, 14)
	phase.FontFace = F.medium
	phase.TextXAlignment = Enum.TextXAlignment.Center
	self.phaseLabel = phase
end

--=============================================================================
-- Classement (haut droite)
--=============================================================================

function HUD.buildLeaderboard(self: HUD)
	local board = Theme.panel("Leaderboard", self.root)
	board.AnchorPoint = Vector2.new(1, 0)
	board.Position = UDim2.new(1, -S.md, 0, S.md)
	board.Size = UDim2.fromOffset(244, 30 + LEADER_ROWS * 22)

	local title = Theme.label(board, "DOMINATION", T.tiny, C.textFaint)
	title.Position = UDim2.fromOffset(S.md, S.sm)
	title.Size = UDim2.new(1, -S.md * 2, 0, 14)

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(S.sm, 26)
	list.Size = UDim2.new(1, -S.sm * 2, 1, -32)
	list.Parent = board
	Theme.list(list, Enum.FillDirection.Vertical, 2)

	for i = 1, LEADER_ROWS do
		local row = Instance.new("TextButton")
		row.LayoutOrder = i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 20)
		row.Text = ""
		row.AutoButtonColor = false
		row.Parent = list

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
		name.Size = UDim2.new(1, -70, 1, 0)
		name.TextTruncate = Enum.TextTruncate.AtEnd

		local value = Theme.label(row, "", T.small, C.textFaint)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -S.sm, 0, 0)
		value.Size = UDim2.fromOffset(56, 20)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.FontFace = F.medium

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

		self.leaderRows[i] = { button = row, bar = bar, name = name, value = value } :: LeaderRow
	end
end

--=============================================================================
-- Panneau diplomatique (droite)
--=============================================================================

function HUD.buildDiplomacyPanel(self: HUD)
	local p = Theme.panel("Diplomacy", self.root)
	p.AnchorPoint = Vector2.new(1, 0)
	p.Position = UDim2.new(1, -S.md, 0, 30 + LEADER_ROWS * 22 + S.md * 2)
	p.Size = UDim2.fromOffset(244, 186)
	p.Visible = false
	self.diploPanel = p

	local title = Theme.label(p, "", T.title, C.text)
	title.Position = UDim2.fromOffset(S.md, S.sm)
	title.Size = UDim2.new(1, -S.md * 2, 0, 22)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	self.diploTitle = title

	local status = Theme.label(p, "", T.tiny, C.textMuted)
	status.Position = UDim2.fromOffset(S.md, 30)
	status.Size = UDim2.new(1, -S.md * 2, 0, 14)
	status.FontFace = F.medium
	self.diploStatus = status

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(S.sm, 50)
	list.Size = UDim2.new(1, -S.sm * 2, 1, -58)
	list.Parent = p
	Theme.list(list, Enum.FillDirection.Vertical, S.xs)

	local actions = {
		{ id = "request", text = "Proposer une alliance", color = C.ally, order = 1 },
		{ id = "accept", text = "Accepter l'alliance", color = C.ally, order = 2 },
		{ id = "break", text = "Rompre le pacte", color = C.danger, order = 3 },
		{ id = "embargo", text = "Declarer un embargo", color = C.warning, order = 4 },
		{ id = "unembargo", text = "Lever l'embargo", color = C.info, order = 5 },
	}

	for _, action in actions do
		local b = button(list, action.text, T.small)
		b.LayoutOrder = action.order
		b.Size = UDim2.new(1, 0, 0, 28)
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

--=============================================================================
-- Barre de commandement (bas centre)
--=============================================================================

function HUD.buildCommandBar(self: HUD)
	local bar = Theme.panel("CommandBar", self.root)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -S.md)
	bar.Size = UDim2.fromOffset(548, 164)

	-- Ligne 1 : le compteur de troupes est le plus gros chiffre de l'ecran,
	-- parce que c'est la seule valeur consultee en permanence.
	local troops = Theme.label(bar, "0", T.hero, C.text)
	troops.Position = UDim2.fromOffset(S.lg, 6)
	troops.Size = UDim2.fromOffset(240, 38)
	troops.FontFace = F.display
	self.troopsLabel = troops

	-- Jauge de remplissage : dit d'un coup d'oeil s'il faut attendre que la
	-- population monte ou si on plafonne et qu'il faut depenser.
	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(240, 4)
	track.Position = UDim2.fromOffset(S.lg, 44)
	track.BackgroundColor3 = C.surfaceRaised
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

	local gold = Theme.label(bar, "0", 20, C.gold)
	gold.AnchorPoint = Vector2.new(1, 0)
	gold.Position = UDim2.new(1, -S.lg, 0, 8)
	gold.Size = UDim2.fromOffset(180, 24)
	gold.TextXAlignment = Enum.TextXAlignment.Right
	gold.FontFace = F.display
	self.goldLabel = gold

	local tiles = Theme.label(bar, "0 territoires", T.small, C.textMuted)
	tiles.AnchorPoint = Vector2.new(1, 0)
	tiles.Position = UDim2.new(1, -S.lg, 0, 32)
	tiles.Size = UDim2.fromOffset(180, 18)
	tiles.TextXAlignment = Enum.TextXAlignment.Right
	tiles.FontFace = F.medium
	self.tilesLabel = tiles

	self:buildEngagementSlider(bar)
	self:buildModeRow(bar)

	local hint = Theme.label(bar, "", T.tiny, C.textFaint)
	hint.Position = UDim2.fromOffset(S.lg, 138)
	hint.Size = UDim2.new(1, -S.lg * 2, 0, 16)
	hint.FontFace = F.medium
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	self.hintLabel = hint
end

--[[
	Curseur d'engagement.

	C'est la decision tactique centrale du jeu, donc elle merite un vrai
	curseur continu plutot que quatre boutons : le joueur doit pouvoir doser
	precisement ce qu'il risque, et voir en chiffres absolus combien de troupes
	partent.
]]
function HUD.buildEngagementSlider(self: HUD, parent: GuiObject)
	local label = Theme.label(parent, "ENGAGEMENT", T.tiny, C.textFaint)
	label.Position = UDim2.fromOffset(S.lg, 56)
	label.Size = UDim2.fromOffset(120, 14)

	local readout = Theme.label(parent, "", T.tiny, C.textMuted)
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.new(1, -S.lg, 0, 56)
	readout.Size = UDim2.fromOffset(220, 14)
	readout.TextXAlignment = Enum.TextXAlignment.Right
	readout.FontFace = F.medium
	self.ratioReadout = readout

	local track = Instance.new("TextButton")
	track.Name = "EngagementTrack"
	track.Text = ""
	track.AutoButtonColor = false
	track.Position = UDim2.fromOffset(S.lg, 74)
	track.Size = UDim2.new(1, -S.lg * 2, 0, 14)
	track.BackgroundColor3 = C.surfaceRaised
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

	local function ratioFromInput(inputX: number)
		local origin = track.AbsolutePosition.X
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local ratio = math.clamp((inputX - origin) / width, 0.05, 1)
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
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(S.lg, 98)
	row.Size = UDim2.new(1, -S.lg * 2, 0, 34)
	row.Parent = parent
	Theme.list(row, Enum.FillDirection.Horizontal, S.sm)

	local modes: { { id: Mode, text: string, key: string } } = {
		{ id = "attack", text = "Attaquer", key = "1" },
		{ id = "boat", text = "Debarquer", key = "2" },
		{ id = "build", text = "Construire", key = "3" },
		{ id = "nuke", text = "Nucleaire", key = "4" },
	}

	for i, entry in modes do
		local b = button(row, entry.text, T.small)
		b.LayoutOrder = i
		b.Size = UDim2.new(0.25, -6, 1, 0)

		-- Rappel du raccourci clavier dans le coin : c'est ainsi qu'on fait
		-- passer un joueur de la souris au clavier sans tutoriel.
		local key = Theme.label(b, entry.key, T.tiny, C.textFaint)
		key.AnchorPoint = Vector2.new(1, 1)
		key.Position = UDim2.new(1, -5, 1, -2)
		key.Size = UDim2.fromOffset(10, 12)
		key.TextXAlignment = Enum.TextXAlignment.Right

		b.Activated:Connect(function()
			self:setMode(entry.id)
		end)
		self.modeButtons[entry.id] = b
	end
end

--=============================================================================
-- Palettes contextuelles (bas gauche)
--=============================================================================

local function paletteEntry(parent: GuiObject, order: number, symbol: string, name: string, cost: number): TextButton
	local b = button(parent, "", T.small)
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 38)

	local glyph = Theme.label(b, symbol, 18, C.text)
	glyph.Position = UDim2.fromOffset(S.sm, 0)
	glyph.Size = UDim2.fromOffset(22, 38)
	glyph.TextXAlignment = Enum.TextXAlignment.Center

	local title = Theme.label(b, name, T.small, C.textMuted)
	title.Position = UDim2.fromOffset(S.sm + 26, 4)
	title.Size = UDim2.new(1, -S.sm - 26, 0, 16)

	local price = Theme.label(b, `{cost} or`, T.tiny, C.gold)
	price.Position = UDim2.fromOffset(S.sm + 26, 19)
	price.Size = UDim2.new(1, -S.sm - 26, 0, 14)
	price.FontFace = F.medium

	return b
end

function HUD.buildPalettes(self: HUD)
	--- Construction ---------------------------------------------------------
	local build = Theme.panel("BuildPalette", self.root)
	build.AnchorPoint = Vector2.new(0, 1)
	build.Position = UDim2.new(0, S.md, 1, -S.md)
	build.Size = UDim2.fromOffset(208, 34 + #BuildingDefs.BUILDABLE * 42)
	build.Visible = false
	self.buildPalette = build

	local buildTitle = Theme.label(build, "CONSTRUIRE", T.tiny, C.textFaint)
	buildTitle.Position = UDim2.fromOffset(S.md, S.sm)
	buildTitle.Size = UDim2.new(1, -S.md * 2, 0, 14)

	local buildList = Instance.new("Frame")
	buildList.BackgroundTransparency = 1
	buildList.Position = UDim2.fromOffset(S.sm, 28)
	buildList.Size = UDim2.new(1, -S.sm * 2, 1, -36)
	buildList.Parent = build
	Theme.list(buildList, Enum.FillDirection.Vertical, S.xs)

	for i, def in BuildingDefs.BUILDABLE do
		local b = paletteEntry(buildList, i, def.symbol, def.name, def.cost)
		b.Activated:Connect(function()
			self.buildKind = def.id
			self:setMode("build")
		end)
		self.buildButtons[def.id] = b
	end

	--- Arsenal --------------------------------------------------------------
	local nuke = Theme.panel("NukePalette", self.root)
	nuke.AnchorPoint = Vector2.new(0, 1)
	nuke.Position = UDim2.new(0, S.md, 1, -S.md)
	nuke.Size = UDim2.fromOffset(208, 34 + 2 * 42)
	nuke.Visible = false
	self.nukePalette = nuke

	local nukeTitle = Theme.label(nuke, "ARSENAL", T.tiny, C.textFaint)
	nukeTitle.Position = UDim2.fromOffset(S.md, S.sm)
	nukeTitle.Size = UDim2.new(1, -S.md * 2, 0, 14)

	local nukeList = Instance.new("Frame")
	nukeList.BackgroundTransparency = 1
	nukeList.Position = UDim2.fromOffset(S.sm, 28)
	nukeList.Size = UDim2.new(1, -S.sm * 2, 1, -36)
	nukeList.Parent = nuke
	Theme.list(nukeList, Enum.FillDirection.Vertical, S.xs)

	for kind = 1, 2 do
		local stats = Config.NUKE_STATS[kind]
		local b = paletteEntry(nukeList, kind, "\u{2622}", stats.name, stats.cost)
		b.Activated:Connect(function()
			self.nukeKind = kind
			self:setMode("nuke")
		end)
		self.nukeButtons[kind] = b
	end
end

--=============================================================================
-- Fil de notifications
--=============================================================================

function HUD.buildFeed(self: HUD)
	local feed = Instance.new("Frame")
	feed.Name = "Feed"
	feed.AnchorPoint = Vector2.new(0.5, 0)
	feed.Position = UDim2.new(0.5, 0, 0, 66)
	-- Hauteur bornee au nombre maximal de messages, et decoupage actif : le
	-- fil ne doit jamais pouvoir grandir jusqu'a manger la carte.
	feed.Size = UDim2.fromOffset(440, MAX_FEED_ENTRIES * (FEED_ENTRY_HEIGHT + S.xs))
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
	une phase agitee, les messages arrivent bien plus vite qu'ils n'expirent, et
	un simple minuteur laissait le fil recouvrir tout l'ecran.
]]
function HUD.notify(self: HUD, text: string, kind: string)
	-- Un meme message repete remonte en compteur au lieu de s'empiler.
	local last = self.feedEntries[#self.feedEntries]
	if last and last.Parent and last:GetAttribute("Body") == text then
		local repeats = (last:GetAttribute("Repeats") or 1) + 1
		last:SetAttribute("Repeats", repeats)
		last.Text = `{text}   x{repeats}`
		return
	end

	local entry = Instance.new("TextLabel")
	entry.Size = UDim2.new(1, 0, 0, FEED_ENTRY_HEIGHT)
	entry.BackgroundColor3 = C.surface
	entry.BackgroundTransparency = 0.1
	entry.BorderSizePixel = 0
	entry.FontFace = F.bold
	entry.TextSize = T.small
	entry.TextColor3 = FEED_COLORS[kind] or C.text
	entry.Text = text
	entry.TextTruncate = Enum.TextTruncate.AtEnd
	entry.LayoutOrder = self.feedCounter
	entry:SetAttribute("Body", text)
	entry.Parent = self.feed
	Theme.corner(entry, Theme.radius.sm)
	Theme.stroke(entry, FEED_COLORS[kind] or C.line, 1)

	local sound = FEED_SOUNDS[kind]
	if sound then
		SoundManager.play(sound)
	end

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
			Theme.motion.smooth,
			{ BackgroundTransparency = 1, TextTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		entry:Destroy()
	end)
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
	box.Size = UDim2.fromOffset(620, 330)
	box.ZIndex = 21

	local title = Theme.label(box, "CHOISIS TA DOCTRINE", 24, C.text)
	title.Position = UDim2.fromOffset(S.xl, S.lg)
	title.Size = UDim2.new(1, -S.xl * 2, 0, 30)
	title.FontFace = F.display
	title.ZIndex = 22

	local subtitle = Theme.label(box, "Un engagement definitif pour toute la partie.", T.body, C.textMuted)
	subtitle.Position = UDim2.fromOffset(S.xl, S.lg + 30)
	subtitle.Size = UDim2.new(1, -S.xl * 2, 0, 18)
	subtitle.FontFace = F.medium
	subtitle.ZIndex = 22

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(S.xl, 92)
	row.Size = UDim2.new(1, -S.xl * 2, 0, 210)
	row.ZIndex = 22
	row.Parent = box
	Theme.list(row, Enum.FillDirection.Horizontal, S.md)

	for i, doctrine in Doctrines.LIST do
		local card = button(row, "", T.small)
		card.LayoutOrder = i
		card.Size = UDim2.new(0.25, -9, 1, 0)
		card.ZIndex = 22

		local symbol = Theme.label(card, doctrine.symbol, 34, C.text)
		symbol.Position = UDim2.fromOffset(0, S.lg)
		symbol.Size = UDim2.new(1, 0, 0, 40)
		symbol.TextXAlignment = Enum.TextXAlignment.Center
		symbol.ZIndex = 23

		local name = Theme.label(card, doctrine.name, T.title, C.text)
		name.Position = UDim2.fromOffset(0, 64)
		name.Size = UDim2.new(1, 0, 0, 22)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.ZIndex = 23

		local tagline = Theme.label(card, doctrine.tagline, T.tiny, C.textMuted)
		tagline.Position = UDim2.fromOffset(S.sm, 92)
		tagline.Size = UDim2.new(1, -S.sm * 2, 0, 100)
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
		end)
	end
end

function HUD.showDoctrineModal(self: HUD)
	self.doctrineModal.Visible = true
end

--=============================================================================
-- Etat
--=============================================================================

function HUD.setRatio(self: HUD, ratio: number)
	self.ratio = ratio
	self.ratioFill.Size = UDim2.fromScale(ratio, 1)
	self:refreshRatioReadout()
end

function HUD.refreshRatioReadout(self: HUD)
	local committed = math.floor(self.troops * self.ratio)
	self.ratioReadout.Text = `{math.floor(self.ratio * 100)} %  \u{2192}  {committed} troupes engagees`
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
		setSelected(b, id == mode)
	end

	self.buildPalette.Visible = mode == "build"
	self.nukePalette.Visible = mode == "nuke"
	self.hintLabel.Text = HINTS[mode] or ""

	if mode == "build" then
		self:refreshPalettes()
	elseif mode == "nuke" then
		self:refreshPalettes()
		if not self.nukesUnlocked then
			self.hintLabel.Text = "Arsenal verrouille tant que la carte n'est pas majoritairement colonisee."
		end
	end

	if self.onModeChanged then
		self.onModeChanged(mode)
	end
end

-- Ce qu'on ne peut pas payer est grise : le joueur lit son budget sans avoir a
-- comparer des chiffres.
function HUD.refreshPalettes(self: HUD)
	for id, b in self.buildButtons do
		local def = BuildingDefs.get(id)
		local affordable = def ~= nil and self.gold >= def.cost
		setSelected(b, id == self.buildKind)
		if id ~= self.buildKind then
			b.BackgroundTransparency = if affordable then 0 else 0.55
		else
			b.BackgroundTransparency = 0
		end
	end

	for kind, b in self.nukeButtons do
		local stats = Config.NUKE_STATS[kind]
		local affordable = self.gold >= stats.cost and self.nukesUnlocked
		setSelected(b, kind == self.nukeKind, C.nuclear)
		if kind ~= self.nukeKind then
			b.BackgroundTransparency = if affordable then 0 else 0.55
		else
			b.BackgroundTransparency = 0
		end
	end
end

function HUD.setIdentity(self: HUD, slot: number, name: string, doctrineId: number, betrayals: number)
	self.mySlot = slot
	local color = Theme.factionColor(slot)
	self.nameLabel.Text = name
	self.nameLabel.TextColor3 = color
	self.identityStripe.BackgroundColor3 = color

	local doctrine = Doctrines.get(doctrineId)
	local reputation = if betrayals > 0 then `  \u{26A0} {betrayals} trahison(s)` else ""
	self.identitySub.Text = `{doctrine.symbol} {doctrine.name}{reputation}`
	self.identitySub.TextColor3 = if betrayals > 0 then C.warning else C.textMuted
end

function HUD.setMatch(self: HUD, match: Types.MatchInfo)
	local minutes = math.floor(match.timeLeft / 60)
	local seconds = math.floor(match.timeLeft % 60)
	self.timerLabel.Text = string.format("%d:%02d", minutes, seconds)

	-- Le passage du seuil nucleaire est l'evenement de rythme le plus
	-- important de la partie : il change la couleur du bandeau.
	local wasUnlocked = self.nukesUnlocked
	self.nukesUnlocked = match.nukesUnlocked

	if match.nukesUnlocked then
		self.phaseLabel.Text = "\u{2622} ARSENAL ACTIF"
		self.phaseLabel.TextColor3 = C.nuclear
		self.timerLabel.TextColor3 = C.nuclear
	else
		self.phaseLabel.Text = "EXPANSION"
		self.phaseLabel.TextColor3 = C.textMuted
		self.timerLabel.TextColor3 = C.text
	end

	if match.nukesUnlocked and not wasUnlocked then
		self:notify("\u{2622} Technologie nucleaire disponible.", "alert")
		self:refreshPalettes()
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
	end

	self:refreshDiplomacyPanel()
end

function HUD.selectFaction(self: HUD, slot: number?)
	self.selectedSlot = if slot ~= self.mySlot then slot else nil
	self:refreshDiplomacyPanel()
end

function HUD.refreshDiplomacyPanel(self: HUD)
	local slot = self.selectedSlot
	if not slot or slot <= 0 or not self.roster[slot] then
		self.diploPanel.Visible = false
		return
	end

	local entry = self.roster[slot]
	self.diploPanel.Visible = true
	self.diploTitle.Text = entry.name
	self.diploTitle.TextColor3 = Theme.factionColor(slot)

	local d = self.diplomacy
	local allied = d.allies[slot] == true
	local incoming = d.incoming[slot] == true
	local outgoing = d.outgoing[slot] == true
	local embargoed = d.embargoes[slot] == true

	local status = if allied then "Allie" elseif incoming then "Te propose une alliance" elseif outgoing then "Proposition envoyee" else "Neutre"
	if entry.betrayals > 0 then
		status ..= `  \u{26A0} {entry.betrayals} trahison(s)`
	end
	if embargoed then
		status ..= "  \u{2716} sous embargo"
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
		self.troops = mine.troops
		self.troopsLabel.Text = tostring(mine.troops)
		self.tilesLabel.Text = `{mine.tiles} territoires`
		self.goldLabel.Text = tostring(mine.gold)

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
			row.button.Visible = false
			continue
		end

		row.button.Visible = true
		local info = roster[item.slot]
		local color = Theme.factionColor(item.slot)

		-- Marqueurs sociaux : l'allie et le traitre doivent se reperer d'un
		-- coup d'oeil, sans ouvrir de panneau.
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
end

return HUD
