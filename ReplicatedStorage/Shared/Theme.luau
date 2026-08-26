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

--[[
	Palette CONQUEST (Blackline Studio) : gris ardoise pour les surfaces, bleu
	vif pour l'action, bleu secondaire pour l'information.

	Les noms de jetons ne changent pas : seules les valeurs bougent, donc
	aucun ecran n'a a etre reecrit pour suivre le nouveau style.
]]
Theme.color = {
	-- Fonds, du plus profond au plus clair
	void = Color3.fromRGB(3, 7, 18), -- derriere la carte (gray-950)
	surface = Color3.fromRGB(31, 41, 55), -- panneaux (gray-800, pose a 92 %)
	surfaceRaised = Color3.fromRGB(55, 65, 81), -- boutons, lignes (gray-700)
	surfaceHover = Color3.fromRGB(75, 85, 99), -- survol (gray-600)
	surfaceBright = Color3.fromRGB(107, 114, 128), -- (gray-500)
	glass = Color3.fromRGB(17, 24, 39), -- rails de jauge (gray-900)

	-- Bordures
	line = Color3.fromRGB(75, 85, 99), -- gray-600
	lineStrong = Color3.fromRGB(100, 116, 139), -- slate-500

	-- Texte
	text = Color3.fromRGB(255, 255, 255),
	textMuted = Color3.fromRGB(209, 213, 219), -- gray-300
	textFaint = Color3.fromRGB(156, 163, 175), -- gray-400

	-- Accents semantiques
	accent = Color3.fromRGB(0, 132, 209), -- malibu : action active, selection
	accentSoft = Color3.fromRGB(14, 78, 126), -- malibu assombri : fonds actifs
	gold = Color3.fromRGB(250, 204, 21), -- yellow-400 : ressource
	ally = Color3.fromRGB(74, 222, 128), -- green-400 : diplomatie positive
	danger = Color3.fromRGB(248, 113, 113), -- red-400
	warning = Color3.fromRGB(251, 146, 60), -- orange-400
	info = Color3.fromRGB(63, 169, 245), -- aquarius : information, troupes
	nuclear = Color3.fromRGB(163, 230, 53), -- lime-400
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
