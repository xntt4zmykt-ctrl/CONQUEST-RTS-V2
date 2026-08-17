--!strict
--[[
	Geometrie de collision du monde, cote serveur.

	Pourquoi elle existe alors que le client construit deja le monde visible :
	le rendu du client est **local**, le serveur n'en voit rien. Sans sol cote
	serveur, un avatar depose sur sa capitale tombe indefiniment.

	L'observation qui rend la chose economique : **le relief ne change jamais**.
	Une conquete change la couleur d'une tuile, pas sa hauteur. Le serveur peut
	donc poser une collision statique une seule fois, fusionnee par relief
	uniquement — ce qui donne beaucoup moins de blocs que la version coloree du
	client, puisqu'on ne decoupe pas par proprietaire.

	Repartition finale :
	  serveur -> collision invisible, statique, repliquee une fois
	  client  -> geometrie coloree, locale, reconstruite a volonte
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
	Cle de fusion cote serveur : le relief seul. On ignore volontairement le
	proprietaire, puisque la collision n'a pas de couleur — ce qui donne
	beaucoup moins de blocs que la version visuelle du client.
]]
function WorldBuilder.blocksFor(terrain: buffer): { GreedyMesh.Rect }
	local function keyAt(x: number, y: number): number?
		local kind = buffer.readu8(terrain, MapGen.toIndex(x, y))
		if kind == OCEAN then
			return nil
		end
		return kind
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

	local folder = Instance.new("Folder")
	folder.Name = "ConquestCollision"

	local blocks = WorldBuilder.blocksFor(terrain)

	for _, rect in blocks do
		local height = Config.TERRAIN_HEIGHT[rect.key]
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

	-- Plan d'eau : un avatar tombe a la mer doit flotter quelque part plutot
	-- que de sombrer sans fin.
	local water = Instance.new("Part")
	water.Name = "OceanFloor"
	water.Anchored = true
	water.CanCollide = true
	water.CanTouch = false
	water.CanQuery = false
	water.CastShadow = false
	water.Transparency = 1
	water.Size = Vector3.new(Config.WORLD_WIDTH, 1, Config.WORLD_DEPTH)
	water.CFrame = CFrame.new(0, Config.OCEAN_LEVEL - 0.5, 0)
	water.Parent = folder

	folder.Parent = Workspace

	print(`[{Config.GAME_NAME}] collision du monde : {#blocks} blocs`)
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
