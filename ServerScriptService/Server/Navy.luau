--!strict
--[[
	Marine : debarquements et commerce maritime.

	Sans elle, un joueur insulaire est en prison et un continent voisin est
	imprenable — c'est la mecanique qui ouvre reellement la carte.

	Les navires suivent un vrai chemin maritime calcule en BFS, pas une ligne
	droite : un transport ne traverse jamais la terre, et une invasion est donc
	reellement contournable et interceptable une fois qu'on ajoutera les
	navires de guerre.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState

local Navy = {}

local NEUTRAL = Config.NEUTRAL_SLOT
local OCEAN = Config.TERRAIN.OCEAN
local KIND_TRANSPORT = 1
local KIND_TRADE = 2

local MAX_BFS_NODES = 24000

local scratch = table.create(4, 0)

--=============================================================================
-- Recherche de route maritime
--=============================================================================

--[[
	BFS depuis une tuile cotiere de depart jusqu'a une tuile cotiere d'arrivee,
	en ne traversant que de l'ocean. Renvoie la liste des indices de tuiles a
	suivre, arrivee comprise, ou nil s'il n'y a pas de route.

	Le cout est borne par MAX_BFS_NODES : sur une carte de 40 000 tuiles c'est
	quelques millisecondes, et ce n'est appele qu'au lancement d'un navire,
	jamais dans la boucle de tick.
]]
function Navy.findSeaPath(state: GameState, fromTile: number, toTile: number): { number }?
	local terrain = state.terrain

	local visited = buffer.create(Config.TILE_COUNT)
	local parent: { [number]: number } = {}

	local queue = table.create(512)
	local head = 1
	local explored = 0

	-- On amorce avec les cases d'ocean adjacentes au point de depart.
	local n = MapGen.neighbors(fromTile, scratch)
	for i = 1, n do
		local nb = scratch[i]
		if buffer.readu8(terrain, nb) == OCEAN and buffer.readu8(visited, nb) == 0 then
			buffer.writeu8(visited, nb, 1)
			parent[nb] = fromTile
			table.insert(queue, nb)
		end
	end

	while head <= #queue do
		local current = queue[head]
		head += 1
		explored += 1
		if explored > MAX_BFS_NODES then
			return nil
		end

		local count = MapGen.neighbors(current, scratch)
		for i = 1, count do
			local nb = scratch[i]

			if nb == toTile then
				-- Arrivee : on remonte la chaine des parents.
				local path = { toTile }
				local node = current
				while node ~= fromTile do
					table.insert(path, node)
					node = parent[node]
				end
				-- Le chemin a ete reconstruit a l'envers.
				local reversed = table.create(#path)
				for k = #path, 1, -1 do
					table.insert(reversed, path[k])
				end
				return reversed
			end

			if buffer.readu8(terrain, nb) == OCEAN and buffer.readu8(visited, nb) == 0 then
				buffer.writeu8(visited, nb, 1)
				parent[nb] = current
				table.insert(queue, nb)
			end
		end
	end

	return nil
end

-- Tuile cotiere possedee par `slot` la plus proche de `target`, point de depart
-- naturel d'un debarquement.
function Navy.nearestOwnCoast(state: GameState, slot: number, target: number): number?
	local tx, ty = MapGen.fromIndex(target)
	local best: number? = nil
	local bestDist = math.huge

	local ps = state.players[slot]
	if not ps then
		return nil
	end

	-- On balaie l'ensemble cotier maintenu par GameState, pas la frontiere :
	-- une cote entouree de son propre territoire n'est pas une frontiere, et
	-- la chercher la rendait injouable tout empire ayant absorbe son littoral.
	for index in ps.coast do
		local x, y = MapGen.fromIndex(index)
		local dx, dy = x - tx, y - ty
		local dist = dx * dx + dy * dy
		if dist < bestDist then
			bestDist = dist
			best = index
		end
	end

	return best
end

--=============================================================================
-- Debarquements
--=============================================================================

function Navy.countBoats(state: GameState, slot: number, kind: number): number
	local count = 0
	for _, boat in state.boats do
		if boat.slot == slot and boat.kind == kind then
			count += 1
		end
	end
	return count
end

function Navy.launchInvasion(state: GameState, slot: number, targetTile: number): (boolean, string?)
	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	if targetTile < 0 or targetTile >= Config.TILE_COUNT then
		return false, "Position hors carte."
	end

	if not state:isLand(targetTile) then
		return false, "Vise une cote, pas la pleine mer."
	end

	if not MapGen.isCoastal(state.terrain, targetTile) then
		return false, "Cette tuile n'est pas accessible depuis la mer."
	end

	local targetOwner = buffer.readu8(state.owner, targetTile)
	if targetOwner == slot then
		return false, "Ce territoire est deja a toi."
	end
	if targetOwner ~= NEUTRAL and state:areAllied(slot, targetOwner) then
		return false, "Tu es allie a cette faction."
	end

	if Navy.countBoats(state, slot, KIND_TRANSPORT) >= Config.MAX_BOATS_PER_PLAYER then
		return false, "Tous tes transports sont deja en mer."
	end

	local doctrine = state:doctrineOf(slot)
	local capacity = Config.BOAT_TROOP_RATIO * doctrine.boatCapacity
	local troops = math.floor(ps.troops * math.min(capacity, 0.9))
	if troops < Config.MIN_BOAT_TROOPS then
		return false, `Il faut au moins {Config.MIN_BOAT_TROOPS} troupes embarquables.`
	end

	local origin = Navy.nearestOwnCoast(state, slot, targetTile)
	if not origin then
		return false, "Tu n'as aucun acces a la mer."
	end

	local path = Navy.findSeaPath(state, origin, targetTile)
	if not path then
		return false, "Aucune route maritime vers cette cote."
	end
	if #path > Config.BOAT_MAX_RANGE then
		return false, "Cette cote est hors de portee de tes transports."
	end

	ps.troops -= troops

	local ox, oy = MapGen.fromIndex(origin)
	table.insert(state.boats, {
		id = state:nextId(),
		slot = slot,
		kind = KIND_TRANSPORT,
		troops = troops,
		x = ox,
		y = oy,
		path = path,
		step = 1,
		targetTile = targetTile,
	})

	return true, `Debarquement en route — {troops} troupes.`
end

--[[
	Resolution d'un debarquement. La tete de pont coute plus cher qu'une
	avancee terrestre normale : arriver par la mer est un pari, pas un
	raccourci.
]]
local function resolveLanding(state: GameState, boat: GameState.Boat)
	local ps = state.players[boat.slot]
	if not ps then
		return
	end

	local tile = boat.targetTile
	local targetOwner = buffer.readu8(state.owner, tile)

	if targetOwner == boat.slot then
		ps.troops += boat.troops -- la cote est devenue notre : les troupes rentrent
		return
	end

	local defender = if targetOwner ~= NEUTRAL then state.players[targetOwner] else nil
	local cost = state:tileCost(tile, boat.slot, defender) * Config.BOAT_LANDING_BONUS

	if cost > boat.troops then
		-- Debarquement repousse a la mer.
		if defender then
			defender.troops = math.max(0, defender.troops - boat.troops * 0.35)
		end
		state:notify(`Ton debarquement a ete repousse.`, "bad", boat.slot)
		return
	end

	local remaining = boat.troops - cost
	if defender then
		defender.troops = math.max(0, defender.troops - cost * Config.DEFENDER_LOSS_RATIO)
		state:notify(`{ps.name} a debarque sur ton territoire !`, "bad", defender.slot)
	end

	state:setOwner(tile, boat.slot)
	state:seedBeachhead(boat.slot, targetOwner, remaining, tile)
	state:notify(`Tete de pont etablie.`, "good", boat.slot)
end

--=============================================================================
-- Navires marchands (visuels)
--=============================================================================
-- L'or du commerce est calcule dans l'economie ; ces navires sont la
-- representation visible de ces routes. Voir passer les convois d'un rival
-- donne envie de lui couper la route — c'est ce qui rend l'embargo lisible.

local function spawnTradeShip(state: GameState, rng: Random)
	local ports: { { index: number, slot: number } } = {}
	for index, building in state.buildings do
		if building.kind == Config.BUILDING.PORT then
			table.insert(ports, { index = index, slot = building.slot })
		end
	end
	if #ports < 2 then
		return
	end

	local a = ports[rng:NextInteger(1, #ports)]
	local b = ports[rng:NextInteger(1, #ports)]
	if a.slot == b.slot then
		return
	end

	local embargoA = state.embargoes[a.slot]
	local embargoB = state.embargoes[b.slot]
	if (embargoA and embargoA[b.slot]) or (embargoB and embargoB[a.slot]) then
		return -- route commerciale fermee
	end

	local path = Navy.findSeaPath(state, a.index, b.index)
	if not path or #path > Config.BOAT_MAX_RANGE then
		return
	end

	local ox, oy = MapGen.fromIndex(a.index)
	table.insert(state.boats, {
		id = state:nextId(),
		slot = a.slot,
		kind = KIND_TRADE,
		troops = 0,
		x = ox,
		y = oy,
		path = path,
		step = 1,
		targetTile = b.index,
	})
end

--=============================================================================
-- Tick
--=============================================================================

function Navy.step(state: GameState, rng: Random)
	if state.tick % Config.TRADE_SHIP_INTERVAL == 0 then
		spawnTradeShip(state, rng)
	end

	for i = #state.boats, 1, -1 do
		local boat = state.boats[i]
		local speed = Config.BOAT_SPEED * state:doctrineOf(boat.slot).boatSpeed

		-- Avance le long du chemin, en interpolant pour un mouvement fluide
		-- cote client meme a 10 ticks/seconde.
		local remaining = speed
		while remaining > 0 and boat.step <= #boat.path do
			local nextTile = boat.path[boat.step]
			local nx, ny = MapGen.fromIndex(nextTile)
			local dx, dy = nx - boat.x, ny - boat.y
			local dist = math.sqrt(dx * dx + dy * dy)

			if dist <= remaining then
				boat.x, boat.y = nx, ny
				boat.step += 1
				remaining -= dist
			else
				boat.x += dx / dist * remaining
				boat.y += dy / dist * remaining
				remaining = 0
			end
		end

		if boat.step > #boat.path then
			if boat.kind == KIND_TRANSPORT then
				resolveLanding(state, boat)
			end
			table.remove(state.boats, i)
		end
	end
end

Navy.KIND_TRANSPORT = KIND_TRANSPORT
Navy.KIND_TRADE = KIND_TRADE

return Navy
