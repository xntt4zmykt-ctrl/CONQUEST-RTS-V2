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
local SoundManager = require(script.Parent.SoundManager)

local C = Theme.color
local S = Theme.space
local F = Theme.font
local T = Theme.textSize

local MainMenu = {}
MainMenu.__index = MainMenu

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

	local root = Instance.new("Frame")
	root.Name = "MainMenu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = C.void
	root.BorderSizePixel = 0
	root.ZIndex = 50
	root.Parent = parent
	self.root = root

	-- Voile degrade : donne de la profondeur sans image de fond.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(16, 22, 34), Color3.fromRGB(6, 8, 14))
	gradient.Parent = root

	self:buildHeader()
	self:buildNations()
	self:buildModes()
	self:buildDeploy()

	self:selectNation(1)
	self:selectMode(GameModes.DEFAULT)

	return self
end

function MainMenu.buildHeader(self: MainMenu)
	local title = Theme.label(self.root, Config.GAME_NAME, 46, C.text)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 46)
	title.Size = UDim2.fromOffset(700, 52)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.FontFace = F.display
	title.ZIndex = 51

	local rule = Instance.new("Frame")
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 100)
	rule.Size = UDim2.fromOffset(120, 2)
	rule.BackgroundColor3 = C.accent
	rule.BorderSizePixel = 0
	rule.ZIndex = 51
	rule.Parent = self.root

	local subtitle = Theme.label(self.root, "Conquiers le monde. Trahis tes allies.", T.body, C.textMuted)
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0, 110)
	subtitle.Size = UDim2.fromOffset(700, 18)
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.FontFace = F.medium
	subtitle.ZIndex = 51
end

function MainMenu.buildNations(self: MainMenu)
	local label = Theme.label(self.root, "CHOISIS TA NATION", T.tiny, C.textFaint)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 150)
	label.Size = UDim2.fromOffset(660, 14)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 51

	local grid = Instance.new("Frame")
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.Position = UDim2.new(0.5, 0, 0, 172)
	grid.Size = UDim2.fromOffset(672, 176)
	grid.BackgroundTransparency = 1
	grid.ZIndex = 51
	grid.Parent = self.root

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(78, 76)
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
		flag.Position = UDim2.fromOffset(9, 8)
		flag.Size = UDim2.fromOffset(60, 38)
		flag.BackgroundColor3 = C.void
		flag.BorderSizePixel = 0
		flag.ClipsDescendants = true
		flag.ZIndex = 52
		flag.Parent = card
		Theme.corner(flag, 2)
		MainMenu.drawFlag(flag, nation.flag)

		local name = Theme.label(card, nation.name, T.tiny, C.textMuted)
		name.Position = UDim2.fromOffset(0, 50)
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

function MainMenu.buildModes(self: MainMenu)
	local label = Theme.label(self.root, "MODE DE JEU", T.tiny, C.textFaint)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 366)
	label.Size = UDim2.fromOffset(660, 14)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 51

	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 388)
	row.Size = UDim2.fromOffset(672, 64)
	row.BackgroundTransparency = 1
	row.ZIndex = 51
	row.Parent = self.root
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
		tagline.Size = UDim2.new(1, -S.md * 2, 0, 24)
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
	deploy.Position = UDim2.new(0.5, 0, 0, 476)
	deploy.Size = UDim2.fromOffset(280, 46)
	deploy.BackgroundColor3 = C.accent
	deploy.BorderSizePixel = 0
	deploy.AutoButtonColor = false
	deploy.FontFace = F.display
	deploy.TextSize = 18
	deploy.TextColor3 = C.text
	deploy.Text = "DEPLOYER"
	deploy.ZIndex = 51
	deploy.Parent = self.root
	Theme.corner(deploy, Theme.radius.md)

	deploy.MouseEnter:Connect(function()
		TweenService:Create(deploy, Theme.motion.quick, { Size = UDim2.fromOffset(292, 48) }):Play()
	end)
	deploy.MouseLeave:Connect(function()
		TweenService:Create(deploy, Theme.motion.quick, { Size = UDim2.fromOffset(280, 46) }):Play()
	end)
	deploy.Activated:Connect(function()
		SoundManager.play("uiClick")
		self:close()
		if self.onDeploy then
			self.onDeploy(self.nationId, self.modeId)
		end
	end)

	local hint = Theme.label(self.root, "Le mode choisi s'applique a la prochaine partie.", T.tiny, C.textFaint)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 530)
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
	for nationId, entry in self.nationButtons do
		local selected = nationId == id
		entry.stroke.Color = if selected then C.accent else C.line
		entry.stroke.Thickness = if selected then 2 else 1
		entry.stroke.Transparency = if selected then 0 else 0.35
		entry.card.BackgroundColor3 = if selected then C.surfaceHover else C.surfaceRaised
		entry.name.TextColor3 = if selected then C.text else C.textMuted
	end
end

function MainMenu.selectMode(self: MainMenu, id: string)
	self.modeId = id
	for modeId, entry in self.modeButtons do
		local selected = modeId == id
		entry.stroke.Color = if selected then C.accent else C.line
		entry.stroke.Thickness = if selected then 2 else 1
		entry.stroke.Transparency = if selected then 0 else 0.35
		entry.card.BackgroundColor3 = if selected then C.surfaceHover else C.surfaceRaised
	end
end

function MainMenu.close(self: MainMenu)
	local tween = TweenService:Create(self.root, Theme.motion.smooth, { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		self.root.Visible = false
	end)
	for _, child in self.root:GetDescendants() do
		if child:IsA("GuiObject") then
			TweenService:Create(child, Theme.motion.smooth, { BackgroundTransparency = 1 }):Play()
		end
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			TweenService:Create(child, Theme.motion.smooth, { TextTransparency = 1 }):Play()
		end
	end
end

return MainMenu
