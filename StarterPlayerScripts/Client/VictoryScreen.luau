--!strict
--[[
	Ecran de fin de partie.

	Une partie sans conclusion lisible ne donne pas envie d'en relancer une.
	Cet ecran doit repondre en une seconde a "qui a gagne, ou j'ai fini, et
	quand est-ce que ca recommence".

	Il est volontairement non bloquant : la carte reste visible derriere, et le
	compte a rebours vers la partie suivante est explicite.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))
local SoundManager = require(script.Parent.SoundManager)

local C = Theme.color
local S = Theme.space
local F = Theme.font
local T = Theme.textSize

local VictoryScreen = {}
VictoryScreen.__index = VictoryScreen

export type VictoryScreen = typeof(setmetatable({} :: any, VictoryScreen))

local PODIUM = 5

function VictoryScreen.new(parent: GuiObject): VictoryScreen
	local self = setmetatable({}, VictoryScreen) :: any

	local root = Instance.new("Frame")
	root.Name = "VictoryScreen"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = C.void
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Visible = false
	root.ZIndex = 30
	root.Parent = parent
	self.root = root

	local box = Theme.panel("Box", root)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(460, 108 + PODIUM * 26)
	box.ZIndex = 31
	self.box = box

	local banner = Theme.label(box, "", T.tiny, C.textFaint)
	banner.Position = UDim2.fromOffset(S.xl, S.lg)
	banner.Size = UDim2.new(1, -S.xl * 2, 0, 14)
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.ZIndex = 32
	banner.Text = "FIN DE PARTIE"
	self.banner = banner

	local winner = Theme.label(box, "", 30, C.text)
	winner.Position = UDim2.fromOffset(S.xl, S.lg + 18)
	winner.Size = UDim2.new(1, -S.xl * 2, 0, 36)
	winner.TextXAlignment = Enum.TextXAlignment.Center
	winner.FontFace = F.display
	winner.TextTruncate = Enum.TextTruncate.AtEnd
	winner.ZIndex = 32
	self.winnerLabel = winner

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(S.xl, 96)
	list.Size = UDim2.new(1, -S.xl * 2, 0, PODIUM * 26)
	list.ZIndex = 32
	list.Parent = box
	Theme.list(list, Enum.FillDirection.Vertical, S.xs)

	self.rows = {}
	for i = 1, PODIUM do
		local row = Theme.label(list, "", T.body, C.textMuted)
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 22)
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.ZIndex = 32
		self.rows[i] = row
	end

	local countdown = Theme.label(box, "", T.small, C.textFaint)
	countdown.AnchorPoint = Vector2.new(0.5, 1)
	countdown.Position = UDim2.new(0.5, 0, 1, -S.md)
	countdown.Size = UDim2.new(1, -S.xl * 2, 0, 16)
	countdown.TextXAlignment = Enum.TextXAlignment.Center
	countdown.FontFace = F.medium
	countdown.ZIndex = 32
	self.countdown = countdown

	return self
end

--[[
	Affiche le resultat. `mySlot` sert uniquement a colorer et a formuler :
	gagner et finir huitieme ne doivent pas produire le meme ecran.
]]
function VictoryScreen.show(
	self: VictoryScreen,
	winnerSlot: number?,
	winnerName: string?,
	ranked: { { slot: number, tiles: number, troops: number } },
	roster: Types.Roster,
	mySlot: number
)
	if self.root.Visible then
		return
	end

	self.root.Visible = true
	self.root.BackgroundTransparency = 1
	TweenService:Create(self.root, Theme.motion.dramatic, { BackgroundTransparency = 0.35 }):Play()

	local won = winnerSlot ~= nil and winnerSlot == mySlot

	if won then
		self.banner.Text = "VICTOIRE"
		self.banner.TextColor3 = C.gold
		self.winnerLabel.Text = "Le monde est a toi."
		self.winnerLabel.TextColor3 = C.gold
		SoundManager.play("victory")
	elseif winnerName then
		self.banner.Text = "FIN DE PARTIE"
		self.banner.TextColor3 = C.textFaint
		self.winnerLabel.Text = `{winnerName} l'emporte`
		self.winnerLabel.TextColor3 = if winnerSlot then Theme.factionColor(winnerSlot) else C.text
		SoundManager.play("defeat")
	else
		self.banner.Text = "FIN DE PARTIE"
		self.banner.TextColor3 = C.textFaint
		self.winnerLabel.Text = "Aucune domination"
		self.winnerLabel.TextColor3 = C.textMuted
	end

	for i, row in self.rows do
		local item = ranked[i]
		if not item then
			row.Text = ""
			continue
		end
		local info = roster[item.slot]
		local name = if info then info.name else `#{item.slot}`
		local mark = if item.slot == mySlot then "  \u{25C0} toi" else ""
		row.Text = `{i}.  {name}{mark}`
		row.TextColor3 = if item.slot == mySlot then C.text else Theme.factionColor(item.slot)

		-- On retire l'ancien score AVANT de creer le nouveau : les deux portent
		-- le meme nom, donc chercher "le precedent" apres coup peut tomber sur
		-- celui qu'on vient d'ajouter et l'effacer aussitot.
		local previous = row:FindFirstChild("Value")
		if previous then
			previous:Destroy()
		end

		local value = Theme.label(row, tostring(item.tiles), T.body, C.textFaint)
		value.Name = "Value"
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, 0, 0, 0)
		value.Size = UDim2.fromOffset(70, 22)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.ZIndex = 32
	end
end

function VictoryScreen.setCountdown(self: VictoryScreen, seconds: number)
	self.countdown.Text = `Nouvelle partie dans {math.max(0, math.ceil(seconds))} s`
end

function VictoryScreen.hide(self: VictoryScreen)
	if not self.root.Visible then
		return
	end
	local tween = TweenService:Create(self.root, Theme.motion.smooth, { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		self.root.Visible = false
	end)
end

return VictoryScreen
