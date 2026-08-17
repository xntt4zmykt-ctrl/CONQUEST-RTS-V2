--!strict
--[[
	Interface de commandement.

	Deux elements portent tout le jeu et doivent rester lisibles a 100 % :
	le compteur de troupes, et le curseur d'engagement. Le reste est secondaire.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local HUD = {}
HUD.__index = HUD

export type HUD = typeof(setmetatable(
	{} :: {
		root: Frame,
		troopsLabel: TextLabel,
		tilesLabel: TextLabel,
		statusLabel: TextLabel,
		nameLabel: TextLabel,
		ratioButtons: { [number]: TextButton },
		leaderboard: Frame,
		leaderRows: { [number]: TextLabel },
		ratio: number,
		statusUntil: number,
		onRatioChanged: ((number) -> ())?,
	},
	HUD
))

local RATIOS = { 0.1, 0.25, 0.5, 1.0 }

local FONT = Font.fromEnum(Enum.Font.GothamBold)
local PANEL_COLOR = Color3.fromRGB(18, 22, 32)

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

function HUD.new(parent: ScreenGui): HUD
	local self = setmetatable({}, HUD) :: HUD
	self.ratio = Config.DEFAULT_ATTACK_RATIO
	self.ratioButtons = {}
	self.leaderRows = {}
	self.statusUntil = 0

	local root = Instance.new("Frame")
	root.Name = "HUD"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = parent
	self.root = root

	--------------------------------------------------------------------------
	-- Bandeau bas : troupes + engagement. L'element signature du genre.
	--------------------------------------------------------------------------
	local bottom = Instance.new("Frame")
	bottom.Name = "CommandBar"
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 1, -18)
	bottom.Size = UDim2.fromOffset(460, 96)
	bottom.BackgroundColor3 = PANEL_COLOR
	bottom.BackgroundTransparency = 0.08
	bottom.BorderSizePixel = 0
	bottom.Parent = root
	corner(bottom, 12)
	stroke(bottom, Color3.fromRGB(90, 110, 140), 1.5)

	local troops = Instance.new("TextLabel")
	troops.Name = "Troops"
	troops.BackgroundTransparency = 1
	troops.Position = UDim2.fromOffset(18, 10)
	troops.Size = UDim2.fromOffset(240, 34)
	troops.FontFace = FONT
	troops.TextSize = 30
	troops.TextColor3 = Color3.fromRGB(255, 255, 255)
	troops.TextXAlignment = Enum.TextXAlignment.Left
	troops.Text = "0"
	troops.Parent = bottom
	self.troopsLabel = troops

	local tiles = Instance.new("TextLabel")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1
	tiles.AnchorPoint = Vector2.new(1, 0)
	tiles.Position = UDim2.new(1, -18, 0, 14)
	tiles.Size = UDim2.fromOffset(180, 26)
	tiles.FontFace = FONT
	tiles.TextSize = 18
	tiles.TextColor3 = Color3.fromRGB(150, 170, 200)
	tiles.TextXAlignment = Enum.TextXAlignment.Right
	tiles.Text = "0 territoires"
	tiles.Parent = bottom
	self.tilesLabel = tiles

	local ratioRow = Instance.new("Frame")
	ratioRow.Name = "RatioRow"
	ratioRow.BackgroundTransparency = 1
	ratioRow.Position = UDim2.fromOffset(18, 52)
	ratioRow.Size = UDim2.new(1, -36, 0, 32)
	ratioRow.Parent = bottom

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = ratioRow

	for i, value in RATIOS do
		local button = Instance.new("TextButton")
		button.Name = `Ratio{i}`
		button.LayoutOrder = i
		button.Size = UDim2.new(0.25, -6, 1, 0)
		button.BackgroundColor3 = Color3.fromRGB(38, 46, 62)
		button.BorderSizePixel = 0
		button.FontFace = FONT
		button.TextSize = 16
		button.TextColor3 = Color3.fromRGB(200, 215, 235)
		button.Text = `{math.floor(value * 100)}%`
		button.AutoButtonColor = true
		button.Parent = ratioRow
		corner(button, 8)

		button.Activated:Connect(function()
			self:setRatio(value)
			if self.onRatioChanged then
				self.onRatioChanged(value)
			end
		end)

		self.ratioButtons[i] = button
	end

	--------------------------------------------------------------------------
	-- Bandeau haut : identite + message contextuel
	--------------------------------------------------------------------------
	local top = Instance.new("Frame")
	top.Name = "TopBar"
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 14)
	top.Size = UDim2.fromOffset(420, 56)
	top.BackgroundColor3 = PANEL_COLOR
	top.BackgroundTransparency = 0.08
	top.BorderSizePixel = 0
	top.Parent = root
	corner(top, 12)
	stroke(top, Color3.fromRGB(90, 110, 140), 1.5)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(14, 6)
	nameLabel.Size = UDim2.new(1, -28, 0, 22)
	nameLabel.FontFace = FONT
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = Config.GAME_NAME
	nameLabel.Parent = top
	self.nameLabel = nameLabel

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(14, 28)
	status.Size = UDim2.new(1, -28, 0, 20)
	status.FontFace = Font.fromEnum(Enum.Font.Gotham)
	status.TextSize = 14
	status.TextColor3 = Color3.fromRGB(150, 170, 200)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Text = "Connexion..."
	status.Parent = top
	self.statusLabel = status

	--------------------------------------------------------------------------
	-- Classement : c'est lui qui cree la tension sociale, il reste visible.
	--------------------------------------------------------------------------
	local board = Instance.new("Frame")
	board.Name = "Leaderboard"
	board.AnchorPoint = Vector2.new(1, 0)
	board.Position = UDim2.new(1, -14, 0, 14)
	board.Size = UDim2.fromOffset(210, 224)
	board.BackgroundColor3 = PANEL_COLOR
	board.BackgroundTransparency = 0.15
	board.BorderSizePixel = 0
	board.Parent = root
	corner(board, 10)
	stroke(board, Color3.fromRGB(90, 110, 140), 1.5)
	self.leaderboard = board

	local boardPadding = Instance.new("UIPadding")
	boardPadding.PaddingTop = UDim.new(0, 8)
	boardPadding.PaddingLeft = UDim.new(0, 10)
	boardPadding.PaddingRight = UDim.new(0, 10)
	boardPadding.Parent = board

	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 2)
	boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boardLayout.Parent = board

	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.LayoutOrder = i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 20)
		row.FontFace = FONT
		row.TextSize = 13
		row.TextColor3 = Color3.fromRGB(200, 215, 235)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.Text = ""
		row.Parent = board
		self.leaderRows[i] = row
	end

	self:setRatio(self.ratio)
	return self
end

function HUD.setRatio(self: HUD, ratio: number)
	self.ratio = ratio
	for i, button in self.ratioButtons do
		local selected = math.abs(RATIOS[i] - ratio) < 1e-3
		button.BackgroundColor3 = if selected then Color3.fromRGB(210, 70, 60) else Color3.fromRGB(38, 46, 62)
		button.TextColor3 = if selected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(200, 215, 235)
	end
end

function HUD.setIdentity(self: HUD, slot: number, name: string)
	local color = Config.PLAYER_COLORS[((slot - 1) % #Config.PLAYER_COLORS) + 1]
	self.nameLabel.Text = name
	self.nameLabel.TextColor3 = color
end

function HUD.setStatus(self: HUD, text: string)
	self.statusLabel.Text = text
	self.statusUntil = os.clock() + 4
end

function HUD.update(self: HUD, mySlot: number, stats: Types.Stats, roster: Types.Roster)
	local mine = stats[mySlot]
	if mine then
		self.troopsLabel.Text = tostring(mine.troops)
		self.tilesLabel.Text = `{mine.tiles} territoires`
	end

	if self.statusUntil > 0 and os.clock() > self.statusUntil then
		self.statusLabel.Text = ""
		self.statusUntil = 0
	end

	local ranked = {}
	for slot, s in stats do
		table.insert(ranked, { slot = slot, tiles = s.tiles, troops = s.troops })
	end
	table.sort(ranked, function(a, b)
		if a.tiles == b.tiles then
			return a.troops > b.troops
		end
		return a.tiles > b.tiles
	end)

	for i, row in self.leaderRows do
		local entry = ranked[i]
		if entry then
			local info = roster[entry.slot]
			local name = if info then info.name else `#{entry.slot}`
			row.Text = `{i}. {name}  ·  {entry.tiles}`
			row.TextColor3 = Config.PLAYER_COLORS[((entry.slot - 1) % #Config.PLAYER_COLORS) + 1]
			-- Sa propre ligne en gras blanc : on doit se retrouver instantanement.
			if entry.slot == mySlot then
				row.Text = `▸ {row.Text}`
			end
		else
			row.Text = ""
		end
	end
end

return HUD
