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

-- N173 : recycle les TextLabel Value du podium. Distinct previewFree (N172,
-- tuiles miniature). Distinct flagFree (N171, bandes drapeau). Distinct
-- chatFree (N170, catalogue HUD). Distinct feedFree (N167, fil notify).
-- Name = "Value" obligatoire (FindFirstChild contrat). Parent = row
-- (self.rows[i]), pas self.box / hud.feed / featuredPreview. Pas de
-- UICorner / UIStroke (Value n'en a pas). Pas visual V110 (ne pas
-- merger 9726). Distinct leftover N152 flame.
local valueFree: { TextLabel } = {}
VictoryScreen.valueFree = valueFree

local function parkValue(row: GuiObject)
	local previous = row:FindFirstChild("Value")
	if previous and previous:IsA("TextLabel") then
		if previous.Parent then
			previous.Parent = nil
		end
		valueFree[#valueFree + 1] = previous :: TextLabel
	end
end

local function takeValue(row: GuiObject, text: string): TextLabel
	local n = #valueFree
	local value: TextLabel
	if n > 0 then
		value = valueFree[n]
		valueFree[n] = nil
		value.Text = text
		value.TextColor3 = C.textFaint
		value.TextSize = T.body
		value.FontFace = F.bold
		value.BackgroundTransparency = 1
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, 0, 0, 0)
		value.Size = UDim2.fromOffset(70, 22)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.ZIndex = 32
		value.Name = "Value"
		value.Parent = row
	else
		value = Theme.label(row, text, T.body, C.textFaint)
		value.Name = "Value"
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, 0, 0, 0)
		value.Size = UDim2.fromOffset(70, 22)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.ZIndex = 32
	end
	return value
end

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
	box.Size = UDim2.fromOffset(620, 390)
	box.ZIndex = 31
	self.box = box

	local accent = Instance.new("Frame")
	accent.Position = UDim2.fromOffset(S.xl, 0)
	accent.Size = UDim2.new(1, -S.xl * 2, 0, 3)
	accent.BackgroundColor3 = C.gold
	accent.BorderSizePixel = 0
	accent.ZIndex = 33
	accent.Parent = box

	local section = Theme.label(box, "BILAN DE CAMPAGNE", T.tiny, C.gold)
	section.Position = UDim2.fromOffset(S.xl, S.lg)
	section.Size = UDim2.new(1, -S.xl * 2, 0, 14)
	section.TextXAlignment = Enum.TextXAlignment.Center
	section.FontFace = F.medium
	section.ZIndex = 32

	local banner = Theme.label(box, "", T.tiny, C.textFaint)
	banner.Position = UDim2.fromOffset(S.xl, S.lg + 18)
	banner.Size = UDim2.new(1, -S.xl * 2, 0, 14)
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.ZIndex = 32
	banner.Text = "FIN DE PARTIE"
	self.banner = banner

	local winner = Theme.label(box, "", 30, C.text)
	winner.Position = UDim2.fromOffset(S.xl, S.lg + 34)
	winner.Size = UDim2.new(1, -S.xl * 2, 0, 36)
	winner.TextXAlignment = Enum.TextXAlignment.Center
	winner.FontFace = F.display
	winner.TextTruncate = Enum.TextTruncate.AtEnd
	winner.ZIndex = 32
	self.winnerLabel = winner

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(S.xl, 112)
	list.Size = UDim2.fromOffset(260, PODIUM * 24)
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

	local divider = Instance.new("Frame")
	divider.Position = UDim2.fromOffset(309, 112)
	divider.Size = UDim2.fromOffset(1, 124)
	divider.BackgroundColor3 = C.line
	divider.BackgroundTransparency = 0.35
	divider.BorderSizePixel = 0
	divider.ZIndex = 32
	divider.Parent = box

	local recapTitle = Theme.label(box, "TA CAMPAGNE", T.tiny, C.accent)
	recapTitle.Position = UDim2.fromOffset(330, 112)
	recapTitle.Size = UDim2.fromOffset(250, 14)
	recapTitle.FontFace = F.bold
	recapTitle.ZIndex = 32

	self.statLabels = {}
	local statNames = { "Territoires conquis", "Capitales prises", "Batiments fondes", "Offensives lancees" }
	for i, statName in statNames do
		local stat = Theme.label(box, statName, T.small, C.textMuted)
		stat.Position = UDim2.fromOffset(330, 132 + (i - 1) * 24)
		stat.Size = UDim2.fromOffset(250, 18)
		stat.ZIndex = 32

		local value = Theme.label(stat, "0", T.small, C.text)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, 0, 0, 0)
		value.Size = UDim2.fromOffset(70, 18)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.FontFace = F.bold
		value.ZIndex = 33
		self.statLabels[i] = value
	end

	local titleEarned = Theme.label(box, "", 20, C.gold)
	titleEarned.Position = UDim2.fromOffset(S.xl, 258)
	titleEarned.Size = UDim2.new(1, -S.xl * 2, 0, 24)
	titleEarned.TextXAlignment = Enum.TextXAlignment.Center
	titleEarned.FontFace = F.display
	titleEarned.ZIndex = 32
	self.titleEarned = titleEarned

	local profile = Theme.label(box, "", T.body, C.textMuted)
	profile.Position = UDim2.fromOffset(S.xl, 289)
	profile.Size = UDim2.new(1, -S.xl * 2, 0, 20)
	profile.TextXAlignment = Enum.TextXAlignment.Center
	profile.FontFace = F.medium
	profile.ZIndex = 32
	self.profileLabel = profile

	local countdown = Theme.label(box, "", T.small, C.textFaint)
	countdown.AnchorPoint = Vector2.new(0.5, 1)
	countdown.Position = UDim2.new(0.5, 0, 1, -S.lg)
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
	mySlot: number,
	summary: Types.Stats?,
	profile: Types.Profile?
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
			-- N173 : ligne vide — parker Value s'il existe, sinon un score
			-- fantôme survit. Pas Destroy. Pas de parcours de self.box.
			parkValue(row)
			continue
		end
		local info = roster[item.slot]
		local name = if info then info.name else `#{item.slot}`
		local mark = if item.slot == mySlot then "  \u{25C0} toi" else ""
		row.Text = `{i}.  {name}{mark}`
		row.TextColor3 = if item.slot == mySlot then C.text else Theme.factionColor(item.slot)

		-- N173 : Parent = nil + push valueFree. Pas Destroy. On parque
		-- AVANT de reprendre : les deux portent le meme Name, donc
		-- chercher "le precedent" apres coup peut tomber sur celui
		-- qu'on vient d'ajouter. Reset Text / TextXAlignment / Name.
		-- Distinct N172 previewFree. Distinct leftover N152 flame.
		parkValue(row)
		takeValue(row, tostring(item.tiles))
	end

	local mine = if summary then summary[mySlot] else nil
	local values = {
		if mine then mine.capturedTiles or 0 else 0,
		if mine then mine.capitalsCaptured or 0 else 0,
		if mine then mine.buildingsBuilt or 0 else 0,
		if mine then mine.attacksLaunched or 0 else 0,
	}
	for i, value in values do
		self.statLabels[i].Text = tostring(value)
	end

	local title = "Bâtisseur de nation"
	if won then
		title = "Souverain du monde"
	elseif values[2] >= 2 then
		title = "Briseur de couronnes"
	elseif values[3] >= 6 then
		title = "Grand architecte"
	elseif values[4] >= 5 then
		title = "Marechal de campagne"
	elseif values[1] >= 150 then
		title = "Conquerant"
	end
	self.titleEarned.Text = `TITRE  ·  {string.upper(title)}`
	self:setProfile(profile)
end

function VictoryScreen.setProfile(self: VictoryScreen, profile: Types.Profile?)
	if not profile then
		return
	end
	local gain = if profile.lastGain and profile.lastGain > 0 then `  ·  +{profile.lastGain} XP` else ""
	self.profileLabel.Text = `Niveau {profile.level}  ·  {profile.xp} XP{gain}`
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
