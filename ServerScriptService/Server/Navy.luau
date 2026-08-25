--!strict
--[[
	Marine : debarquements, commerce, retraite en mer (OpenFront).
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

function Navy.findSeaPath(state: GameState, fromTile: number, toTile: number): { number }?
	local terrain = state.terrain
	local visited = buffer.create(Config.TILE_COUNT)
	local parent: { [number]: number } = {}
	local queue = table.create(512)
	local head = 1
	local explored = 0

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
				local path = { toTile }
				local node = current
				while node ~= fromTile do
					table.insert(path, node)
					node = parent[node]
				end
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

function Navy.nearestOwnCoast(state: GameState, slot: number, target: number): number?
	local tx, ty = MapGen.fromIndex(target)
	local best: number? = nil
	local bestDist = math.huge
	local ps = state.players[slot]
	if not ps then
		return nil
	end
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

function Navy.countBoats(state: GameState, slot: number, kind: number): number
	local count = 0
	for _, boat in state.boats do
		if boat.slot == slot and boat.kind == kind then
			count += 1
		end
	end
	return count
end

local function boatIndex(boat): number
	local x = math.clamp(math.floor(boat.x + 0.5), 0, Config.MAP_WIDTH - 1)
	local y = math.clamp(math.floor(boat.y + 0.5), 0, Config.MAP_HEIGHT - 1)
	return MapGen.toIndex(x, y)
end

local function applyRetreatMalus(state: GameState, boat)
	local ps = state.players[boat.slot]
	if not ps then
		return
	end
	local loss = Config.BOAT_RETREAT_LOSS or 0.25
	local survivors = math.floor(boat.troops * (1 - loss))
	ps.troops += survivors
	if boat.troops - survivors > 0 then
		state:notify(`Retraite navale : {boat.troops - survivors} troupes perdues.`, "bad", boat.slot)
	end
end

function Navy.beginRetreat(state: GameState, boat): boolean
	if boat.kind ~= KIND_TRANSPORT or boat.retreating then
		return false
	end
	local here = boatIndex(boat)
	local home = boat.homeTile or Navy.nearestOwnCoast(state, boat.slot, here)
	if not home then
		applyRetreatMalus(state, boat)
		boat.troops = 0
		return true
	end
	local path = Navy.findSeaPath(state, here, home)
	if not path then
		applyRetreatMalus(state, boat)
		boat.troops = 0
		return true
	end
	boat.retreating = true
	boat.path = path
	boat.step = 1
	boat.targetTile = home
	return true
end

function Navy.retreatBoats(state: GameState, slot: number, targetOwner: number?): number
	local n = 0
	for _, boat in state.boats do
		if boat.kind ~= KIND_TRANSPORT or boat.slot ~= slot or boat.retreating then
			continue
		end
		local destOwner = buffer.readu8(state.owner, boat.targetTile)
		if targetOwner == nil or destOwner == targetOwner then
			if Navy.beginRetreat(state, boat) then
				n += 1
			end
		end
	end
	return n
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

	local cap = Config.MAX_BOATS_PER_PLAYER or 3
	if Navy.countBoats(state, slot, KIND_TRANSPORT) >= cap then
		return false, `Tous tes transports sont deja en mer ({cap} max).`
	end

	local doctrine = state:doctrineOf(slot)
	local troops = math.floor(ps.troops / 5 * (doctrine.boatCapacity or 1))
	if troops < Config.MIN_BOAT_TROOPS then
		return false, `Il faut au moins {Config.MIN_BOAT_TROOPS} troupes embarquables.`
	end
	troops = math.min(troops, math.floor(ps.troops))

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
		homeTile = origin,
		retreating = false,
	})

	state:sound("boatLaunch", slot)
	return true, `Debarquement en route — {troops} troupes.`
end

local function resolveLanding(state: GameState, boat)
	local ps = state.players[boat.slot]
	if not ps then
		return
	end

	if boat.retreating or boat.troops <= 0 then
		if boat.troops > 0 then
			applyRetreatMalus(state, boat)
		end
		return
	end

	local tile = boat.targetTile
	local targetOwner = buffer.readu8(state.owner, tile)

	if targetOwner == boat.slot then
		applyRetreatMalus(state, boat)
		return
	end

	if targetOwner ~= NEUTRAL and state:areAllied(boat.slot, targetOwner) then
		ps.troops += boat.troops
		return
	end

	local defender = if targetOwner ~= NEUTRAL then state.players[targetOwner] else nil
	state:setOwner(tile, boat.slot)
	if defender then
		state:notify(`{ps.name} a debarque sur ton territoire !`, "bad", defender.slot)
	end
	state:seedBeachhead(boat.slot, targetOwner, boat.troops, tile)
	state:notify(`Tete de pont etablie.`, "good", boat.slot)
	state:sound("boatLand")
end

local function tradeValue(distance: number): number
	return Config.TRADE_GOLD_BASE + distance * Config.TRADE_GOLD_PER_TILE
end

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
	table.sort(ports, function(a, b)
		return a.index < b.index
	end)
	local afloat = countTradeShips(state)
	for _, source in ports do
		if afloat >= Config.MAX_TRADE_SHIPS then
			return
		end
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
			homeTile = source.index,
		})
		afloat += 1
	end
end

local function resolveTrade(state: GameState, boat)
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
				angle = (index % 360) * math.pi / 180,
			})
		end
	end
end

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

function Navy.step(state: GameState, rng: Random)
	syncCarriers(state)
	stepCarriers(state)
	if state.tick % Config.TRADE_SHIP_INTERVAL == 0 then
		spawnTradeShips(state, rng)
	end

	for i = #state.boats, 1, -1 do
		local boat = state.boats[i]
		if boat.kind == KIND_CARRIER then
			continue
		end

		if boat.kind == KIND_TRANSPORT and not boat.retreating then
			local destOwner = buffer.readu8(state.owner, boat.targetTile)
			local destLand = state:isLand(boat.targetTile)
			if destOwner == boat.slot or not destLand or (destOwner ~= NEUTRAL and state:areAllied(boat.slot, destOwner)) then
				Navy.beginRetreat(state, boat)
				if boat.troops <= 0 then
					table.remove(state.boats, i)
					continue
				end
			end
		end

		local speed = Config.BOAT_SPEED * state:doctrineOf(boat.slot).boatSpeed
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
