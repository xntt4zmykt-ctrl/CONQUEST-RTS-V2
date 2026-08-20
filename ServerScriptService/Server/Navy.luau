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
local KIND_CARRIER = 3

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
	if targetOwner ~= NEUTRAL and not state.combatUnlocked then
		return false, "Les flottes ennemies sont protegees pendant la preparation."
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
	ps.attacksLaunched += 1

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

	state:sound("boatLaunch", slot)
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
	state:sound("boatLand")
end

--=============================================================================
-- Navires marchands
--=============================================================================

--[[
	Commerce maritime, modele OpenFront.

	Trois regles portent tout le systeme :

	  1. Un port ne commerce **jamais** avec ses propres ports. L'or vient de
	     l'etranger, ce qui fait d'un voisin cotier une ressource et pas
	     seulement une menace.
	  2. Il faut une route navigable reelle entre les deux ports. Un embargo,
	     une mer fermee ou une distance excessive coupent la ligne.
	  3. Les deux ports touchent, a l'arrivee. Couler un convoi prive donc deux
	     factions a la fois, dont celle qui ne l'escortait pas.

	Le niveau du port est son debit : chaque niveau tire une chance d'armer un
	navire, exactement comme un port de niveau 3 tire trois fois dans le jeu de
	reference.
]]

-- Or verse a chaque extremite d'une route, selon sa longueur.
local function tradeValue(distance: number): number
	return Config.TRADE_GOLD_BASE + distance * Config.TRADE_GOLD_PER_TILE
end

--[[
	Le commerce est-il ouvert entre ces deux factions ?

	L'embargo est unilateral dans les deux sens : il suffit qu'un seul camp
	l'ait declare pour que la route soit morte.
]]
local function canTrade(state: GameState, a: number, b: number): boolean
	if a == b then
		return false
	end
	local fromA = state.embargoes[a]
	local fromB = state.embargoes[b]
	if (fromA and fromA[b]) or (fromB and fromB[a]) then
		return false
	end
	return true
end

local function countTradeShips(state: GameState): number
	local n = 0
	for _, boat in state.boats do
		if boat.kind == KIND_TRADE then
			n += 1
		end
	end
	return n
end

--[[
	Arme les convois du tick.

	On collecte les ports une seule fois puis chaque port tire pour lui-meme :
	un balayage par port couterait O(ports^2) sur une carte saturee, alors que
	le partenaire se tire dans la liste deja construite.
]]
local function spawnTradeShips(state: GameState, rng: Random)
	local ports: { { index: number, slot: number, level: number } } = {}
	for index, building in state.buildings do
		if building.kind == Config.BUILDING.PORT then
			table.insert(ports, { index = index, slot = building.slot, level = building.level })
		end
	end
	if #ports < 2 then
		return
	end

	-- L'ordre d'iteration d'une table Luau n'est pas garanti. Sans tri, deux
	-- serveurs partis de la meme graine divergeraient des le premier convoi.
	table.sort(ports, function(a, b)
		return a.index < b.index
	end)

	local afloat = countTradeShips(state)

	for _, source in ports do
		if afloat >= Config.MAX_TRADE_SHIPS then
			return
		end

		-- Un tirage par niveau : le niveau du port EST son debit.
		local armed = false
		for _ = 1, source.level do
			if rng:NextNumber() < Config.TRADE_SHIP_CHANCE then
				armed = true
				break
			end
		end
		if not armed then
			continue
		end

		--[[
			Partenaires possibles, ponderes par niveau.

			Un port etranger de niveau 3 apparait trois fois dans le tirage : les
			grandes places commerciales attirent naturellement plus de trafic,
			sans avoir a ecrire de regle pour le dire.
		]]
		local candidates: { number } = {}
		for i, other in ports do
			if canTrade(state, source.slot, other.slot) then
				for _ = 1, other.level do
					table.insert(candidates, i)
				end
			end
		end
		if #candidates == 0 then
			continue
		end

		local target = ports[candidates[rng:NextInteger(1, #candidates)]]
		local path = Navy.findSeaPath(state, source.index, target.index)
		if not path or #path > Config.BOAT_MAX_RANGE then
			continue
		end

		local ox, oy = MapGen.fromIndex(source.index)
		table.insert(state.boats, {
			id = state:nextId(),
			slot = source.slot,
			kind = KIND_TRADE,
			troops = 0,
			x = ox,
			y = oy,
			path = path,
			step = 1,
			targetTile = target.index,
			-- Port d'attache : il faut savoir qui paie a l'arrivee, et le
			-- proprietaire du navire a pu changer entre-temps.
			homeTile = source.index,
		})
		afloat += 1
	end
end

--[[
	Le convoi arrive a bon port.

	Tout est reverifie ici plutot qu'au depart : entre le depart et l'arrivee,
	le port de destination a pu etre detruit, capture, ou un embargo a pu tomber.
	Payer sur la foi des conditions de depart reviendrait a recompenser une
	route qui n'existe plus.
]]
local function resolveTrade(state: GameState, boat: GameState.Boat)
	local destination = state.buildings[boat.targetTile]
	if not destination or destination.kind ~= Config.BUILDING.PORT then
		return
	end

	local origin = if boat.homeTile then state.buildings[boat.homeTile] else nil
	if not origin or origin.kind ~= Config.BUILDING.PORT then
		return
	end

	if not canTrade(state, origin.slot, destination.slot) then
		return
	end

	local seller = state.players[origin.slot]
	local buyer = state.players[destination.slot]
	if not seller or not buyer then
		return
	end

	local gold = tradeValue(#boat.path)
	seller.gold += gold
	buyer.gold += gold

	local rounded = math.floor(gold)
	state:notify(`\u{1F6A2} Convoi arrive chez {buyer.name} : +{rounded} or.`, "good", seller.slot)
	state:notify(`\u{1F6A2} Convoi de {seller.name} accoste : +{rounded} or.`, "good", buyer.slot)
end

--=============================================================================
-- Porte-avions de patrouille
--=============================================================================

--[[
	Synchronise la flotte de patrouille avec les bases navales.

	Un porte-avions par base : on en cree un quand une base apparait, on le
	retire quand elle disparait ou change de main. Passer par cette
	reconciliation plutot que par des evenements evite toute flotte fantome
	apres une capture ou une frappe nucleaire.
]]
local function syncCarriers(state: GameState)
	local seen: { [number]: boolean } = {}

	for i = #state.boats, 1, -1 do
		local boat = state.boats[i]
		if boat.kind ~= KIND_CARRIER then
			continue
		end

		local base = state.buildings[boat.homeTile]
		if not base or base.kind ~= Config.BUILDING.NAVAL_BASE then
			table.remove(state.boats, i)
			continue
		end

		-- La base a change de main : le porte-avions suit son nouveau
		-- proprietaire plutot que de rester au service du vaincu.
		boat.slot = base.slot
		seen[boat.homeTile] = true
	end

	for index, building in state.buildings do
		if building.kind == Config.BUILDING.NAVAL_BASE and not seen[index] then
			local x, y = MapGen.fromIndex(index)
			table.insert(state.boats, {
				id = state:nextId(),
				slot = building.slot,
				kind = KIND_CARRIER,
				troops = 0,
				x = x,
				y = y,
				path = {},
				step = 1,
				targetTile = index,
				homeTile = index,
				-- L'angle de depart derive de la tuile : deux bases voisines
				-- n'ont pas leurs porte-avions superposes.
				angle = (index % 360) * math.pi / 180,
			})
		end
	end
end

--[[
	Patrouille et interception.

	L'orbite est purement geometrique — pas de trajectoire a calculer, pas de
	collision a resoudre. Un transport ennemi a portee perd une fraction de ses
	troupes a chaque tick, et coule s'il descend sous le seuil d'embarquement :
	longer une cote defendue coute cher, la contourner coute du temps.
]]
local function stepCarriers(state: GameState)
	for _, boat in state.boats do
		if boat.kind ~= KIND_CARRIER then
			continue
		end

		local hx, hy = MapGen.fromIndex(boat.homeTile)
		boat.angle += Config.CARRIER_PATROL_SPEED
		boat.x = hx + math.cos(boat.angle) * Config.CARRIER_PATROL_RADIUS
		boat.y = hy + math.sin(boat.angle) * Config.CARRIER_PATROL_RADIUS
	end

	for i = #state.boats, 1, -1 do
		local target = state.boats[i]
		if target.kind ~= KIND_TRANSPORT then
			continue
		end

		for _, carrier in state.boats do
			if carrier.kind ~= KIND_CARRIER or carrier.slot == target.slot then
				continue
			end
			if state:areAllied(carrier.slot, target.slot) then
				continue
			end

			local dx = carrier.x - target.x
			local dy = carrier.y - target.y
			if dx * dx + dy * dy > Config.CARRIER_INTERCEPT_RANGE * Config.CARRIER_INTERCEPT_RANGE then
				continue
			end

			target.troops -= target.troops * Config.CARRIER_INTERCEPT_DAMAGE

			if target.troops < Config.MIN_BOAT_TROOPS then
				local owner = state.players[target.slot]
				local defender = state.players[carrier.slot]
				state:notify("Ton convoi a ete coule en mer.", "bad", target.slot)
				if defender then
					state:notify(
						`Ta flotte a coule un debarquement{if owner then ` de {owner.name}` else ""}.`,
						"good",
						carrier.slot
					)
				end
				state:sound("boatLand")
				table.remove(state.boats, i)
			end
			break
		end
	end
end

--=============================================================================
-- Tick
--=============================================================================

function Navy.step(state: GameState, rng: Random)
	syncCarriers(state)
	stepCarriers(state)
	if state.tick % Config.TRADE_SHIP_INTERVAL == 0 then
		spawnTradeShips(state, rng)
	end

	for i = #state.boats, 1, -1 do
		local boat = state.boats[i]
		if boat.kind == KIND_CARRIER then
			continue -- la patrouille est geree plus haut, sans chemin a suivre
		end
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
			elseif boat.kind == KIND_TRADE then
				resolveTrade(state, boat)
			end
			table.remove(state.boats, i)
		end
	end
end

Navy.KIND_TRANSPORT = KIND_TRANSPORT
Navy.KIND_TRADE = KIND_TRADE
Navy.KIND_CARRIER = KIND_CARRIER

return Navy
