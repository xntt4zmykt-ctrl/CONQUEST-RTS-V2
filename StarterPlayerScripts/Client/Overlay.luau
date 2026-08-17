--!strict
--[[
	Calque des entites dans le monde 3D : batiments, navires, missiles,
	explosions.

	Le terrain est de la geometrie fusionnee (voir WorldRenderer) et ne peut
	donc pas porter d'information ponctuelle : un bloc couvre parfois cinquante
	tuiles. Tout ce qui est localise vit donc ici, sous forme de vrais objets
	poses dans le monde.

	Le nombre d'elements reste petit — quelques centaines de batiments, quelques
	dizaines de navires — ce qui rend l'approche par instances viable ici, alors
	qu'elle serait catastrophique pour les 40 000 tuiles du terrain.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BuildingDefs = require(Shared:WaitForChild("BuildingDefs"))
local BuildingModels = require(script.Parent.BuildingModels)
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))
local Types = require(Shared:WaitForChild("Types"))

local Overlay = {}
Overlay.__index = Overlay

export type Overlay = typeof(setmetatable({} :: any, Overlay))

local colorFor = Theme.factionColor

--=============================================================================
-- Construction
--=============================================================================

function Overlay.new(parent: Instance, terrain: buffer): Overlay
	local self = setmetatable({}, Overlay) :: any

	self.terrain = terrain
	self.buildings = {}
	self.units = {}
	self.seen = {}
	-- Les batiments deja presents a l'arrivee ne s'animent pas : voir trente
	-- chantiers demarrer en meme temps a la connexion serait absurde. Seuls
	-- ceux poses apres ce delai sont mis en scene.
	self.animateFrom = os.clock() + 3

	local root = Instance.new("Folder")
	root.Name = "Entities"
	root.Parent = parent
	self.root = root

	return self
end

function Overlay.clear(self: Overlay)
	for _, part in self.buildings do
		part:Destroy()
	end
	for _, unit in self.units do
		unit.part:Destroy()
	end
	table.clear(self.buildings)
	table.clear(self.units)
	table.clear(self.seen)
end

--=============================================================================
-- Batiments
--=============================================================================

--[[
	Un batiment est un vrai petit modele 3D pose sur le relief, surmonte d'une
	etiquette toujours face camera.

	Le modele donne la presence et la lisibilite de pres ; l'etiquette garantit
	qu'on identifie le batiment meme completement dezoome, ou le modele ne ferait
	plus que quelques pixels.
]]
local function makeBuilding(parent: Instance, index: number, kind: number, slot: number, terrain: buffer): Model
	local def = BuildingDefs.get(kind)
	local color = colorFor(slot)

	local base = WorldSpace.indexToWorld(index)
	local ground = WorldSpace.surfaceHeight(terrain, index)
	local model = BuildingModels.create(kind, color, Vector3.new(base.X, ground, base.Z))
	model.Name = `Building{index}`

	-- L'etiquette a besoin d'un ancrage : le premier bloc du modele fait
	-- l'affaire et evite d'ajouter une Part uniquement pour la porter.
	local anchor = model:FindFirstChildWhichIsA("BasePart")
	if anchor then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Marker"
		local size = if kind == Config.BUILDING.CAPITAL then 32 else 22
		billboard.Size = UDim2.fromOffset(size, size)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 1400
		-- Positionnee en absolu depuis le sol, pas depuis l'ancre : le premier
		-- bloc n'est pas au meme endroit selon le modele.
		billboard.StudsOffsetWorldSpace =
			Vector3.new(base.X, ground + BuildingModels.heightOf(kind) + 3, base.Z) - anchor.Position
		billboard.Parent = anchor

		local label = Instance.new("TextLabel")
		label.Name = "Symbol"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Theme.font.bold
		label.TextScaled = true
		label.Text = if def then def.symbol else "?"
		label.TextColor3 = color
		label.Parent = billboard

		local outline = Instance.new("UIStroke")
		outline.Color = Color3.fromRGB(8, 10, 16)
		outline.Thickness = 2
		outline.Parent = label
	end

	model:SetAttribute("Kind", kind)
	model:SetAttribute("TintR", color.R)
	model:SetAttribute("TintG", color.G)
	model:SetAttribute("TintB", color.B)
	model.Parent = parent
	return model
end

function Overlay.applyBuildingDelta(self: Overlay, deltas: { Types.BuildingSnapshot })
	for _, entry in deltas do
		local existing = self.buildings[entry.index]

		if entry.kind == 0 then
			if existing then
				existing:Destroy()
				self.buildings[entry.index] = nil
			end
			continue
		end

		-- Un batiment capture change de couleur, pas de forme : reconstruire tout
		-- le modele a chaque prise serait du gaspillage, et les prises sont
		-- frequentes en fin de partie.
		if existing and existing:GetAttribute("Kind") == entry.kind then
			local previous = Color3.new(
				existing:GetAttribute("TintR") :: number,
				existing:GetAttribute("TintG") :: number,
				existing:GetAttribute("TintB") :: number
			)
			local next = colorFor(entry.slot)
			BuildingModels.recolor(existing, previous, next)
			existing:SetAttribute("TintR", next.R)
			existing:SetAttribute("TintG", next.G)
			existing:SetAttribute("TintB", next.B)

			local anchor = existing:FindFirstChildWhichIsA("BasePart")
			local marker = anchor and anchor:FindFirstChild("Marker")
			local label = marker and marker:FindFirstChild("Symbol")
			if label and label:IsA("TextLabel") then
				label.TextColor3 = next
			end
			continue
		end

		if existing then
			existing:Destroy()
		end

		local model = makeBuilding(self.root, entry.index, entry.kind, entry.slot, self.terrain)
		self.buildings[entry.index] = model

		if os.clock() >= self.animateFrom then
			local base = WorldSpace.indexToWorld(entry.index)
			local ground = WorldSpace.surfaceHeight(self.terrain, entry.index)
			BuildingModels.playConstruction(model, Vector3.new(base.X, ground + 0.4, base.Z))
		end
	end
end

--=============================================================================
-- Unites
--=============================================================================

local function makeUnit(parent: Instance, slot: number, kind: number, isMissile: boolean): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if isMissile then
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 230, 140)
		part.Size = Vector3.new(1.6, 1.6, 5)
	elseif kind == 2 then
		-- Navire marchand : petit, dore, visuellement inoffensif.
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Theme.color.gold
		part.Size = Vector3.new(2.2, 1.2, 4)
	else
		-- Transport de troupes : plus gros, aux couleurs de la faction.
		part.Material = Enum.Material.SmoothPlastic
		part.Color = colorFor(slot)
		part.Size = Vector3.new(3.2, 1.8, 6)
	end

	part.Parent = parent
	return part
end

--[[
	Les instantanes arrivent a 10 Hz. On stocke la position cible et on
	interpole a chaque frame, sinon les navires avancent par saccades visibles.
]]
function Overlay.applyUnits(self: Overlay, boats: { Types.BoatSnapshot }, missiles: { Types.MissileSnapshot })
	table.clear(self.seen)

	local function track(id: number, slot: number, kind: number, x: number, y: number, isMissile: boolean, extra: any?)
		local unit = self.units[id]
		if not unit then
			unit = {
				part = makeUnit(self.root, slot, kind, isMissile),
				current = Vector2.new(x, y),
				target = Vector2.new(x, y),
				isMissile = isMissile,
				extra = extra,
			}
			self.units[id] = unit
		end
		unit.target = Vector2.new(x, y)
		unit.extra = extra
		self.seen[id] = true
	end

	for _, boat in boats do
		track(boat.id, boat.slot, boat.kind, boat.x, boat.y, false)
	end

	for _, missile in missiles do
		track(missile.id, missile.slot, missile.kind, missile.x, missile.y, true, {
			tx = missile.tx,
			ty = missile.ty,
		})
	end

	-- Toute unite absente de l'instantane a disparu cote serveur.
	for id, unit in self.units do
		if not self.seen[id] then
			unit.part:Destroy()
			self.units[id] = nil
		end
	end
end

function Overlay.stepInterpolation(self: Overlay, dt: number)
	local alpha = math.min(1, dt * 9)

	for _, unit in self.units do
		unit.current += (unit.target - unit.current) * alpha

		local x, y = unit.current.X, unit.current.Y
		local ground = WorldSpace.tileToWorld(x, y)

		local height
		if unit.isMissile then
			-- Trajectoire en cloche : un missile qui rase le sol ne se lit pas,
			-- alors que c'est l'evenement le plus spectaculaire de la partie.
			-- L'altitude se deduit de la distance restante, donc elle retombe
			-- naturellement a zero au point d'impact.
			local remaining = 80
			if unit.extra then
				remaining = math.sqrt((unit.extra.tx - x) ^ 2 + (unit.extra.ty - y) ^ 2)
			end
			local approach = math.clamp(remaining / 60, 0, 1)
			height = 25 + math.sin(approach * math.pi * 0.5) * 95
		else
			height = Config.OCEAN_LEVEL + 1
		end

		local position = Vector3.new(ground.X, height, ground.Z)
		local direction = unit.target - unit.current

		if direction.Magnitude > 0.01 then
			local look = Vector3.new(direction.X, 0, direction.Y).Unit
			unit.part.CFrame = CFrame.lookAt(position, position + look)
		else
			unit.part.CFrame = CFrame.new(position)
		end
	end
end

--=============================================================================
-- Effets
--=============================================================================

--[[
	Onde de choc nucleaire : une sphere qui se dilate jusqu'au rayon reel de la
	frappe, donc le joueur juge la zone d'effet a l'oeil.
]]
function Overlay.explosion(self: Overlay, x: number, y: number, radius: number)
	local ground = WorldSpace.tileToWorld(x, y)
	local worldRadius = radius * Config.TILE_SIZE

	local sphere = Instance.new("Part")
	sphere.Name = "Blast"
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanTouch = false
	sphere.CanQuery = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.Neon
	sphere.Color = Color3.fromRGB(255, 190, 110)
	sphere.Transparency = 0.15
	sphere.Size = Vector3.new(4, 4, 4)
	sphere.CFrame = CFrame.new(ground.X, 14, ground.Z)
	sphere.Parent = self.root

	TweenService:Create(sphere, TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(worldRadius * 2, worldRadius * 2, worldRadius * 2),
		Transparency = 1,
	}):Play()

	local light = Instance.new("PointLight")
	light.Brightness = 8
	light.Range = math.min(worldRadius * 2, 60)
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Parent = sphere
	TweenService:Create(light, TweenInfo.new(1.1), { Brightness = 0 }):Play()

	task.delay(1.3, function()
		sphere:Destroy()
	end)
end

return Overlay
