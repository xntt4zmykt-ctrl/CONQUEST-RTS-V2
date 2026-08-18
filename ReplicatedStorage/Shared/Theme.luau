--!strict
--[[
	Jetons de design.

	Toute valeur visuelle repetee vit ici : couleurs, espacements, tailles de
	texte, durees d'animation. Aucun nombre magique de style ne doit apparaitre
	dans les fichiers d'interface — sinon l'ensemble derive et l'ecran finit par
	avoir six gris legerement differents.

	L'echelle typographique et l'echelle d'espacement sont volontairement
	courtes : moins de choix possibles, plus de coherence.
]]

local Theme = {}

--=============================================================================
-- Couleurs
--=============================================================================

Theme.color = {
	-- Fonds, du plus profond au plus clair
	void = Color3.fromRGB(5, 9, 16), -- derriere la carte
	surface = Color3.fromRGB(10, 17, 28), -- panneaux
	surfaceRaised = Color3.fromRGB(18, 29, 45), -- boutons, lignes
	surfaceHover = Color3.fromRGB(28, 48, 68),
	surfaceBright = Color3.fromRGB(36, 58, 77),
	glass = Color3.fromRGB(8, 15, 25),

	-- Bordures
	line = Color3.fromRGB(47, 72, 93),
	lineStrong = Color3.fromRGB(92, 136, 155),

	-- Texte
	text = Color3.fromRGB(239, 247, 250),
	textMuted = Color3.fromRGB(156, 183, 194),
	textFaint = Color3.fromRGB(101, 132, 146),

	-- Accents semantiques
	accent = Color3.fromRGB(45, 194, 177), -- identite Blackline / action active
	accentSoft = Color3.fromRGB(24, 92, 93),
	gold = Color3.fromRGB(246, 193, 77), -- ressource
	ally = Color3.fromRGB(86, 218, 153), -- diplomatie positive
	danger = Color3.fromRGB(255, 94, 91),
	warning = Color3.fromRGB(255, 180, 69),
	info = Color3.fromRGB(102, 178, 242),
	nuclear = Color3.fromRGB(195, 255, 119),
}

--=============================================================================
-- Espacement
--=============================================================================
-- Echelle de 4 px. Utiliser exclusivement ces valeurs.

Theme.space = {
	xs = 4,
	sm = 8,
	md = 12,
	lg = 16,
	xl = 24,
}

-- Rayons plus serres : un grand arrondi sur un petit panneau fait "application
-- mobile gratuite". Les interfaces de strategie sont anguleuses.
Theme.radius = {
	sm = 6,
	md = 8,
	lg = 12,
	pill = 999,
}

--=============================================================================
-- Typographie
--=============================================================================

Theme.font = {
	display = Font.fromEnum(Enum.Font.GothamBlack), -- chiffres vedettes
	bold = Font.fromEnum(Enum.Font.GothamBold),
	medium = Font.fromEnum(Enum.Font.GothamMedium),
	regular = Font.fromEnum(Enum.Font.Gotham),
}

--[[
	Echelle typographique resserree.

	Les tailles precedentes (hero 34, body 14) donnaient une interface qui
	mangeait un tiers de l'ecran et faisait, de l'aveu du testeur, "cheap".
	Une interface de strategie doit etre dense : beaucoup d'information, petits
	caracteres, hierarchie portee par le contraste et la graisse plutot que par
	la taille.
]]
Theme.textSize = {
	hero = 28, -- compteur de troupes
	title = 15,
	body = 13,
	small = 11,
	tiny = 10,
}

--=============================================================================
-- Animation
--=============================================================================
-- Trois durees seulement. Les transitions d'interface doivent etre percues
-- comme instantanees : au-dela de ~200 ms, le jeu parait mou.

Theme.motion = {
	instant = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	quick = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	smooth = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	dramatic = TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

--=============================================================================
-- Helpers d'instanciation
--=============================================================================

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
	s.Transparency = 0.18
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

--[[
	Panneau standard : fond sombre translucide, coin arrondi, liseré discret.
	C'est la brique de base de toute l'interface.
]]
function Theme.panel(name: string, parent: GuiObject): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Theme.color.surface
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.corner(frame, Theme.radius.md)
	local stroke = Theme.stroke(frame, Theme.color.line, 1)
	frame:SetAttribute("PanelStroke", true)
	stroke.Transparency = 0.22
	return frame
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

--=============================================================================
-- Couleurs de faction
--=============================================================================

local Config = require(script.Parent.Config)

function Theme.factionColor(slot: number): Color3
	if slot <= 0 then
		return Color3.fromRGB(168, 178, 194)
	end
	return Config.PLAYER_COLORS[((slot - 1) % #Config.PLAYER_COLORS) + 1]
end

return Theme
