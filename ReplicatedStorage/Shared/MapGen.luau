--!strict
-- Generation de carte deterministe.
--
-- Le serveur et le client appellent tous les deux generate(seed) et obtiennent
-- un resultat identique, donc on ne replique que la seed (4 octets) au lieu
-- des 40 Ko du terrain.
--
-- math.noise est du Perlin deterministe cote Roblox, et les seuils terre/mer
-- sont calibres par histogramme : quelle que soit la seed, on retombe sur le
-- LAND_RATIO demande. Sans ca, certaines seeds donnent une carte 100 % ocean.

local Config = require(script.Parent.Config)

local MapGen = {}

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT

local OCEAN = Config.TERRAIN.OCEAN
local PLAINS = Config.TERRAIN.PLAINS
local HILLS = Config.TERRAIN.HILLS
local MOUNTAIN = Config.TERRAIN.MOUNTAIN

local HIST_BUCKETS = 512

-- Bruit fractal (fBm) sur 5 octaves.
local function fbm(x: number, y: number, ox: number, oy: number): number
	local total = 0
	local amp = 1
	local freq = 2.4
	local norm = 0
	for _ = 1, 5 do
		total += amp * math.noise(x * freq + ox, y * freq + oy)
		norm += amp
		amp *= 0.5
		freq *= 2.07
	end
	return total / norm
end

--[[
	Renvoie un buffer de W*H octets, un par tuile, contenant un TERRAIN.
	L'index d'une tuile est toujours y * W + x.
]]
function MapGen.generate(seed: number): buffer
	local ox = (seed % 4096) * 0.1373 + 11.5
	local oy = (math.floor(seed / 4096) % 4096) * 0.1907 + 7.25

	local elevation = table.create(W * H, 0)
	local minE, maxE = math.huge, -math.huge

	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local nx = x / W
			local ny = y / H

			local e = fbm(nx, ny, ox, oy)

			-- Attenuation radiale : force les bords de carte a etre de l'ocean,
			-- sinon les joueurs qui spawnent au bord ont un flanc invulnerable.
			local dx = (nx - 0.5) * 2.0
			local dy = (ny - 0.5) * 2.0
			local d2 = dx * dx * 0.85 + dy * dy
			e -= d2 * 0.55

			local i = y * W + x
			elevation[i + 1] = e
			if e < minE then
				minE = e
			end
			if e > maxE then
				maxE = e
			end
		end
	end

	-- Calibration par histogramme : on cherche les seuils d'elevation qui
	-- decoupent la carte selon les ratios voulus.
	local span = math.max(maxE - minE, 1e-6)
	local hist = table.create(HIST_BUCKETS, 0)
	for i = 1, W * H do
		local b = math.clamp(math.floor((elevation[i] - minE) / span * (HIST_BUCKETS - 1)), 0, HIST_BUCKETS - 1)
		hist[b + 1] += 1
	end

	local function thresholdAtFractionFromTop(fraction: number): number
		-- Renvoie l'elevation au-dessus de laquelle se trouve `fraction` de la carte.
		local target = fraction * (W * H)
		local acc = 0
		for b = HIST_BUCKETS, 1, -1 do
			acc += hist[b]
			if acc >= target then
				return minE + ((b - 1) / (HIST_BUCKETS - 1)) * span
			end
		end
		return minE
	end

	local seaLevel = thresholdAtFractionFromTop(Config.LAND_RATIO)
	local hillLevel = thresholdAtFractionFromTop(Config.LAND_RATIO * Config.HILL_RATIO)
	local mountainLevel = thresholdAtFractionFromTop(Config.LAND_RATIO * Config.MOUNTAIN_RATIO)

	local terrain = buffer.create(W * H)
	for i = 0, W * H - 1 do
		local e = elevation[i + 1]
		local t
		if e < seaLevel then
			t = OCEAN
		elseif e < hillLevel then
			t = PLAINS
		elseif e < mountainLevel then
			t = HILLS
		else
			t = MOUNTAIN
		end
		buffer.writeu8(terrain, i, t)
	end

	return terrain
end

-- Helpers d'index partages par le serveur et le client.

function MapGen.toIndex(x: number, y: number): number
	return y * W + x
end

function MapGen.fromIndex(index: number): (number, number)
	return index % W, math.floor(index / W)
end

function MapGen.inBounds(x: number, y: number): boolean
	return x >= 0 and x < W and y >= 0 and y < H
end

--[[
	Ecrit les 4 voisins cardinaux de `index` dans la table `out` (reutilisee par
	l'appelant pour eviter des milliers d'allocations par tick) et renvoie leur
	nombre. Adjacence a 4 et pas a 8 : les diagonales rendraient les fronts
	poreux et illisibles.
]]
function MapGen.neighbors(index: number, out: { number }): number
	local x = index % W
	local y = math.floor(index / W)
	local n = 0

	if x > 0 then
		n += 1
		out[n] = index - 1
	end
	if x < W - 1 then
		n += 1
		out[n] = index + 1
	end
	if y > 0 then
		n += 1
		out[n] = index - W
	end
	if y < H - 1 then
		n += 1
		out[n] = index + W
	end

	return n
end

return MapGen
