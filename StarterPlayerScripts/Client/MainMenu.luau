--!strict
--[[
	Menu principal.

	C'est le premier ecran du jeu, donc celui qui decide si le joueur pense
	"c'est un vrai jeu" ou "c'est une maquette". Il fait trois choses et rien
	d'autre : choisir sa nation, choisir un mode, deployer.

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

local function debugMenu(message: string)
end

local function formatDuration(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return `{minutes} MIN`
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
-- Construction
--=============================================================================

function MainMenu.new(parent: ScreenGui): MainMenu
	local self = setmetatable({}, MainMenu) :: any

	self.nationId = 1
	self.modeId = GameModes.DEFAULT
	self.nationButtons = {}
	self.modeButtons = {}
	self.transitionId = 0

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

	-- Les dimensions du lobby sont pensees en pixels logiques. Sur Roblox
	-- mobile/retina, la hauteur utile est souvent 640 alors que le contenu
	-- complet depasse 720 : il faut reduire l'ensemble, pas couper le bouton.
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
		local widthScale = viewport.X / 1024
		local heightScale = viewport.Y / 760
		scale.Scale = math.clamp(math.min(widthScale, heightScale), 0.72, 1)
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

	-- Grille tactique tres legere : elle donne une profondeur de carte sans
	-- imposer une fausse image de fond et reste nette sur mobile.
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

	local topBar = Theme.panel("Navigation", content)
	topBar.AnchorPoint = Vector2.new(0.5, 0)
	topBar.Position = UDim2.new(0.5, 0, 0, 20)
	topBar.Size = UDim2.fromOffset(1000, 66)
	topBar.BackgroundTransparency = 0.04
	topBar.ZIndex = 51

	local brand = Theme.label(topBar, "CONQUEST RTS", 20, C.text)
	-- La barre Roblox recouvre la zone haut-gauche : la marque commence plus a
	-- droite pour rester lisible sur desktop, tablette et mobile.
	brand.Position = UDim2.fromOffset(240, 10)
	brand.Size = UDim2.fromOffset(210, 24)
	brand.FontFace = F.display
	brand.ZIndex = 52

	local studio = Theme.label(topBar, "BLACKLINE STUDIO  /  BETA", T.tiny, C.accent)
	studio.Position = UDim2.fromOffset(240, 36)
	studio.Size = UDim2.fromOffset(240, 14)
	studio.FontFace = F.medium
	studio.ZIndex = 52

	local navItems = { "JOUER", "GUIDE", "ACTUS", "A PROPOS" }
	for i, item in navItems do
		local nav = Theme.label(topBar, item, T.small, if i == 1 then C.accent else C.textMuted)
		nav.AnchorPoint = Vector2.new(1, 0.5)
		nav.Position = UDim2.new(1, -S.lg - (4 - i) * 82, 0.5, 0)
		nav.Size = UDim2.fromOffset(74, 18)
		nav.TextXAlignment = Enum.TextXAlignment.Center
		nav.FontFace = F.bold
		nav.ZIndex = 52
	end

	-- Cadre de briefing : il donne une colonne vertebrale a l'ecran et evite
	-- l'effet "widgets poses dans le vide" du menu prototype.
	local frame = Instance.new("Frame")
	frame.Name = "BriefingFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 100)
	frame.Size = UDim2.fromOffset(900, 620)
	frame.BackgroundColor3 = C.surface
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.ZIndex = 50
	frame.Parent = content
	Theme.corner(frame, Theme.radius.lg)
	local frameStroke = Theme.stroke(frame, C.lineStrong, 1)
	frameStroke.Transparency = 0.32

	local accentLine = Instance.new("Frame")
	accentLine.AnchorPoint = Vector2.new(0.5, 0)
	accentLine.Position = UDim2.new(0.5, 0, 0, 100)
	accentLine.Size = UDim2.fromOffset(150, 2)
	accentLine.BackgroundColor3 = C.accent
	accentLine.BorderSizePixel = 0
	accentLine.ZIndex = 51
	accentLine.Parent = content

	local eyebrow = Theme.label(content, "GLOBAL CONQUEST  /  CHOOSE YOUR STORY", T.tiny, C.accent)
	eyebrow.AnchorPoint = Vector2.new(0.5, 0)
	eyebrow.Position = UDim2.new(0.5, 0, 0, 116)
	eyebrow.Size = UDim2.fromOffset(700, 14)
	eyebrow.TextXAlignment = Enum.TextXAlignment.Center
	eyebrow.FontFace = F.medium
	eyebrow.ZIndex = 51

	-- Voile degrade : donne de la profondeur sans image de fond.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(16, 22, 34), Color3.fromRGB(6, 8, 14))
	-- Le gradient ne doit teinter que le fond. Sur le CanvasGroup racine,
	-- Roblox l'applique aussi au rendu des enfants et assombrit textes,
	-- drapeaux et boutons.
	gradient.Parent = backdrop

	self:buildHeader()
	self:buildNations()
	self:buildPreview()
	self:buildModes()
	self:buildDeploy()

	self:selectNation(1)
	self:selectMode(GameModes.DEFAULT)
	debugMenu(`created visible={root.Visible} group={root.GroupTransparency} background={root.BackgroundTransparency}`)

	return self
end

function MainMenu.buildHeader(self: MainMenu)
	local title = Theme.label(self.content, Config.GAME_NAME, 46, C.text)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 132)
	title.Size = UDim2.fromOffset(700, 52)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.FontFace = F.display
	title.ZIndex = 51

	local rule = Instance.new("Frame")
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 184)
	rule.Size = UDim2.fromOffset(72, 1)
	rule.BackgroundColor3 = C.lineStrong
	rule.BorderSizePixel = 0
	rule.ZIndex = 51
	rule.Parent = self.content

	local subtitle = Theme.label(self.content, "CONSTRUIS TA NATION. FAIS EQUIPE. ECRIS TON HISTOIRE.", T.body, C.textMuted)
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0, 193)
	subtitle.Size = UDim2.fromOffset(700, 18)
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.FontFace = F.medium
	subtitle.ZIndex = 51
end

function MainMenu.buildNations(self: MainMenu)
	local label = Theme.label(self.content, "01  /  CHOISIS TA NATION", T.tiny, C.textFaint)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, -230, 0, 225)
	label.Size = UDim2.fromOffset(380, 14)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 51

	local grid = Instance.new("Frame")
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.Position = UDim2.new(0.5, -230, 0, 250)
	grid.Size = UDim2.fromOffset(380, 264)
	grid.BackgroundTransparency = 1
	grid.ZIndex = 51
	grid.Parent = self.content

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(88, 60)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for _, nation in Nations.LIST do
		local card = Instance.new("TextButton")
		card.LayoutOrder = nation.id
		card.Text = ""
		card.AutoButtonColor = false
		card.BackgroundColor3 = C.surfaceRaised
		card.BorderSizePixel = 0
		card.ZIndex = 51
		card.Parent = grid
		Theme.corner(card, Theme.radius.sm)
		local stroke = Theme.stroke(card, C.line, 1)

		local flag = Instance.new("Frame")
		flag.Position = UDim2.fromOffset(14, 7)
		flag.Size = UDim2.fromOffset(60, 28)
		flag.BackgroundColor3 = C.void
		flag.BorderSizePixel = 0
		flag.ClipsDescendants = true
		flag.ZIndex = 52
		flag.Parent = card
		Theme.corner(flag, 2)
		MainMenu.drawFlag(flag, nation.flag)

		local name = Theme.label(card, nation.name, T.tiny, C.textMuted)
		name.Position = UDim2.fromOffset(0, 39)
		name.Size = UDim2.new(1, 0, 0, 14)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.ZIndex = 52

		card.Activated:Connect(function()
			SoundManager.play("uiSelect")
			self:selectNation(nation.id)
		end)

		self.nationButtons[nation.id] = { card = card, stroke = stroke, name = name }
	end
end

function MainMenu.buildPreview(self: MainMenu)
	local preview = Theme.panel("MapPreview", self.content)
	preview.AnchorPoint = Vector2.new(0, 0)
	preview.Position = UDim2.new(0.5, 10, 0, 225)
	preview.Size = UDim2.fromOffset(420, 286)
	preview.BackgroundColor3 = C.surfaceRaised
	preview.BackgroundTransparency = 0.02
	preview.ZIndex = 51

	local mapTitle = Theme.label(preview, "CARTE DE DEPLOIEMENT", T.tiny, C.accent)
	mapTitle.Position = UDim2.fromOffset(S.md, 10)
	mapTitle.Size = UDim2.fromOffset(190, 14)
	mapTitle.FontFace = F.bold
	mapTitle.ZIndex = 53

	local mapMeta = Theme.label(preview, "PROCEDURALE  /  SEED 2026", T.tiny, C.textFaint)
	mapMeta.AnchorPoint = Vector2.new(1, 0)
	mapMeta.Position = UDim2.new(1, -S.md, 0, 10)
	mapMeta.Size = UDim2.fromOffset(180, 14)
	mapMeta.TextXAlignment = Enum.TextXAlignment.Right
	mapMeta.FontFace = F.medium
	mapMeta.ZIndex = 53

	local map = Instance.new("Frame")
	map.Name = "TerrainPreview"
	map.Position = UDim2.fromOffset(S.md, 32)
	map.Size = UDim2.fromOffset(388, 150)
	map.BackgroundColor3 = Config.TERRAIN_COLORS[Config.TERRAIN.OCEAN]
	map.BorderSizePixel = 0
	map.ClipsDescendants = true
	map.ZIndex = 52
	map.Parent = preview
	Theme.corner(map, Theme.radius.sm)

	-- Une version miniature de la vraie generation de terrain rend le choix
	-- concret, sans charger une image ou un asset externe dans le menu.
	local terrain = MapGen.generate(2026)
	local cellsX = 32
	local cellsY = 16
	local cellWidth = 388 / cellsX
	local cellHeight = 150 / cellsY
	for y = 0, cellsY - 1 do
		for x = 0, cellsX - 1 do
			local sourceX = math.clamp(math.floor((x + 0.5) * Config.MAP_WIDTH / cellsX), 0, Config.MAP_WIDTH - 1)
			local sourceY = math.clamp(math.floor((y + 0.5) * Config.MAP_HEIGHT / cellsY), 0, Config.MAP_HEIGHT - 1)
			local terrainKind = buffer.readu8(terrain, MapGen.toIndex(sourceX, sourceY))
			if terrainKind ~= Config.TERRAIN.OCEAN then
				local tile = Instance.new("Frame")
				tile.BorderSizePixel = 0
				tile.BackgroundColor3 = Config.TERRAIN_COLORS[terrainKind] or Config.TERRAIN_COLORS[2]
				tile.BackgroundTransparency = 0.08
				tile.Position = UDim2.fromOffset(math.floor(x * cellWidth), math.floor(y * cellHeight))
				tile.Size = UDim2.fromOffset(math.ceil(cellWidth + 1), math.ceil(cellHeight + 1))
				tile.ZIndex = 52
				tile.Parent = map
			end
		end
	end

	local scanline = Instance.new("Frame")
	scanline.Name = "PreviewScanline"
	scanline.Position = UDim2.fromOffset(0, 74)
	scanline.Size = UDim2.new(1, 0, 0, 1)
	scanline.BackgroundColor3 = C.text
	scanline.BackgroundTransparency = 0.88
	scanline.BorderSizePixel = 0
	scanline.ZIndex = 53
	scanline.Parent = map

	local nationLabel = Theme.label(preview, "VALORIA", 20, C.text)
	nationLabel.Position = UDim2.fromOffset(S.md, 194)
	nationLabel.Size = UDim2.fromOffset(210, 24)
	nationLabel.FontFace = F.display
	nationLabel.ZIndex = 53

	local nationHint = Theme.label(preview, "Point de depart recommande", T.tiny, C.textFaint)
	nationHint.Position = UDim2.fromOffset(S.md, 219)
	nationHint.Size = UDim2.fromOffset(220, 14)
	nationHint.FontFace = F.medium
	nationHint.ZIndex = 53

	local modeLabel = Theme.label(preview, "CLASSIQUE", T.body, C.accent)
	modeLabel.AnchorPoint = Vector2.new(1, 0)
	modeLabel.Position = UDim2.new(1, -S.md, 0, 198)
	modeLabel.Size = UDim2.fromOffset(160, 18)
	modeLabel.TextXAlignment = Enum.TextXAlignment.Right
	modeLabel.FontFace = F.bold
	modeLabel.ZIndex = 53

	local modeMeta = Theme.label(preview, "25 MIN  ·  12 NATIONS", T.tiny, C.textMuted)
	modeMeta.AnchorPoint = Vector2.new(1, 0)
	modeMeta.Position = UDim2.new(1, -S.md, 0, 220)
	modeMeta.Size = UDim2.fromOffset(200, 14)
	modeMeta.TextXAlignment = Enum.TextXAlignment.Right
	modeMeta.FontFace = F.medium
	modeMeta.ZIndex = 53

	self.previewNation = nationLabel
	self.previewNationHint = nationHint
	self.previewMode = modeLabel
	self.previewModeMeta = modeMeta
end

function MainMenu.buildModes(self: MainMenu)
	local label = Theme.label(self.content, "02  /  CHOISIS TON OPERATION", T.tiny, C.textFaint)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 532)
	label.Size = UDim2.fromOffset(820, 14)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 51

	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 553)
	row.Size = UDim2.fromOffset(820, 58)
	row.BackgroundTransparency = 1
	row.ZIndex = 51
	row.Parent = self.content
	Theme.list(row, Enum.FillDirection.Horizontal, S.sm)

	for i, mode in GameModes.LIST do
		local card = Instance.new("TextButton")
		card.LayoutOrder = i
		card.Text = ""
		card.AutoButtonColor = false
		card.Size = UDim2.new(1 / 3, -4, 1, 0)
		card.BackgroundColor3 = C.surfaceRaised
		card.BorderSizePixel = 0
		card.ZIndex = 51
		card.Parent = row
		Theme.corner(card, Theme.radius.sm)
		local stroke = Theme.stroke(card, C.line, 1)

		local name = Theme.label(card, `{mode.symbol}  {mode.name}`, T.body, C.text)
		name.Position = UDim2.fromOffset(S.md, 10)
		name.Size = UDim2.new(1, -S.md * 2, 0, 16)
		name.ZIndex = 52

		local tagline = Theme.label(card, mode.tagline, T.tiny, C.textFaint)
		tagline.Position = UDim2.fromOffset(S.md, 30)
		tagline.Size = UDim2.new(1, -S.md * 2, 0, 18)
		tagline.FontFace = F.medium
		tagline.TextWrapped = true
		tagline.ZIndex = 52

		card.Activated:Connect(function()
			SoundManager.play("uiSelect")
			self:selectMode(mode.id)
		end)

		self.modeButtons[mode.id] = { card = card, stroke = stroke }
	end
end

function MainMenu.buildDeploy(self: MainMenu)
	local deploy = Instance.new("TextButton")
	deploy.Name = "Deploy"
	deploy.AnchorPoint = Vector2.new(0.5, 0)
	deploy.Position = UDim2.new(0.5, 0, 0, 620)
	deploy.Size = UDim2.fromOffset(360, 46)
	deploy.BackgroundColor3 = C.accentSoft
	deploy.BorderSizePixel = 0
	deploy.AutoButtonColor = false
	deploy.FontFace = F.display
	deploy.TextSize = 18
	deploy.TextColor3 = C.text
	deploy.Text = "COMMENCER L'OPERATION"
	deploy.ZIndex = 51
	deploy.Parent = self.content
	Theme.corner(deploy, Theme.radius.md)
	local deployStroke = Theme.stroke(deploy, C.accent, 1)
	deployStroke.Transparency = 0.05

	deploy.MouseEnter:Connect(function()
		TweenService:Create(deploy, Theme.motion.quick, { Size = UDim2.fromOffset(372, 48), BackgroundColor3 = C.accent }):Play()
	end)
	deploy.MouseLeave:Connect(function()
		TweenService:Create(deploy, Theme.motion.quick, { Size = UDim2.fromOffset(360, 46), BackgroundColor3 = C.accentSoft }):Play()
	end)
	deploy.Activated:Connect(function()
		SoundManager.play("uiClick")
		self:close()
		if self.onDeploy then
			self.onDeploy(self.nationId, self.modeId)
		end
	end)

	local hint = Theme.label(self.content, "La simulation demarre a ton deploiement  ·  aucun bot ne joue derriere ce menu", T.tiny, C.textFaint)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 676)
	hint.Size = UDim2.fromOffset(660, 14)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.FontFace = F.medium
	hint.ZIndex = 51
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
	if self.previewNation then
		self.previewNation.Text = string.upper(nation.name)
		self.previewNationHint.Text = `{nation.name}  ·  point de depart selectionne`
	end
end

function MainMenu.selectMode(self: MainMenu, id: string)
	self.modeId = id
	local mode = GameModes.get(id)
	local modeAccent: { [string]: Color3 } = {
		classic = C.accent,
		blitz = C.warning,
		marathon = C.info,
	}
	for modeId, entry in self.modeButtons do
		local selected = modeId == id
		entry.stroke.Color = if selected then (modeAccent[modeId] or C.accent) else C.line
		entry.stroke.Thickness = if selected then 2 else 1
		entry.stroke.Transparency = if selected then 0 else 0.35
		entry.card.BackgroundColor3 = if selected then C.accentSoft else C.surfaceRaised
	end
	if self.previewMode then
		self.previewMode.Text = string.upper(`{mode.symbol}  {mode.name}`)
		self.previewMode.TextColor3 = modeAccent[id] or C.accent
		self.previewModeMeta.Text = `{formatDuration(mode.duration)}  ·  {mode.botCount} NATIONS`
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
	debugMenu(`close visible={self.root.Visible} group={self.root.GroupTransparency}`)
end

function MainMenu.open(self: MainMenu)
	self.transitionId += 1
	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween = nil
	end
	self.root.GroupTransparency = 0
	self.root.Visible = true
	debugMenu(`open visible={self.root.Visible} group={self.root.GroupTransparency}`)
end

return MainMenu
