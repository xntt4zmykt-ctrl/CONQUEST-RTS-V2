--!strict
--[[
	Hint client N58 : le hover spawn colore comme claimSpawn.

	Carre SPAWN_RADIUS+3 tout NEUTRAL, ou voisin r=6 isole. Pas une source
	de verite : claimSpawn serveur refuse encore splash / fallout (N52) et
	l'isolation (N55). Pas de RemoteFunction. Pas de duplication d'isSpawnSafe.
]]

local Config = require(script.Parent.Config)
local MapGen = require(script.Parent.MapGen)

local SpawnHint = {}

local NEUTRAL = Config.NEUTRAL_SLOT
local OCEAN = Config.TERRAIN.OCEAN
local CHECK = Config.SPAWN_RADIUS + 3
local SEARCH = 6

function SpawnHint.isIsolated(owner: buffer, center: number): boolean
	if center < 0 or center >= Config.TILE_COUNT then
		return false
	end
	local x, y = MapGen.fromIndex(center)
	for dy = -CHECK, CHECK do
		for dx = -CHECK, CHECK do
			local nx, ny = x + dx, y + dy
			if MapGen.inBounds(nx, ny) then
				local idx = MapGen.toIndex(nx, ny)
				if buffer.readu8(owner, idx) ~= NEUTRAL then
					return false
				end
			end
		end
	end
	return true
end

local function isHintClaimable(terrain: buffer, owner: buffer, index: number): boolean
	if index < 0 or index >= Config.TILE_COUNT then
		return false
	end
	if buffer.readu8(terrain, index) == OCEAN then
		return false
	end
	if buffer.readu8(owner, index) ~= NEUTRAL then
		return false
	end
	return SpawnHint.isIsolated(owner, index)
end

--[[
	claimSpawn refuse la mer AVANT la recherche r=6. Le hover fait de meme :
	un ocean n'est jamais vert, meme si une terre isolee est a 2 cases.
]]
function SpawnHint.looksClaimable(terrain: buffer, owner: buffer, index: number): boolean
	if index < 0 or index >= Config.TILE_COUNT then
		return false
	end
	if buffer.readu8(terrain, index) == OCEAN then
		return false
	end
	if isHintClaimable(terrain, owner, index) then
		return true
	end
	local ox, oy = MapGen.fromIndex(index)
	for r = 1, SEARCH do
		for dy = -r, r do
			for dx = -r, r do
				local nx, ny = ox + dx, oy + dy
				if MapGen.inBounds(nx, ny) then
					local i = MapGen.toIndex(nx, ny)
					if isHintClaimable(terrain, owner, i) then
						return true
					end
				end
			end
		end
	end
	return false
end

return SpawnHint
