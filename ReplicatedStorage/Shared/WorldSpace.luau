--!strict
--[[
	Conversions entre la grille de simulation et le monde 3D.

	Un seul endroit connait cette correspondance. Le serveur s'en sert pour
	poser un avatar sur sa capitale, le client pour placer les blocs, la camera
	et les marqueurs — s'ils divergeaient d'une demi-tuile, un joueur
	apparaitrait a cote de son territoire.

	Le monde est centre sur l'origine : la tuile (0,0) est au coin nord-ouest,
	en coordonnees negatives.
]]

local Config = require(script.Parent.Config)
local MapGen = require(script.Parent.MapGen)

local WorldSpace = {}

local TILE = Config.TILE_SIZE
local HALF_W = Config.WORLD_WIDTH / 2
local HALF_D = Config.WORLD_DEPTH / 2

-- Centre d'une tuile, au niveau du sol (y = 0).
function WorldSpace.tileToWorld(x: number, y: number): Vector3
	return Vector3.new(x * TILE - HALF_W + TILE / 2, 0, y * TILE - HALF_D + TILE / 2)
end

function WorldSpace.indexToWorld(index: number): Vector3
	local x, y = MapGen.fromIndex(index)
	return WorldSpace.tileToWorld(x, y)
end

-- Position du monde -> index de tuile, ou nil hors carte.
function WorldSpace.worldToIndex(position: Vector3): number?
	local x = math.floor((position.X + HALF_W) / TILE)
	local y = math.floor((position.Z + HALF_D) / TILE)
	if not MapGen.inBounds(x, y) then
		return nil
	end
	return MapGen.toIndex(x, y)
end

-- Hauteur du sol d'une tuile, sommet du bloc.
function WorldSpace.surfaceHeight(terrain: buffer, index: number): number
	local kind = buffer.readu8(terrain, index)
	if kind == Config.TERRAIN.OCEAN then
		return Config.OCEAN_LEVEL
	end
	return Config.TERRAIN_HEIGHT[kind]
end

--[[
	Point ou deposer un personnage sur une tuile : centre de la tuile, juste
	au-dessus du sol. Le decalage vertical evite que l'avatar naisse coince
	dans le bloc.
]]
function WorldSpace.spawnCFrame(terrain: buffer, index: number): CFrame
	local base = WorldSpace.indexToWorld(index)
	local height = WorldSpace.surfaceHeight(terrain, index)
	return CFrame.new(base.X, height + 4, base.Z)
end

return WorldSpace
