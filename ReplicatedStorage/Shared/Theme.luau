--!strict
--[[
	Jetons de design CONQUEST — palette premium sombre, surfaces vitrees,
	accents lumineux. Toute valeur visuelle repetee vit ici.
]]

local Theme = {}

Theme.color = {
	void = Color3.fromRGB(6, 10, 20),
	surface = Color3.fromRGB(18, 24, 38),
	surfaceRaised = Color3.fromRGB(28, 36, 54),
	surfaceHover = Color3.fromRGB(42, 52, 72),
	surfaceBright = Color3.fromRGB(58, 68, 88),
	glass = Color3.fromRGB(12, 18, 30),

	line = Color3.fromRGB(58, 72, 96),
	lineStrong = Color3.fromRGB(88, 108, 132),
	lineGlow = Color3.fromRGB(56, 189, 248),

	text = Color3.fromRGB(248, 250, 252),
	textMuted = Color3.fromRGB(203, 213, 225),
	textFaint = Color3.fromRGB(148, 163, 184),

	accent = Color3.fromRGB(56, 189, 248),
	accentSoft = Color3.fromRGB(12, 74, 110),
	accentGlow = Color3.fromRGB(125, 211, 252),
	gold = Color3.fromRGB(250, 204, 21),
	goldSoft = Color3.fromRGB(180, 130, 20),
	ally = Color3.fromRGB(52, 211, 153),
	danger = Color3.fromRGB(248, 113, 113),
	warning = Color3.fromRGB(251, 146, 60),
	info = Color3.fromRGB(96, 165, 250),
	nuclear = Color3.fromRGB(163, 230, 53),
	construct = Color3.fromRGB(255, 200, 120),
}

Theme.space = {
	xs = 4,
	sm = 8,
	md = 12,
	lg = 16,
	xl = 24,
}

Theme.radius = {
	sm = 6,
	md = 10,
	lg = 14,
	pill = 999,
}

Theme.font = {
	display = Font.fromEnum(Enum.Font.GothamBlack),
	bold = Font.fromEnum(Enum.Font.GothamBold),
	medium = Font.fromEnum(Enum.Font.GothamMedium),
	regular = Font.fromEnum(Enum.Font.Gotham),
}

Theme.textSize = {
	hero = 30,
	title = 16,
	body = 13,
	small = 11,
	tiny = 10,
}

Theme.motion = {
	instant = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	quick = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	smooth = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	dramatic = TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

function Theme.corner(parent: GuiObject, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function Theme.stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.color.line
	s.Thickness = thickness or 1
	s.Transparency = 0.12
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Theme.padding(parent: GuiObject, amount: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, amount)
	p.PaddingBottom = UDim.new(0, amount)
	p.PaddingLeft = UDim.new(0, amount)
	p.PaddingRight = UDim.new(0, amount)
	p.Parent = parent
	return p
end

function Theme.list(parent: GuiObject, direction: Enum.FillDirection, gap: number): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

function Theme.gradient(parent: GuiObject, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(1, bottom),
	})
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

function Theme.panel(name: string, parent: GuiObject): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Theme.color.surface
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.corner(frame, Theme.radius.md)
	local stroke = Theme.stroke(frame, Theme.color.line, 1)
	frame:SetAttribute("PanelStroke", true)
	stroke.Transparency = 0.18
	Theme.gradient(frame, Color3.fromRGB(36, 46, 66), Theme.color.surface, 90)
	return frame
end

function Theme.glassPanel(name: string, parent: GuiObject): Frame
	local frame = Theme.panel(name, parent)
	frame.BackgroundTransparency = 0.22
	for _, child in frame:GetChildren() do
		if child.ClassName == "UIStroke" then
			child.Color = Theme.color.lineGlow
			child.Transparency = 0.55
			break
		end
	end
	return frame
end

function Theme.accentBar(parent: GuiObject, color: Color3?): Frame
	local bar = Instance.new("Frame")
	bar.Name = "AccentBar"
	bar.BackgroundColor3 = color or Theme.color.accent
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 0, 2)
	bar.Position = UDim2.fromScale(0, 0)
	bar.ZIndex = 2
	bar.Parent = parent
	Theme.gradient(bar, Theme.color.accentGlow, color or Theme.color.accent, 0)
	return bar
end

function Theme.label(parent: GuiObject, text: string, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = Theme.font.bold
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local Config = require(script.Parent.Config)

function Theme.factionColor(slot: number): Color3
	if slot <= 0 then
		return Color3.fromRGB(168, 178, 194)
	end
	return Config.PLAYER_COLORS[((slot - 1) % #Config.PLAYER_COLORS) + 1]
end

return Theme
