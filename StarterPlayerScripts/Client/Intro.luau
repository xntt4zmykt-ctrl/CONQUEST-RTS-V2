--!strict
--[[
	Ecran de chargement et compte a rebours d'ouverture.

	Le monde 3D se construit en une soixantaine de frames (voir WorldRenderer) :
	sans cet ecran, le joueur voit un vide bleu se remplir par morceaux, ce qui
	donne l'impression que le jeu est casse plutot qu'en train de charger.

	Le compte a rebours qui suit sert a autre chose : il donne le temps de
	regarder sa position de depart avant que la partie ne demarre. Sans lui, on
	est jete dans une carte inconnue en pleine expansion.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Nations = require(Shared:WaitForChild("Nations"))
local SoundManager = require(script.Parent.SoundManager)

local C = Theme.color
local F = Theme.font
local T = Theme.textSize

local Intro = {}
Intro.__index = Intro

export type Intro = typeof(setmetatable({} :: any, Intro))

local TIPS = {
	"Les troupes engagees dans une offensive ne defendent plus ton territoire.",
	"Un empire compact se defend mieux qu'un empire etale : la densite compte.",
	"Rompre une alliance est public et permanent. Ta reputation te suit.",
	"Un port ouvre les routes commerciales — et l'embargo coupe celles des autres.",
	"Perdre sa capitale coute la moitie de son armee.",
	"Les laboratoires reduisent le cout de chaque ere. Investis tot.",
	"Une batterie SAM rend une frappe incertaine : la menace vaut souvent le tir.",
	"Espace recentre la vue sur ta capitale. F te fait descendre dans ton avatar.",
}

function Intro.new(parent: ScreenGui): Intro
	local self = setmetatable({}, Intro) :: any
	self.transitionId = 0

	-- CanvasGroup : voir MainMenu. Le fondu par enfant laissait l'ecran de
	-- chargement noir et vide a la deuxieme partie.
	local root = Instance.new("CanvasGroup")
	root.Name = "Intro"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = C.void
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Visible = false
	root.GroupTransparency = 0
	root.ZIndex = 40
	root.Parent = parent
	self.root = root

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = C.void
	backdrop.BackgroundTransparency = 0.08
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 40
	backdrop.Parent = root

	local card = Theme.panel("DeploymentCard", root)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.44)
	card.Size = UDim2.fromOffset(560, 330)
	card.BackgroundTransparency = 0.04
	card.ZIndex = 40

	local eyebrow = Theme.label(root, "BLACKLINE STUDIO  /  THEATRE OF OPERATIONS", T.tiny, C.accent)
	eyebrow.AnchorPoint = Vector2.new(0.5, 0)
	eyebrow.Position = UDim2.new(0.5, 0, 0.21, 0)
	eyebrow.Size = UDim2.fromOffset(560, 14)
	eyebrow.TextXAlignment = Enum.TextXAlignment.Center
	eyebrow.FontFace = Theme.font.medium
	eyebrow.ZIndex = 41

	local flagFrame = Instance.new("Frame")
	flagFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	flagFrame.Position = UDim2.fromScale(0.5, 0.34)
	flagFrame.Size = UDim2.fromOffset(150, 94)
	flagFrame.BackgroundColor3 = C.surface
	flagFrame.BorderSizePixel = 0
	flagFrame.ClipsDescendants = true
	flagFrame.ZIndex = 41
	flagFrame.Parent = root
	Theme.corner(flagFrame, Theme.radius.sm)
	self.flagFrame = flagFrame

	local nation = Theme.label(root, "", 26, C.text)
	nation.AnchorPoint = Vector2.new(0.5, 0)
	nation.Position = UDim2.new(0.5, 0, 0.34, 66)
	nation.Size = UDim2.fromOffset(500, 32)
	nation.TextXAlignment = Enum.TextXAlignment.Center
	nation.FontFace = F.display
	nation.ZIndex = 41
	self.nationLabel = nation

	local status = Theme.label(root, "Construction du monde...", T.body, C.textMuted)
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0.34, 106)
	status.Size = UDim2.fromOffset(500, 18)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.FontFace = F.medium
	status.ZIndex = 41
	self.status = status

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0.34, 136)
	track.Size = UDim2.fromOffset(360, 6)
	track.BackgroundColor3 = C.surfaceRaised
	track.BorderSizePixel = 0
	track.ZIndex = 41
	track.Parent = root
	Theme.corner(track, Theme.radius.pill)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.accent
	fill.BorderSizePixel = 0
	fill.ZIndex = 42
	fill.Parent = track
	Theme.corner(fill, Theme.radius.pill)
	self.fill = fill

	local tip = Theme.label(root, "", T.small, C.textFaint)
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Position = UDim2.new(0.5, 0, 1, -40)
	tip.Size = UDim2.fromOffset(560, 18)
	tip.TextXAlignment = Enum.TextXAlignment.Center
	tip.FontFace = F.medium
	tip.ZIndex = 41
	self.tip = tip

	local footer = Theme.label(root, "SYNCHRONISATION DES FORCES  ·  CARTE PROCEDURALE  ·  SECURE LINK", T.tiny, C.textFaint)
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -18)
	footer.Size = UDim2.fromOffset(700, 14)
	footer.TextXAlignment = Enum.TextXAlignment.Center
	footer.FontFace = Theme.font.medium
	footer.ZIndex = 41

	-- Compte a rebours, superpose au meme calque
	local countdown = Theme.label(root, "", 96, C.text)
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = UDim2.fromScale(0.5, 0.5)
	countdown.Size = UDim2.fromOffset(300, 120)
	countdown.TextXAlignment = Enum.TextXAlignment.Center
	countdown.FontFace = F.display
	countdown.Visible = false
	countdown.ZIndex = 45
	countdown.Parent = parent
	self.countdown = countdown

	return self
end

--=============================================================================
-- Chargement
--=============================================================================

function Intro.show(self: Intro, nationId: number)
	local nation = Nations.get(nationId)
	self.transitionId += 1
	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween = nil
	end
	self.root.Visible = true
	self.root.GroupTransparency = 0
	self.countdown.Visible = false
	self.nationLabel.Text = string.upper(nation.name)
	self.tip.Text = TIPS[math.random(1, #TIPS)]
	self.fill.Size = UDim2.fromScale(0, 1)
	self.status.Text = "Construction du monde..."

	-- Le drapeau est dessine par MainMenu : on reutilise la meme fonction pour
	-- garantir qu'un drapeau choisi au menu est exactement celui affiche ici.
	local MainMenu = require(script.Parent.MainMenu)
	MainMenu.drawFlag(self.flagFrame, nation.flag)
end

function Intro.setProgress(self: Intro, ratio: number)
	self.fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	if ratio >= 1 then
		self.status.Text = "Deploiement des forces..."
	end
end

function Intro.hide(self: Intro)
	self.transitionId += 1
	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween = nil
	end
	-- Cet ecran est un verrou de chargement, pas une decoration : il doit
	-- disparaitre immediatement, meme si Roblox interrompt un tween ou si une
	-- nouvelle partie arrive pendant le compte a rebours.
	self.root.GroupTransparency = 1
	self.root.Visible = false
	self.countdown.Visible = false
end

--=============================================================================
-- Compte a rebours
--=============================================================================

--[[
	Compte a rebours d'ouverture. Chaque chiffre apparait grand puis se
	retracte : le mouvement fait la difference entre un minuteur et un depart.
]]
function Intro.runCountdown(self: Intro, seconds: number, onFinished: () -> ())
	local transition = self.transitionId
	task.spawn(function()
		for remaining = seconds, 1, -1 do
			if self.transitionId ~= transition then
				self.countdown.Visible = false
				return
			end
			self.countdown.Visible = true
			self.countdown.Text = tostring(remaining)
			self.countdown.TextColor3 = if remaining <= 3 then C.accent else C.text
			self.countdown.TextTransparency = 0
			self.countdown.Size = UDim2.fromOffset(420, 160)

			SoundManager.play("uiSelect")
			TweenService:Create(self.countdown, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(300, 120),
			}):Play()

			task.wait(1)
		end
		if self.transitionId ~= transition then
			self.countdown.Visible = false
			return
		end

		self.countdown.Text = "EN GUERRE"
		self.countdown.TextColor3 = C.accent
		self.countdown.Size = UDim2.fromOffset(520, 160)
		SoundManager.play("eraAdvance")
		TweenService:Create(self.countdown, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			Size = UDim2.fromOffset(700, 200),
		}):Play()

		task.wait(0.9)
		if self.transitionId ~= transition then
			self.countdown.Visible = false
			return
		end
		self.countdown.Visible = false
		onFinished()
	end)
end

Intro.COUNTDOWN_SECONDS = 5

return Intro
