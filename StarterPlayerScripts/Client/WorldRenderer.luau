--!strict
--[[
	Rendu du monde en vraie geometrie.

	Contrainte fondamentale : la carte compte 40 960 tuiles, et Roblox s'ecroule
	bien avant 40 000 Parts. On ne peut donc pas poser un bloc par tuile.

	Solution : **fusion gloutonne**. Dans chaque chunk, les tuiles voisines
	partageant le meme proprietaire et le meme relief sont fusionnees en grands
	rectangles, chacun devenant un seul Part. Un empire d'un seul tenant occupe
	quelques dizaines de blocs au lieu de milliers, et le nombre total reste de
	l'ordre du millier meme en fin de partie.

	La carte est decoupee en chunks pour que la reconstruction soit locale :
	quand une offensive prend vingt tuiles, on ne refait pas le monde, on refait
	les deux ou trois chunks concernes. Les reconstructions sont en plus
	etalees sur plusieurs frames, parce qu'une grande offensive salit des
	dizaines de chunks dans le meme tick — exactement le moment ou le joueur
	regarde l'ecran.
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

-- Assombrissement par relief : sans lui, un plateau et une montagne de la meme
-- faction forment une masse illisible malgre leur difference de hauteur.
local TERRAIN_SHADE = {
	[1] = 1.0,
	[2] = 0.88,
	[3] = 0.74,
}

--=============================================================================
-- Construction
--=============================================================================

function WorldRenderer.new(seed: number): WorldRenderer
	local self = setmetatable({}, WorldRenderer) :: any

	self.terrain = MapGen.generate(seed)
	self.owner = buffer.create(W * H)
	self.chunkFolders = {} :: { [number]: Folder }
	self.dirty = {} :: { [number]: boolean }
	self.dirtyQueue = {} :: { number }
	self.partCount = 0
	-- Table de travail du mailleur, reutilisee entre chunks pour eviter une
	-- allocation par reconstruction.
	self.meshScratch = {}

	local root = Workspace:FindFirstChild("ConquestWorld")
	if root then
		root:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "ConquestWorld"
	root.Parent = Workspace
	self.root = root

	self:buildOcean()

	-- Tous les chunks sont marques sales : le monde apparait progressivement
	-- sur environ une seconde plutot qu'en figeant la frame de chargement.
	for chunk = 0, Config.CHUNKS_X * Config.CHUNKS_Y - 1 do
		self:markChunkDirty(chunk)
	end

	return self
end

--[[
	L'ocean est un unique plan : il n'a pas de relief, donc le decouper en
	blocs serait du gaspillage pur.
]]
function WorldRenderer.buildOcean(self: WorldRenderer)
	local water = Instance.new("Part")
	water.Name = "Ocean"
	water.Anchored = true
	water.CanCollide = true
	water.CanTouch = false
	water.CastShadow = false
	water.Material = Enum.Material.Glass
	water.Transparency = 0.25
	water.Color = Color3.fromRGB(28, 58, 96)
	water.Size = Vector3.new(Config.WORLD_WIDTH, Config.OCEAN_LEVEL * 2, Config.WORLD_DEPTH)
	water.CFrame = CFrame.new(0, 0, 0)
	water.TopSurface = Enum.SurfaceType.Smooth
	water.BottomSurface = Enum.SurfaceType.Smooth
	water.Parent = self.root
	self.ocean = water

	-- Fond sombre sous l'eau, pour que l'ocean ne soit pas transparent sur le
	-- vide quand la camera passe au ras de la surface.
	local floor = Instance.new("Part")
	floor.Name = "SeaFloor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.CanTouch = false
	floor.CanQuery = false
	floor.CastShadow = false
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(14, 24, 40)
	floor.Size = Vector3.new(Config.WORLD_WIDTH, 2, Config.WORLD_DEPTH)
	floor.CFrame = CFrame.new(0, -2, 0)
	floor.Parent = self.root
end

--=============================================================================
-- Chunks
--=============================================================================

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

--[[
	Marque sale le chunk d'une tuile, plus les chunks voisins si la tuile est
	sur un bord : un bloc fusionne peut deborder logiquement sur la frontiere du
	chunk, et ne pas le rafraichir laisse une couture visible.
]]
function WorldRenderer.markTileDirty(self: WorldRenderer, index: number)
	local x, y = MapGen.fromIndex(index)
	self:markChunkDirty(chunkOf(x, y))

	if x % CHUNK == 0 and x > 0 then
		self:markChunkDirty(chunkOf(x - 1, y))
	end
	if x % CHUNK == CHUNK - 1 and x < W - 1 then
		self:markChunkDirty(chunkOf(x + 1, y))
	end
	if y % CHUNK == 0 and y > 0 then
		self:markChunkDirty(chunkOf(x, y - 1))
	end
	if y % CHUNK == CHUNK - 1 and y < H - 1 then
		self:markChunkDirty(chunkOf(x, y + 1))
	end
end

local function colorFor(slot: number, terrain: number): Color3
	local base = if slot == NEUTRAL then Config.TERRAIN_COLORS[terrain] else Theme.factionColor(slot)
	local shade = TERRAIN_SHADE[terrain] or 1
	return Color3.new(base.R * shade, base.G * shade, base.B * shade)
end

--[[
	Cle de fusion cote client : proprietaire **et** relief. Deux tuiles ne
	fusionnent que si elles ont la meme couleur et la meme hauteur, sinon le
	bloc obtenu serait a cheval sur deux factions.
]]
function WorldRenderer.chunkKeyAt(self: WorldRenderer, x: number, y: number): number?
	local index = MapGen.toIndex(x, y)
	local terrain = buffer.readu8(self.terrain, index)
	if terrain == OCEAN then
		return nil -- l'ocean n'a pas de bloc, c'est un plan unique
	end
	return buffer.readu8(self.owner, index) * 8 + terrain
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

	local cx = (chunk % Config.CHUNKS_X) * CHUNK
	local cy = (chunk // Config.CHUNKS_X) * CHUNK
	local x1 = math.min(cx + CHUNK - 1, W - 1)
	local y1 = math.min(cy + CHUNK - 1, H - 1)

	local rects = GreedyMesh.rectangles(function(x, y)
		return self:chunkKeyAt(x, y)
	end, cx, cy, x1, y1, self.meshScratch)

	for _, rect in rects do
		local terrain = rect.key % 8
		local slot = (rect.key - terrain) // 8
		local blockHeight = Config.TERRAIN_HEIGHT[terrain]

		local origin = WorldSpace.tileToWorld(rect.x, rect.y)

		local part = Instance.new("Part")
		part.Anchored = true
		-- La collision est assuree par la geometrie du serveur : celle-ci n'est
		-- que visuelle, et la rendre solide dupliquerait inutilement le travail
		-- du moteur physique.
		part.CanCollide = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(rect.width * TILE, blockHeight, rect.depth * TILE)
		part.CFrame = CFrame.new(
			origin.X + (rect.width - 1) * TILE / 2,
			blockHeight / 2,
			origin.Z + (rect.depth - 1) * TILE / 2
		)
		part.Color = colorFor(slot, terrain)
		part.Parent = folder
	end

	self.partCount += #rects
	folder.Parent = self.root
end

--[[
	Traite la file de reconstruction, dans la limite du budget par frame.
	Renvoie le nombre de chunks reellement reconstruits.
]]
function WorldRenderer.stepRebuilds(self: WorldRenderer): number
	local budget = Config.CHUNK_REBUILDS_PER_FRAME
	local done = 0

	while done < budget and #self.dirtyQueue > 0 do
		local chunk = table.remove(self.dirtyQueue, 1)
		if chunk and self.dirty[chunk] then
			self.dirty[chunk] = nil
			self:rebuildChunk(chunk)
			done += 1
		end
	end

	return done
end

--=============================================================================
-- Reseau
--=============================================================================

--[[
	Applique un delta serveur ([u32 index][u8 slot] repete) et marque les chunks
	concernes pour reconstruction.

	Renvoie aussi les **conquetes**, classees par camp : ce sont elles qui
	alimentent les effets visuels. On distingue la colonisation de terrain
	neutre — aucun effet, prendre du vide n'est pas un fait d'armes — d'une
	prise sur une autre faction.
]]
function WorldRenderer.applyDelta(
	self: WorldRenderer,
	delta: buffer,
	mySlot: number
): (number, { number }, { number }, { number })
	local count = buffer.len(delta) // 5

	local gains: { number } = {} -- arrachees a une faction par le joueur local
	local losses: { number } = {} -- perdues par le joueur local
	local others: { number } = {} -- prises entre tierces factions

	for i = 0, count - 1 do
		local offset = i * 5
		local index = buffer.readu32(delta, offset)
		if index >= W * H then
			continue
		end

		local previous = buffer.readu8(self.owner, index)
		local nextOwner = buffer.readu8(delta, offset + 4)

		buffer.writeu8(self.owner, index, nextOwner)
		self:markTileDirty(index)

		if previous ~= NEUTRAL then
			if nextOwner == mySlot then
				table.insert(gains, index)
			elseif previous == mySlot then
				table.insert(losses, index)
			else
				table.insert(others, index)
			end
		end
	end

	return count, gains, losses, others
end

function WorldRenderer.ownerAt(self: WorldRenderer, index: number): number
	return buffer.readu8(self.owner, index)
end

function WorldRenderer.isLand(self: WorldRenderer, index: number): boolean
	return buffer.readu8(self.terrain, index) ~= OCEAN
end

function WorldRenderer.destroy(self: WorldRenderer)
	self.root:Destroy()
end

return WorldRenderer
