--!strict
--[[
	Effets de conquete.

	Le probleme qu'ils resolvent : prendre du territoire etait invisible. Les
	tuiles changeaient de couleur au prochain rafraichissement de chunk, sans
	transition ni bruit, et le moment central du jeu — arracher du terrain a une
	autre nation — ne produisait aucune sensation.

	Trois couches se superposent, du plus local au plus global :

	  1. **Eclat de tuile** — une plaque lumineuse sur chaque case prise, qui
	     s'eleve et s'efface. C'est ce qui donne la texture du front qui avance.
	  2. **Onde de conquete** — un anneau au barycentre de la vague, dimensionne
	     sur son ampleur. Il attire l'oeil au bon endroit sans qu'on ait a
	     surveiller la carte.
	  3. **Texte flottant** — le nombre de tuiles gagnees, une seule fois par
	     vague. Le chiffre transforme une impression en resultat.

	Toutes les couches sont **plafonnees**. Une offensive prend des centaines de
	tuiles par seconde ; sans plafond, ce module creerait plus d'instances que
	le terrain lui-meme.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))

local Effects = {}
Effects.__index = Effects

export type Effects = typeof(setmetatable({} :: any, Effects))

-- Au-dela, les eclats se chevauchent et ne se lisent plus de toute facon.
local MAX_FLASHES_PER_WAVE = 28
local MAX_LIVE_FLASHES = 90
local MAX_LIVE_PULSES = 8

function Effects.new(parent: Instance, terrain: buffer): Effects
	local self = setmetatable({}, Effects) :: any

	self.terrain = terrain
	self.live = 0
	self.livePulses = 0

	local root = Instance.new("Folder")
	root.Name = "Effects"
	root.Parent = parent
	self.root = root

	-- V82 : rotation cylindre plat cuite une fois (recette V75 footprintRot /
	-- V78 wakeRot / feel N134). Plus de CFrame.Angles a chaque onde de
	-- conquete. fromEulerAnglesYXZ(0, 0, rad(90)) ≡ Angles(0, 0, 90°)
	-- (rx=0, ry=0 → Z seul). Height = surface + 0.8 (fallback 3 hors carte)
	-- inchange — ne pas porter Y = 3 feel. Tween Size/Transparency inchange.
	-- MAX_LIVE_PULSES=8 inchange. Distinct de Overlay Shockwave (V81,
	-- PLAINS + 0.5). V83 : SelectionRing reutilise le meme pulseRot
	-- (geste selectTile, height = surface + 0.48, pas +0.8).
	self.pulseRot = CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))

	return self
end

--=============================================================================
-- Selection tactique
--=============================================================================

function Effects.selectTile(self: Effects, index: number, color: Color3)
	if self.selection then
		self.selection:Destroy()
	end

	local base = WorldSpace.indexToWorld(index)
	local height = WorldSpace.surfaceHeight(self.terrain, index)
	local marker = Instance.new("Part")
	marker.Name = "SelectedTerritory"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Color = color
	marker.Transparency = 0.32
	marker.Size = Vector3.new(Config.TILE_SIZE * 1.22, 0.32, Config.TILE_SIZE * 1.22)
	marker.CFrame = CFrame.new(base.X, height + 0.58, base.Z)
	marker.Parent = self.root
	self.selection = marker

	local ring = Instance.new("Part")
	ring.Name = "SelectionRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.55
	ring.Size = Vector3.new(0.2, Config.TILE_SIZE * 1.5, Config.TILE_SIZE * 1.5)
	-- V83 : translation * pulseRot (V82). Plus de CFrame.Angles a la
	-- selection. Height = surfaceHeight sans +0.8, puis + 0.48 inchange.
	-- Name SelectionRing inchange. Tweens Transparency/Size inchanges.
	-- Marker SelectedTerritory inchange (translation seule). Distinct de
	-- V82 (onde, surface+0.8, Name=ConquestPulse). Distinct de V81
	-- (explosion Overlay, PLAINS + 0.5). Distinct de ActionPreview
	-- (pas de cylindre). Geste joueur, pas 60 Hz. Recette V82 pulseRot
	-- — ne pas merger feel bfcc, ne pas inventer selectionRot.
	ring.CFrame = CFrame.new(base.X, height + 0.48, base.Z) * self.pulseRot
	ring.Parent = self.root
	self.selectionRing = ring

	TweenService:Create(marker, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.62,
	}):Play()
	TweenService:Create(ring, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.78,
		Size = Vector3.new(0.2, Config.TILE_SIZE * 1.75, Config.TILE_SIZE * 1.75),
	}):Play()
end

function Effects.clearSelection(self: Effects)
	if self.selection then
		self.selection:Destroy()
		self.selection = nil
	end
	if self.selectionRing then
		self.selectionRing:Destroy()
		self.selectionRing = nil
	end
end

-- Apercu leger de l'action sous le curseur. Contrairement a `selectTile`, ce
-- marqueur est reutilise et simplement deplace : le raycast tourne chaque
-- frame, il ne doit donc jamais creer une Part par mouvement de souris.
function Effects.previewTile(self: Effects, index: number, color: Color3, valid: boolean)
	local marker = self.actionPreview
	if not marker then
		marker = Instance.new("Part")
		marker.Name = "ActionPreview"
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.CastShadow = false
		marker.Material = Enum.Material.Neon
		marker.Size = Vector3.new(Config.TILE_SIZE * 1.04, 0.18, Config.TILE_SIZE * 1.04)
		marker.Parent = self.root
		self.actionPreview = marker
	end

	local base = WorldSpace.indexToWorld(index)
	local height = WorldSpace.surfaceHeight(self.terrain, index)
	marker.Color = color
	marker.Transparency = if valid then 0.5 else 0.72
	marker.CFrame = CFrame.new(base.X, height + 0.42, base.Z)
	self.actionPreviewIndex = index
end

function Effects.clearActionPreview(self: Effects)
	if self.actionPreview then
		self.actionPreview:Destroy()
		self.actionPreview = nil
		self.actionPreviewIndex = nil
	end
end

--=============================================================================
-- Eclat de tuile
--=============================================================================

function Effects.tileFlash(self: Effects, index: number, color: Color3)
	if self.live >= MAX_LIVE_FLASHES then
		return
	end
	self.live += 1

	local base = WorldSpace.indexToWorld(index)
	local height = WorldSpace.surfaceHeight(self.terrain, index)

	local plate = Instance.new("Part")
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanTouch = false
	plate.CanQuery = false
	plate.CastShadow = false
	plate.Material = Enum.Material.Neon
	plate.Color = color
	plate.Transparency = 0.15
	plate.Size = Vector3.new(Config.TILE_SIZE, 0.4, Config.TILE_SIZE)
	plate.CFrame = CFrame.new(base.X, height + 0.3, base.Z)
	plate.Parent = self.root

	-- La plaque s'eleve legerement en s'effacant : le mouvement vertical rend
	-- la prise lisible meme quand la couleur du sol change peu.
	TweenService:Create(plate, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(base.X, height + 3.2, base.Z),
		Transparency = 1,
		Size = Vector3.new(Config.TILE_SIZE * 0.4, 0.4, Config.TILE_SIZE * 0.4),
	}):Play()

	task.delay(0.7, function()
		plate:Destroy()
		self.live -= 1
	end)
end

--=============================================================================
-- Onde de conquete
--=============================================================================

function Effects.conquestPulse(self: Effects, x: number, y: number, radius: number, color: Color3)
	if (self.livePulses or 0) >= MAX_LIVE_PULSES then
		return
	end
	self.livePulses += 1
	local ground = WorldSpace.tileToWorld(x, y)
	local height = 3
	if self.terrain and MapGen.inBounds(x, y) then
		height = WorldSpace.surfaceHeight(self.terrain, MapGen.toIndex(x, y)) + 0.8
	end
	local worldRadius = math.clamp(radius, 3, 40) * Config.TILE_SIZE

	local ring = Instance.new("Part")
	ring.Name = "ConquestPulse"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.45
	ring.Size = Vector3.new(0.6, 4, 4)
	-- V82 : translation * rot cuit. Plus de CFrame.Angles a l'onde.
	-- Recette feel N134 — ne pas merger bfcc. Ne pas porter Y = 3
	-- (visuel = surface + 0.8 / fallback 3). Distinct de V81 (explosion
	-- Overlay, PLAINS + 0.5). Distinct de V80 (arrivee camion). Distinct
	-- de SelectionRing (V83, surface + 0.48). lossWave passe par ce site.
	ring.CFrame = CFrame.new(ground.X, height, ground.Z) * self.pulseRot
	ring.Parent = self.root

	TweenService:Create(ring, TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.6, worldRadius * 2, worldRadius * 2),
		Transparency = 1,
	}):Play()

	task.delay(1, function()
		ring:Destroy()
		self.livePulses = math.max(0, (self.livePulses or 1) - 1)
	end)
end

--=============================================================================
-- Texte flottant
--=============================================================================

function Effects.floatingText(self: Effects, x: number, y: number, text: string, color: Color3)
	local ground = WorldSpace.tileToWorld(x, y)

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(ground.X, 12, ground.Z)
	anchor.Parent = self.root

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 30)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 900
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.font.display
	label.TextSize = 20
	label.TextColor3 = color
	label.Text = text
	label.Parent = billboard

	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(6, 8, 14)
	outline.Thickness = 2.5
	outline.Parent = label

	TweenService:Create(anchor, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(ground.X, 26, ground.Z),
	}):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
	TweenService:Create(outline, TweenInfo.new(1.2), { Transparency = 1 }):Play()

	task.delay(1.3, function()
		anchor:Destroy()
	end)
end

--=============================================================================
-- Vague de conquete
--=============================================================================

--[[
	Traite une vague complete de captures.

	`conquests` liste les tuiles prises a une autre faction (le terrain neutre
	en est exclu : coloniser du vide n'est pas un fait d'armes et ne merite pas
	d'effet). On calcule le barycentre pour placer l'onde et le texte, et on
	echantillonne les eclats pour rester dans le budget.
]]
function Effects.conquestWave(self: Effects, conquests: { number }, color: Color3, mine: boolean)
	local count = #conquests
	if count == 0 then
		return
	end

	local sumX, sumY = 0, 0
	for _, index in conquests do
		local x, y = MapGen.fromIndex(index)
		sumX += x
		sumY += y
	end
	local centreX = sumX / count
	local centreY = sumY / count

	-- Echantillonnage regulier plutot que les N premieres : les premieres
	-- tuiles d'une vague sont contigues, et n'eclairer qu'elles donnerait
	-- l'impression d'un front beaucoup plus etroit qu'il n'est.
	local step = math.max(1, count // MAX_FLASHES_PER_WAVE)
	for i = 1, count, step do
		self:tileFlash(conquests[i], color)
	end

	-- Rayon approche a partir de l'aire : une vague de 100 tuiles couvre a peu
	-- pres un disque de rayon 5.6.
	local radius = math.sqrt(count / math.pi) + 2
	self:conquestPulse(centreX, centreY, radius, color)

	-- Le texte n'apparait que pour les vagues significatives, et seulement pour
	-- ses propres conquetes : afficher celles des douze autres factions
	-- transformerait la carte en pluie de chiffres.
	if mine and count >= 4 then
		self:floatingText(centreX, centreY, `+{count}`, color)
	end
end

--[[
	Perte de territoire : meme geometrie, couleur d'alerte et pas d'eclats.
	On doit sentir qu'on recule sans que l'effet soit gratifiant.
]]
function Effects.lossWave(self: Effects, conquests: { number }, count: number)
	if count < 4 then
		return
	end

	local sumX, sumY = 0, 0
	for _, index in conquests do
		local x, y = MapGen.fromIndex(index)
		sumX += x
		sumY += y
	end
	local centreX = sumX / #conquests
	local centreY = sumY / #conquests

	self:conquestPulse(centreX, centreY, math.sqrt(count / math.pi) + 2, Theme.color.danger)
	self:floatingText(centreX, centreY, `-{count}`, Theme.color.danger)
end

return Effects
