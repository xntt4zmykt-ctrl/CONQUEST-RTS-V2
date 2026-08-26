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

local VALID = Color3.fromRGB(110, 235, 160)
local SNAPPED = Color3.fromRGB(120, 200, 255)
local INVALID = Color3.fromRGB(255, 105, 95)

-- N92 : ctx hover recycle. Record + champs reecrits a chaque resolve
-- (recette N85 ctxBuf serveur). Distinct de ctxBuf Buildings et de
-- candBuf Placement. Unique appelant synchrone (resolve). Pas de
-- RemoteFunction. Ne pas table.clone. ownerAt/buildingAt viennent
-- du caller (init.client) — ne pas cacher si la tuile change de camp.
local function previewOwnerAt(_index: number): number
	return 0
end
local function previewBuildingAt(_index: number): (number?, number?, number?)
	return nil, nil, nil
end
local previewCtx: Placement.Context = {
	slot = 0,
	era = 0,
	gold = 0,
	terrain = buffer.create(1),
	ownerAt = previewOwnerAt,
	buildingAt = previewBuildingAt,
}
PlacementPreview.previewCtx = previewCtx

function PlacementPreview.new(parent: Instance, terrain: buffer): PlacementPreview
	local self = setmetatable({}, PlacementPreview) :: any

	self.terrain = terrain
	self.kind = nil
	self.tile = nil
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
	previewCtx.slot = mySlot
	previewCtx.era = era
	previewCtx.gold = gold
	previewCtx.terrain = self.terrain
	previewCtx.ownerAt = ownerAt
	previewCtx.buildingAt = buildingAt

	local resolution = Placement.resolve(previewCtx, tile, kind, counts, buildCostModifier)
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

	if self.model then
		self.model:Destroy()
		self.model = nil
	end

	if not kind then
		self.footprint.Transparency = 1
		return
	end

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
		if model then
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					part.Transparency = 1
				end
			end
		end
		return
	end

	local color = if status == "exact"
		then VALID
		elseif status == "snap" or status == "upgrade" then SNAPPED
		else INVALID
	local base = WorldSpace.indexToWorld(tile)
	local ground = WorldSpace.surfaceHeight(self.terrain, tile)

	if self.tile ~= tile then
		self.tile = tile
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
	end

	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = 0.55
			part.Color = color
		end
	end

	-- Le bunker montre son rayon d'effet complet : c'est la seule facon de le
	-- placer intelligemment plutot qu'au hasard.
	local radius = if self.kind == Config.BUILDING.DEFENSE
		then Config.DEFENSE_RADIUS * Config.TILE_SIZE * 2
		else Config.TILE_SIZE * 3

	self.footprint.Transparency = 0.6
	self.footprint.Color = color
	self.footprint.Size = Vector3.new(0.3, radius, radius)
	-- N129 : translation * euler Z=90. Plus de CFrame.Angles 60 Hz.
	-- fromEulerAnglesYXZ(0, 0, math.rad(90)) ≡ Angles(0, 0, π/2)
	-- (rx=0, ry=0 → Z seul). Angle 90° inchange. Hauteur ground + 0.4
	-- inchangee (feel ≠ visual 0.42). Size Vector3.new inchange (API).
	-- Pas de pulse (feel n'en a pas). Distinct LaunchWake N130 (evenement).
	-- Distinct N127/N128 pieces navire. Distinct N124 Radar rest identite.
	-- Recette visual V75 leftover deja sur 1b5c — portee euler, pas mergee.
	self.footprint.CFrame = CFrame.new(base.X, ground + 0.4, base.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))
end

function PlacementPreview.hide(self: PlacementPreview)
	self:setKind(nil)
end

function PlacementPreview.destroy(self: PlacementPreview)
	self.root:Destroy()
end

return PlacementPreview
