--!strict
--[[
	Calque des entites : batiments, navires, missiles, explosions.

	La carte elle-meme est peinte au pixel (voir MapRenderer). Tout ce qui doit
	rester lisible quel que soit le zoom vit ici, sous forme de petits GuiObjects
	enfants de l'image : leur position est en Scale (donc suit le zoom et le
	pan automatiquement) mais leur taille est en Offset (donc reste constante a
	l'ecran). Un port reste identifiable aussi bien de loin que de pres.

	Le nombre d'elements est volontairement petit — quelques centaines de
	batiments et quelques dizaines de navires — ce qui rend l'approche par
	instances viable ici, alors qu'elle serait catastrophique pour les 40 000
	tuiles du terrain.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))
local BuildingDefs = require(Shared:WaitForChild("BuildingDefs"))
local Theme = require(Shared:WaitForChild("Theme"))
local Types = require(Shared:WaitForChild("Types"))

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT

local Overlay = {}
Overlay.__index = Overlay

type UnitVisual = {
	frame: Frame,
	targetX: number,
	targetY: number,
	currentX: number,
	currentY: number,
}

export type Overlay = typeof(setmetatable(
	{} :: {
		root: Frame,
		buildingLayer: Frame,
		unitLayer: Frame,
		effectLayer: Frame,
		buildings: { [number]: TextLabel },
		units: { [number]: UnitVisual },
		seen: { [number]: boolean },
	},
	Overlay
))

local colorFor = Theme.factionColor

-- Position en Scale d'une tuile, centre de la case.
local function scalePosition(x: number, y: number): UDim2
	return UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H)
end

local function makeLayer(name: string, parent: GuiObject): Frame
	local layer = Instance.new("Frame")
	layer.Name = name
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.Parent = parent
	return layer
end

function Overlay.new(mapLabel: ImageLabel): Overlay
	local self = setmetatable({}, Overlay) :: Overlay

	local root = Instance.new("Frame")
	root.Name = "Overlay"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = mapLabel
	self.root = root

	self.buildingLayer = makeLayer("Buildings", root)
	self.unitLayer = makeLayer("Units", root)
	self.effectLayer = makeLayer("Effects", root)

	self.buildings = {}
	self.units = {}
	self.seen = {}

	return self
end

function Overlay.clear(self: Overlay)
	for _, label in self.buildings do
		label:Destroy()
	end
	for _, unit in self.units do
		unit.frame:Destroy()
	end
	table.clear(self.buildings)
	table.clear(self.units)
	table.clear(self.seen)
end

--=============================================================================
-- Batiments
--=============================================================================

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

		local def = BuildingDefs.get(entry.kind)
		if not def then
			continue
		end

		-- La capitale est le seul batiment qu'on doit reperer en un coup d'oeil
		-- depuis n'importe quel niveau de zoom : elle est nettement plus grosse.
		local isCapital = entry.kind == Config.BUILDING.CAPITAL
		local glyphSize = if isCapital then 26 else 18

		local label = existing
		if not label then
			label = Instance.new("TextLabel")
			label.Name = `B{entry.index}`
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Size = UDim2.fromOffset(glyphSize, glyphSize)
			label.BackgroundTransparency = 1
			label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
			label.TextScaled = true
			-- Contour sombre : sans lui, un symbole de faction claire disparait
			-- sur un territoire de teinte proche.
			local outline = Instance.new("UIStroke")
			outline.Color = Color3.fromRGB(10, 12, 18)
			outline.Thickness = 2
			outline.Parent = label

			local x, y = MapGen.fromIndex(entry.index)
			label.Position = scalePosition(x, y)
			label.Parent = self.buildingLayer
			self.buildings[entry.index] = label
		end

		label.Size = UDim2.fromOffset(glyphSize, glyphSize)
		label.Text = def.symbol
		label.TextColor3 = colorFor(entry.slot)
	end
end

--=============================================================================
-- Unites
--=============================================================================

local function makeBoatVisual(parent: Frame, slot: number, kind: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = colorFor(slot)

	if kind == 2 then
		-- Navire marchand : petit losange dore, visuellement inoffensif.
		frame.Size = UDim2.fromOffset(7, 7)
		frame.BackgroundColor3 = Theme.color.gold
		frame.Rotation = 45
	else
		-- Transport de troupes : plus gros, aux couleurs de la faction.
		frame.Size = UDim2.fromOffset(11, 11)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = frame
	end

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = frame

	frame.Parent = parent
	return frame
end

local function makeMissileVisual(parent: Frame, slot: number, kind: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(if kind == 2 then 14 else 10, if kind == 2 then 14 else 10)
	frame.BackgroundColor3 = Color3.fromRGB(255, 230, 120)
	frame.BorderSizePixel = 0
	frame.Rotation = 45

	local stroke = Instance.new("UIStroke")
	stroke.Color = colorFor(slot)
	stroke.Thickness = 2
	stroke.Parent = frame

	frame.Parent = parent
	return frame
end

--[[
	Les instantanes arrivent a 10 Hz. On stocke la position cible et on
	interpole a chaque frame, sinon les navires avancent par saccades visibles.
]]
function Overlay.applyUnits(self: Overlay, boats: { Types.BoatSnapshot }, missiles: { Types.MissileSnapshot })
	table.clear(self.seen)

	for _, boat in boats do
		local unit = self.units[boat.id]
		if not unit then
			unit = {
				frame = makeBoatVisual(self.unitLayer, boat.slot, boat.kind),
				targetX = boat.x,
				targetY = boat.y,
				currentX = boat.x,
				currentY = boat.y,
			}
			self.units[boat.id] = unit
		end
		unit.targetX = boat.x
		unit.targetY = boat.y
		self.seen[boat.id] = true
	end

	for _, missile in missiles do
		local unit = self.units[missile.id]
		if not unit then
			unit = {
				frame = makeMissileVisual(self.unitLayer, missile.slot, missile.kind),
				targetX = missile.x,
				targetY = missile.y,
				currentX = missile.x,
				currentY = missile.y,
			}
			self.units[missile.id] = unit
		end
		unit.targetX = missile.x
		unit.targetY = missile.y
		self.seen[missile.id] = true
	end

	-- Toute unite absente de l'instantane a disparu cote serveur.
	for id, unit in self.units do
		if not self.seen[id] then
			unit.frame:Destroy()
			self.units[id] = nil
		end
	end
end

function Overlay.stepInterpolation(self: Overlay, dt: number)
	local alpha = math.min(1, dt * 10)
	for _, unit in self.units do
		unit.currentX += (unit.targetX - unit.currentX) * alpha
		unit.currentY += (unit.targetY - unit.currentY) * alpha
		unit.frame.Position = scalePosition(unit.currentX, unit.currentY)
	end
end

--=============================================================================
-- Effets
--=============================================================================

--[[
	Onde de choc nucleaire. Elle est dimensionnee en Scale sur le rayon reel de
	la frappe, donc elle couvre exactement les tuiles reellement touchees — un
	joueur peut juger de la zone d'effet a l'oeil.
]]
function Overlay.explosion(self: Overlay, x: number, y: number, radius: number)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = scalePosition(x, y)
	ring.Size = UDim2.fromScale(0, 0)
	ring.BackgroundColor3 = Color3.fromRGB(255, 180, 90)
	ring.BackgroundTransparency = 0.25
	ring.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 240, 200)
	stroke.Thickness = 3
	stroke.Parent = ring

	ring.Parent = self.effectLayer

	local finalSize = UDim2.fromScale((radius * 2) / W, (radius * 2) / H)
	local tween = TweenService:Create(
		ring,
		TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = finalSize, BackgroundTransparency = 1 }
	)
	tween:Play()

	TweenService:Create(stroke, TweenInfo.new(0.9), { Transparency = 1 }):Play()

	task.delay(1.1, function()
		ring:Destroy()
	end)
end

return Overlay
