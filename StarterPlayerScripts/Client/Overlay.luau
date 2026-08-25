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

	Routes logistiques : 2 calques (ballast beton + deck metal teinte faction)
	via Shared/RouteStyle — moins de Parts, lecture faction claire.
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
local RailPath = require(Shared:WaitForChild("RailPath"))
local RouteStyle = require(Shared:WaitForChild("RouteStyle"))
local Format = require(Shared:WaitForChild("Format"))
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
	self.counts = {}
	self.mySlot = 0
	self.routes = {}
	self.units = {}
	self.seen = {}
	self.animateFrom = os.clock() + 3

	local root = Instance.new("Folder")
	root.Name = "Entities"
	root.Parent = parent
	self.root = root

	return self
end

function Overlay.clear(self: Overlay)
	table.clear(self.counts)
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

	local anchor = model:FindFirstChildWhichIsA("BasePart")
	if anchor then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Marker"
		local size = if kind == Config.BUILDING.CAPITAL then 32 else 22
		billboard.Size = UDim2.fromOffset(size, size)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 1400
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
			then `{def.symbol}{if level > 1 and BuildingDefs.isUpgradable(kind) then level else ""}`
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

local function applyRouteProgress(construction: any, progress: number)
	local covered = construction.total * math.clamp(progress, 0, 1)
	for _, segment in construction.segments do
		local visible = math.clamp(covered - segment.startsAt, 0, segment.length)
		for _, layer in segment.layers do
			local part = layer.part
			local shown = math.max(0.01, visible * layer.ratio)
			part.Size = Vector3.new(layer.width, layer.thickness, shown)
			local centre = segment.origin + segment.direction * (visible - shown / 2)
			part.CFrame = CFrame.lookAt(centre, centre + segment.direction) + Vector3.new(0, layer.lift, 0)
			part.Transparency = if visible <= 0.01
				then 1
				elseif layer.ratio < 1 then 0.28
				else 0
		end
	end
end

function Overlay.buildFactoryRoute(self: Overlay, factoryIndex: number, cityIndex: number, slot: number)
	local tiles = RailPath.find(self.terrain, factoryIndex, cityIndex)
	if not tiles or #tiles < 2 then
		return
	end

	local roadY = WorldSpace.surfaceHeight(self.terrain, factoryIndex) + 0.38

	local model = Instance.new("Model")
	model.Name = `LogisticsRoute{factoryIndex}`
	model.Parent = self.root

	local function worldAt(index: number): Vector3
		local base = WorldSpace.indexToWorld(index)
		return Vector3.new(base.X, roadY, base.Z)
	end

	local runs = RailPath.runs(tiles)
	local tileSize = Config.TILE_SIZE
	local segments: { any } = {}
	local totalLength = 0

	for _, run in runs do
		local a = worldAt(run.fromIndex)
		local b = worldAt(run.toIndex)
		local span = b - a
		if span.Magnitude < 0.01 then
			continue
		end

		local length = span.Magnitude + tileSize
		local frame = CFrame.lookAt(a + span * 0.5, b)
		local direction = span.Unit
		local origin = a - direction * (tileSize / 2)

		local layers = RouteStyle.makeLayers(routePart, model, frame, length, slot)
		table.insert(segments, {
			layers = layers,
			origin = origin,
			direction = direction,
			length = length,
			startsAt = totalLength,
		})
		totalLength += length
	end

	if #segments > 0 and totalLength > 0 and os.clock() >= self.animateFrom then
		local construction = {
			progress = 0,
			duration = math.clamp(totalLength / Config.ROUTE_BUILD_SPEED, 0.35, 3),
			segments = segments,
			total = totalLength,
		}
		applyRouteProgress(construction, 0)
		self.pendingConstruction = construction
	end

	local path: { Vector3 } = { worldAt(tiles[1]) }
	for _, run in runs do
		table.insert(path, worldAt(run.toIndex))
	end

	local from = path[1]
	local to = path[#path]

	local truckModel = Instance.new("Model")
	truckModel.Name = "CargoTruck"
	truckModel.Parent = nil
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

	self.routes[factoryIndex * 100000 + cityIndex] = {
		factory = factoryIndex,
		model = model,
		truck = truck,
		truckModel = truckModel,
		from = from + Vector3.new(0, 0.8, 0),
		to = to + Vector3.new(0, 0.8, 0),
		path = path,
		slot = slot,
		delivery = nil,
		construction = self.pendingConstruction,
	}
	self.pendingConstruction = nil
end

function Overlay.onTradeEvent(self: Overlay, action: string, a: number, b: number, slot: number, value: number)
	if action == "dispatch" then
		local route = self.routes[a * 100000 + b]
		if not route then
			return
		end
		route.delivery = {
			progress = 0,
			duration = math.max(value / Config.TICK_RATE, 0.1),
		}
		route.truckModel.Parent = route.model
	elseif action == "arrival" then
		self:goldPopup(a, value, slot == self.mySlot)
	end
end

function Overlay.setLocalSlot(self: Overlay, slot: number)
	self.mySlot = slot
end

function Overlay.goldPopup(self: Overlay, tileIndex: number, gold: number, mine: boolean?)
	local base = WorldSpace.indexToWorld(tileIndex)
	local y = WorldSpace.surfaceHeight(self.terrain, tileIndex)

	local anchor = Instance.new("Part")
	anchor.Name = "GoldPopup"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(base.X, y + 7 * Config.WORLD_SCALE, base.Z)
	anchor.Parent = self.root

	local ours = mine ~= false
	local board = Instance.new("BillboardGui")
	board.Name = "Board"
	board.Size = UDim2.fromOffset(if ours then 120 else 80, if ours then 32 else 22)
	board.StudsOffset = Vector3.new(0, 1.5, 0)
	board.AlwaysOnTop = true
	board.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.FontFace = Theme.font.display
	text.TextSize = if ours then 22 else 15
	text.TextColor3 = Theme.color.gold
	text.TextStrokeTransparency = if ours then 0.35 else 0.7
	text.TextTransparency = if ours then 0 else 0.35
	text.Text = `+{Format.compact(gold)} or`
	text.Parent = board

	local lift = TweenService:Create(anchor, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame + Vector3.new(0, 5 * Config.WORLD_SCALE, 0),
	})
	lift:Play()
	TweenService:Create(text, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.5, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

local EMPTY_COUNTS: { [number]: number } = {}

function Overlay.buildingCounts(self: Overlay, slot: number): { [number]: number }
	return self.counts[slot] or EMPTY_COUNTS
end

function Overlay.tally(self: Overlay, slot: number?, kind: number?, sign: number)
	if not slot or not kind or kind == 0 then
		return
	end
	local bucket = self.counts[slot]
	if not bucket then
		bucket = {}
		self.counts[slot] = bucket
	end
	bucket[kind] = math.max(0, (bucket[kind] or 0) + sign)
end

function Overlay.applyBuildingDelta(self: Overlay, deltas: { Types.BuildingSnapshot })
	for _, entry in deltas do
		local existing = self.buildings[entry.index]
		local level = entry.level or 1

		if existing then
			self:tally(existing:GetAttribute("Slot") :: number?, existing:GetAttribute("Kind") :: number?, -1)
		end
		if entry.kind ~= 0 then
			self:tally(entry.slot, entry.kind, 1)
		end

		if entry.kind == 0 then
			self:syncFactoryRoutes(entry.index, nil, 0)
			if existing then
				existing:Destroy()
				self.buildings[entry.index] = nil
			end
			continue
		end

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
-- Unites (boats / missiles) — kept intact from master
--=============================================================================

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

	for id, unit in self.units do
		if not self.seen[id] then
			unit.visual.model:Destroy()
			self.units[id] = nil
		end
	end
end

function Overlay.stepInterpolation(self: Overlay, dt: number)
	local alpha = math.min(1, dt * 9)
	local now = os.clock()

	for _, route in self.routes do
		local construction = route.construction
		if construction then
			construction.progress += dt / construction.duration
			applyRouteProgress(construction, construction.progress)
			if construction.progress >= 1 then
				route.construction = nil
			end
		end
	end

	for _, route in self.routes do
		local delivery = route.delivery
		if not delivery then
			continue
		end
		delivery.progress += dt / delivery.duration
		if delivery.progress >= 1 then
			route.delivery = nil
			route.truckModel.Parent = nil
			continue
		end
		local scaled = delivery.progress * (#route.path - 1)
		local segmentIndex = math.min(#route.path - 1, math.floor(scaled) + 1)
		local segmentProgress = scaled - math.floor(scaled)
		local a = route.path[segmentIndex] + Vector3.new(0, 0.8, 0)
		local b = route.path[segmentIndex + 1] + Vector3.new(0, 0.8, 0)
		local direction = b - a
		local position = a + direction * segmentProgress
		local frame = CFrame.lookAt(position, position + direction)
		for _, piece in route.truck do
			local spin = if piece.part.Name == "Wheel" then CFrame.Angles(delivery.progress * math.pi * 20, 0, 0) else CFrame.new()
			piece.part.CFrame = frame * piece.offset * spin
		end
	end

	for _, model in self.buildings do
		BuildingModels.animate(model, now, dt)
	end

	for _, unit in self.units do
		unit.current += (unit.target - unit.current) * alpha
		local x, y = unit.current.X, unit.current.Y
		local ground = WorldSpace.tileToWorld(x, y)
		local height = if unit.isMissile then 40 else Config.OCEAN_LEVEL + 1
		if unit.isMissile and unit.extra then
			local remaining = math.sqrt((unit.extra.tx - x) ^ 2 + (unit.extra.ty - y) ^ 2)
			local approach = math.clamp(remaining / 60, 0, 1)
			height = 25 + math.sin(approach * math.pi * 0.5) * 95
		end
		local bob = if unit.isMissile then 0 else math.sin(now * 2.4 + unit.phase) * 0.24
		local position = Vector3.new(ground.X, height + bob, ground.Z)
		local direction = unit.target - unit.current
		if direction.Magnitude > 0.01 then
			local look = Vector3.new(direction.X, 0, direction.Y).Unit
			UnitModels.place(unit.visual, CFrame.lookAt(position, position + look), now + unit.phase, direction.Magnitude)
		else
			UnitModels.place(unit.visual, CFrame.new(position), now + unit.phase, 0)
		end
	end
end

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
	task.delay(1.3, function()
		sphere:Destroy()
	end)
end

return Overlay
