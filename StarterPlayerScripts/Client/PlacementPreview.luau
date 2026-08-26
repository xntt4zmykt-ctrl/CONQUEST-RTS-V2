--!strict
--[[
	Apercu de placement.

	Quand le mode Construire est arme, le batiment choisi suit le curseur en
	fantome translucide. Le disque au sol montre l'emprise reelle, et pour un
	bunker le rayon d'effet complet.

	Ce que le fantome montre a change, et c'est le point important : il ne se
	pose plus sous le curseur, il se pose **la ou le batiment va reellement
	atterrir**. Le serveur accroche le clic a la meilleure tuile valide du
	voisinage ; le fantome fait exactement le meme calcul, avec le meme code
	(Shared/Placement), et saute donc au meme endroit. Le joueur voit le report
	avant de cliquer au lieu de le decouvrir apres.

	Trois etats au lieu de deux :
	  vert  — pose sur la tuile visee ;
	  bleu  — pose reportee a cote, ou amelioration d'un batiment existant ;
	  rouge — rien de possible ici (ere, or, ou aucune place a portee).

	Avant, la validation locale et la validation serveur etaient deux
	implementations distinctes de la meme regle et elles divergeaient : un
	fantome vert pouvait etre refuse. Ce n'etait pas un accident, c'etait
	structurel. Les deux camps executent maintenant la meme fonction.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))
local BuildingModels = require(script.Parent.BuildingModels)

local PlacementPreview = {}
PlacementPreview.__index = PlacementPreview

export type PlacementPreview = typeof(setmetatable({} :: any, PlacementPreview))

local VALID = Color3.fromRGB(82, 230, 168)
local SNAPPED = Color3.fromRGB(96, 196, 255)
local INVALID = Color3.fromRGB(255, 96, 96)
local UPGRADE = Color3.fromRGB(255, 210, 96)

-- V51 : resolve recycle previewCtxBuf (recette V40 ctxBuf / feel N92).
-- Distinct de V40 (serveur Buildings) et de V47 (validTiles).
-- Non reentrant — un seul fantome. Placement.resolve lit tout de suite
-- et n'en conserve pas l'identite. Slot / closures poses sur le buf,
-- pas de nouvelle table. Preview n'appelle pas validTiles.
local previewCtxBuf: Placement.Context = {
	slot = 0,
	era = 0,
	gold = 0,
	terrain = buffer.create(1),
	ownerAt = function(_index: number): number
		return 0
	end,
	buildingAt = function(_index: number): (number?, number?, number?)
		return nil, nil, nil
	end,
}

function PlacementPreview.new(parent: Instance, terrain: buffer): PlacementPreview
	local self = setmetatable({}, PlacementPreview) :: any

	self.terrain = terrain
	self.kind = nil
	self.tile = nil
	self.status = nil
	self.shown = false
	self.model = nil

	local root = Instance.new("Folder")
	root.Name = "Placement"
	root.Parent = parent
	self.root = root

	-- Disque d'emprise, toujours present : c'est lui qui ancre le fantome au
	-- sol et rend la tuile visee sans ambiguite.
	local footprint = Instance.new("Part")
	footprint.Name = "Footprint"
	footprint.Anchored = true
	footprint.CanCollide = false
	footprint.CanTouch = false
	footprint.CanQuery = false
	footprint.CastShadow = false
	footprint.Shape = Enum.PartType.Cylinder
	footprint.Material = Enum.Material.Neon
	footprint.Transparency = 1
	footprint.Size = Vector3.new(0.3, 10, 10)
	footprint.Parent = root
	self.footprint = footprint

	local pulse = Instance.new("Part")
	pulse.Name = "Pulse"
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanTouch = false
	pulse.CanQuery = false
	pulse.CastShadow = false
	pulse.Shape = Enum.PartType.Cylinder
	pulse.Material = Enum.Material.Neon
	pulse.Transparency = 1
	pulse.Size = Vector3.new(0.15, 8, 8)
	pulse.Parent = root
	self.pulse = pulse

	-- V75 : rotation cylindre plat cuite une fois (recette V63 segment.rot).
	-- Plus de CFrame.Angles 60 Hz hover. fromEulerAnglesYXZ(0, 0, rad(90))
	-- ≡ Angles(0, 0, 90°) (rx=0, ry=0 → Z seul). Hauteurs +0.42 / +0.38
	-- inchangees. V76 : Size pose dans setKind (rayon = kind). V77 :
	-- early-out update si tuile+statut inchanges. Radar/flag unites
	-- inchanges (V73). Flame Size inchange (V74 API). Overlay /
	-- BuildingModels / WorldCamera non edites.
	self.footprintRot = CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))
	self.pulseRot = CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))

	return self
end

--=============================================================================
-- Resolution
--=============================================================================

--[[
	Ou ce batiment atterrirait-il si on cliquait maintenant ?

	Renvoie (tuile affichee, etat) ou l'etat vaut "exact", "snap", "upgrade" ou
	"invalid". Le module partage fait tout le travail : cette fonction ne fait
	que brancher les calques du client dessus.
]]
function PlacementPreview.resolve(
	self: PlacementPreview,
	tile: number,
	kind: number,
	ownerAt: (number) -> number,
	buildingAt: (number) -> (number?, number?, number?),
	mySlot: number,
	era: number,
	gold: number,
	counts: { [number]: number },
	buildCostModifier: number
): (number, string)
	previewCtxBuf.slot = mySlot
	previewCtxBuf.era = era
	previewCtxBuf.gold = gold
	previewCtxBuf.terrain = self.terrain
	previewCtxBuf.ownerAt = ownerAt
	previewCtxBuf.buildingAt = buildingAt

	local resolution = Placement.resolve(previewCtxBuf, tile, kind, counts, buildCostModifier)
	if not resolution then
		return tile, "invalid"
	end
	if resolution.action == "upgrade" then
		return resolution.tile, "upgrade"
	end
	return resolution.tile, if resolution.tile == tile then "exact" else "snap"
end

--=============================================================================
-- Affichage
--=============================================================================

function PlacementPreview.setKind(self: PlacementPreview, kind: number?)
	if self.kind == kind then
		return
	end
	self.kind = kind
	self.tile = nil
	self.status = nil
	self.shown = false

	if self.model then
		self.model:Destroy()
		self.model = nil
	end

	if not kind then
		self.footprint.Transparency = 1
		self.pulse.Transparency = 1
		return
	end

	-- V76 : rayon = kind seulement. Le bunker montre son rayon d'effet
	-- complet (DEFENSE_RADIUS * TILE * 2) : c'est la seule facon de le
	-- placer intelligemment plutot qu'au hasard. Autres kinds : TILE * 3.
	-- pulseSize = radius * 1.08. Plus de Vector3.new Size 60 Hz hover.
	-- Distinct de V74 (flame Z pulse sin(time*18)). Distinct de V75
	-- (CFrame translation, rot deja cuit). Placeholder 10×10 / 8×8 du
	-- new n'est pas le rayon reel — ne pas geler Size ici.
	local radius = if kind == Config.BUILDING.DEFENSE
		then Config.DEFENSE_RADIUS * Config.TILE_SIZE * 2
		else Config.TILE_SIZE * 3
	self.footprint.Size = Vector3.new(0.35, radius, radius)
	self.pulse.Size = Vector3.new(0.12, radius * 1.08, radius * 1.08)

	-- Le fantome est construit une fois puis simplement deplace : le recreer a
	-- chaque mouvement de souris produirait des dizaines de modeles par seconde.
	local model = BuildingModels.create(kind, Theme.color.text, Vector3.zero)
	model.Name = "Ghost"
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = 0.55
			part.Material = Enum.Material.ForceField
			part.CanQuery = false
			part.CanCollide = false
		end
	end
	model.Parent = self.root
	self.model = model
end

function PlacementPreview.update(self: PlacementPreview, tile: number?, status: string)
	local model = self.model
	if not self.kind or not model or not tile then
		self.footprint.Transparency = 1
		self.pulse.Transparency = 1
		if model then
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					part.Transparency = 1
				end
			end
		end
		-- V77 : update(nil) nil le tile. Sans ca, un early-out
		-- self.tile == tile bloquerait le restore au retour souris
		-- (setKind(nil) nil deja, pas le chemin update(nil) sans hide).
		self.tile = nil
		self.status = nil
		self.shown = false
		return
	end

	-- V77 : early-out si tuile + statut inchanges et deja visible.
	-- Color ne depend que de status. CFrame ne depend que de tile
	-- (rot deja cuit V75). Size deja pose dans setKind (V76).
	-- Distinct de V74 (flame Z DOIT changer). Distinct de
	-- CityWindows / beacons Transparency sin(time) (ne pas geler).
	if self.shown and self.tile == tile and self.status == status then
		return
	end

	local wasHidden = not self.shown
	local tileChanged = self.tile ~= tile
	local statusChanged = self.status ~= status

	if tileChanged then
		self.tile = tile
		local base = WorldSpace.indexToWorld(tile)
		local ground = WorldSpace.surfaceHeight(self.terrain, tile)
		-- Les modeles sont construits autour de l'origine : on repositionne en
		-- recreant les decalages locaux memorises a la construction.
		local target = Vector3.new(base.X, ground, base.Z)
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				local local_ = part:GetAttribute("LocalPos")
				if typeof(local_) ~= "Vector3" then
					local_ = part.Position
					part:SetAttribute("LocalPos", local_)
				end
				part.Position = (local_ :: Vector3) + target
			end
		end
		-- V75 : CFrame seulement si la tuile bouge. Ne pas cuire la
		-- translation a new (le curseur bouge).
		self.footprint.CFrame = CFrame.new(base.X, ground + 0.42, base.Z) * self.footprintRot
		self.pulse.CFrame = CFrame.new(base.X, ground + 0.38, base.Z) * self.pulseRot
	end

	if statusChanged or wasHidden then
		local color = if status == "exact"
			then VALID
			elseif status == "upgrade" then UPGRADE
			elseif status == "snap" then SNAPPED
			else INVALID
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				if wasHidden then
					part.Transparency = 0.55
				end
				part.Color = color
			end
		end
		self.footprint.Color = color
		self.pulse.Color = color
	end

	if wasHidden then
		self.footprint.Transparency = 0.52
		self.pulse.Transparency = 0.72
	end

	self.status = status
	self.shown = true
end

function PlacementPreview.hide(self: PlacementPreview)
	self:setKind(nil)
end

function PlacementPreview.destroy(self: PlacementPreview)
	self.root:Destroy()
end

return PlacementPreview
