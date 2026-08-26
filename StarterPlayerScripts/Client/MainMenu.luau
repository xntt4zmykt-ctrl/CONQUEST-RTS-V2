--!strict
--[[
	Menu principal, cale sur l'ecran d'accueil du direction visuelle CONQUEST.

	Disposition 1:1, adaptee a notre contexte (un serveur, des bots, pas de
	salons inter-serveurs) :

	  barre du haut   logo + onglets a gauche, joueur a droite
	  colonne gauche  nouveautes, carte joueur, choix de la nation
	  centre          la carte vedette : le mode selectionne et sa carte
	                  procedurale reelle, compte a rebours en pastille
	  colonne droite  le salon en cours, puis les deux autres modes
	  bas             le gros bouton JOUER SOLO, puis les trois boutons salon

	Leurs cartes de maps deviennent nos cartes de modes : chacune montre un
	apercu reel du terrain genere (graine fixe par mode), son rythme et son
	remplissage. La ou d'autres titres du genre promet une partie qui commence, nous montrons
	exactement ce que le joueur va affronter.

	Le drapeau est dessine a la volee a partir d'un motif et de deux ou trois
	couleurs (voir Nations). Aucun asset, net a toutes les tailles, et
	l'ajout d'une nation ne demande qu'une ligne de donnees.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Nations = require(Shared:WaitForChild("Nations"))
local GameModes = require(Shared:WaitForChild("GameModes"))
local MapGen = require(Shared:WaitForChild("MapGen"))
local SoundManager = require(script.Parent.SoundManager)

local C = Theme.color
local S = Theme.space
local F = Theme.font
local T = Theme.textSize

local MainMenu = {}
MainMenu.__index = MainMenu

-- Chaque mode a sa graine d'apercu : la carte du menu est une vraie carte du
-- jeu, pas une image stockee — trois modes reconnaissables au premier coup
-- d'oeil, comme leurs maps Montréal / Russie / Labyrinthe.
local MODE_SEEDS: { [string]: number } = {
	classic = 2026,
	blitz = 77,
	marathon = 555,
}

local MODE_ACCENTS: { [string]: Color3 } = {
	classic = C.accent,
	blitz = C.warning,
	marathon = C.info,
}

-- Geometrie du pavage central, en pixels logiques.
local GRID_TOP = 64
local COL_LEFT_W = 236
local COL_CENTER_W = 368
local COL_RIGHT_W = 252
local COL_GAP = 12
local GRID_W = COL_LEFT_W + COL_CENTER_W + COL_RIGHT_W + COL_GAP * 2 -- 880
local CENTER_X = COL_LEFT_W + COL_GAP -- 248
local RIGHT_X = CENTER_X + COL_CENTER_W + COL_GAP -- 628

local function formatCountdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return `{s // 60} min {string.format("%02d", s % 60)}`
end

export type MainMenu = typeof(setmetatable({} :: any, MainMenu))

--=============================================================================
-- Drapeaux
--=============================================================================

--[[
	Dessine un drapeau dans `parent`. Les motifs couvrent l'essentiel du
	vocabulaire vexillologique reel avec quatre Frames au maximum.
]]
function MainMenu.drawFlag(parent: GuiObject, flag: Nations.Flag)
	for _, child in parent:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local function band(position: UDim2, size: UDim2, color: Color3, rotation: number?)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Position = position
		f.Size = size
		f.Rotation = rotation or 0
		f.Parent = parent
		return f
	end

	local colors = flag.colors
	local pattern = flag.pattern

	if pattern == "vertical" then
		local n = #colors
		for i, color in colors do
			band(UDim2.fromScale((i - 1) / n, 0), UDim2.fromScale(1 / n, 1), color)
		end
	elseif pattern == "horizontal" then
		local n = #colors
		for i, color in colors do
			band(UDim2.fromScale(0, (i - 1) / n), UDim2.fromScale(1, 1 / n), color)
		end
	elseif pattern == "cross" then
		band(UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), colors[1])
		band(UDim2.fromScale(0.32, 0), UDim2.fromScale(0.18, 1), colors[2])
		band(UDim2.fromScale(0, 0.4), UDim2.fromScale(1, 0.2), colors[2])
	elseif pattern == "diagonal" then
		band(UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), colors[1])
		-- Une bande large tournee a 45 degres, debordant volontairement du
		-- cadre : le parent est en ClipsDescendants, elle est donc coupee net.
		band(UDim2.fromScale(-0.3, 0.3), UDim2.fromScale(1.6, 0.34), colors[2], -30)
	else -- quarters
		band(UDim2.fromScale(0, 0), UDim2.fromScale(0.5, 0.5), colors[1])
		band(UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.5), colors[1])
		band(UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 0.5), colors[2])
		band(UDim2.fromScale(0, 0.5), UDim2.fromScale(0.5, 0.5), colors[2])
	end
end

--=============================================================================
-- Apercu de terrain
--=============================================================================

--[[
	Remplit `frame` d'une miniature de la vraie generation procedurale : c'est
	ce qui rend le choix concret sans charger aucun asset externe. Les tuiles
	ocean ne sont pas dessinees — le fond du cadre porte deja leur couleur.
]]
local function drawTerrainPreview(frame: GuiObject, seed: number, cellsX: number, cellsY: number)
	for _, child in frame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local terrain = MapGen.generate(seed)
	local width = frame.AbsoluteSize.X > 0 and frame.AbsoluteSize.X or 360
	local height = frame.AbsoluteSize.Y > 0 and frame.AbsoluteSize.Y or 220
	local cellWidth = width / cellsX
	local cellHeight = height / cellsY

	for y = 0, cellsY - 1 do
		for x = 0, cellsX - 1 do
			local sourceX = math.clamp(math.floor((x + 0.5) * Config.MAP_WIDTH / cellsX), 0, Config.MAP_WIDTH - 1)
			local sourceY = math.clamp(math.floor((y + 0.5) * Config.MAP_HEIGHT / cellsY), 0, Config.MAP_HEIGHT - 1)
			local terrainKind = buffer.readu8(terrain, MapGen.toIndex(sourceX, sourceY))
			if terrainKind ~= Config.TERRAIN.OCEAN then
				local tile = Instance.new("Frame")
				tile.BorderSizePixel = 0
				tile.BackgroundColor3 = Config.TERRAIN_COLORS[terrainKind] or Config.TERRAIN_COLORS[2]
				tile.BackgroundTransparency = 0.05
				tile.Position = UDim2.fromOffset(math.floor(x * cellWidth), math.floor(y * cellHeight))
				tile.Size = UDim2.fromOffset(math.ceil(cellWidth + 1), math.ceil(cellHeight + 1))
				tile.ZIndex = frame.ZIndex + 1
				tile.Parent = frame
			end
		end
	end
end

--=============================================================================
-- Construction
--=============================================================================

function MainMenu.new(parent: ScreenGui): MainMenu
	local self = setmetatable({}, MainMenu) :: any

	self.nationId = 1
	self.modeId = GameModes.DEFAULT
	self.playerName = "COMMANDANT"
	self.nationButtons = {}
	self.modeButtons = {}
	self.transitionId = 0
	self.newsDismissed = false

	-- CanvasGroup et non Frame : le fondu se fait par GroupTransparency, une
	-- seule propriete sur le conteneur. La version precedente tweenait la
	-- transparence de chaque enfant, ce qui les laissait definitivement
	-- invisibles — rouvrir le menu affichait alors un rectangle noir vide.
	local root = Instance.new("CanvasGroup")
	root.Name = "MainMenu"
	root.Size = UDim2.fromScale(1, 1)
	-- Le canvas de fond doit toujours couvrir toute la viewport. Le safe-area
	-- vertical est applique au contenu plus bas, jamais au conteneur entier :
	-- sinon des bandes du monde 3D apparaissent en haut et sur les cotes.
	root.Position = UDim2.fromOffset(0, 0)
	root.BackgroundColor3 = C.void
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = 50
	root.Parent = parent
	root.GroupTransparency = 0
	self.root = root

	-- Le fond reste dans le CanvasGroup non redimensionne. Seul le contenu
	-- positionne en dessous est adapte a la resolution ; c'etait l'erreur de
	-- la version precedente, qui redimensionnait aussi le fond et laissait des
	-- bandes grises autour du jeu.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.Position = UDim2.fromOffset(0, 26)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ZIndex = 51
	content.Parent = root
	self.content = content

	-- Le contenu tient volontairement en 640 px de haut, et tout est mesure en
	-- pixels logiques : sur mobile/retina on reduit l'ensemble, on ne coupe
	-- jamais le bouton.
	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Parent = content
	self.responsiveScale = scale

	local function refreshScale()
		local camera = if workspace then workspace.CurrentCamera else nil
		if not camera then
			scale.Scale = 0.86
			return
		end
		local viewport = camera.ViewportSize
		local widthScale = viewport.X / 1000
		local heightScale = viewport.Y / 640
		scale.Scale = math.clamp(math.min(widthScale, heightScale), 0.82, 1)
	end
	refreshScale()
	if workspace and workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end
	if workspace then
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshScale)
	end

	-- Le fond doit etre un enfant du CanvasGroup. Le BackgroundColor3 du
	-- CanvasGroup lui-meme n'est pas toujours affecte par GroupTransparency et
	-- pouvait donc rester comme un voile noir apres le deploiement.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = C.void
	backdrop.BackgroundTransparency = 0.02
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 50
	backdrop.Parent = root

	-- Voile degrade : donne de la profondeur sans image de fond. Il ne doit
	-- teinter que le fond — sur le CanvasGroup racine, Roblox l'appliquerait
	-- aussi au rendu des enfants.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(14, 19, 30), Color3.fromRGB(5, 7, 12))
	gradient.Parent = backdrop

	-- La trame hexagonale CONQUEST, traduite en diagonales legeres :
	-- une profondeur de carte sans fausse image de fond.
	local tacticalGrid = Instance.new("Frame")
	tacticalGrid.Name = "TacticalGrid"
	tacticalGrid.Size = UDim2.fromScale(1, 1)
	tacticalGrid.BackgroundTransparency = 1
	tacticalGrid.ZIndex = 50
	tacticalGrid.Parent = root
	for i = -8, 8 do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(0, 1, 1.5, 0)
		line.Position = UDim2.new(0.5, i * 92, -0.2, 0)
		line.Rotation = 25
		line.BackgroundColor3 = C.info
		line.BackgroundTransparency = 0.96
		line.BorderSizePixel = 0
		line.Parent = tacticalGrid
	end
	for i = -5, 5 do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1.4, 0, 0, 1)
		line.Position = UDim2.new(-0.2, 0, 0.5, i * 80)
		line.Rotation = -12
		line.BackgroundColor3 = C.accent
		line.BackgroundTransparency = 0.97
		line.BorderSizePixel = 0
		line.Parent = tacticalGrid
	end

	-- Le pavage central est un bloc unique centre : a l'interieur, toutes les
	-- positions sont relatives a ce bloc, comme sur la maquette de reference.
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Position = UDim2.new(0.5, 0, 0, 0)
	stage.Size = UDim2.fromOffset(GRID_W, 620)
	stage.BackgroundTransparency = 1
	stage.ZIndex = 51
	stage.Parent = content
	self.stage = stage

	self:buildTopBar()
	self:buildLeftColumn()
	self:buildFeaturedCard()
	self:buildRightColumn()
	self:buildDeployRow()
	self:buildFooter()

	self:selectNation(1)
	self:selectMode(GameModes.DEFAULT)

	return self
end

--=============================================================================
-- Barre du haut : logo, onglets, joueur
--=============================================================================

function MainMenu.buildTopBar(self: MainMenu)
	local bar = Theme.panel("TopBar", self.stage)
	bar.Position = UDim2.fromOffset(0, 0)
	bar.Size = UDim2.new(1, 0, 0, 44)
	bar.BackgroundTransparency = 0.08
	bar.ZIndex = 51

	local logo = Theme.label(bar, ">CONQUEST<", 18, C.text)
	logo.Position = UDim2.fromOffset(S.md, 6)
	logo.Size = UDim2.fromOffset(170, 18)
	logo.FontFace = F.display
	logo.ZIndex = 52

	local version = Theme.label(bar, "v0.9 — BETA", T.tiny, C.accent)
	version.Position = UDim2.fromOffset(S.md + 2, 25)
	version.Size = UDim2.fromOffset(140, 12)
	version.FontFace = F.medium
	version.ZIndex = 52

	-- Les onglets non implementes ne mentent pas : ils annoncent leur arrivee
	-- plutot que de faire semblant d'ouvrir quelque chose.
	local toast = Theme.label(bar, "BIENTOT DISPONIBLE", T.tiny, C.warning)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.62, 0, 0, 46)
	toast.Size = UDim2.fromOffset(180, 13)
	toast.TextXAlignment = Enum.TextXAlignment.Center
	toast.FontFace = F.bold
	toast.ZIndex = 52
	toast.Visible = false
	self.navToast = toast
	self.navToastId = 0

	local tabs = { "JOUER", "ACTUS", "PARAMETRES", "CLASSEMENT", "AIDE" }
	for i, tab in tabs do
		local active = i == 1
		local b = Instance.new("TextButton")
		b.Text = tab
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.FontFace = F.bold
		b.TextSize = T.small
		b.TextColor3 = if active then C.accent else C.textMuted
		b.Position = UDim2.fromOffset(190 + (i - 1) * 104, 0)
		b.Size = UDim2.fromOffset(96, 44)
		b.ZIndex = 52
		b.Parent = bar
		b.Activated:Connect(function()
			SoundManager.play("uiSelect")
			if tab == "ACTUS" then
				self.newsDismissed = not self.newsDismissed
				if self.newsCard then
					self.newsCard.Visible = not self.newsDismissed
				end
				return
			end
			if not active then
				self.navToastId += 1
				local id = self.navToastId
				toast.Visible = true
				task.delay(1.4, function()
					if self.navToastId == id then
						toast.Visible = false
					end
				end)
			end
		end)
	end

	-- Pastille joueur, a droite : le drapeau choisi et le nom Roblox.
	local chip = Instance.new("Frame")
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.new(1, -S.md, 0.5, 0)
	chip.Size = UDim2.fromOffset(170, 30)
	chip.BackgroundColor3 = C.surfaceRaised
	chip.BorderSizePixel = 0
	chip.ZIndex = 52
	chip.Parent = bar
	Theme.corner(chip, Theme.radius.pill)

	local flag = Instance.new("Frame")
	flag.AnchorPoint = Vector2.new(0, 0.5)
	flag.Position = UDim2.new(0, 5, 0.5, 0)
	flag.Size = UDim2.fromOffset(30, 20)
	flag.BackgroundColor3 = C.void
	flag.BorderSizePixel = 0
	flag.ClipsDescendants = true
	flag.ZIndex = 53
	flag.Parent = chip
	Theme.corner(flag, Theme.radius.sm)
	self.playerFlag = flag

	local name = Theme.label(chip, self.playerName, T.small, C.text)
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, 41, 0.5, 0)
	name.Size = UDim2.fromOffset(122, 16)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.FontFace = F.bold
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 53
	self.playerNameLabel = name
end

--=============================================================================
-- Colonne gauche : nouveautes, joueur, nations
--=============================================================================

function MainMenu.buildLeftColumn(self: MainMenu)
	local left = Instance.new("Frame")
	left.Name = "LeftColumn"
	left.Position = UDim2.fromOffset(0, GRID_TOP)
	left.Size = UDim2.fromOffset(COL_LEFT_W, 380)
	left.BackgroundTransparency = 1
	left.ZIndex = 51
	left.Parent = self.stage

	-- Nouveautes : la carte qui dit que le jeu est vivant.
	local chip = Theme.label(left, "NOUVEAUTES", T.tiny, C.ally)
	chip.Position = UDim2.fromOffset(0, 0)
	chip.Size = UDim2.fromOffset(110, 13)
	chip.FontFace = F.bold
	chip.ZIndex = 52

	local news = Theme.panel("News", left)
	news.Position = UDim2.fromOffset(0, 18)
	news.Size = UDim2.fromOffset(COL_LEFT_W, 66)
	news.ZIndex = 52
	self.newsCard = news

	local newsTitle = Theme.label(news, "La diplomatie s'arme", T.small, C.text)
	newsTitle.Position = UDim2.fromOffset(S.sm, S.sm)
	newsTitle.Size = UDim2.fromOffset(COL_LEFT_W - S.sm * 2 - 18, 14)
	newsTitle.FontFace = F.bold
	newsTitle.ZIndex = 53

	local newsBody = Theme.label(news, "MIRV, retraites, dons entre allies et messages rapides.", T.tiny, C.textMuted)
	newsBody.Position = UDim2.fromOffset(S.sm, 26)
	newsBody.Size = UDim2.fromOffset(COL_LEFT_W - S.sm * 2 - 18, 32)
	newsBody.FontFace = F.medium
	newsBody.TextWrapped = true
	newsBody.TextXAlignment = Enum.TextXAlignment.Left
	newsBody.TextYAlignment = Enum.TextYAlignment.Top
	newsBody.ZIndex = 53

	local dismiss = Instance.new("TextButton")
	dismiss.Text = "\u{2715}"
	dismiss.AutoButtonColor = false
	dismiss.BackgroundTransparency = 1
	dismiss.FontFace = F.bold
	dismiss.TextSize = T.tiny
	dismiss.TextColor3 = C.textFaint
	dismiss.AnchorPoint = Vector2.new(1, 0)
	dismiss.Position = UDim2.new(1, -S.xs, 0, S.xs)
	dismiss.Size = UDim2.fromOffset(16, 16)
	dismiss.ZIndex = 54
	dismiss.Parent = news
	dismiss.Activated:Connect(function()
		SoundManager.play("uiClick")
		self.newsDismissed = true
		news.Visible = false
	end)

	-- Carte joueur : le drapeau choisi, le nom, la nation. C'est l'identite
	-- que le joueur portera en partie — elle doit etre visible avant de
	-- deployer, pas decouverte apres.
	local identity = Theme.panel("Identity", left)
	identity.Position = UDim2.fromOffset(0, 92)
	identity.Size = UDim2.fromOffset(COL_LEFT_W, 58)
	identity.ZIndex = 52

	local flag = Instance.new("Frame")
	flag.Position = UDim2.fromOffset(S.sm, 13)
	flag.Size = UDim2.fromOffset(46, 32)
	flag.BackgroundColor3 = C.void
	flag.BorderSizePixel = 0
	flag.ClipsDescendants = true
	flag.ZIndex = 53
	flag.Parent = identity
	Theme.corner(flag, Theme.radius.sm)
	MainMenu.drawFlag(flag, Nations.get(self.nationId).flag)
	self.identityFlag = flag

	local playerName = Theme.label(identity, self.playerName, T.body, C.text)
	playerName.Position = UDim2.fromOffset(S.sm + 56, 12)
	playerName.Size = UDim2.fromOffset(COL_LEFT_W - 70, 16)
	playerName.FontFace = F.bold
	playerName.TextTruncate = Enum.TextTruncate.AtEnd
	playerName.ZIndex = 53
	self.identityName = playerName

	local nationName = Theme.label(identity, "Valoria", T.tiny, C.accent)
	nationName.Position = UDim2.fromOffset(S.sm + 56, 32)
	nationName.Size = UDim2.fromOffset(COL_LEFT_W - 70, 13)
	nationName.FontFace = F.medium
	nationName.ZIndex = 53
	self.identityNation = nationName

	-- Choix de la nation : une grille de drapeaux compacts, le nom vit sur la
	-- carte d'identite au-dessus.
	local label = Theme.label(left, "CHOISIS TA NATION", T.tiny, C.textFaint)
	label.Position = UDim2.fromOffset(0, 162)
	label.Size = UDim2.fromOffset(COL_LEFT_W, 13)
	label.FontFace = F.bold
	label.ZIndex = 52

	local grid = Instance.new("Frame")
	grid.Position = UDim2.fromOffset(0, 180)
	grid.Size = UDim2.fromOffset(COL_LEFT_W, 200)
	grid.BackgroundTransparency = 1
	grid.ZIndex = 52
	grid.Parent = left

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(56, 44)
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for _, nation in Nations.LIST do
		local card = Instance.new("TextButton")
		card.LayoutOrder = nation.id
		card.Text = ""
		card.AutoButtonColor = false
		card.BackgroundColor3 = C.surfaceRaised
		card.BorderSizePixel = 0
		card.ZIndex = 52
		card.Parent = grid
		Theme.corner(card, Theme.radius.sm)
		local stroke = Theme.stroke(card, C.line, 1)

		local flagCell = Instance.new("Frame")
		flagCell.Position = UDim2.fromOffset(6, 5)
		flagCell.Size = UDim2.fromOffset(44, 26)
		flagCell.BackgroundColor3 = C.void
		flagCell.BorderSizePixel = 0
		flagCell.ClipsDescendants = true
		flagCell.ZIndex = 53
		flagCell.Parent = card
		Theme.corner(flagCell, 2)
		MainMenu.drawFlag(flagCell, nation.flag)

		local name = Theme.label(card, nation.name, 8, C.textMuted)
		name.Position = UDim2.fromOffset(0, 33)
		name.Size = UDim2.new(1, 0, 0, 10)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.FontFace = F.medium
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 53

		card.Activated:Connect(function()
			SoundManager.play("uiSelect")
			self:selectNation(nation.id)
		end)

		self.nationButtons[nation.id] = { card = card, stroke = stroke, name = name }
	end
end

--=============================================================================
-- Carte vedette : le mode selectionne
--=============================================================================

--[[
	La grande carte centrale, apercu de carte CONQUEST : apercu reel du
	terrain en plein cadre, degrade en bas, pastille de compte a rebours en
	haut a droite, nom et rythme en bas a gauche, remplissage en bas a droite.
]]
function MainMenu.buildFeaturedCard(self: MainMenu)
	local card = Theme.panel("Featured", self.stage)
	card.Position = UDim2.fromOffset(CENTER_X, GRID_TOP)
	card.Size = UDim2.fromOffset(COL_CENTER_W, 320)
	card.BackgroundColor3 = Config.TERRAIN_COLORS[Config.TERRAIN.OCEAN]
	card.ClipsDescendants = true
	card.ZIndex = 51

	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.Size = UDim2.fromScale(1, 1)
	preview.BackgroundTransparency = 1
	preview.ZIndex = 52
	preview.Parent = card
	self.featuredPreview = preview

	-- Le degrade assure la lisibilite du texte sur n'importe quel terrain.
	local shade = Instance.new("Frame")
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.new(0, 0, 1, 0)
	shade.Size = UDim2.new(1, 0, 0, 110)
	shade.BackgroundColor3 = C.void
	shade.BorderSizePixel = 0
	shade.ZIndex = 53
	shade.Parent = card
	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Rotation = 90
	shadeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	shadeGradient.Parent = shade

	-- Pastille de compte a rebours, en haut a droite.
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.new(1, -S.sm, 0, S.sm)
	pill.Size = UDim2.fromOffset(96, 20)
	pill.BackgroundColor3 = C.accent
	pill.BorderSizePixel = 0
	pill.ZIndex = 54
	pill.Parent = card
	Theme.corner(pill, Theme.radius.pill)

	local pillText = Theme.label(pill, "", T.tiny, C.text)
	pillText.Size = UDim2.fromScale(1, 1)
	pillText.TextXAlignment = Enum.TextXAlignment.Center
	pillText.FontFace = F.bold
	pillText.ZIndex = 55
	self.featuredPill = pill
	self.featuredPillText = pillText

	local modeName = Theme.label(card, "CLASSIQUE", 24, C.text)
	modeName.AnchorPoint = Vector2.new(0, 1)
	modeName.Position = UDim2.new(0, S.md, 1, -34)
	modeName.Size = UDim2.fromOffset(COL_CENTER_W - S.md * 2 - 90, 24)
	modeName.FontFace = F.display
	modeName.TextXAlignment = Enum.TextXAlignment.Left
	modeName.ZIndex = 54
	self.featuredName = modeName

	local modeTagline = Theme.label(card, "", T.tiny, C.textMuted)
	modeTagline.AnchorPoint = Vector2.new(0, 1)
	modeTagline.Position = UDim2.new(0, S.md, 1, -18)
	modeTagline.Size = UDim2.fromOffset(COL_CENTER_W - S.md * 2 - 90, 13)
	modeTagline.FontFace = F.medium
	modeTagline.TextXAlignment = Enum.TextXAlignment.Left
	modeTagline.ZIndex = 54
	self.featuredTagline = modeTagline

	local fill = Theme.label(card, "", T.tiny, C.text)
	fill.AnchorPoint = Vector2.new(1, 1)
	fill.Position = UDim2.new(1, -S.md, 1, -S.md)
	fill.Size = UDim2.fromOffset(90, 14)
	fill.TextXAlignment = Enum.TextXAlignment.Right
	fill.FontFace = F.bold
	fill.ZIndex = 54
	self.featuredFill = fill
end

--=============================================================================
-- Colonne droite : salon en cours, autres modes
--=============================================================================

function MainMenu.buildRightColumn(self: MainMenu)
	local right = Instance.new("Frame")
	right.Name = "RightColumn"
	right.Position = UDim2.fromOffset(RIGHT_X, GRID_TOP)
	right.Size = UDim2.fromOffset(COL_RIGHT_W, 380)
	right.BackgroundTransparency = 1
	right.ZIndex = 51
	right.Parent = self.stage

	-- La ou d'autres titres du genre montre un stream, nous montrons la partie qui tourne
	-- reellement sur ce serveur : meme case, meme promesse, donnees vraies.
	local liveChip = Theme.label(right, "EN DIRECT MAINTENANT", T.tiny, C.danger)
	liveChip.Position = UDim2.fromOffset(0, 0)
	liveChip.Size = UDim2.fromOffset(COL_RIGHT_W, 13)
	liveChip.FontFace = F.bold
	liveChip.ZIndex = 52

	local live = Theme.panel("LiveLobby", right)
	live.Position = UDim2.fromOffset(0, 18)
	live.Size = UDim2.fromOffset(COL_RIGHT_W, 56)
	live.ZIndex = 52

	local liveTitle = Theme.label(live, "Aucune partie en cours", T.small, C.text)
	liveTitle.Position = UDim2.fromOffset(S.sm, 10)
	liveTitle.Size = UDim2.fromOffset(COL_RIGHT_W - S.sm * 2, 14)
	liveTitle.FontFace = F.bold
	liveTitle.TextTruncate = Enum.TextTruncate.AtEnd
	liveTitle.ZIndex = 53
	self.liveTitle = liveTitle

	local liveMeta = Theme.label(live, "Le salon demarre a ton deploiement.", T.tiny, C.textMuted)
	liveMeta.Position = UDim2.fromOffset(S.sm, 30)
	liveMeta.Size = UDim2.fromOffset(COL_RIGHT_W - S.sm * 2, 13)
	liveMeta.FontFace = F.medium
	liveMeta.TextTruncate = Enum.TextTruncate.AtEnd
	liveMeta.ZIndex = 53
	self.liveMeta = liveMeta

	-- Les deux modes non selectionnes, empiles : miniatures cliquables qui
	-- echangent leur place avec la carte vedette.
	local y = 86
	for _, mode in GameModes.LIST do
		local card = Instance.new("TextButton")
		card.Name = `ModeCard_{mode.id}`
		card.Text = ""
		card.AutoButtonColor = false
		card.Position = UDim2.fromOffset(0, y)
		card.Size = UDim2.fromOffset(COL_RIGHT_W, 114)
		card.BackgroundColor3 = Config.TERRAIN_COLORS[Config.TERRAIN.OCEAN]
		card.BorderSizePixel = 0
		card.ClipsDescendants = true
		card.ZIndex = 52
		card.Parent = right
		Theme.corner(card, Theme.radius.sm)
		local stroke = Theme.stroke(card, C.line, 1)

		local preview = Instance.new("Frame")
		preview.Size = UDim2.fromScale(1, 1)
		preview.BackgroundTransparency = 1
		preview.ZIndex = 53
		preview.Parent = card
		drawTerrainPreview(preview, MODE_SEEDS[mode.id] or 1, 24, 12)

		local shade = Instance.new("Frame")
		shade.AnchorPoint = Vector2.new(0, 1)
		shade.Position = UDim2.new(0, 0, 1, 0)
		shade.Size = UDim2.new(1, 0, 0, 52)
		shade.BackgroundColor3 = C.void
		shade.BorderSizePixel = 0
		shade.ZIndex = 54
		shade.Parent = card
		local shadeGradient = Instance.new("UIGradient")
		shadeGradient.Rotation = 90
		shadeGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		shadeGradient.Parent = shade

		local pill = Instance.new("Frame")
		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Position = UDim2.new(1, -S.xs, 0, S.xs)
		pill.Size = UDim2.fromOffset(78, 16)
		pill.BackgroundColor3 = C.surfaceRaised
		pill.BorderSizePixel = 0
		pill.ZIndex = 55
		pill.Parent = card
		Theme.corner(pill, Theme.radius.pill)

		local pillText = Theme.label(pill, "", 9, C.text)
		pillText.Size = UDim2.fromScale(1, 1)
		pillText.TextXAlignment = Enum.TextXAlignment.Center
		pillText.FontFace = F.bold
		pillText.ZIndex = 56

		local name = Theme.label(card, string.upper(mode.name), T.small, C.text)
		name.AnchorPoint = Vector2.new(0, 1)
		name.Position = UDim2.new(0, S.sm, 1, -24)
		name.Size = UDim2.fromOffset(COL_RIGHT_W - S.sm * 2, 14)
		name.FontFace = F.bold
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = 55

		local meta = Theme.label(card, "", 9, C.textMuted)
		meta.AnchorPoint = Vector2.new(0, 1)
		meta.Position = UDim2.new(0, S.sm, 1, -11)
		meta.Size = UDim2.fromOffset(COL_RIGHT_W - S.sm * 2, 11)
		meta.FontFace = F.medium
		meta.TextXAlignment = Enum.TextXAlignment.Left
		meta.ZIndex = 55

		card.Activated:Connect(function()
			SoundManager.play("uiSelect")
			self:selectMode(mode.id)
		end)

		self.modeButtons[mode.id] = { card = card, stroke = stroke, pill = pill, pillText = pillText, meta = meta }
		y += 114 + 8
	end
end

--=============================================================================
-- Deploiement et salons
--=============================================================================

function MainMenu.buildDeployRow(self: MainMenu)
	local deploy = Instance.new("TextButton")
	deploy.Name = "Deploy"
	deploy.Position = UDim2.fromOffset(CENTER_X, GRID_TOP + 332)
	deploy.Size = UDim2.fromOffset(COL_CENTER_W, 44)
	deploy.BackgroundColor3 = C.accentSoft
	deploy.BorderSizePixel = 0
	deploy.AutoButtonColor = false
	deploy.FontFace = F.display
	deploy.TextSize = 18
	deploy.TextColor3 = C.text
	deploy.Text = "JOUER SOLO"
	deploy.ZIndex = 51
	deploy.Parent = self.stage
	Theme.corner(deploy, Theme.radius.md)
	local deployStroke = Theme.stroke(deploy, C.accent, 1)
	deployStroke.Transparency = 0.05

	deploy.MouseEnter:Connect(function()
		TweenService:Create(deploy, Theme.motion.quick, { BackgroundColor3 = C.accent }):Play()
	end)
	deploy.MouseLeave:Connect(function()
		TweenService:Create(deploy, Theme.motion.quick, { BackgroundColor3 = C.accentSoft }):Play()
	end)
	deploy.Activated:Connect(function()
		SoundManager.play("uiClick")
		self:close()
		if self.onDeploy then
			self.onDeploy(self.nationId, self.modeId)
		end
	end)

	-- Les trois boutons salon de la reference. Ils annoncent le mode Equipes
	-- plutot que de faire semblant d'ouvrir un annuaire qui n'existe pas.
	local labels = { "CREER UN SALON", "CLASSES", "REJOINDRE UN SALON" }
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(CENTER_X, GRID_TOP + 384)
	row.Size = UDim2.fromOffset(COL_CENTER_W, 34)
	row.BackgroundTransparency = 1
	row.ZIndex = 51
	row.Parent = self.stage
	Theme.list(row, Enum.FillDirection.Horizontal, S.sm)

	for i, text in labels do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		b.Text = text
		b.AutoButtonColor = false
		b.Size = UDim2.new(1 / 3, -6, 1, 0)
		b.BackgroundColor3 = C.surfaceRaised
		b.BorderSizePixel = 0
		b.FontFace = F.bold
		b.TextSize = T.tiny
		b.TextColor3 = C.textMuted
		b.ZIndex = 52
		b.Parent = row
		Theme.corner(b, Theme.radius.sm)
		b.Activated:Connect(function()
			SoundManager.play("uiClick")
			self.navToastId += 1
			local id = self.navToastId
			self.navToast.Text = "LES SALONS ARRIVENT AVEC LE MODE EQUIPES"
			self.navToast.Visible = true
			task.delay(1.6, function()
				if self.navToastId == id then
					self.navToast.Visible = false
				end
			end)
		end)
	end
end

function MainMenu.buildFooter(self: MainMenu)
	local left = Theme.label(self.stage, "CONQUEST RTS  /  BETA", T.tiny, C.textFaint)
	left.AnchorPoint = Vector2.new(0, 1)
	left.Position = UDim2.new(0, 0, 0, 600)
	left.Size = UDim2.fromOffset(240, 13)
	left.FontFace = F.medium
	left.ZIndex = 51

	local right = Theme.label(self.stage, "Simulation a ton deploiement  ·  aucun bot ne joue derriere ce menu", T.tiny, C.textFaint)
	right.AnchorPoint = Vector2.new(1, 1)
	right.Position = UDim2.new(1, 0, 0, 600)
	right.Size = UDim2.fromOffset(360, 13)
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.FontFace = F.medium
	right.ZIndex = 51
end

--=============================================================================
-- Etat diffuse par le serveur
--=============================================================================

--[[
	Etat du salon courant, tel que le serveur le diffuse.

	La carte "EN DIRECT" porte la partie qui tourne, et la pastille du mode
	concerne affiche son compte a rebours ou son remplissage. Quand la liste
	viendra d'un vrai annuaire inter-serveurs, seule la SOURCE changera.
]]
function MainMenu.setLobby(self: MainMenu, match: any)
	if match == nil or match.phase == nil then
		self.liveTitle.Text = "Aucune partie en cours"
		self.liveMeta.Text = "Le salon demarre a ton deploiement."
	else
		local mode = GameModes.get(match.mode)
		local players = match.players or 0
		local capacity = match.maxPlayers or players
		if match.phase == "waiting" then
			self.liveTitle.Text = `{mode.name} — en attente`
			self.liveMeta.Text = `{players}/{capacity} nations au depart`
		elseif match.phase == "ended" then
			self.liveTitle.Text = `{mode.name} — terminee`
			self.liveMeta.Text = "Le prochain salon demarre sous peu."
		else
			local left = math.max(0, math.floor(match.timeLeft or 0))
			self.liveTitle.Text = `{mode.name} — en cours`
			self.liveMeta.Text = `{players} nations  ·  {formatCountdown(left)} restantes`
		end
	end
	self:refreshFeatured()
end

--=============================================================================
-- Selection
--=============================================================================

function MainMenu.selectNation(self: MainMenu, id: number)
	self.nationId = id
	local nation = Nations.get(id)
	for nationId, entry in self.nationButtons do
		local selected = nationId == id
		entry.stroke.Color = if selected then C.accent else C.line
		entry.stroke.Thickness = if selected then 2 else 1
		entry.stroke.Transparency = if selected then 0 else 0.35
		entry.card.BackgroundColor3 = if selected then C.accentSoft else C.surfaceRaised
		entry.name.TextColor3 = if selected then C.text else C.textMuted
	end
	if self.identityFlag then
		MainMenu.drawFlag(self.identityFlag, nation.flag)
	end
	if self.playerFlag then
		MainMenu.drawFlag(self.playerFlag, nation.flag)
	end
	if self.identityNation then
		self.identityNation.Text = nation.name
	end
end

function MainMenu.selectMode(self: MainMenu, id: string)
	self.modeId = id
	for modeId, entry in self.modeButtons do
		local selected = modeId == id
		local accent = MODE_ACCENTS[modeId] or C.accent
		entry.stroke.Color = if selected then accent else C.line
		entry.stroke.Thickness = if selected then 2 else 1
		entry.stroke.Transparency = if selected then 0 else 0.4
	end
	self:refreshFeatured()
end

--[[
	Repeint la carte vedette pour le mode selectionne : la miniature est
	regeneree depuis la graine du mode, comme si l'on changeait de map.
]]
function MainMenu.refreshFeatured(self: MainMenu)
	local mode = GameModes.get(self.modeId)
	if self.featuredPreview then
		drawTerrainPreview(self.featuredPreview, MODE_SEEDS[mode.id] or 1, 32, 20)
	end
	if self.featuredName then
		self.featuredName.Text = string.upper(mode.name)
		self.featuredName.TextColor3 = MODE_ACCENTS[mode.id] or C.text
	end
	if self.featuredTagline then
		self.featuredTagline.Text = mode.tagline
	end
	if self.featuredFill then
		self.featuredFill.Text = `{mode.botCount} NATIONS`
	end
	if self.featuredPillText then
		self.featuredPillText.Text = formatCountdown(mode.duration)
	end
	for modeId, entry in self.modeButtons do
		local m = GameModes.get(modeId)
		entry.pillText.Text = formatCountdown(m.duration)
		entry.meta.Text = `{m.botCount} nations  ·  x{m.eraCostMultiplier} ere`
	end
end

-- Le nom Roblox du joueur, injecte par init.client : le menu ne connait pas
-- le service Players, ce qui le garde testable hors de Studio.
function MainMenu.setPlayer(self: MainMenu, displayName: string)
	self.playerName = displayName
	if self.playerNameLabel then
		self.playerNameLabel.Text = displayName
	end
	if self.identityName then
		self.identityName.Text = displayName
	end
end

function MainMenu.close(self: MainMenu)
	self.transitionId += 1
	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween = nil
	end

	-- Le menu ne doit jamais rester comme un voile noir au-dessus de la partie
	-- si Roblox interrompt le tween ou si le joueur change de contexte pendant
	-- la transition. Le déploiement est un changement d'écran, pas une simple
	-- animation : on masque donc la racine immédiatement.
	self.root.GroupTransparency = 1
	self.root.Visible = false
end

function MainMenu.open(self: MainMenu)
	self.transitionId += 1
	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween = nil
	end
	self.root.GroupTransparency = 0
	self.root.Visible = true
end

return MainMenu
