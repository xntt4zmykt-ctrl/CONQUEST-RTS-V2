--!strict
--[[
	Rendu du monde en blocs.

	Contrainte fondamentale : la carte compte 40 960 tuiles, et Roblox s'ecroule
	bien avant 40 000 Parts. Les tuiles voisines partageant le meme proprietaire
	et le meme relief sont donc fusionnees en grands rectangles, chacun devenant
	un seul Part.

	Pourquoi des blocs et non du SmoothTerrain : la carte **est** une grille de
	tuiles. Un terrain voxel lisse se bat en permanence contre cette grille —
	les frontieres politiques suivent des cases, pas des courbes — et il oblige
	a peindre la couleur des nations sur une couche separee, qui flotte au-dessus
	du sol au lieu d'en faire partie.

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

-- V48 : applyDelta recycle gains / losses / others (recette V47 candBuf).
-- Distinct de V14b (filaire buffer.create) et de V26 (boatSnapBuf).
-- Distinct de V101 (dirtyHead file, pas applyDelta). Distinct de V102
-- (compact prefix dirtyQueue, pas applyDelta).
-- Non reentrant — applyDelta synchrone unique par frame. Truncate leftover
-- AVANT return (vague A rejouerait un splash sur une tuile de vague B).
-- Early-out count == 0 : truncate a 0, retourner les pools (JAMAIS {}).
-- Overlay n'appelle pas applyDelta ; Effects lit les listes tout de suite
-- et n'en conserve pas l'identite. Retourner les pools est licite.
local gainBuf: { number } = table.create(16)
local lossBuf: { number } = table.create(16)
local otherBuf: { number } = table.create(16)

-- V102 : compact du prefixe consomme. Seuil 32 = ~10 frames de budget 3.
-- Pas de table.remove(1). Drain complet (V101) inchange. Recycle
-- Ground/Border (feel N106) non porte. Recette feel N114 inline —
-- ne PAS merger 846c. Distinct de V101 (curseur + truncate). Distinct
-- de V100 (trail offset.Z, UnitModels.place). HUD feed leftover V103.
-- FactoryOutput / SiloWarning fermees (V104). Feux navire fermes
-- (V105). Wake Transparency fermee (V106). Flag pitch leftover V107.
local DIRTY_COMPACT_HEAD = 32

local WorldRenderer = {}
WorldRenderer.__index = WorldRenderer

export type WorldRenderer = typeof(setmetatable({} :: any, WorldRenderer))

--=============================================================================
-- Construction
--=============================================================================

function WorldRenderer.new(seed: number): WorldRenderer
	local self = setmetatable({}, WorldRenderer) :: any

	self.seed = seed
	self.terrain = MapGen.generate(seed)
	self.owner = buffer.create(W * H)
	self.chunkFolders = {} :: { [number]: Folder }
	self.dirty = {} :: { [number]: boolean }
	self.dirtyQueue = {} :: { number }
	-- V101 : curseur de consommation. table.remove(1) decalait tout le
	-- tableau a chaque rebuild (budget 3 / frame). Recette feel N112
	-- inline — ne PAS merger 04e7. Truncate seulement quand la file
	-- est consommee. V102 : compact prefix (feel N114, seuil 32)
	-- apres la boucle. Recycle Ground/Border (feel N106) non porte.
	-- Trail offset.Z (V100) inchange. FactoryOutput / SiloWarning
	-- fermees (V104). Feux navire fermes (V105). HUD feed leftover
	-- V103. Wake Transparency fermee (V106). Flag pitch leftover
	-- V107.
	self.dirtyHead = 1
	self.partCount = 0
	-- Table de travail du mailleur, reutilisee entre chunks pour eviter une
	-- allocation par reconstruction.
	self.meshScratch = {}
	self.elapsed = 0
	self.oceanRipples = {}
	self.animatedFoliage = {}

	-- Suivi de la construction initiale, distinct de la file de reconstruction.
	-- Attendre que la file soit vide ne marche pas : la simulation tourne
	-- pendant le chargement et resalit des chunks en continu, donc la file
	-- n'atteint jamais zero et l'ecran de chargement reste bloque.
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

	-- Tous les chunks sont marques sales : le monde apparait progressivement
	-- sur environ une seconde plutot qu'en figeant la frame de chargement.
	for chunk = 0, Config.CHUNKS_X * Config.CHUNKS_Y - 1 do
		self:markChunkDirty(chunk)
	end

	return self
end

--[[
	L'ocean est un unique plan translucide : il n'a pas de relief, donc le
	decouper en blocs serait du gaspillage pur. Quelques reflets courts poses
	sur de vraies tuiles d'eau lui donnent du mouvement sans texture externe.
]]
function WorldRenderer.buildOcean(self: WorldRenderer)
	local water = Instance.new("Part")
	water.Name = "Ocean"
	water.Anchored = true
	water.CanCollide = false
	water.CanTouch = false
	water.CanQuery = true -- cliquer la mer doit designer une tuile d'ocean
	water.CastShadow = false
	water.Material = Enum.Material.Glass
	water.Transparency = 0.3
	water.Reflectance = 0.12
	water.Color = Color3.fromRGB(26, 62, 104)
	water.Size = Vector3.new(Config.WORLD_WIDTH, Config.OCEAN_LEVEL * 2, Config.WORLD_DEPTH)
	water.CFrame = CFrame.new(0, 0, 0)
	water.TopSurface = Enum.SurfaceType.Smooth
	water.BottomSurface = Enum.SurfaceType.Smooth
	water.Parent = self.root
	self.ocean = water

	-- Fond sombre sous l'eau : sans lui, la mer est transparente sur le vide
	-- des que la camera passe au ras de la surface.
	local floor = Instance.new("Part")
	floor.Name = "SeaFloor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.CanTouch = false
	floor.CanQuery = false
	floor.CastShadow = false
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(12, 22, 38)
	floor.Size = Vector3.new(Config.WORLD_WIDTH, 2, Config.WORLD_DEPTH)
	floor.CFrame = CFrame.new(0, -2, 0)
	floor.Parent = self.root

	-- Des reflets courts uniquement poses sur de vraies tuiles d'ocean donnent
	-- un mouvement a la surface sans texture externe ni immense decal statique.
	for i = 1, 54 do
		local x = (i * 47 + self.seed * 3) % W
		local y = (i * 83 + self.seed * 5) % H
		for probe = 0, 28 do
			local px = (x + probe * 11) % W
			local py = (y + probe * 7) % H
			if buffer.readu8(self.terrain, MapGen.toIndex(px, py)) == OCEAN then
				x, y = px, py
				break
			end
		end
		if buffer.readu8(self.terrain, MapGen.toIndex(x, y)) ~= OCEAN then
			continue
		end

		local world = WorldSpace.tileToWorld(x, y)
		local glint = Instance.new("Part")
		glint.Name = "OceanGlint"
		glint.Anchored = true
		glint.CanCollide = false
		glint.CanTouch = false
		glint.CanQuery = false
		glint.CastShadow = false
		glint.Material = Enum.Material.Neon
		glint.Color = Color3.fromRGB(116, 205, 226)
		glint.Transparency = 0.74
		glint.Size = Vector3.new(4 + i % 8, 0.05, 0.18 + (i % 3) * 0.08)
		local angle = math.rad(-18 + (i % 9) * 4)
		-- V84 : translation * fromEulerAnglesYXZ (yaw `angle` variable).
		-- Plus de CFrame.Angles a la construction des chunks océan.
		-- Formule `angle` inchangee. Y = OCEAN_LEVEL + 0.08 inchange.
		-- Size / Transparency / Color / Name inchanges. Ne PAS cuire un
		-- glintRot (yaw distinct par glint, pas une constante 90°).
		-- Distinct de V58 (houle 60 Hz : X/Z nombres depuis `base`, pas
		-- la pose initiale). Distinct de V83 (selectTile, pulseRot, Y =
		-- surface+0.48). Distinct de V82 (onde, pulseRot, Y = surface+0.8).
		-- Construction de chunk, pas 60 Hz. Recette feel N135 — ne pas
		-- merger 595e. `base = glint.CFrame` APRES la pose (V58 lit base).
		glint.CFrame = CFrame.new(world.X, Config.OCEAN_LEVEL + 0.08, world.Z)
			* CFrame.fromEulerAnglesYXZ(0, angle, 0)
		glint.Parent = self.root
		table.insert(self.oceanRipples, {
			part = glint,
			base = glint.CFrame,
			phase = i * 0.71,
		})
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

-- Vegetation et rochers restent purement visuels et tres espaces. Ils donnent
-- une echelle a l'avatar sans transformer le RTS en foret de milliers de Parts.
function WorldRenderer.buildDecorations(self: WorldRenderer)
	local folder = Instance.new("Folder")
	folder.Name = "Environment"
	folder.Parent = self.root
	self.decorations = folder

	for y = 5, H - 1, 9 do
		for x = 5, W - 1, 9 do
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
				-- V86 : translation * fromEulerAnglesYXZ (Z=90° fixe, cylindre).
				-- Plus de CFrame.Angles a buildDecorations pour TreeTrunk.
				-- Recette feel N137 inline — ne PAS cuire un trunkRot
				-- (Y TreeTrunk = ground + height/2, Y SavannaTrunk = ground + 1.6).
				-- Distinct de V85 (BuildRing, BuildingModels). Distinct de V84
				-- (OceanGlint yaw `angle` variable). Distinct de V59 (feuillage
				-- 60 Hz, couronne). Distinct de V87 (Rock yaw `phase` variable).
				-- Construction de chunk, pas 60 Hz.
				-- Shape = Cylinder pose APRES. Couronne translation seule.
				-- Ne pas retoucher Rock (V87 deja). Leftover V88 = cylinder()
				-- BuildingModels, pas ce fichier.
				local trunk = decorationPart(folder, "Part", "TreeTrunk", Vector3.new(height, 0.55, 0.55), Color3.fromRGB(91, 67, 47), CFrame.new(base.X, ground + height / 2, base.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90)), Enum.Material.Wood)
				trunk.Shape = Enum.PartType.Cylinder
				local crown = decorationPart(folder, "Part", "TreeCrown", Vector3.new(3.2, 3.8, 3.2), Color3.fromRGB(48 + (px % 3) * 6, 104 + (py % 4) * 6, 69), CFrame.new(base.X, ground + height + 1.1, base.Z), Enum.Material.LeafyGrass)
				crown.Shape = Enum.PartType.Ball
				table.insert(self.animatedFoliage, { part = crown, base = crown.CFrame, phase = phase })
			elseif terrain == Config.TERRAIN.SAVANNA and (px + py) % 3 == 0 then
				-- V86 : meme recette, Z=90° fixe, Y = ground + 1.6. Inline.
				local trunk = decorationPart(folder, "Part", "SavannaTrunk", Vector3.new(3.2, 0.45, 0.45), Color3.fromRGB(100, 70, 44), CFrame.new(base.X, ground + 1.6, base.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90)), Enum.Material.Wood)
				trunk.Shape = Enum.PartType.Cylinder
				local crown = decorationPart(folder, "Part", "SavannaCrown", Vector3.new(4.2, 1.5, 3.7), Color3.fromRGB(103, 131, 67), CFrame.new(base.X, ground + 3.5, base.Z), Enum.Material.LeafyGrass)
				crown.Shape = Enum.PartType.Ball
				table.insert(self.animatedFoliage, { part = crown, base = crown.CFrame, phase = phase })
			elseif terrain >= Config.TERRAIN.HILLS then
				-- V87 : translation * fromEulerAnglesYXZ (yaw `phase` variable).
				-- Plus de CFrame.Angles a buildDecorations pour Rock.
				-- Recette feel N138 inline — ne PAS cuire un rockRot
				-- (yaw distinct par rocher, comme V84 glintRot interdit).
				-- Distinct de V86 (TreeTrunk Z=90° fixe). Distinct de V84
				-- (OceanGlint yaw `angle` variable, buildOcean). Distinct de V59
				-- (feuillage 60 Hz, couronne). Construction de chunk, pas 60 Hz.
				-- ClassName WedgePart. CastShadow pose APRES.
				-- Ne pas retoucher TreeTrunk / SavannaTrunk (V86 deja).
				-- Leftover V88 = BuildingModels cylinder(), pas ce fichier.
				local rock = decorationPart(folder, "WedgePart", "Rock", Vector3.new(1.8 + px % 3, 1.1 + py % 2, 1.8 + (px + py) % 2), Color3.fromRGB(103, 111, 118), CFrame.new(base.X, ground + 0.55, base.Z) * CFrame.fromEulerAnglesYXZ(0, phase, 0), Enum.Material.Rock)
				rock.CastShadow = true
			end
		end
	end
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

--[[
	Cle de fusion de la couche politique. Les tuiles neutres restent sans teinte :
	on voit alors directement le biome naturel du SmoothTerrain.
]]
--[[
	Assombrissement par relief.

	Sans lui, un plateau et une montagne de la meme faction forment une masse
	illisible malgre leur difference de hauteur. La plage est au contraire
	eclaircie : un littoral doit se lire meme sous une couleur sombre.
]]
--[[
	Assombrissement par type de terrain.

	C'etait a l'origine un faux eclairage : plus c'etait haut, plus c'etait
	sombre. La carte etant maintenant plate, ce degrade est devenu la seule
	chose qui distingue une haute terre d'une plaine au premier coup d'oeil —
	il gagne en importance au lieu d'en perdre.
]]
local TERRAIN_SHADE = {
	[1] = 1.14, -- plage
	[2] = 1.0, -- plaines
	[3] = 1.03, -- savane
	[4] = 0.88, -- foret
	[5] = 0.84, -- collines
	[6] = 0.77, -- hautes terres
	[7] = 0.7, -- montagne
	[8] = 0.66, -- sommet
}

-- Facteur d'encodage de la cle de fusion. Il doit rester strictement superieur
-- au plus grand identifiant de terrain, sinon le terrain deborde sur le
-- proprietaire et deux factions fusionnent en un seul bloc.
local KEY_STRIDE = 16

local function blockColor(slot: number, terrain: number): Color3
	local shade = TERRAIN_SHADE[terrain] or 1
	local base = Config.TERRAIN_COLORS[terrain]

	if slot ~= NEUTRAL then
		-- La couleur de faction domine, mais on melange un peu de terrain pour
		-- que la nature du sol reste lisible a l'interieur d'un empire.
		base = Theme.factionColor(slot):Lerp(base, 0.24)
	end

	return Color3.new(
		math.clamp(base.R * shade, 0, 1),
		math.clamp(base.G * shade, 0, 1),
		math.clamp(base.B * shade, 0, 1)
	)
end

--[[
	Cle de fusion : proprietaire **et** type de terrain.

	Deux tuiles ne fusionnent que si elles ont exactement la meme couleur. La
	hauteur ne fait plus partie de la cle puisqu'elle est uniforme, mais le
	terrain si : il porte toujours sa teinte et son assombrissement.
]]
function WorldRenderer.chunkKeyAt(self: WorldRenderer, x: number, y: number): number?
	local index = MapGen.toIndex(x, y)
	local terrain = buffer.readu8(self.terrain, index)
	if terrain == OCEAN then
		return nil -- l'ocean n'a pas de bloc, c'est un plan unique
	end
	return buffer.readu8(self.owner, index) * KEY_STRIDE + terrain
end

--=============================================================================
-- Frontieres
--=============================================================================

--[[
	Couleur du liseré d'une faction.

	C'est la couleur de faction **pure**, alors que le remplissage du sol est
	cette meme couleur melangee a 24 % de terrain. Le liseré est donc toujours
	plus sature que ce qu'il entoure, sans qu'on ait a inventer une seconde
	palette : chaque nation reste reconnaissable a une seule teinte, et le
	contour se detache quand meme du remplissage.
]]
local function borderColor(slot: number): Color3
	return Theme.factionColor(slot)
end

-- Epaisseur du liseré, et hauteur a laquelle il flotte au-dessus du sol.
-- A l'echelle : un lisere de 0,8 stud disparait des que la tuile en fait douze.
local BORDER_THICKNESS = 0.8 * Config.WORLD_SCALE
local BORDER_LIFT = 0.05 * Config.WORLD_SCALE

--[[
	Trace le contour des territoires d'un chunk.

	Chaque tuile ne dessine que **ses propres** cotes, et le liseré est pose a
	l'INTERIEUR de la tuile. Deux consequences voulues :

	  - Deux nations voisines tracent chacune sa ligne, cote a cote, comme sur
	    une carte politique — au lieu d'une seule ligne mitoyenne dont la
	    couleur devrait trancher entre les deux.
	  - Aucune geometrie ne se superpose a la couture, donc pas de scintillement
	    de profondeur entre deux Parts coplanaires.

	Les cotes consecutifs de meme proprietaire sont fusionnes en un seul segment
	long. Une frontiere de cent tuiles coute alors une poignee de Parts au lieu
	de cent : c'est la meme economie que la fusion gloutonne du sol, appliquee a
	une dimension de moins.
]]
function WorldRenderer.buildChunkBorders(
	self: WorldRenderer,
	folder: Folder,
	cx: number,
	cy: number,
	x1: number,
	y1: number
): number
	local drawn = 0
	local surface = Config.LAND_HEIGHT + BORDER_LIFT

	-- Proprietaire d'une tuile, ou nil si elle est en mer ou sans maitre : dans
	-- les deux cas elle ne porte pas de frontiere.
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
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Color = borderColor(slot)
		part.Size = if horizontal
			then Vector3.new(length, 0.12 * Config.WORLD_SCALE, BORDER_THICKNESS)
			else Vector3.new(BORDER_THICKNESS, 0.12 * Config.WORLD_SCALE, length)
		part.CFrame = CFrame.new(
			(a.X + b.X) / 2 + dx * inset,
			surface,
			(a.Z + b.Z) / 2 + dy * inset
		)
		part.Parent = folder
		drawn += 1
	end

	--[[
		Deux balayages : les cotes nord/sud se fusionnent le long des lignes, les
		cotes est/ouest le long des colonnes. Ecrire les quatre a la main serait
		quatre fois la meme boucle a une permutation d'axe pres — et quatre
		occasions de se tromper d'indice.
	]]
	local passes = {
		{ dx = 0, dy = -1 },
		{ dx = 0, dy = 1 },
		{ dx = -1, dy = 0 },
		{ dx = 1, dy = 0 },
	}

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

				-- Le tour supplementaire (innerTo + 1) sert uniquement a fermer
				-- le dernier segment : sans lui, une frontiere qui touche le bord
				-- du chunk ne serait jamais emise.
				if inner <= innerTo then
					local x = if alongRow then inner else outer
					local y = if alongRow then outer else inner
					local mine = ownerOf(x, y)
					if mine ~= nil and ownerOf(x + pass.dx, y + pass.dy) ~= mine then
						slot = mine
					end
				end

				if slot ~= runSlot then
					if runSlot ~= nil then
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
		-- La collision est assuree par la geometrie du serveur : celle-ci n'est
		-- que visuelle, et la rendre solide dupliquerait le travail du moteur
		-- physique.
		part.CanCollide = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(rect.width * TILE, height, rect.depth * TILE)
		part.CFrame = CFrame.new(
			origin.X + (rect.width - 1) * TILE / 2,
			height / 2,
			origin.Z + (rect.depth - 1) * TILE / 2
		)
		part.Color = blockColor(slot, terrain)
		part.Parent = folder
	end

	self.partCount += #rects
	self.partCount += self:buildChunkBorders(folder, cx, cy, x1, y1)
	folder.Parent = self.root
end

-- Animation ambiante a tres faible amplitude : elle se lit en vue avatar sans
-- faire onduler toute la carte en vue strategique.
function WorldRenderer.step(self: WorldRenderer, dt: number)
	self.elapsed += dt
	local time = self.elapsed
	for _, ripple in self.oceanRipples do
		local wave = math.sin(time * 1.45 + ripple.phase)
		ripple.part.Transparency = 0.73 + wave * 0.09
		-- V58 : X/Z en nombres depuis base. Plus de Vector3.new 60 Hz
		-- (base + offset). Un CFrame.new. Feuillage inchange (V59).
		-- Camion / unites inchanges (V57/V56). 0 glint = zéro alloc.
		local base = ripple.base
		ripple.part.CFrame = CFrame.new(
			base.X + wave * 0.45,
			base.Y,
			base.Z + math.cos(time + ripple.phase) * 0.2
		)
	end
	for _, leaf in self.animatedFoliage do
		-- V59 : Y en nombres depuis base. Plus de CFrame.Angles 60 Hz
		-- (tilt ~1° invisible sur Ball). Amplitude 0.018 conservee en
		-- translation Y. Houle / camion / unites inchanges (V58/V57/V56).
		-- 0 couronne = zéro alloc.
		local base = leaf.base
		leaf.part.CFrame = CFrame.new(
			base.X,
			base.Y + math.sin(time * 1.2 + leaf.phase) * 0.018,
			base.Z
		)
	end
end

--[[
	Traite la file de reconstruction, dans la limite du budget par frame.
	Renvoie le nombre de chunks reellement reconstruits.
]]
function WorldRenderer.stepRebuilds(self: WorldRenderer): number
	local budget = Config.CHUNK_REBUILDS_PER_FRAME
	local done = 0
	local queue = self.dirtyQueue
	local head = self.dirtyHead

	-- V101 : curseur + truncate. Plus de table.remove(1). markDirty /
	-- table.insert inchanges. Stale (dirty deja nil) saute sans compter
	-- le budget, comme avant. Recette feel N112 inline — ne PAS merger
	-- 04e7. Distinct de V100 (trail offset.Z, UnitModels.place).
	-- Distinct de V48 (applyDelta pools). V102 compact prefix apres
	-- la boucle (feel N114). Recycle Ground/Border (feel N106) non
	-- porte. Houle / feuillage inchanges (V58/V59). Pas de RemoteFunction.
	while done < budget and head <= #queue do
		local chunk = queue[head]
		head += 1
		if chunk and self.dirty[chunk] then
			self.dirty[chunk] = nil
			self:rebuildChunk(chunk)
			done += 1
		end
	end

	if head > #queue then
		table.clear(queue)
		head = 1
	elseif head > DIRTY_COMPACT_HEAD then
		-- V102 : prefixe 1..head-1 mort tant que la vague n'est pas
		-- rattrapee. Copie in-place des restants, nil du surplus,
		-- tete a 1. Pas a chaque frame (seuil 32). Pas de table.remove.
		-- Drain V101 inchange. Recette feel N114 inline — ne PAS
		-- merger 846c. Distinct de V101 (curseur). Distinct de V48
		-- (applyDelta). Recycle Ground/Border (feel N106) non porte.
		local n = #queue
		local remaining = n - head + 1
		for i = 1, remaining do
			queue[i] = queue[head + i - 1]
		end
		for i = remaining + 1, n do
			queue[i] = nil
		end
		head = 1
	end
	self.dirtyHead = head

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

	-- Colonisation du neutre : aucun effet. Prise sur une faction :
	-- gains si nextOwner == mySlot, losses si previous == mySlot, others sinon.
	local nG, nL, nO = 0, 0, 0
	if count > 0 then
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
					nG += 1
					gainBuf[nG] = index
				elseif previous == mySlot then
					nL += 1
					lossBuf[nL] = index
				else
					nO += 1
					otherBuf[nO] = index
				end
			end
		end
	end
	for i = #gainBuf, nG + 1, -1 do
		gainBuf[i] = nil
	end
	for i = #lossBuf, nL + 1, -1 do
		lossBuf[i] = nil
	end
	for i = #otherBuf, nO + 1, -1 do
		otherBuf[i] = nil
	end

	return count, gainBuf, lossBuf, otherBuf
end

--[[
	Remplace le buffer owner entier (resync) et salit tous les chunks.
]]
function WorldRenderer.applyOwnerSnapshot(self: WorldRenderer, owner: buffer)
	local len = math.min(buffer.len(owner), buffer.len(self.owner))
	buffer.copy(self.owner, 0, owner, 0, len)
	for chunk = 0, self.totalChunks - 1 do
		self:markChunkDirty(chunk)
	end
end

-- Avancement de la construction initiale, entre 0 et 1.
function WorldRenderer.initialProgress(self: WorldRenderer): number
	return self.builtCount / math.max(1, self.totalChunks)
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
