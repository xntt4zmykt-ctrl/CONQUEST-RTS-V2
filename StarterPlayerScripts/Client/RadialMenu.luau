--!strict
--[[
	Menu radial, regle CONQUEST.

	C'est la piece qui organise toute l'interface CONQUEST, et la
	raison pour laquelle son ecran reste vide : **aucun bouton d'action n'est
	affiche en permanence**. On clique droit sur la case qu'on regarde deja, et
	les actions viennent a l'endroit ou l'oeil se trouve — au lieu d'obliger a
	faire l'aller-retour vers une barre en bas de l'ecran.

	Le gain n'est pas seulement esthetique. Un menu contextuel connait sa cible :
	il peut griser "Debarquer" sur une case interieure ou "Frapper" sur son
	propre territoire, alors qu'une barre permanente doit rester generique et
	laisse le joueur decouvrir l'erreur apres coup.

	Deux niveaux, comme dans CONQUEST : l'anneau racine porte les modes, et
	"Construire" remplace l'anneau par la liste des batiments sans fermer le
	menu ni perdre la case visee.

	Note d'implementation : Roblox ne sait pas dessiner de secteurs de disque
	sans texture. Les petales sont donc des boutons circulaires disposes sur un
	cercle par trigonometrie — la lecture est la meme, et rien a importer.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local BuildingDefs = require(Shared:WaitForChild("BuildingDefs"))
local Eras = require(Shared:WaitForChild("Eras"))

local C = Theme.color
local T = Theme.textSize
local F = Theme.font

local RadialMenu = {}
RadialMenu.__index = RadialMenu

export type RadialMenu = typeof(setmetatable({} :: any, RadialMenu))

-- Rayon du moyeu et du cercle sur lequel se posent les petales, en pixels.
local HUB_RADIUS = 26
local RING_RADIUS = 78
local PETAL_RADIUS = 25

-- Marge minimale au bord de l'ecran : un menu ouvert dans un coin doit rester
-- entierement visible, sinon la moitie de ses actions devient inatteignable.
local EDGE_MARGIN = RING_RADIUS + PETAL_RADIUS + 8

export type Context = {
	tile: number,
	-- Proprietaire de la case visee, pour griser ce qui n'a pas de sens ici.
	ownerSlot: number,
	mySlot: number,
	era: number,
	nukesUnlocked: boolean,
	-- Une offensive contre ce proprietaire est en cours : la retraite a un
	-- sens ici, et seulement ici.
	attacking: boolean,
}

type Petal = {
	button: TextButton,
	label: TextLabel,
	icon: TextLabel,
}

--=============================================================================
-- Construction
--=============================================================================

local function petal(parent: GuiObject): Petal
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromOffset(PETAL_RADIUS * 2, PETAL_RADIUS * 2)
	b.BackgroundColor3 = C.surfaceRaised
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.Visible = false
	b.Parent = parent
	Theme.corner(b, PETAL_RADIUS)
	local edge = Theme.stroke(b, C.lineGlow, 1.5)
	edge.Transparency = 0.35
	Theme.gradient(b, C.surfaceBright, C.surfaceRaised, 135)

	local icon = Theme.label(b, "", T.body, C.text)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.38)
	icon.Size = UDim2.fromOffset(PETAL_RADIUS * 2, 20)
	icon.TextXAlignment = Enum.TextXAlignment.Center

	local label = Theme.label(b, "", T.tiny, C.textMuted)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.74)
	label.Size = UDim2.fromOffset(PETAL_RADIUS * 2 - 4, 12)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.FontFace = F.medium

	return { button = b, label = label, icon = icon }
end

function RadialMenu.new(parent: Instance): RadialMenu
	local self = setmetatable({}, RadialMenu) :: any

	self.page = "root"
	self.context = nil
	self.petals = {}
	-- Action courante de chaque petale, remplacee a chaque page.
	self.actions = {}

	--[[
		Le voile plein ecran capte le clic "a cote".

		Sans lui, fermer le menu demanderait de viser le moyeu — et un clic sur
		la carte passerait au travers en declenchant une action non voulue. Il
		est transparent mais bien present.
	]]
	local veil = Instance.new("TextButton")
	veil.Name = "RadialMenu"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = C.void
	veil.BackgroundTransparency = 0.45
	veil.Text = ""
	veil.AutoButtonColor = false
	veil.Visible = false
	veil.ZIndex = 20
	veil.Parent = parent
	self.veil = veil

	veil.Activated:Connect(function()
		self:close()
	end)

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset((RING_RADIUS + PETAL_RADIUS) * 2, (RING_RADIUS + PETAL_RADIUS) * 2)
	ring.BackgroundTransparency = 1
	ring.Parent = veil
	self.ring = ring

	-- L'echelle sert a l'animation d'ouverture : le menu jaillit du point
	-- clique, ce qui rattache visuellement les actions a leur cible.
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = ring
	self.scale = scale

	--[[
		Le moyeu ferme le menu, et affiche en permanence la case visee.

		Il sert aussi de fil d'Ariane : sur la page des batiments il revient a
		l'anneau racine au lieu de tout fermer, pour qu'une erreur de navigation
		ne coute pas le clic droit.
	]]
	local hub = Instance.new("TextButton")
	hub.Name = "Hub"
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(HUB_RADIUS * 2, HUB_RADIUS * 2)
	hub.BackgroundColor3 = C.surface
	hub.BorderSizePixel = 0
	hub.AutoButtonColor = false
	hub.Text = ""
	hub.Parent = ring
	Theme.corner(hub, HUB_RADIUS)
	Theme.stroke(hub, C.accent, 1)
	self.hub = hub

	local hubIcon = Theme.label(hub, "\u{2715}", T.body, C.textMuted)
	hubIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	hubIcon.Position = UDim2.fromScale(0.5, 0.5)
	hubIcon.Size = UDim2.fromScale(1, 1)
	hubIcon.TextXAlignment = Enum.TextXAlignment.Center
	self.hubIcon = hubIcon

	hub.Activated:Connect(function()
		if self.page == "build" then
			self:showPage("root")
		else
			self:close()
		end
	end)

	-- On alloue une reserve de petales une fois pour toutes : les deux pages
	-- n'en montrent jamais plus, et recreer des boutons a chaque ouverture
	-- rendrait le menu saccade.
	local slots = math.max(6, #BuildingDefs.BUILDABLE)
	for i = 1, slots do
		local p = petal(ring)
		self.petals[i] = p

		--[[
			Connexion unique, posee une seule fois pour toute la partie.

			La version precedente reconnectait chaque petale a chaque changement
			de page — donc *depuis le gestionnaire d'un petale*, puisque "Batir"
			change de page. Selon l'ordre d'iteration des gestionnaires, le
			nouveau pouvait etre appele dans la meme diffusion que l'ancien : le
			joueur cliquait "Batir" et le premier batiment de la page suivante se
			declenchait tout seul. Ici le gestionnaire est fige et c'est la
			*donnee* qui change ; le probleme n'existe plus.
		]]
		p.button.Activated:Connect(function()
			if p.button:GetAttribute("Disabled") then
				return
			end
			local run = self.actions[i]
			if run then
				run()
			end
		end)
	end

	return self
end

--=============================================================================
-- Disposition
--=============================================================================

--[[
	Repartit n petales sur le cercle, premier au sommet puis dans le sens des
	aiguilles d'une montre.

	Le sommet est un point d'ancrage stable : quel que soit le nombre d'entrees,
	la premiere action est toujours au meme endroit, et la memoire du geste se
	construit malgre un menu qui change de contenu.
]]
local function placePetals(petals: { Petal }, count: number)
	for i, p in petals do
		if i > count then
			p.button.Visible = false
			continue
		end
		local angle = -math.pi / 2 + (i - 1) * (2 * math.pi / count)
		p.button.Position = UDim2.new(
			0.5,
			math.cos(angle) * RING_RADIUS,
			0.5,
			math.sin(angle) * RING_RADIUS
		)
		p.button.Visible = true
	end
end

local function setEnabled(p: Petal, enabled: boolean)
	p.button.BackgroundTransparency = if enabled then 0 else 0.55
	p.icon.TextTransparency = if enabled then 0 else 0.6
	p.label.TextTransparency = if enabled then 0 else 0.6
	p.button:SetAttribute("Disabled", not enabled)
end

--=============================================================================
-- Pages
--=============================================================================

function RadialMenu.showPage(self: RadialMenu, page: string)
	self.page = page
	self.hubIcon.Text = if page == "build" then "\u{2190}" else "\u{2715}"

	local ctx: Context? = self.context
	if not ctx then
		return
	end
	local context = ctx :: Context

	local entries: { { icon: string, label: string, enabled: boolean, run: () -> () } } = {}

	if page == "root" then
		local foreign = context.ownerSlot ~= context.mySlot
		local owned = context.ownerSlot == context.mySlot

		table.insert(entries, {
			icon = "\u{2694}",
			label = "Attaquer",
			enabled = foreign,
			run = function()
				self:emit("attack")
			end,
		})
		table.insert(entries, {
			icon = "\u{1F3D7}",
			label = "Batir",
			enabled = owned,
			run = function()
				self:showPage("build")
			end,
		})
		table.insert(entries, {
			icon = "\u{26F5}",
			label = "Debarquer",
			enabled = foreign,
			run = function()
				self:emit("boat")
			end,
		})
		table.insert(entries, {
			icon = "\u{2622}",
			label = "Frapper",
			enabled = foreign and context.ownerSlot ~= 0 and context.nukesUnlocked,
			run = function()
				self:emit("nuke")
			end,
		})
		table.insert(entries, {
			icon = "\u{1F5FA}",
			label = "Inspecter",
			enabled = true,
			run = function()
				self:emit("inspect")
			end,
		})
		table.insert(entries, {
			icon = "\u{1F3F3}",
			label = "Rappeler",
			enabled = foreign and context.attacking,
			run = function()
				self:emit("retreat")
			end,
		})
	else
		for _, def in BuildingDefs.BUILDABLE do
			local required = Eras.requiredFor(def.id)
			table.insert(entries, {
				icon = def.symbol,
				label = def.name,
				enabled = context.era >= required,
				run = function()
					self:emitBuild(def.id)
				end,
			})
		end
	end

	placePetals(self.petals, #entries)

	table.clear(self.actions)
	for i, entry in entries do
		local p = self.petals[i]
		p.icon.Text = entry.icon
		p.label.Text = entry.label
		setEnabled(p, entry.enabled)
		self.actions[i] = entry.run
	end
end

--=============================================================================
-- Ouverture et fermeture
--=============================================================================

function RadialMenu.open(self: RadialMenu, screenX: number, screenY: number, context: Context)
	self.context = context

	local viewport = self.veil.AbsoluteSize
	local x = math.clamp(screenX, EDGE_MARGIN, math.max(EDGE_MARGIN, viewport.X - EDGE_MARGIN))
	local y = math.clamp(screenY, EDGE_MARGIN, math.max(EDGE_MARGIN, viewport.Y - EDGE_MARGIN))
	self.ring.Position = UDim2.fromOffset(x, y)

	self.veil.Visible = true
	self:showPage("root")

	-- Le menu jaillit du point clique. Court : une ouverture lente sur un geste
	-- repete des centaines de fois par partie devient vite penible.
	self.scale.Scale = 0.72
	TweenService:Create(self.scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

function RadialMenu.close(self: RadialMenu)
	self.veil.Visible = false
	self.context = nil
	self.page = "root"
end

function RadialMenu.isOpen(self: RadialMenu): boolean
	return self.veil.Visible
end

--=============================================================================
-- Sorties
--=============================================================================

function RadialMenu.emit(self: RadialMenu, action: string)
	local context = self.context
	self:close()
	if context and self.onAction then
		self.onAction(action, context.tile)
	end
end

function RadialMenu.emitBuild(self: RadialMenu, kind: number)
	local context = self.context
	self:close()
	if context and self.onBuild then
		self.onBuild(kind, context.tile)
	end
end

function RadialMenu.destroy(self: RadialMenu)
	self.veil:Destroy()
end

return RadialMenu
