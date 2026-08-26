--!strict
--[[
	Chantier B-E : combat CONQUEST, fallout, spawn, warships, SAM, tribus config.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Doctrines = require(ReplicatedStorage.Shared.Doctrines)
local Eras = require(ReplicatedStorage.Shared.Eras)
local Heap = require(ReplicatedStorage.Shared.Heap)
local Doomsday = require(ReplicatedStorage.Shared.Doomsday)

local ChantierB = {}

-- Debit vivant de captures par front par tick. Config.MAX_TILES_PER_TICK
-- (400 brut / 56 apres apply) est mort : ne pas le lire pour limiter le combat.
ChantierB.CAPTURE_GUARD = 80

local NEUTRAL = Config.NEUTRAL_SLOT
local OCEAN = Config.TERRAIN.OCEAN
local scratch = table.create(4, 0)
local annexScratch = table.create(4, 0)
local annexVisited: { [number]: boolean } = {}
local annexQueue: { number } = {}
local annexPocket: { number } = {}

local function within(x: number, lo: number, hi: number): number
	return math.clamp(x, lo, hi)
end

local function terrainMagSpeed(terrain: number): (number, number)
	local T = Config.TERRAIN
	if terrain == T.MOUNTAIN or terrain == T.PEAK then
		return 120, 25
	end
	if terrain == T.HILLS or terrain == T.HIGHLAND then
		return 100, 20
	end
	return 80, 16.5
end

function ChantierB.attackLogic(state, attackTroops: number, attacker: any, defender: any, tile: number)
	local terrain = buffer.readu8(state.terrain, tile)
	local mag, speed = terrainMagSpeed(terrain)
	local posted = false
	if defender then
		local bunkers = state.bunkersBySlot and state.bunkersBySlot[defender.slot]
		if bunkers then
			local cx, cy = MapGen.fromIndex(tile)
			local r = Config.DEFENSE_RADIUS or 30
			local r2 = r * r
			for index in bunkers do
				local bx, by = MapGen.fromIndex(index)
				local dx, dy = bx - cx, by - cy
				if dx * dx + dy * dy <= r2 then
					posted = true
					break
				end
			end
		end
	end
	local fallout = state.fallout and state.fallout[tile] and state.fallout[tile] > state.tick

	if defender then
		local tiles = math.max(1, defender.tiles)
		local defenderTroopLoss = defender.troops / tiles
		local ratio = within(defender.troops / math.max(1, attackTroops), 0.6, 2)
		local marked = defender.traitorUntil and state.tick < defender.traitorUntil
		local traitorMod = if marked then 0.5 else 1
		local traitorSpeed = if marked then (1 / 0.8) else 1
		local largeDef = state:sizeDefenseFactor(defender)
		local _, costFactor = state:sizeAttackFactors(attacker)
		local current = ratio * mag * 0.8 * largeDef * traitorMod
		local alt = 1.3 * defenderTroopLoss * (mag / 100) * traitorMod
		local attackerTroopLoss = (0.6 * current + 0.4 * alt) * costFactor
		local tilesPerTickUsed = within(defender.troops / (5 * math.max(1, attackTroops)), 0.2, 1.5)
			* speed
			* largeDef
			* traitorSpeed
		if posted then
			attackerTroopLoss *= (Config.DEFENSE_POST_BONUS or 5)
			tilesPerTickUsed *= (Config.DEFENSE_POST_SPEED_BONUS or 3)
		end
		if fallout then
			attackerTroopLoss *= Config.FALLOUT_DEFENSE_MULT
		end
		-- Tables OF brutes : pas de multiplicateur de doctrine sur la perte.
		return attackerTroopLoss, defenderTroopLoss, tilesPerTickUsed
	else
		local attackerTroopLoss = if attacker.isBot then mag / 10 else mag / 5
		local tilesPerTickUsed = within((2000 * math.max(10, speed)) / math.max(1, attackTroops), 5, 100)
		if fallout then
			attackerTroopLoss *= Config.FALLOUT_DEFENSE_MULT
		end
		return attackerTroopLoss, 0, tilesPerTickUsed
	end
end

function ChantierB.attackTilesPerTick(attackTroops: number, defender: any, contact: number): number
	local adj = math.max(1, contact)
	if defender then
		return within(((5 * attackTroops) / math.max(1, defender.troops)) * 2, 0.01, 0.5) * adj * 3
	end
	return adj * 2
end

function ChantierB.tryAnnex(state, attackerSlot: number, defenderSlot: number, seed: number)
	if defenderSlot == NEUTRAL then
		return
	end
	-- Apres setOwner, `seed` appartient deja a l'attaquant. Le BFS part des
	-- voisins encore detenus par le defenseur (sinon la poche n'est jamais vue).
	table.clear(annexVisited)
	table.clear(annexQueue)
	table.clear(annexPocket)
	local n0 = MapGen.neighbors(seed, annexScratch)
	for i = 1, n0 do
		local nb = annexScratch[i]
		if buffer.readu8(state.owner, nb) == defenderSlot and not annexVisited[nb] then
			annexVisited[nb] = true
			table.insert(annexQueue, nb)
		end
	end
	if #annexQueue == 0 then
		return
	end
	local head = 1
	while head <= #annexQueue do
		local cur = annexQueue[head]
		head += 1
		if buffer.readu8(state.owner, cur) ~= defenderSlot then
			continue
		end
		table.insert(annexPocket, cur)
		if #annexPocket > 280 then
			return
		end
		local n = MapGen.neighbors(cur, annexScratch)
		for i = 1, n do
			local nb = annexScratch[i]
			local owner = buffer.readu8(state.owner, nb)
			if buffer.readu8(state.terrain, nb) == OCEAN then
				return
			end
			if owner ~= attackerSlot and owner ~= defenderSlot then
				return
			end
			if owner == defenderSlot and not annexVisited[nb] then
				annexVisited[nb] = true
				table.insert(annexQueue, nb)
			end
		end
	end
	if #annexPocket == 0 then
		return
	end
	for _, index in annexPocket do
		state:setOwner(index, attackerSlot)
	end
end

function ChantierB.apply(cfg)
	cfg.START_TROOPS = 8000
	cfg.HUMAN_START_TROOPS = 12000
	cfg.BASE_MAX_TROOPS = 0
	cfg.MAX_TROOPS_TILE_SCALE = 1000
	cfg.MAX_TROOPS_TILE_EXPONENT = 0.6
	cfg.MAX_TROOPS_LAND_BASE = 50000
	cfg.CITY_TROOP_INCREASE = 250000
	cfg.FLAT_GOLD_HUMAN = 1.2
	cfg.FLAT_GOLD_BOT = 0.6
	cfg.GOLD_TILE_SCALE = 0
	cfg.GOLD_PER_PORT = 0
	cfg.GOLD_PER_CAPITAL = 0
	cfg.TRADE_GOLD_SCALE = 0.002
	cfg.TRAIN_GOLD_SELF = 20
	cfg.TRAIN_GOLD_ALLY = 70 -- mort apres install (Trade lit TRUCK_GOLD_*)
	cfg.TRAIN_GOLD_OTHER = 50 -- mort apres install
	cfg.BUILD_MIN_SPACING = 15
	cfg.BUILD_SNAP_RADIUS = 15
	cfg.BUILD_SNAP_RADIUS_COASTAL = 20
	cfg.SPAWN_MIN_PLAYER_DISTANCE = 30
	cfg.MAX_BOATS_PER_PLAYER = 3
	cfg.VICTORY_LAND_RATIO = 0.80
	cfg.TRAITOR_MARK_DURATION = 300
	cfg.GROWTH_RATE = 0
	cfg.MIN_GROWTH = 0
	cfg.TILE_BASE_COST = 18
	cfg.NEUTRAL_COST_MULT = 0.88
	cfg.DEFENSE_DENSITY_K = 1.15
	cfg.MAX_TILES_PER_TICK = 56 -- MORT : debit vivant = ChantierB.CAPTURE_GUARD (80)
	cfg.FRONT_TILES_PER_CONTACT = 2.4 -- mort apres install
	cfg.DEFENSE_RADIUS = 30
	cfg.DEFENSE_STRENGTH = 200
	cfg.DEFENSE_POST_BONUS = 5
	cfg.DEFENSE_POST_SPEED_BONUS = 3
	cfg.DEFENSE_COST_DIVISOR = 42 -- mort apres install (buffer defense ignore)
	cfg.WARSHIP_PATROL_RANGE = 100
	cfg.WARSHIP_TARGET_RANGE = 100
	cfg.WARSHIP_SHELL_RATE = 20
	cfg.WARSHIP_MAX_HEALTH = 1000
	cfg.WARSHIP_SHELL_DAMAGE = 250
	cfg.WARSHIP_TRANSPORT_DAMAGE = 0.28
	cfg.WARSHIP_TRADE_SINK = true
	cfg.WARSHIP_RESPAWN_TICKS = 300
	cfg.CARRIER_PATROL_RADIUS = 100
	cfg.CARRIER_INTERCEPT_RANGE = 100
	cfg.RETREAT_LOSS = 0.25 -- malusForRetreat contre joueur ; neutre = 0 (voir stepAttacks)
	cfg.RETREAT_LOSS_NEUTRAL = 0
	cfg.COLLAPSE_MIN_TILES = 100
	cfg.COLLAPSE_TILE_RATIO = 0
	-- Anti-blob OF : MIDPOINT 150k / DECAY ln2/50k sur carte pleine ; ici on
	-- scale au landCount pour garder le meme profil relatif.
	cfg.LARGE_EMPIRE_MIDPOINT_RATIO = 0.55 -- ~ OF 150k / ~270k terres typiques
	cfg.LARGE_EMPIRE_SPREAD = 1 / 3
	cfg.LARGE_DEFENDER_FLOOR = 0.70
	cfg.LARGE_ATTACKER_THRESHOLD_RATIO = 100000 / 150000 -- OF : bonus au-dela de 100k vs midpoint 150k
	cfg.LARGE_ATTACKER_SPEED_EXPONENT = 0.6
	cfg.LARGE_ATTACKER_COST_EXPONENT = 0.35
	cfg.LARGE_ATTACKER_SPEED_FLOOR = 0.35
	cfg.SPAWN_NUKE_IMMUNITY = 5
	cfg.PREPARATION_DURATION = 0
	cfg.MISSILE_SPEED = 14
	cfg.SAM_INTERCEPT_CHANCE = 1
	cfg.SAM_COOLDOWN = 90
	cfg.NUKE_ALLIANCE_BREAK_TILES = 100
	cfg.NUKE_STATS[1] = {
		radius = 12,
		outerRadius = 30,
		troopKill = 0.38,
		cost = 550,
		name = "Bombe atomique",
	}
	cfg.NUKE_STATS[2] = {
		radius = 80,
		outerRadius = 100,
		troopKill = 0.62,
		cost = 1400,
		name = "Bombe H",
	}
	cfg.NUKE_STATS[3].warheads = 8
	cfg.NUKE_STATS[3].warheadRadius = 6
	cfg.NUKE_STATS[3].warheadTroopKill = 0.14
	cfg.DOOMSDAY.WARN_SECONDS = 30
	cfg.DOOMSDAY.ROT_DEATH_SECONDS = 120
	cfg.FALLOUT_TICKS = 800
	cfg.FALLOUT_DEFENSE_MULT = 3.2
	cfg.SPAWN_RADIUS = 18
	cfg.DEPLOY_DURATION = 15
	-- Tribus PvE (TribeSpawner)
	cfg.TRIBE_COUNT = 6
	cfg.TRIBE_START_TROOPS = 4000
	-- Trains / commerce (TrainExecution feel)
	cfg.TRUCK_GOLD_BASE = cfg.TRAIN_GOLD_SELF
	cfg.TRUCK_GOLD_PER_TILE = 0.05
	cfg.TRAIN_STOP_BONUS = 0.12
	if cfg.CITY_LEVELS then
		cfg.CITY_LEVELS[1].popCapBonus = 250000
		cfg.CITY_LEVELS[1].goldBonus = 0
		cfg.CITY_LEVELS[2].popCapBonus = 500000
		cfg.CITY_LEVELS[2].goldBonus = 0
		cfg.CITY_LEVELS[3].popCapBonus = 750000
		cfg.CITY_LEVELS[3].goldBonus = 0
	end
end

local function terrainMag(terrain: number): number
	if terrain == Config.TERRAIN.MOUNTAIN or terrain == Config.TERRAIN.PEAK then
		return 2
	end
	if terrain == Config.TERRAIN.HILLS or terrain == Config.TERRAIN.HIGHLAND then
		return 1.5
	end
	return 1
end

local function frontPriority(state, index, attackerSlot): number
	local n = MapGen.neighbors(index, scratch)
	local owned = 0
	for i = 1, n do
		if buffer.readu8(state.owner, scratch[i]) == attackerSlot then
			owned += 1
		end
	end
	local mag = terrainMag(buffer.readu8(state.terrain, index))
	local noise = (index * 2654435761 + state.tick * 40503) % 8
	return (noise + 10) * (1 - owned * 0.5 + mag / 2) + state.tick
end

local function enqueueFront(state, atk, index)
	if atk.queued[index] then
		return
	end
	atk.queued[index] = true
	Heap.push(atk.frontier, index, frontPriority(state, index, atk.attacker))
end

function ChantierB.cancelOpposingFronts(state)
	local doomed: { boolean } = {}
	for i = 1, #state.attacks do
		if doomed[i] then
			continue
		end
		local a = state.attacks[i]
		for j = i + 1, #state.attacks do
			if doomed[j] then
				continue
			end
			local b = state.attacks[j]
			if a.attacker == b.target and b.attacker == a.target then
				local clash = math.min(a.troops, b.troops)
				a.troops -= clash
				b.troops -= clash
				if a.troops <= 0 then
					doomed[i] = true
				end
				if b.troops <= 0 then
					doomed[j] = true
				end
			end
		end
	end
	for i = #state.attacks, 1, -1 do
		if doomed[i] or state.attacks[i].troops <= 0 then
			local atk = state.attacks[i]
			local owner = state.players[atk.attacker]
			if owner and atk.troops > 0 then
				owner.troops += atk.troops
			end
			table.remove(state.attacks, i)
		end
	end
end

function ChantierB.stripTerritory(state, ps)
	local slot = ps.slot
	if ps.capitalTile then
		state:destroyBuilding(ps.capitalTile)
	end
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(state.owner, index) == slot then
			state:setOwner(index, NEUTRAL)
		end
	end
	ps.tiles = 0
	ps.capitalTile = nil
	ps.spawnCenter = nil
	ps.awaitingSpawn = true
	ps.border = {}
	ps.coast = {}
end

function ChantierB.placeDisk(state, slot, center)
	local cx, cy = MapGen.fromIndex(center)
	local r = Config.SPAWN_RADIUS
	for dy = -r, r do
		for dx = -r, r do
			if dx * dx + dy * dy <= r * r then
				local nx, ny = cx + dx, cy + dy
				if MapGen.inBounds(nx, ny) then
					local idx = MapGen.toIndex(nx, ny)
					if state:isLand(idx) and buffer.readu8(state.owner, idx) == NEUTRAL then
						state:setOwner(idx, slot)
					end
				end
			end
		end
	end
	state:placeBuilding(center, Config.BUILDING.CAPITAL, slot)
	local ps = state.players[slot]
	if ps then
		ps.capitalTile = center
		ps.spawnCenter = center
		ps.awaitingSpawn = false
		ps.spawnTick = state.tick
	end
end

function ChantierB.install(GameState, Nukes)
	if GameState.__chantierB then
		ChantierB.apply(Config)
		if Nukes and not GameState.__chantierFallout then
			ChantierB.installFallout(GameState, Nukes)
		end
		if not GameState.claimSpawn then
			ChantierB.installSpawn(GameState)
		end
		return
	end
	GameState.__chantierB = true
	ChantierB.apply(Config)

	function GameState.maxTroops(self, ps)
		local tiles = math.max(0, ps.tiles)
		local fromLand = 2 * (tiles ^ Config.MAX_TROOPS_TILE_EXPONENT * Config.MAX_TROOPS_TILE_SCALE + Config.MAX_TROOPS_LAND_BASE)
		local fromCities = ps.cityPopBonus or 0
		local maxT = fromLand + fromCities
		if ps.isBot then
			maxT = maxT / 3
		end
		return math.max(1, maxT)
	end

	local origStepEconomy = GameState.stepEconomy
	function GameState.stepEconomy(self)
		for _, ps in self.players do
			if ps.awaitingSpawn then
				continue
			end
			local doctrine = Doctrines.get(ps.doctrine)
			local era = Eras.accumulate(ps.era)
			local maxTroops = self:maxTroops(ps)
			if ps.troops < maxTroops then
				local toAdd = 10 + (ps.troops ^ 0.73) / 4
				toAdd *= (1 - ps.troops / maxTroops)
				if ps.isBot then
					toAdd *= 0.5
				end
				local humanGrowth = if ps.isBot then 1 else (Config.HUMAN_GROWTH_MULTIPLIER or 1.18)
				ps.troops = math.min(maxTroops, ps.troops + toAdd * doctrine.growth * era.growth * humanGrowth)
			end
			local flat = if ps.isBot then (Config.FLAT_GOLD_BOT or 0.6) else (Config.FLAT_GOLD_HUMAN or 1.2)
			local modeGold = if self.mode then self.mode.goldMultiplier else 1
			local humanGold = if ps.isBot then 1 else (Config.HUMAN_GOLD_MULTIPLIER or 1)
			ps.gold += flat * doctrine.goldRate * era.gold * modeGold * humanGold
		end
		local _ = origStepEconomy
	end

	local origNew = GameState.new
	function GameState.new(seed: number)
		local self = origNew(seed)
		self.doomWarnedAt = {}
		self.doomUnderSince = {}
		self.fallout = {}
		return self
	end

	function GameState.tileCost(self, index: number, attackerSlot: number, defender: any): number
		local attacker = self.players[attackerSlot]
		if not attacker then
			return 18
		end
		local loss = select(1, ChantierB.attackLogic(self, math.max(1, attacker.troops), attacker, defender, index))
		return math.max(1, loss)
	end

	local origStepAttacks = GameState.stepAttacks
	function GameState.stepAttacks(self)
		ChantierB.cancelOpposingFronts(self)
		local collapsing = {}
		for i = #self.attacks, 1, -1 do
			local atk = self.attacks[i]
			local attacker = self.players[atk.attacker]
			local defender = if atk.target ~= NEUTRAL then self.players[atk.target] else nil
			if not attacker then
				table.remove(self.attacks, i)
				continue
			end
			if atk.target ~= NEUTRAL and not defender then
				attacker.troops += math.max(0, atk.troops)
				table.remove(self.attacks, i)
				continue
			end
			if atk.retreatAt and self.tick >= atk.retreatAt then
				-- OF malusForRetreat : 25 % contre joueur, 0 % contre neutre.
				local loss = if atk.target == NEUTRAL
					then (Config.RETREAT_LOSS_NEUTRAL or 0)
					else (Config.RETREAT_LOSS or 0.25)
				attacker.troops += math.max(0, atk.troops) * (1 - loss)
				table.remove(self.attacks, i)
				continue
			end
			local speedFactor = select(1, self:sizeAttackFactors(attacker))
			local contact = math.max(1, atk.frontier.size)
			local numTiles = ChantierB.attackTilesPerTick(atk.troops, defender, contact) * speedFactor
			local guard = 0
			while numTiles > 0 and guard < ChantierB.CAPTURE_GUARD do
				guard += 1
				local index = Heap.pop(atk.frontier)
				if not index then
					break
				end
				atk.queued[index] = nil
				if buffer.readu8(self.owner, index) ~= atk.target then
					continue
				end
				local attLoss, defLoss, used = ChantierB.attackLogic(self, atk.troops, attacker, defender, index)
				if attLoss > atk.troops then
					atk.troops = 0
					break
				end
				atk.troops -= attLoss
				numTiles -= used
				if defender then
					defender.troops = math.max(0, defender.troops - defLoss)
					defender.grudges[atk.attacker] = self.tick + Config.GRUDGE_DURATION
				end
				self:setOwner(index, atk.attacker)
				ChantierB.tryAnnex(self, atk.attacker, atk.target, index)
				local n = MapGen.neighbors(index, scratch)
				for k = 1, n do
					local nb = scratch[k]
					if buffer.readu8(self.owner, nb) == atk.target and self:isLand(nb) then
						enqueueFront(self, atk, nb)
					end
				end
			end
			if defender and defender.tiles > 0 and defender.tiles < self:collapseThreshold() then
				table.insert(collapsing, { victim = atk.target, captor = atk.attacker })
			end
			if atk.troops <= 0 or Heap.isEmpty(atk.frontier) then
				attacker.troops += math.max(0, atk.troops)
				table.remove(self.attacks, i)
			end
		end
		for _, entry in collapsing do
			local victim = self.players[entry.victim]
			if victim and victim.tiles > 0 and victim.tiles < self:collapseThreshold() then
				if not victim.isBot then
					self:notify(`\u{1F3F3} {victim.name} s'effondre : son territoire est partage.`, "alert")
				end
				self:collapseFaction(entry.victim, entry.captor)
			end
		end
		local _ = origStepAttacks
	end

	local origStep = GameState.step
	function GameState.step(self)
		self:stepDoomsday()
		if self.fallout then
			for index, untilTick in self.fallout do
				if untilTick <= self.tick then
					self.fallout[index] = nil
				end
			end
		end
		return origStep(self)
	end

	function GameState.stepDoomsday(self)
		local mode = self.mode
		local duration = if mode then mode.duration else Config.MATCH_DURATION
		local elapsed = self.tick * Config.TICK_DT
		local required = Doomsday.requiredTiles(duration, self.landCount, elapsed)
		local wave = Doomsday.waveState(duration, elapsed)
		if not wave.armed or required <= 0 then
			return
		end
		self.doomWarnedAt = self.doomWarnedAt or {}
		self.doomUnderSince = self.doomUnderSince or {}
		local cfg = Config.DOOMSDAY
		local leaderSlot, leaderTiles = nil, 0
		for slot, ps in self.players do
			if ps.tiles > leaderTiles then
				leaderTiles = ps.tiles
				leaderSlot = slot
			end
		end
		for slot, ps in self.players do
			if slot == leaderSlot or ps.tiles >= required then
				self.doomWarnedAt[slot] = nil
				self.doomUnderSince[slot] = nil
				continue
			end
			if not self.doomWarnedAt[slot] then
				self.doomWarnedAt[slot] = elapsed
				if not ps.isBot then
					self:notify("Le cadran te marque. Tiens ta part ou le territoire pourrira.", "alert", slot)
				end
			end
			local pastWarn = elapsed - self.doomWarnedAt[slot]
			if pastWarn < cfg.WARN_SECONDS then
				continue
			end
			local maxTroops = self:maxTroops(ps)
			local floor = Doomsday.troopFloor(maxTroops, pastWarn - cfg.WARN_SECONDS, cfg)
			local drain = Doomsday.drain(maxTroops, pastWarn - cfg.WARN_SECONDS, cfg) * Config.TICK_DT
			if ps.troops > floor then
				ps.troops = math.max(floor, ps.troops - drain)
			end
			self.doomUnderSince[slot] = (self.doomUnderSince[slot] or 0) + Config.TICK_DT
			local under = self.doomUnderSince[slot]
			if under < cfg.WARN_SECONDS then
				continue
			end
			local quota = Doomsday.rotQuota(ps.tiles, under - cfg.WARN_SECONDS, cfg)
			if quota <= 0 or ps.tiles <= 0 then
				continue
			end
			local ripped, toStrip = 0, {}
			for index = 0, Config.TILE_COUNT - 1 do
				if buffer.readu8(self.owner, index) == slot then
					table.insert(toStrip, index)
					if #toStrip >= quota * 4 then
						break
					end
				end
			end
			for _, index in toStrip do
				if ripped >= quota then
					break
				end
				if buffer.readu8(self.owner, index) == slot then
					if self.buildings[index] then
						self:destroyBuilding(index)
					end
					self:setOwner(index, NEUTRAL)
					ripped += 1
				end
			end
		end
	end

	ChantierB.installSpawn(GameState)
	if Nukes then
		ChantierB.installFallout(GameState, Nukes)
	end
end

function ChantierB.installSpawn(GameState)
	if GameState.__chantierSpawn then
		return
	end
	GameState.__chantierSpawn = true
	local origAdd = GameState.addPlayer
	function GameState.addPlayer(self, player, name, rng, betrayals)
		local ps = origAdd(self, player, name, rng, betrayals)
		if ps and typeof(player) == "Instance" then
			ChantierB.stripTerritory(self, ps)
		end
		return ps
	end
	function GameState.claimSpawn(self, slot: number, index: number): (boolean, string?)
		local ps = self.players[slot]
		if not ps then
			return false, "Faction inconnue."
		end
		if not ps.awaitingSpawn then
			return false, "Tu as deja un territoire."
		end
		if index < 0 or index >= Config.TILE_COUNT then
			return false, "Hors carte."
		end
		if not self:isLand(index) then
			return false, "Choisis une terre."
		end
		local best = nil
		if buffer.readu8(self.owner, index) == NEUTRAL then
			-- Terre libre collee a une capitale : refus, pas de snap r=6 (V16b).
			if not self.isSpawnIsolated or self:isSpawnIsolated(index) then
				best = index
			end
		else
			local ox, oy = MapGen.fromIndex(index)
			for r = 1, 6 do
				for dy = -r, r do
					for dx = -r, r do
						local nx, ny = ox + dx, oy + dy
						if MapGen.inBounds(nx, ny) then
							local i = MapGen.toIndex(nx, ny)
							if
								self:isLand(i)
								and buffer.readu8(self.owner, i) == NEUTRAL
								and (not self.isSpawnIsolated or self:isSpawnIsolated(i))
							then
								best = i
								break
							end
						end
					end
					if best then
						break
					end
				end
				if best then
					break
				end
			end
		end
		if not best then
			return false, "Aucune terre libre ici."
		end
		ps.tiles = 0
		ChantierB.placeDisk(self, slot, best)
		self:notify("Capitale posee. Colonise avant l'ouverture des frontieres.", "good", slot)
		return true, "Territoire revendique."
	end
	function GameState.autoPlacePending(self, rng)
		for slot, ps in self.players do
			if ps.awaitingSpawn then
				local center = self:findSpawn(rng)
				if center then
					ps.tiles = 0
					ChantierB.placeDisk(self, slot, center)
				end
			end
		end
	end
end

function ChantierB.installFallout(GameState, Nukes)
	if GameState.__chantierFallout or not Nukes or not Nukes.detonate then
		return
	end
	GameState.__chantierFallout = true
	local orig = Nukes.detonate
	function Nukes.detonate(state, missile, rng)
		orig(state, missile, rng)
		state.fallout = state.fallout or {}
		local stats = Config.NUKE_STATS[missile.kind]
		local radius = missile.radius or (if stats then stats.radius else 8)
		if radius <= 0 then
			radius = 5
		end
		local cx, cy = math.floor(missile.tx), math.floor(missile.ty)
		local untilTick = state.tick + Config.FALLOUT_TICKS
		for dy = -radius, radius do
			for dx = -radius, radius do
				if dx * dx + dy * dy <= radius * radius then
					local nx, ny = cx + dx, cy + dy
					if MapGen.inBounds(nx, ny) then
						local index = MapGen.toIndex(nx, ny)
						if state:isLand(index) then
							state.fallout[index] = untilTick
						end
					end
				end
			end
		end
	end
end

return ChantierB
