--!strict
--[[
	Collision du monde, cote serveur.

	Pourquoi elle existe alors que le client construit deja le monde visible :
	le rendu du client est **local**, le serveur n'en voit rien. Sans sol cote
	serveur, un avatar depose sur sa capitale tombe indefiniment.

	L'observation qui rend la chose economique : **le relief ne change jamais**.
	Une conquete change la couleur d'une tuile, pas sa hauteur. Le serveur pose
	donc une collision statique une seule fois, fusionnee par altitude
	uniquement — une collision invisible n'a ni couleur ni matiere, donc deux
	terrains de meme hauteur sont interchangeables.

	Repartition finale :
	  serveur -> collision invisible et bordures, statiques, repliquees une fois
	  client  -> geometrie coloree en blocs, locale, reconstruite a volonte
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local GreedyMesh = require(ReplicatedStorage.Shared.GreedyMesh)
local WorldSpace = require(ReplicatedStorage.Shared.WorldSpace)

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT
local TILE = Config.TILE_SIZE
local OCEAN = Config.TERRAIN.OCEAN

local WorldBuilder = {}

--[[
	Cle de fusion cote serveur : la hauteur seule. On ignore volontairement le
	proprietaire ET le type de terrain, puisqu'une collision invisible n'a ni
	couleur ni matiere — ce qui donne beaucoup moins de blocs que la version
	visuelle du client.
]]
function WorldBuilder.blocksFor(terrain: buffer): { GreedyMesh.Rect }
	--[[
		La cle est la **hauteur**, pas le type de terrain.

		Une collision invisible n'a ni couleur ni matiere : deux terrains de
		meme altitude sont interchangeables. Depuis que la carte est plate, cette
		cle est constante sur toute la terre ferme et le continent fusionne en
		quelques centaines de dalles au lieu de trois mille cinq cents.

		On renvoie quand meme la hauteur plutot qu'un simple marqueur : build()
		lit `rect.key` comme altitude, et remettre du relief un jour ne
		demanderait alors aucun autre changement ici.
	]]
	local function keyAt(x: number, y: number): number?
		local kind = buffer.readu8(terrain, MapGen.toIndex(x, y))
		if kind == OCEAN then
			return nil
		end
		return Config.TERRAIN_HEIGHT[kind]
	end

	-- Pas de decoupage en chunks ici : la geometrie n'etant jamais
	-- reconstruite, autant laisser les rectangles s'etendre au maximum.
	return GreedyMesh.rectangles(keyAt, 0, 0, W - 1, H - 1)
end

function WorldBuilder.build(terrain: buffer): Folder
	local existing = Workspace:FindFirstChild("ConquestCollision")
	if existing then
		existing:Destroy()
	end

	-- Le SmoothTerrain d'une partie precedente doit disparaitre, sinon il
	-- flotte au milieu des blocs.
	Workspace.Terrain:Clear()

	local folder = Instance.new("Folder")
	folder.Name = "ConquestCollision"

	local blocks = WorldBuilder.blocksFor(terrain)

	for _, rect in blocks do
		-- La cle EST la hauteur.
		local height = rect.key
		local origin = WorldSpace.tileToWorld(rect.x, rect.y)

		local part = Instance.new("Part")
		part.Name = "Ground"
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		-- Invisible et non interrogeable : le joueur voit et clique la
		-- geometrie coloree du client, jamais celle-ci.
		part.Transparency = 1
		part.CanQuery = false
		part.CastShadow = false
		part.Size = Vector3.new(rect.width * TILE, height, rect.depth * TILE)
		part.CFrame = CFrame.new(
			origin.X + (rect.width - 1) * TILE / 2,
			height / 2,
			origin.Z + (rect.depth - 1) * TILE / 2
		)
		part.Parent = folder
	end

	-- Plancher oceanique : un avatar tombe a la mer doit s'arreter quelque part
	-- plutot que de sombrer sans fin.
	local seabed = Instance.new("Part")
	seabed.Name = "Seabed"
	seabed.Anchored = true
	seabed.CanCollide = true
	seabed.CanTouch = false
	seabed.CanQuery = false
	seabed.CastShadow = false
	seabed.Transparency = 1
	seabed.Size = Vector3.new(Config.WORLD_WIDTH, 1, Config.WORLD_DEPTH)
	seabed.CFrame = CFrame.new(0, Config.OCEAN_LEVEL - 0.5, 0)
	seabed.Parent = folder

	-- Quatre murs invisibles ferment les bords du monde. Le serveur les possede
	-- car la geometrie du client est locale et ne peut pas retenir un
	-- personnage. Ils debordent aux coins pour qu'aucun passage ne reste ouvert.
	local thickness = Config.WORLD_BORDER_THICKNESS
	local wallHeight = Config.WORLD_BORDER_HEIGHT
	local halfWidth = Config.WORLD_WIDTH / 2
	local halfDepth = Config.WORLD_DEPTH / 2

	local function borderWall(name: string, size: Vector3, position: Vector3)
		local wall = Instance.new("Part")
		wall.Name = name
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanTouch = false
		wall.CanQuery = false
		wall.CastShadow = false
		wall.Transparency = 1
		wall.Size = size
		wall.CFrame = CFrame.new(position)
		wall.Parent = folder
	end

	borderWall(
		"BorderWest",
		Vector3.new(thickness, wallHeight, Config.WORLD_DEPTH + thickness * 2),
		Vector3.new(-halfWidth - thickness / 2, wallHeight / 2, 0)
	)
	borderWall(
		"BorderEast",
		Vector3.new(thickness, wallHeight, Config.WORLD_DEPTH + thickness * 2),
		Vector3.new(halfWidth + thickness / 2, wallHeight / 2, 0)
	)
	borderWall(
		"BorderNorth",
		Vector3.new(Config.WORLD_WIDTH + thickness * 2, wallHeight, thickness),
		Vector3.new(0, wallHeight / 2, -halfDepth - thickness / 2)
	)
	borderWall(
		"BorderSouth",
		Vector3.new(Config.WORLD_WIDTH + thickness * 2, wallHeight, thickness),
		Vector3.new(0, wallHeight / 2, halfDepth + thickness / 2)
	)

	folder.Parent = Workspace

	print(`[{Config.GAME_NAME}] collision du monde : {#blocks} blocs + 4 bordures`)
	return folder
end

--[[
	Nettoie la scene par defaut de Studio. Sans ca, la baseplate d'origine
	flotte au milieu de la carte et le point d'apparition par defaut projette
	les joueurs a cote du monde.
]]
function WorldBuilder.clearDefaultScene()
	for _, child in Workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
end

return WorldBuilder
