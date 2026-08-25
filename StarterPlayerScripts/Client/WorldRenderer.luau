--!strict
--[[
	Rendu du monde en blocs (greedy mesh + matériaux par terrain).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))
local GreedyMesh = require(Shared:WaitForChild("GreedyMesh"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT
local TILE = Config.TILE_SIZE
local CHUNK = Config.CHUNK_SIZE
local OCEAN = Config.TERRAIN.OCEAN
local NEUTRAL = Config.NEUTRAL_SLOT

local WorldRenderer = {}
WorldRenderer.__index = WorldRenderer

export type WorldRenderer = typeof(setmetatable({} :: any, WorldRenderer))

function WorldRenderer.new(seed: number): WorldRenderer
	local self = setmetatable({}, WorldRenderer) :: any
	self.seed = seed
	self.terrain = MapGen.generate(seed)
	self.owner = buffer.create(W * H)
	self.chunkFolders = {} :: { [number]: Folder }
	self.dirty = {} :: { [number]: boolean }
	self.dirtyQueue = {} :: { number }
	self.partCount = 0
	self.meshScratch = {}
	self.elapsed = 0
	self.oceanRipples = {}
	self.animatedFoliage = {}
	self.everBuilt = {} :: { [number]: boolean }
	self.builtCount = 0
	self.totalChunks = Config.CHUNKS_X * Config.CHUNKS_Y

	local root = Workspace:FindFirstChild("ConquestWorld")
	if root then
		root:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "ConquestWorld"
	root.Parent = Workspace
	self.root = root

	self:buildOcean()
	self:buildDecorations()

	for chunk = 0, Config.CHUNKS_X * Config.CHUNKS_Y - 1 do
		self:markChunkDirty(chunk)
	end
	return self
end

function WorldRenderer.buildOcean(self: WorldRenderer)
	local water = Instance.new("Part")
	water.Name = "Ocean"
	water.Anchored = true
	water.CanCollide = false
	water.CanTouch = false
	water.CanQuery = true
	water.CastShadow = false
	water.Material = Enum.Material.Glass
	water.Transparency = 0.42
	water.Reflectance = 0.12
	water.Color = Color3.fromRGB(26, 62, 104)
	water.Size = Vector3.new(Config.WORLD_WIDTH, Config.OCEAN_LEVEL * 2, Config.WORLD_DEPTH)
	water.CFrame = CFrame.new(0, Config.OCEAN_LEVEL, 0)
	water.TopSurface = Enum.SurfaceType.Smooth
	water.BottomSurface = Enum.SurfaceType.Smooth
	water.Parent = self.root
	self.ocean = water

	local floor = Instance.new("Part")
	floor.Name = "OceanFloor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.CanTouch = false
	floor.CanQuery = false
	floor.CastShadow = false
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(12, 22, 38)
	floor.Size = Vector3.new(Config.WORLD_WIDTH, 1, Config.WORLD_DEPTH)
	floor.CFrame = CFrame.new(0, -2, 0)
	floor.Parent = self.root

	-- Moins de glints (pas 9) pour mobile
	for y = 8, H - 1, 14 do
		for x = 8, W - 1, 14 do
			local jitterX = (x * 17 + y * 13 + self.seed) % 5 - 2
			local jitterY = (x * 11 + y * 19 + self.seed * 2) % 5 - 2
			local px = math.clamp(x + jitterX, 0, W - 1)
			local py = math.clamp(y + jitterY, 0, H - 1)
			if buffer.readu8(self.terrain, MapGen.toIndex(px, py)) ~= OCEAN then
				continue
			end
			local world = WorldSpace.tileToWorld(px, py)
			local angle = ((px * 13 + py * 7) % 180) * math.pi / 180
			local glint = Instance.new("Part")
			glint.Name = "OceanGlint"
			glint.Anchored = true
			glint.CanCollide = false
			glint.CanTouch = false
			glint.CanQuery = false
			glint.CastShadow = false
			glint.Material = Enum.Material.Neon
			glint.Color = Color3.fromRGB(116, 205, 226)
			glint.Transparency = 0.78
			glint.Size = Vector3.new(2.4 * Config.WORLD_SCALE, 0.06, 0.55 * Config.WORLD_SCALE)
			glint.CFrame = CFrame.new(world.X, Config.OCEAN_LEVEL + 0.08, world.Z) * CFrame.Angles(0, angle, 0)
			glint.Parent = self.root
			table.insert(self.oceanRipples, { part = glint, base = glint.CFrame, phase = (px * 0.37 + py * 0.61) % (math.pi * 2) })
		end
	end
end

local function decorationPart(parent: Instance, className: string, name: string, size: Vector3, color: Color3, frame: CFrame, material: Enum.Material): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = frame
	part.Parent = parent
	return part
end

function WorldRenderer.buildDecorations(self: WorldRenderer)
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	folder.Parent = self.root
	-- Densité réduite (pas 9 → 11) pour mobile
	for y = 6, H - 1, 11 do
		for x = 6, W - 1, 11 do
			local jitterX = (x * 17 + y * 13 + self.seed) % 7 - 3
			local jitterY = (x * 11 + y * 19 + self.seed * 2) % 7 - 3
			local px = math.clamp(x + jitterX, 0, W - 1)
			local py = math.clamp(y + jitterY, 0, H - 1)
			local index = MapGen.toIndex(px, py)
			local terrain = buffer.readu8(self.terrain, index)
			local base = WorldSpace.indexToWorld(index)
			local ground = WorldSpace.surfaceHeight(self.terrain, index)
			local phase = (px * 0.37 + py * 0.61) % (math.pi * 2)
			if terrain == Config.TERRAIN.FOREST then
				local height = 3.8 + ((px + py) % 4) * 0.45
				local trunk = decorationPart(folder, "Part", "TreeTrunk", Vector3.new(height, 0.55, 0.55), Color3.fromRGB(91, 67, 47), CFrame.new(base.X, ground + height / 2, base.Z) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Wood)
				trunk.Shape = Enum.PartType.Cylinder
				local crown = decorationPart(folder, "Part", "TreeCrown", Vector3.new(3.2, 3.8, 3.2), Color3.fromRGB(48 + (px % 3) * 6, 104 + (py % 4) * 6, 69), CFrame.new(base.X, ground + height + 1.1, base.Z), Enum.Material.LeafyGrass)
				crown.Shape = Enum.PartType.Ball
				table.insert(self.animatedFoliage, { part = crown, base = crown.CFrame, phase = phase })
			elseif terrain == Config.TERRAIN.SAVANNA and (px + py) % 3 == 0 then
				local trunk = decorationPart(folder, "Part", "SavannaTrunk", Vector3.new(3.2, 0.45, 0.45), Color3.fromRGB(100, 70, 44), CFrame.new(base.X, ground + 1.6, base.Z) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Wood)
				trunk.Shape = Enum.PartType.Cylinder
				local crown = decorationPart(folder, "Part", "SavannaCrown", Vector3.new(4.2, 1.5, 3.7), Color3.fromRGB(103, 131, 67), CFrame.new(base.X, ground + 3.5, base.Z), Enum.Material.LeafyGrass)
				crown.Shape = Enum.PartType.Ball
				table.insert(self.animatedFoliage, { part = crown, base = crown.CFrame, phase = phase })
			elseif terrain >= Config.TERRAIN.HILLS then
				decorationPart(folder, "WedgePart", "Rock", Vector3.new(1.8 + px % 3, 1.1 + py % 2, 1.8 + (px + py) % 2), Color3.fromRGB(103, 111, 118), CFrame.new(base.X, ground + 0.55, base.Z) * CFrame.Angles(0, phase, 0), Enum.Material.Rock)
			end
		end
	end
end

local function chunkOf(x: number, y: number): number
	return (y // CHUNK) * Config.CHUNKS_X + (x // CHUNK)
end

function WorldRenderer.markChunkDirty(self: WorldRenderer, chunk: number)
	if self.dirty[chunk] then
		return
	end
	self.dirty[chunk] = true
	table.insert(self.dirtyQueue, chunk)
end

function WorldRenderer.markTileDirty(self: WorldRenderer, index: number)
	local x, y = MapGen.fromIndex(index)
	self:markChunkDirty(chunkOf(x, y))
	for _, d in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
		local nx, ny = x + d[1], y + d[2]
		if MapGen.inBounds(nx, ny) then
			self:markChunkDirty(chunkOf(nx, ny))
		end
	end
end

local KEY_STRIDE = 16

local function blockColor(slot: number, terrain: number): Color3
	local base = Theme.terrainColor and Theme.terrainColor(terrain) or Color3.fromRGB(90, 120, 70)
	if Theme.terrainBase then
		base = Theme.terrainBase(terrain) or base
	end
	-- Fallback palette if Theme has no terrain helpers
	local T = Config.TERRAIN
	if terrain == T.BEACH then
		base = Color3.fromRGB(194, 178, 128)
	elseif terrain == T.PLAINS then
		base = Color3.fromRGB(92, 140, 72)
	elseif terrain == T.SAVANNA then
		base = Color3.fromRGB(168, 148, 88)
	elseif terrain == T.FOREST then
		base = Color3.fromRGB(48, 98, 58)
	elseif terrain == T.HILLS then
		base = Color3.fromRGB(110, 118, 92)
	elseif terrain == T.HIGHLAND then
		base = Color3.fromRGB(128, 128, 118)
	elseif terrain == T.MOUNTAIN then
		base = Color3.fromRGB(118, 122, 128)
	elseif terrain == T.PEAK then
		base = Color3.fromRGB(210, 214, 220)
	end
	local shade = 1
	if slot ~= NEUTRAL then
		base = Theme.factionColor(slot):Lerp(base, 0.24)
	end
	return Color3.new(math.clamp(base.R * shade, 0, 1), math.clamp(base.G * shade, 0, 1), math.clamp(base.B * shade, 0, 1))
end

function WorldRenderer.chunkKeyAt(self: WorldRenderer, x: number, y: number): number?
	local index = MapGen.toIndex(x, y)
	local terrain = buffer.readu8(self.terrain, index)
	if terrain == OCEAN then
		return nil
	end
	return buffer.readu8(self.owner, index) * KEY_STRIDE + terrain
end

local function borderColor(slot: number): Color3
	return Theme.factionColor(slot)
end

local BORDER_THICKNESS = 0.55 * Config.WORLD_SCALE
local BORDER_LIFT = 0.08 * Config.WORLD_SCALE

function WorldRenderer.buildChunkBorders(self: WorldRenderer, folder: Folder, cx: number, cy: number, x1: number, y1: number): number
	local drawn = 0
	local surface = Config.LAND_HEIGHT + BORDER_LIFT
	local function ownerOf(x: number, y: number): number?
		if x < 0 or x >= W or y < 0 or y >= H then
			return nil
		end
		local index = MapGen.toIndex(x, y)
		if buffer.readu8(self.terrain, index) == OCEAN then
			return nil
		end
		local slot = buffer.readu8(self.owner, index)
		return if slot == NEUTRAL then nil else slot
	end
	local function emit(slot: number, ax: number, ay: number, bx: number, by: number, dx: number, dy: number)
		local a = WorldSpace.tileToWorld(ax, ay)
		local b = WorldSpace.tileToWorld(bx, by)
		local inset = TILE / 2 - BORDER_THICKNESS / 2
		local horizontal = dy ~= 0
		local length = (if horizontal then math.abs(bx - ax) else math.abs(by - ay)) * TILE + TILE
		local part = Instance.new("Part")
		part.Name = "Border"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Color = borderColor(slot)
		part.Transparency = 0.18
		part.Size = if horizontal
			then Vector3.new(length, 0.09 * Config.WORLD_SCALE, BORDER_THICKNESS)
			else Vector3.new(BORDER_THICKNESS, 0.09 * Config.WORLD_SCALE, length)
		part.CFrame = CFrame.new((a.X + b.X) / 2 + dx * inset, surface, (a.Z + b.Z) / 2 + dy * inset)
		part.Parent = folder
		drawn += 1
	end
	local passes = { { dx = 0, dy = -1 }, { dx = 0, dy = 1 }, { dx = -1, dy = 0 }, { dx = 1, dy = 0 } }
	for _, pass in passes do
		local alongRow = pass.dy ~= 0
		local outerFrom = if alongRow then cy else cx
		local outerTo = if alongRow then y1 else x1
		local innerFrom = if alongRow then cx else cy
		local innerTo = if alongRow then x1 else y1
		for outer = outerFrom, outerTo do
			local runSlot: number? = nil
			local runStart = 0
			for inner = innerFrom, innerTo + 1 do
				local slot: number? = nil
				if inner <= innerTo then
					local x = if alongRow then inner else outer
					local y = if alongRow then outer else inner
					local here = ownerOf(x, y)
					if here then
						local nx, ny = x + pass.dx, y + pass.dy
						local neighbor = ownerOf(nx, ny)
						if neighbor ~= here then
							slot = here
						end
					end
				end
				if slot ~= runSlot then
					if runSlot then
						local ax = if alongRow then runStart else outer
						local ay = if alongRow then outer else runStart
						local bx = if alongRow then inner - 1 else outer
						local by = if alongRow then outer else inner - 1
						emit(runSlot, ax, ay, bx, by, pass.dx, pass.dy)
					end
					runSlot = slot
					runStart = inner
				end
			end
		end
	end
	return drawn
end

local function materialForTerrain(terrain: number): Enum.Material
	local T = Config.TERRAIN
	if terrain == T.BEACH or terrain == T.SAVANNA then
		return Enum.Material.Sand
	elseif terrain == T.FOREST then
		return Enum.Material.LeafyGrass
	elseif terrain == T.PLAINS then
		return Enum.Material.Grass
	elseif terrain == T.HILLS or terrain == T.HIGHLAND then
		return Enum.Material.Slate
	elseif terrain == T.MOUNTAIN or terrain == T.PEAK then
		return Enum.Material.Rock
	end
	return Enum.Material.Ground
end

function WorldRenderer.rebuildChunk(self: WorldRenderer, chunk: number)
	local existing = self.chunkFolders[chunk]
	if existing then
		self.partCount -= #existing:GetChildren()
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = `Chunk{chunk}`
	self.chunkFolders[chunk] = folder
	if not self.everBuilt[chunk] then
		self.everBuilt[chunk] = true
		self.builtCount += 1
	end
	local cx = (chunk % Config.CHUNKS_X) * CHUNK
	local cy = (chunk // Config.CHUNKS_X) * CHUNK
	local x1 = math.min(cx + CHUNK - 1, W - 1)
	local y1 = math.min(cy + CHUNK - 1, H - 1)
	local rects = GreedyMesh.rectangles(function(x, y)
		return self:chunkKeyAt(x, y)
	end, cx, cy, x1, y1, self.meshScratch)
	for _, rect in rects do
		local terrain = rect.key % KEY_STRIDE
		local slot = (rect.key - terrain) // KEY_STRIDE
		local height = Config.TERRAIN_HEIGHT[terrain]
		local origin = WorldSpace.tileToWorld(rect.x, rect.y)
		local part = Instance.new("Part")
		part.Name = "Ground"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = materialForTerrain(terrain)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(rect.width * TILE, height, rect.depth * TILE)
		local yaw = ((rect.x * 17 + rect.y * 31) % 4) * math.pi * 0.5
		part.CFrame = CFrame.new(
			origin.X + (rect.width - 1) * TILE / 2,
			height / 2,
			origin.Z + (rect.depth - 1) * TILE / 2
		) * CFrame.Angles(0, yaw, 0)
		part.Color = blockColor(slot, terrain)
		part.Parent = folder
	end
	self.partCount += #rects
	self.partCount += self:buildChunkBorders(folder, cx, cy, x1, y1)
	folder.Parent = self.root
end

function WorldRenderer.step(self: WorldRenderer, dt: number)
	self.elapsed += dt
	local time = self.elapsed
	for _, ripple in self.oceanRipples do
		local wave = math.sin(time * 1.45 + ripple.phase)
		ripple.part.Transparency = 0.73 + wave * 0.09
		ripple.part.CFrame = ripple.base + Vector3.new(wave * 0.45, 0, math.cos(time + ripple.phase) * 0.2)
	end
	for _, foliage in self.animatedFoliage do
		local sway = math.sin(time * 0.7 + foliage.phase) * 0.04
		foliage.part.CFrame = foliage.base * CFrame.Angles(sway, 0, sway * 0.6)
	end
end

function WorldRenderer.stepRebuilds(self: WorldRenderer): number
	local budget = 4
	local rebuilt = 0
	while rebuilt < budget and #self.dirtyQueue > 0 do
		local chunk = table.remove(self.dirtyQueue, 1)
		if chunk and self.dirty[chunk] then
			self.dirty[chunk] = nil
			self:rebuildChunk(chunk)
			rebuilt += 1
		end
	end
	return rebuilt
end

function WorldRenderer.applyDelta(self: WorldRenderer, ownerDelta: buffer?)
	if not ownerDelta then
		return
	end
	for index = 0, Config.TILE_COUNT - 1 do
		local nextOwner = buffer.readu8(ownerDelta, index)
		if nextOwner ~= 255 then
			buffer.writeu8(self.owner, index, nextOwner)
			self:markTileDirty(index)
		end
	end
end

function WorldRenderer.initialProgress(self: WorldRenderer): number
	if self.totalChunks <= 0 then
		return 1
	end
	return self.builtCount / self.totalChunks
end

function WorldRenderer.ownerAt(self: WorldRenderer, index: number): number
	return buffer.readu8(self.owner, index)
end

function WorldRenderer.isLand(self: WorldRenderer, index: number): boolean
	return buffer.readu8(self.terrain, index) ~= OCEAN
end

function WorldRenderer.destroy(self: WorldRenderer)
	if self.root then
		self.root:Destroy()
	end
end

return WorldRenderer
