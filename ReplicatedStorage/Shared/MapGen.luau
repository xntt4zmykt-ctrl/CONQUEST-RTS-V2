--!strict
--[[
	Generation de carte deterministe.

	Le serveur et le client appellent tous les deux generate(seed) et obtiennent
	un resultat identique, donc on ne replique que la seed (4 octets) au lieu
	des 40 Ko du terrain.

	Quatre mecanismes se combinent, chacun corrigeant un defaut precis de la
	version precedente :

	  **Deformation du domaine** — on perturbe les coordonnees avant de tirer le
	  bruit. Un bruit fractal brut produit des cotes molles et arrondies, toutes
	  semblables ; la deformation les etire et les replie, ce qui donne des
	  peninsules, des golfes et des fjords.

	  **Masque continental** — un bruit tres basse frequence decide ou la terre
	  a le droit d'exister. Sans lui, l'attenuation radiale produisait une seule
	  masse centrale a chaque partie. Avec, on obtient plusieurs continents et
	  des archipels, donc une vraie geographie a jouer.

	  **Bruit de crete** — `1 - |bruit|` produit des lignes au lieu de taches.
	  Eleve au cube et ajoute a l'altitude, il forme des chaines de montagnes
	  orientees, la ou un simple seuil d'altitude donnait des patés isoles.

	  **Humidite** — un second champ, independant du relief, qui repartit
	  plaines, savanes et forets a altitude egale. C'est ce qui empeche toutes
	  les basses terres d'avoir la meme couleur.

	Les seuils sont calibres par histogramme : quelle que soit la seed, on
	retombe sur le LAND_RATIO demande et sur la meme repartition par bande. Sans
	cette calibration, certaines seeds donnent une carte sans montagnes et
	d'autres une carte sans plaines.
]]

local Config = require(script.Parent.Config)

local MapGen = {}

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT
local T = Config.TERRAIN

--[[
	Resolution de l'histogramme de calibration.

	Elle doit rester bien superieure au nombre de tuiles concentrees dans une
	meme tranche d'altitude : si un seul seau contient une grosse part de la
	carte, le seuil du niveau de la mer devient instable d'une seed a l'autre.
]]
local HIST_BUCKETS = 1024

--=============================================================================
-- Bruits
--=============================================================================

local function fbm(x: number, y: number, ox: number, oy: number, octaves: number, frequency: number): number
	local total = 0
	local amplitude = 1
	local freq = frequency
	local norm = 0
	for _ = 1, octaves do
		total += amplitude * math.noise(x * freq + ox, y * freq + oy)
		norm += amplitude
		amplitude *= 0.5
		freq *= 2.03
	end
	return total / norm
end

-- Bruit de crete : produit des lignes marquees au lieu de taches douces.
local function ridge(x: number, y: number, ox: number, oy: number, frequency: number): number
	local n = math.noise(x * frequency + ox, y * frequency + oy)
	local r = 1 - math.abs(n) * 2
	return math.clamp(r, 0, 1)
end

--=============================================================================
-- Generation
--=============================================================================

--[[
	Renvoie un buffer de W*H octets, un par tuile, contenant un TERRAIN.
	L'index d'une tuile est toujours y * W + x.
]]
function MapGen.generate(seed: number): buffer
	-- Decalages derives de la seed. Chaque champ a les siens, sinon relief,
	-- humidite et cretes seraient correles et produiraient des motifs visibles.
	local ox = (seed % 4096) * 0.1373 + 11.5
	local oy = (math.floor(seed / 4096) % 4096) * 0.1907 + 7.25
	local wx = ox * 0.61 + 53.1
	local wy = oy * 0.77 + 19.4
	local cx = ox * 1.31 + 131.7
	local cy = oy * 1.09 + 87.3
	local rx = ox * 0.43 + 211.2
	local ry = oy * 0.87 + 167.9
	local mx = ox * 1.77 + 301.4
	local my = oy * 1.23 + 259.8

	local elevation = table.create(W * H, 0)
	local moisture = table.create(W * H, 0)
	local minE, maxE = math.huge, -math.huge

	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local nx = x / W
			local ny = y / H

			-- Deformation du domaine : on decale le point d'echantillonnage.
			local dx = fbm(nx, ny, wx, wy, 2, 7.0)
			local dy = fbm(nx, ny, wx + 41.7, wy + 29.3, 2, 7.0)
			local sx = nx + dx * 0.16
			local sy = ny + dy * 0.16

			local base = fbm(sx, sy, ox, oy, 5, 6.5)

			-- Masque continental : basse frequence *relativement* au relief,
			-- mais assez elevee pour couvrir plusieurs cellules de bruit et
			-- decouper reellement plusieurs continents.
			local mask = fbm(nx, ny, cx, cy, 2, 3.2)

			-- Attenuation aux bords, plus douce qu'avant : le masque fait
			-- desormais l'essentiel du travail de decoupe des continents.
			local ex = (nx - 0.5) * 2
			local ey = (ny - 0.5) * 2
			local edge = math.max(math.abs(ex) * 0.92, math.abs(ey))
			local falloff = math.max(0, edge - 0.62) ^ 2 * 3.4

			local e = base * 0.62 + mask * 0.52 - falloff

			-- Chaines de montagnes : la crete ne s'applique qu'aux zones deja
			-- hautes, sinon des aretes apparaissent au milieu de l'ocean.
			local r = ridge(sx, sy, rx, ry, 12.0)
			e += r * r * r * 0.34 * math.clamp(base * 2 + 0.4, 0, 1)

			local index = y * W + x
			elevation[index + 1] = e
			moisture[index + 1] = fbm(nx, ny, mx, my, 3, 8.0)

			if e < minE then
				minE = e
			end
			if e > maxE then
				maxE = e
			end
		end
	end

	--=========================================================================
	-- Calibration
	--=========================================================================

	local span = math.max(maxE - minE, 1e-6)
	local hist = table.create(HIST_BUCKETS, 0)
	for i = 1, W * H do
		local bucket = math.clamp(math.floor((elevation[i] - minE) / span * (HIST_BUCKETS - 1)), 0, HIST_BUCKETS - 1)
		hist[bucket + 1] += 1
	end

--[[
		Elevation au-dessus de laquelle se trouve `fraction` de la carte.

		On interpole a l'interieur du seau qui fait basculer le compte. Renvoyer
		sa borne basse, comme le faisait la version precedente, comptait tout le
		seau comme terre : le ratio reel depassait de six points celui demande.
	]]
	local function thresholdFromTop(fraction: number): number
		local target = fraction * (W * H)
		local acc = 0
		for b = HIST_BUCKETS, 1, -1 do
			local count = hist[b]
			if acc + count >= target then
				local within = if count > 0 then (target - acc) / count else 0
				local position = (b - 1) + (1 - within)
				return minE + (position / (HIST_BUCKETS - 1)) * span
			end
			acc += count
		end
		return minE
	end

	local seaLevel = thresholdFromTop(Config.LAND_RATIO)

	--[[
		Seuils de bande, eux aussi calibres par percentile.

		Repartir les bandes lineairement entre le niveau de la mer et le sommet
		ne marche pas : la somme de plusieurs bruits concentre les altitudes
		autour de la moyenne, et le point culminant est une valeur aberrante.
		Presque toute la terre tombait alors dans la premiere bande, produisant
		des continents d'un seul tenant sans le moindre relief.
	]]
	local bandLevels = table.create(#Config.TERRAIN_BANDS, 0)
	for i, band in Config.TERRAIN_BANDS do
		-- `upTo` est une part cumulee des terres depuis le rivage ; le seuil
		-- correspondant se lit donc depuis le haut de la distribution.
		bandLevels[i] = thresholdFromTop(Config.LAND_RATIO * (1 - band.upTo))
	end

	--=========================================================================
	-- Classification
	--=========================================================================

	local terrain = buffer.create(W * H)

	for i = 0, W * H - 1 do
		local e = elevation[i + 1]

		if e < seaLevel then
			buffer.writeu8(terrain, i, T.OCEAN)
			continue
		end

		local kind = T.PEAK
		for i, band in Config.TERRAIN_BANDS do
			if e < bandLevels[i] then
				kind = band.kind
				break
			end
		end

		-- A basse altitude, c'est l'humidite qui decide du biome. Le relief
		-- seul donnerait des continents monochromes.
		if kind == T.PLAINS then
			local m = moisture[i + 1]
			if m > 0.12 then
				kind = T.FOREST
			elseif m < -0.12 then
				kind = T.SAVANNA
			end
		end

		buffer.writeu8(terrain, i, kind)
	end

	return terrain
end

--=============================================================================
-- Helpers d'index
--=============================================================================

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

local coastScratch = table.create(4, 0)

--[[
	Une tuile est cotiere si c'est de la terre touchant l'ocean. C'est la
	condition d'implantation d'un port et le seul point de debarquement valide.
]]
function MapGen.isCoastal(terrain: buffer, index: number): boolean
	if buffer.readu8(terrain, index) == T.OCEAN then
		return false
	end
	local n = MapGen.neighbors(index, coastScratch)
	for i = 1, n do
		if buffer.readu8(terrain, coastScratch[i]) == T.OCEAN then
			return true
		end
	end
	return false
end

-- Nombre total de tuiles de terre : denominateur de toutes les conditions de
-- victoire et du deblocage du nucleaire.
function MapGen.countLand(terrain: buffer): number
	local count = 0
	for i = 0, W * H - 1 do
		if buffer.readu8(terrain, i) ~= T.OCEAN then
			count += 1
		end
	end
	return count
end

--[[
	Hash stable d'un buffer de tuiles (terrain ou owner).

	FNV-1a 32 bits sur les octets : deterministe, sans flottant, comparable
	entre client et serveur pour detecter une desync de generation.
]]
function MapGen.hashBuffer(buf: buffer): number
	local hash = 2166136261
	local len = buffer.len(buf)
	for i = 0, len - 1 do
		hash = bit32.bxor(hash, buffer.readu8(buf, i))
		-- FNV prime 16777619 ; pas de bit32.mul en Luau.
		hash = (hash * 16777619) % 4294967296
	end
	return hash
end

function MapGen.terrainHash(terrain: buffer): number
	return MapGen.hashBuffer(terrain)
end

function MapGen.countByBiome(terrain: buffer): { [number]: number }
	local counts: { [number]: number } = {}
	for i = 0, W * H - 1 do
		local kind = buffer.readu8(terrain, i)
		counts[kind] = (counts[kind] or 0) + 1
	end
	return counts
end

--[[
	Metadonnees envoyees dans MapInit pour verifier le contrat client/serveur.
]]
export type MapMeta = {
	mapId: string,
	mapVersion: number,
	seed: number,
	generatorVersion: number,
	terrainHash: number,
	width: number,
	height: number,
}

-- N91 : un record recycle (leftover N90). startMatch + late join ecrasent
-- les 7 champs. Un leftover seed / terrainHash = client qui refuse la
-- carte (contrat hash N4). table.clear interdit (ce n'est pas un hash).
-- Pas de require GameState (cycle Shared). Distinct de profileBuf (N90)
-- et de matchUpdateBuf (N86).
local metaBuf: MapMeta = {
	mapId = "",
	mapVersion = 0,
	seed = 0,
	generatorVersion = 0,
	terrainHash = 0,
	width = 0,
	height = 0,
}

function MapGen.mapMeta(seed: number, terrain: buffer): MapMeta
	local rec = metaBuf
	rec.mapId = Config.MAP_ID
	rec.mapVersion = Config.MAP_VERSION
	rec.seed = seed
	rec.generatorVersion = Config.GENERATOR_VERSION
	rec.terrainHash = MapGen.terrainHash(terrain)
	rec.width = W
	rec.height = H
	return rec
end

-- Banc N91 : rawequal record. Pas replique.
MapGen.metaBuf = metaBuf

return MapGen
