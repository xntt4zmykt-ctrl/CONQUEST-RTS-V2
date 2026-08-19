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
local UnitModels = require(script.Parent.UnitModels)
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))
local Types = require(Shared:WaitForChild("Types"))

local Overlay = {}
Overlay.__index = Overlay

export type Overlay = typeof(setmetatable({} :: any, Overlay))

local colorFor = Theme.factionColor
local DARK = Color3.fromRGB(29, 35, 43)

--=============================================================================
-- Construction
--=============================================================================

function Overlay.new(parent: Instance, terrain: buffer): Overlay
	local self = setmetatable({}, Overlay) :: any

	self.terrain = terrain
	self.buildings = {}
	self.routes = {}
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
		unit.visual.model:Destroy()
	end
	for _, route in self.routes do
		route.model:Destroy()
	end
	table.clear(self.buildings)
	table.clear(self.units)
	table.clear(self.routes)
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
local function makeBuilding(
	parent: Instance,
	index: number,
	kind: number,
	slot: number,
	level: number,
	terrain: buffer
): Model
	local def = BuildingDefs.get(kind)
	local color = colorFor(slot)

	local base = WorldSpace.indexToWorld(index)
	local ground = WorldSpace.surfaceHeight(terrain, index)
	local model = BuildingModels.create(kind, color, Vector3.new(base.X, ground, base.Z), level)
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
			Vector3.new(base.X, ground + BuildingModels.heightOf(kind, level) + 3, base.Z) - anchor.Position
		billboard.Parent = anchor

		local label = Instance.new("TextLabel")
		label.Name = "Symbol"
		label.BackgroundColor3 = Theme.color.surface
		label.BackgroundTransparency = 0.08
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Theme.font.bold
		label.TextScaled = true
		label.Text = if def
			then `{def.symbol}{if kind == Config.BUILDING.CITY and level > 1 then level else ""}`
			else "?"
		label.TextColor3 = color
		label.Parent = billboard
		Theme.corner(label, Theme.radius.pill)

		local outline = Instance.new("UIStroke")
		outline.Color = color
		outline.Transparency = 0.15
		outline.Thickness = 1
		outline.Parent = label
	end

	model:SetAttribute("Kind", kind)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("Level", level)
	model:SetAttribute("TintR", color.R)
	model:SetAttribute("TintG", color.G)
	model:SetAttribute("TintB", color.B)
	model.Parent = parent
	return model
end

local function routePart(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	Retrace toutes les routes d'une usine.

	Une usine dessert plusieurs villes : on efface donc ses routes existantes
	avant de les redessiner, plutot que de tenir un diff par ville. Le nombre
	de routes reste petit et le recalcul n'a lieu qu'a la pose ou a la capture
	d'un batiment.
]]
function Overlay.syncFactoryRoutes(self: Overlay, factoryIndex: number, links: { number }?, slot: number)
	for key, route in self.routes do
		if route.factory == factoryIndex then
			route.model:Destroy()
			self.routes[key] = nil
		end
	end

	for _, cityIndex in links or {} do
		self:buildFactoryRoute(factoryIndex, cityIndex, slot)
	end
end

function Overlay.buildFactoryRoute(self: Overlay, factoryIndex: number, cityIndex: number, slot: number)

	local fromBase = WorldSpace.indexToWorld(factoryIndex)
	local toBase = WorldSpace.indexToWorld(cityIndex)
	local roadY = math.max(
		WorldSpace.surfaceHeight(self.terrain, factoryIndex),
		WorldSpace.surfaceHeight(self.terrain, cityIndex)
	) + 0.38
	local from = Vector3.new(fromBase.X, roadY, fromBase.Z)
	local to = Vector3.new(toBase.X, roadY, toBase.Z)
	local delta = to - from
	local distance = delta.Magnitude
	if distance < 1 then
		return
	end

	local model = Instance.new("Model")
	model.Name = `LogisticsRoute{factoryIndex}`
	model.Parent = self.root

	-- Courbe quadratique tres douce : une route parfaitement droite entre deux
	-- centres ressemble a une ligne de debug. Le coude donne une vraie lecture
	-- d'infrastructure sans rallonger fortement le trajet.
	local forward = delta.Unit
	local side = Vector3.new(-forward.Z, 0, forward.X)
	local sign = if factoryIndex % 2 == 0 then 1 else -1
	local control = from + delta * 0.5 + side * math.min(12, distance * 0.14) * sign
	local path = {}
	for i = 0, 5 do
		local t = i / 5
		local inv = 1 - t
		table.insert(path, from * (inv * inv) + control * (2 * inv * t) + to * (t * t))
	end

	for i = 1, #path - 1 do
		local a = path[i]
		local b = path[i + 1]
		local segment = b - a
		local segmentLength = segment.Magnitude
		local frame = CFrame.lookAt(a + segment * 0.5, b)
		local shoulder = routePart(model, "Shoulder", Vector3.new(2.7, 0.12, segmentLength + 0.4), Color3.fromRGB(39, 43, 48), Enum.Material.Concrete)
		shoulder.CFrame = frame
		local asphalt = routePart(model, "Road", Vector3.new(1.9, 0.16, segmentLength + 0.45), Color3.fromRGB(52, 58, 66), Enum.Material.Asphalt)
		asphalt.CFrame = frame + Vector3.new(0, 0.08, 0)
		local stripe = routePart(model, "CenterMark", Vector3.new(0.1, 0.2, segmentLength * 0.58), Color3.fromRGB(237, 207, 123), Enum.Material.Neon)
		stripe.Transparency = 0.28
		stripe.CFrame = frame + Vector3.new(0, 0.18, 0)
	end

	-- La caisse mobile rend le flux economique concret : ce n'est plus un
	-- simple bonus invisible dans une formule.
	local truckModel = Instance.new("Model")
	truckModel.Name = "CargoTruck"
	truckModel.Parent = model
	local truck = {}
	local function truckPart(name: string, size: Vector3, color: Color3, offset: CFrame, material: Enum.Material?): Part
		local part = routePart(truckModel, name, size, color, material or Enum.Material.Metal)
		part.CastShadow = true
		part.CFrame = CFrame.lookAt(from + Vector3.new(0, 0.8, 0), to) * offset
		table.insert(truck, { part = part, offset = offset })
		return part
	end
	truckPart("Chassis", Vector3.new(1.55, 0.28, 2.9), DARK, CFrame.new(0, 0.35, 0))
	truckPart("Container", Vector3.new(1.45, 1.05, 1.75), Color3.fromRGB(255, 196, 72), CFrame.new(0, 0.94, 0.45))
	truckPart("Cab", Vector3.new(1.45, 0.9, 0.9), colorFor(slot), CFrame.new(0, 0.82, -0.95))
	local windshield = truckPart("Windshield", Vector3.new(1.15, 0.36, 0.08), Color3.fromRGB(125, 210, 235), CFrame.new(0, 1.02, -1.42), Enum.Material.Glass)
	windshield.Transparency = 0.18
	for sideLight = -1, 1, 2 do
		local lamp = truckPart("Headlight", Vector3.new(0.28, 0.24, 0.08), Color3.fromRGB(255, 239, 176), CFrame.new(sideLight * 0.48, 0.72, -1.47), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = lamp.Color
		light.Brightness = 0.8
		light.Range = 8
		light.Parent = lamp
	end
	for side = -1, 1, 2 do
		for axle = -1, 1, 2 do
			local wheel = truckPart("Wheel", Vector3.new(0.3, 0.48, 0.48), Color3.fromRGB(18, 21, 25), CFrame.new(side * 0.78, 0.28, axle * 0.88))
			wheel.Shape = Enum.PartType.Cylinder
		end
	end

	-- Cle composite : une usine peut avoir plusieurs routes simultanees.
	self.routes[factoryIndex * 100000 + cityIndex] = {
		factory = factoryIndex,
		model = model,
		truck = truck,
		from = from + Vector3.new(0, 0.8, 0),
		to = to + Vector3.new(0, 0.8, 0),
		path = path,
		slot = slot,
		progress = (factoryIndex % 29) / 29,
	}
end

function Overlay.hasCityNear(self: Overlay, index: number, slot: number, range: number): boolean
	local x, y = index % Config.MAP_WIDTH, index // Config.MAP_WIDTH
	local range2 = range * range
	for cityIndex, model in self.buildings do
		if model:GetAttribute("Kind") == Config.BUILDING.CITY and model:GetAttribute("Slot") == slot then
			local cx, cy = cityIndex % Config.MAP_WIDTH, cityIndex // Config.MAP_WIDTH
			local dx, dy = cx - x, cy - y
			if dx * dx + dy * dy <= range2 then
				return true
			end
		end
	end
	return false
end

function Overlay.applyBuildingDelta(self: Overlay, deltas: { Types.BuildingSnapshot })
	for _, entry in deltas do
		local existing = self.buildings[entry.index]
		local level = entry.level or 1

		if entry.kind == 0 then
			self:syncFactoryRoutes(entry.index, nil, 0)
			if existing then
				existing:Destroy()
				self.buildings[entry.index] = nil
			end
			continue
		end

		-- Un batiment capture change de couleur, pas de forme : reconstruire tout
		-- le modele a chaque prise serait du gaspillage, et les prises sont
		-- frequentes en fin de partie.
		if
			existing
			and existing:GetAttribute("Kind") == entry.kind
			and existing:GetAttribute("Level") == level
		then
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
			existing:SetAttribute("Slot", entry.slot)

			local anchor = existing:FindFirstChildWhichIsA("BasePart")
			local marker = anchor and anchor:FindFirstChild("Marker")
			local label = marker and marker:FindFirstChild("Symbol")
			if label and label:IsA("TextLabel") then
				label.TextColor3 = next
			end
			if entry.kind == Config.BUILDING.FACTORY then
				existing:SetAttribute("Routes", if entry.links then #entry.links else 0)
				self:syncFactoryRoutes(entry.index, entry.links, entry.slot)
			end
			continue
		end

		if existing then
			existing:Destroy()
		end

		local model = makeBuilding(self.root, entry.index, entry.kind, entry.slot, level, self.terrain)
		self.buildings[entry.index] = model
		if entry.kind == Config.BUILDING.FACTORY then
			model:SetAttribute("Routes", if entry.links then #entry.links else 0)
			self:syncFactoryRoutes(entry.index, entry.links, entry.slot)
		end

		if os.clock() >= self.animateFrom then
			local base = WorldSpace.indexToWorld(entry.index)
			local ground = WorldSpace.surfaceHeight(self.terrain, entry.index)
			BuildingModels.playConstruction(model, Vector3.new(base.X, ground + 0.4, base.Z))
		end
	end
end

function Overlay.buildingAt(self: Overlay, index: number): (number?, number?, number?, number?)
	local model = self.buildings[index]
	if not model then
		return nil, nil, nil, nil
	end
	return
		model:GetAttribute("Kind") :: number?,
		model:GetAttribute("Slot") :: number?,
		model:GetAttribute("Level") :: number?,
		model:GetAttribute("Routes") :: number?
end

--=============================================================================
-- Unites
--=============================================================================

--[[
	Les instantanes arrivent a 10 Hz. On stocke la position cible et on
	interpole a chaque frame, sinon les navires avancent par saccades visibles.
]]
function Overlay.applyUnits(self: Overlay, boats: { Types.BoatSnapshot }, missiles: { Types.MissileSnapshot })
	table.clear(self.seen)

	local function track(id: number, slot: number, kind: number, x: number, y: number, isMissile: boolean, extra: any?)
		local unit = self.units[id]
		if not unit then
			local visual = if isMissile
				then UnitModels.createMissile(self.root, slot, kind)
				else UnitModels.createBoat(self.root, slot, kind)
			unit = {
				visual = visual,
				current = Vector2.new(x, y),
				target = Vector2.new(x, y),
				isMissile = isMissile,
				phase = (id % 31) / 31 * math.pi * 2,
				extra = extra,
			}
			self.units[id] = unit
			if not isMissile then
				local origin = WorldSpace.tileToWorld(x, y)
				local wake = routePart(self.root, "LaunchWake", Vector3.new(0.16, 2.5, 2.5), Color3.fromRGB(174, 231, 244), Enum.Material.Neon)
				wake.Shape = Enum.PartType.Cylinder
				wake.Transparency = 0.34
				wake.CFrame = CFrame.new(origin.X, Config.OCEAN_LEVEL + 0.12, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
				TweenService:Create(wake, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.16, 9, 9),
					Transparency = 1,
				}):Play()
				task.delay(0.8, function()
					if wake.Parent then
						wake:Destroy()
					end
				end)
			end
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
			if not unit.isMissile then
				local last = WorldSpace.tileToWorld(unit.current.X, unit.current.Y)
				local splash = routePart(self.root, "LandingSplash", Vector3.new(0.18, 3, 3), Color3.fromRGB(202, 239, 247), Enum.Material.Neon)
				splash.Shape = Enum.PartType.Cylinder
				splash.Transparency = 0.18
				splash.CFrame = CFrame.new(last.X, Config.OCEAN_LEVEL + 0.14, last.Z) * CFrame.Angles(0, 0, math.rad(90))
				TweenService:Create(splash, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.18, 15, 15),
					Transparency = 1,
				}):Play()
				for _, piece in unit.visual.pieces do
					TweenService:Create(piece.part, TweenInfo.new(0.35), { Transparency = 1 }):Play()
				end
				task.delay(0.95, function()
					if splash.Parent then
						splash:Destroy()
					end
					if unit.visual.model.Parent then
						unit.visual.model:Destroy()
					end
				end)
			else
				unit.visual.model:Destroy()
			end
			self.units[id] = nil
		end
	end
end

function Overlay.stepInterpolation(self: Overlay, dt: number)
	local alpha = math.min(1, dt * 9)
	local now = os.clock()

	-- Les camions font une boucle continue de l'usine vers la ville. Le flux
	-- economique reste ainsi lisible dans le monde sans ouvrir un panneau.
	for _, route in self.routes do
		local previous = route.progress
		route.progress = (route.progress + dt * 0.14) % 1
		local scaled = route.progress * (#route.path - 1)
		local segmentIndex = math.min(#route.path - 1, math.floor(scaled) + 1)
		local segmentProgress = scaled - math.floor(scaled)
		local a = route.path[segmentIndex] + Vector3.new(0, 0.8, 0)
		local b = route.path[segmentIndex + 1] + Vector3.new(0, 0.8, 0)
		local direction = b - a
		local position = a + direction * segmentProgress
		local frame = CFrame.lookAt(position, position + direction)
		for _, piece in route.truck do
			local spin = if piece.part.Name == "Wheel" then CFrame.Angles(route.progress * math.pi * 20, 0, 0) else CFrame.new()
			piece.part.CFrame = frame * piece.offset * spin
		end
		if route.progress < previous then
			local pulse = routePart(self.root, "DeliveryPulse", Vector3.new(0.22, 2.8, 2.8), colorFor(route.slot), Enum.Material.Neon)
			pulse.Shape = Enum.PartType.Cylinder
			pulse.Transparency = 0.28
			pulse.CFrame = CFrame.new(route.to) * CFrame.Angles(0, 0, math.rad(90))
			TweenService:Create(pulse, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.22, 11, 11),
				Transparency = 1,
			}):Play()
			task.delay(0.85, function()
				if pulse.Parent then
					pulse:Destroy()
				end
			end)
		end
	end

	for _, model in self.buildings do
		BuildingModels.animate(model, now, dt)
	end

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

		local bob = if unit.isMissile then 0 else math.sin(now * 2.4 + unit.phase) * 0.24
		local position = Vector3.new(ground.X, height + bob, ground.Z)
		local direction = unit.target - unit.current

		if direction.Magnitude > 0.01 then
			local look = Vector3.new(direction.X, 0, direction.Y).Unit
			local frame = CFrame.lookAt(position, position + look)
			if not unit.isMissile then
				frame *= CFrame.Angles(math.sin(now * 1.7 + unit.phase) * 0.018, 0, math.sin(now * 2.1 + unit.phase) * 0.035)
			end
			UnitModels.place(unit.visual, frame, now + unit.phase, direction.Magnitude)
		else
			UnitModels.place(unit.visual, CFrame.new(position), now + unit.phase, 0)
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

	-- Onde horizontale : elle communique la portee bien mieux qu'une simple
	-- sphere et reste visible quand la camera regarde presque a la verticale.
	local shockwave = routePart(self.root, "Shockwave", Vector3.new(0.32, 5, 5), Color3.fromRGB(255, 229, 181), Enum.Material.Neon)
	shockwave.Shape = Enum.PartType.Cylinder
	shockwave.Transparency = 0.12
	shockwave.CFrame = CFrame.new(ground.X, Config.TERRAIN_HEIGHT[Config.TERRAIN.PLAINS] + 0.5, ground.Z) * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(shockwave, TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.32, worldRadius * 2.5, worldRadius * 2.5),
		Transparency = 1,
	}):Play()

	-- Colonne de fumee en volumes superposes. Elle est courte et stylisee pour
	-- rester lisible de loin sans texture de particules externe.
	for i = 1, 5 do
		local smoke = routePart(self.root, "BlastSmoke", Vector3.new(5 + i, 5 + i, 5 + i), Color3.fromRGB(82 + i * 7, 76 + i * 6, 71 + i * 5), Enum.Material.SmoothPlastic)
		smoke.Shape = Enum.PartType.Ball
		smoke.Transparency = 0.22 + i * 0.07
		smoke.CFrame = CFrame.new(ground.X + math.sin(i * 2.1) * 2, 7 + i * 5, ground.Z + math.cos(i * 1.7) * 2)
		TweenService:Create(smoke, TweenInfo.new(1.7 + i * 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = smoke.CFrame + Vector3.new(0, 18 + i * 3, 0),
			Size = smoke.Size * 2.1,
			Transparency = 1,
		}):Play()
		task.delay(2.5, function()
			if smoke.Parent then
				smoke:Destroy()
			end
		end)
	end

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
	task.delay(1, function()
		if shockwave.Parent then
			shockwave:Destroy()
		end
	end)
end

return Overlay
