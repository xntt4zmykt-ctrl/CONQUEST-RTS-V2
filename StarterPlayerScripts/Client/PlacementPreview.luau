--!strict
--[[
	Apercu de placement.

	Quand le mode Construire est arme, le batiment choisi suit le curseur en
	fantome translucide, teinte en vert ou en rouge selon que l'emplacement est
	valide. Un disque au sol montre l'emprise reelle, et pour un bunker le rayon
	d'effet complet.

	Pourquoi c'est important : avant, construire etait un clic dans le vide
	suivi, au mieux, d'un message d'erreur. Le joueur ne pouvait ni voir ce
	qu'il allait obtenir, ni savoir si l'endroit convenait. C'est exactement le
	genre de friction qui fait qu'un jeu "fait cheap".

	La validation affichee ici est une **estimation locale** : le serveur reste
	seul juge. On verifie les criteres que le client connait de facon fiable
	(propriete, relief, cote, ere, or), pas ceux qui demandent l'etat complet du
	serveur. Un fantome vert peut donc encore etre refuse — mais jamais
	l'inverse, ce qui serait bien plus frustrant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))
local BuildingDefs = require(Shared:WaitForChild("BuildingDefs"))
local Eras = require(Shared:WaitForChild("Eras"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))
local BuildingModels = require(script.Parent.BuildingModels)

local PlacementPreview = {}
PlacementPreview.__index = PlacementPreview

export type PlacementPreview = typeof(setmetatable({} :: any, PlacementPreview))

local VALID = Color3.fromRGB(110, 235, 160)
local INVALID = Color3.fromRGB(255, 105, 95)

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
-- Validation locale
--=============================================================================

function PlacementPreview.isValid(
	self: PlacementPreview,
	tile: number,
	kind: number,
	ownerAt: (number) -> number,
	mySlot: number,
	era: number,
	gold: number,
	buildingAt: ((number) -> (number?, number?))?,
	hasCityNear: ((number, number, number) -> boolean)?
): boolean
	local def = BuildingDefs.get(kind)
	if not def or not def.buildable then
		return false
	end
	if ownerAt(tile) ~= mySlot then
		return false
	end
	if buffer.readu8(self.terrain, tile) == Config.TERRAIN.OCEAN then
		return false
	end
	if def.coastalOnly and not MapGen.isCoastal(self.terrain, tile) then
		return false
	end
	if era < Eras.requiredFor(kind) then
		return false
	end
	if gold < def.cost then
		return false
	end
	if buildingAt then
		local occupied = buildingAt(tile)
		if occupied ~= nil then
			return false
		end

		-- Le serveur applique aussi cette regle. La montrer dans le fantome
		-- evite le classique "vert puis refuse" quand deux villes sont trop
		-- proches l'une de l'autre.
		local cx, cy = MapGen.fromIndex(tile)
		local spacing = Config.BUILD_MIN_SPACING
		for dy = -spacing, spacing do
			for dx = -spacing, spacing do
				if dx * dx + dy * dy <= spacing * spacing then
					local nx, ny = cx + dx, cy + dy
					if MapGen.inBounds(nx, ny) then
						local otherKind = buildingAt(MapGen.toIndex(nx, ny))
						if otherKind == kind then
							return false
						end
					end
				end
			end
		end
	end
	if kind == Config.BUILDING.FACTORY and hasCityNear and not hasCityNear(tile, mySlot, Config.FACTORY_ROUTE_RANGE) then
		return false
	end
	return true
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

function PlacementPreview.update(self: PlacementPreview, tile: number?, valid: boolean)
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

	local color = if valid then VALID else INVALID
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
	self.footprint.CFrame = CFrame.new(base.X, ground + 0.4, base.Z) * CFrame.Angles(0, 0, math.rad(90))
end

function PlacementPreview.hide(self: PlacementPreview)
	self:setKind(nil)
end

function PlacementPreview.destroy(self: PlacementPreview)
	self.root:Destroy()
end

return PlacementPreview
