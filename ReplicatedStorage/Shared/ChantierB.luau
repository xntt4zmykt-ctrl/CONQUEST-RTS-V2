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

local NEUTRAL = Config.NEUTRAL_SLOT
local OCEAN = Config.TERRAIN.OCEAN
local scratch = table.create(4, 0)
local annexScratch = table.create(4, 0)
-- tryAnnex : pools module-level (ISSUE-N39). Meme pattern que findSeaPath N37.
-- Cap poche 280 inchange ; oceán = abort (enclave terrestre only).
local annexVisitBuf = buffer.create(Config.TILE_COUNT)
local annexQueue: { number } = table.create(280)
local annexPocket: { number } = table.create(280)

-- N86 : cancelOpposingFronts / collapsing recycle (recette N79 + table.clear
-- hash N80). Hash sparse — ne pas iterer #doomedBuf. Truncate collapsing
-- leftover AVANT traitement (recette N82). Non reentrant — stepAttacks
-- unique par tick. Distinct de elimBuf (slots) et de retreatAttack (couple).
type CollapseRec = { victim: number, captor: number }
local doomedBuf: { [number]: boolean } = {}
local collapsingBuf: { CollapseRec } = table.create(8)
local collapseRecPool: { CollapseRec } = table.create(8)
ChantierB.doomedBuf = doomedBuf
-- N93 : liste temporaire du rot cadran. Array + truncate (recette
-- visual V43 / N82 elimBuf). Distinct de N9 (scan O(carte) encore)
-- et de N86 (collapsingBuf combat). Truncate leftover AVANT
-- l'arrachage ; reset n=0 / truncate a 0 APRES pour qu'un second
-- slot du meme tick n'arrache pas les tuiles du premier. Pas reentrant.
-- stepDoomsday unique par tick, mais boucle les slots.
local stripBuf: { number } = table.create(64)
ChantierB.stripBuf = stripBuf

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
		-- Index par camp (ISSUE-N42) : O(bunkers_défenseur), pas O(buildings).
		-- Le buffer `defense` n'est plus ecrit (N45 Option A) ni lu ici.
		local cx, cy = MapGen.fromIndex(tile)
		local r = Config.DEFENSE_RADIUS or 30
		local r2 = r * r
		local bunkers = state.bunkersBySlot and state.bunkersBySlot[defender.slot]
		if bunkers then
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
		local traitorMod = if defender.traitorUntil and state.tick < defender.traitorUntil then 0.8 else 1
		local largeDef = state:sizeDefenseFactor(defender)
		local current = ratio * mag * 0.8 * largeDef * traitorMod
		local alt = 1.3 * defenderTroopLoss * (mag / 100) * traitorMod
		local attackerTroopLoss = 0.6 * current + 0.4 * alt
		local tilesPerTickUsed = within(defender.troops / (5 * math.max(1, attackTroops)), 0.2, 1.5) * speed * largeDef
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
	buffer.fill(annexVisitBuf, 0, 0)
	table.clear(annexQueue)
	table.clear(annexPocket)
	local visited = annexVisitBuf
	local queue = annexQueue
	local pocket = annexPocket

	-- Le combat vivant appelle tryAnnex APRES setOwner : `seed` appartient
	-- deja a l'attaquant. L'ancienne file `{ seed }` marquait visited puis
	-- `continue` (owner ~= defender) sans jamais etendre les voisins — BFS
	-- mort, aucune enclave annexee. On part des voisins defenseur du seed
	-- (seed = coupe). Si seed est encore defenseur (appel avant setOwner),
	-- on l'enfile comme avant.
	buffer.writeu8(visited, seed, 1)
	if buffer.readu8(state.owner, seed) == defenderSlot then
		table.insert(queue, seed)
	else
		local n0 = MapGen.neighbors(seed, annexScratch)
		for i = 1, n0 do
			local nb = annexScratch[i]
			if buffer.readu8(state.owner, nb) == defenderSlot and buffer.readu8(visited, nb) == 0 then
				buffer.writeu8(visited, nb, 1)
				table.insert(queue, nb)
			end
		end
	end

	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		if buffer.readu8(state.owner, cur) ~= defenderSlot then
			continue
		end
		table.insert(pocket, cur)
		if #pocket > 280 then
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
			if owner == defenderSlot and buffer.readu8(visited, nb) == 0 then
				buffer.writeu8(visited, nb, 1)
				table.insert(queue, nb)
			end
		end
	end
	if #pocket == 0 then
		return
	end
	for _, index in pocket do
		state:setOwner(index, attackerSlot)
	end
end

function ChantierB.apply(cfg)
	cfg.START_TROOPS = 8000
	cfg.HUMAN_START_TROOPS = 12000
	cfg.BASE_MAX_TROOPS = 0
	cfg.MAX_TROOPS_TILE_SCALE = 200
	cfg.MAX_TROOPS_TILE_EXPONENT = 0.6
	cfg.MAX_TROOPS_LAND_BASE = 10000
	cfg.CITY_TROOP_INCREASE = 50000
	cfg.GROWTH_RATE = 0
	cfg.MIN_GROWTH = 0
	cfg.TILE_BASE_COST = 18
	cfg.NEUTRAL_COST_MULT = 0.88
	cfg.DEFENSE_DENSITY_K = 1.15
	cfg.MAX_TILES_PER_TICK = 56
	cfg.FRONT_TILES_PER_CONTACT = 2.4
	cfg.DEFENSE_RADIUS = 30
	cfg.DEFENSE_STRENGTH = 200
	cfg.DEFENSE_POST_BONUS = 5
	cfg.DEFENSE_POST_SPEED_BONUS = 3
	cfg.DEFENSE_COST_DIVISOR = 42
	cfg.WARSHIP_PATROL_RANGE = 40
	cfg.WARSHIP_TARGET_RANGE = 65
	cfg.WARSHIP_SHELL_RATE = 20
	cfg.WARSHIP_MAX_HEALTH = 100
	cfg.WARSHIP_SHELL_DAMAGE = 22
	cfg.WARSHIP_TRANSPORT_DAMAGE = 0.28
	cfg.WARSHIP_TRADE_SINK = true
	cfg.WARSHIP_RESPAWN_TICKS = 300
	cfg.CARRIER_PATROL_RADIUS = 40
	cfg.CARRIER_INTERCEPT_RANGE = 65
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
	cfg.SAM_RANGE = 70
	cfg.SAM_INTERCEPT_CHANCE = 1
	cfg.SAM_COOLDOWN = 75
	cfg.NUKE_STATS[1] = { radius = 12, troopKill = 0.38, cost = 550, name = "Bombe atomique" }
	cfg.NUKE_STATS[2] = { radius = 32, troopKill = 0.62, cost = 1400, name = "Bombe H" }
	cfg.NUKE_STATS[3].warheads = 8
	cfg.NUKE_STATS[3].warheadRadius = 6
	cfg.NUKE_STATS[3].warheadTroopKill = 0.14
	cfg.DOOMSDAY.WARN_SECONDS = 30
	cfg.DOOMSDAY.ROT_DEATH_SECONDS = 120
	cfg.FALLOUT_TICKS = 800
	cfg.FALLOUT_DEFENSE_MULT = 3.2
	cfg.DEPLOY_DURATION = 15
	-- Tribus PvE (TribeSpawner)
	cfg.TRIBE_COUNT = 6
	cfg.TRIBE_START_TROOPS = 4000
	-- Trains / commerce (TrainExecution feel)
	cfg.TRUCK_GOLD_BASE = 14
	cfg.TRUCK_GOLD_PER_TILE = 1.5
	cfg.TRAIN_STOP_BONUS = 0.12
	if cfg.CITY_LEVELS then
		cfg.CITY_LEVELS[1].popCapBonus = 50000
		cfg.CITY_LEVELS[2].popCapBonus = 100000
		cfg.CITY_LEVELS[3].popCapBonus = 150000
	end
end

local function frontPriority(state, index, attackerSlot): number
	local n = MapGen.neighbors(index, scratch)
	local owned = 0
	for i = 1, n do
		if buffer.readu8(state.owner, scratch[i]) == attackerSlot then
			owned += 1
		end
	end
	local terrain = buffer.readu8(state.terrain, index)
	local roughness = Config.TERRAIN_COST[terrain] or 1
	local noise = (index * 2654435761 + state.tick * 40503) % 8
	return (noise + 10) * (1 - owned * 0.5 + roughness / 2) + state.tick
end

local function enqueueFront(state, atk, index)
	if atk.queued[index] then
		return
	end
	atk.queued[index] = true
	Heap.push(atk.frontier, index, frontPriority(state, index, atk.attacker))
end

function ChantierB.cancelOpposingFronts(state)
	table.clear(doomedBuf)
	for i = 1, #state.attacks do
		if doomedBuf[i] then
			continue
		end
		local a = state.attacks[i]
		for j = i + 1, #state.attacks do
			if doomedBuf[j] then
				continue
			end
			local b = state.attacks[j]
			if a.attacker == b.target and b.attacker == a.target then
				local clash = math.min(a.troops, b.troops)
				a.troops -= clash
				b.troops -= clash
				if a.troops <= 0 then
					doomedBuf[i] = true
				end
				if b.troops <= 0 then
					doomedBuf[j] = true
				end
			end
		end
	end
	for i = #state.attacks, 1, -1 do
		if doomedBuf[i] or state.attacks[i].troops <= 0 then
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
	-- setOwner a deja ramene tiles a 0 ; un 1 fictif faussait colonisedRatio
	-- et les invariants pendant la fenetre de spawn au clic.
	ps.tiles = 0
	ps.capitalTile = nil
	ps.awaitingSpawn = true
	-- N94 : table.clear in-place. Un `= {}` neuf abandonnait les hashes
	-- deja vides par setOwner. Un buf module partage serait mute par
	-- setOwner du premier claimSpawn voisin.
	table.clear(ps.border)
	table.clear(ps.coast)
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
			local territorial = ps.tiles ^ Config.GOLD_TILE_EXPONENT * Config.GOLD_TILE_SCALE
			local income = territorial + ps.cityGoldBonus + ps.portLevels * Config.GOLD_PER_PORT + ps.capitalCount * Config.GOLD_PER_CAPITAL
			local modeGold = if self.mode then self.mode.goldMultiplier else 1
			local humanGold = if ps.isBot then 1 else (Config.HUMAN_GOLD_MULTIPLIER or 1)
			ps.gold += income * doctrine.goldRate * era.gold * modeGold * humanGold
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
		local collapseN = 0
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
			-- NOTE: Config.MAX_TILES_PER_TICK n'est PAS lu ici (valeur apply=56
			-- inutilisee). Debit vivant = attackTilesPerTick * speedFactor, borne
			-- par guard < 80. Voir ISSUE-N1 / ISSUE-N11.
			local speedFactor = select(1, self:sizeAttackFactors(attacker))
			local contact = math.max(1, atk.frontier.size)
			local numTiles = ChantierB.attackTilesPerTick(atk.troops, defender, contact) * speedFactor
			local guard = 0
			while numTiles > 0 and guard < 80 do
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
				collapseN += 1
				local rec = collapseRecPool[collapseN]
				if rec == nil then
					rec = { victim = 0, captor = 0 }
					collapseRecPool[collapseN] = rec
				end
				rec.victim = atk.target
				rec.captor = atk.attacker
				collapsingBuf[collapseN] = rec
			end
			if atk.troops <= 0 or Heap.isEmpty(atk.frontier) then
				attacker.troops += math.max(0, atk.troops)
				table.remove(self.attacks, i)
			end
		end
		for i = #collapsingBuf, collapseN + 1, -1 do
			collapsingBuf[i] = nil
		end
		for i = 1, collapseN do
			local entry = collapsingBuf[i]
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
			-- Pas encore spawn, ou deja elimine : le cadran ne saigne pas une armee fantome.
			if ps.awaitingSpawn or ps.tiles == 0 then
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
			local ripped, n = 0, 0
			for index = 0, Config.TILE_COUNT - 1 do
				if buffer.readu8(self.owner, index) == slot then
					n += 1
					stripBuf[n] = index
					if n >= quota * 4 then
						break
					end
				end
			end
			for i = #stripBuf, n + 1, -1 do
				stripBuf[i] = nil
			end
			for i = 1, n do
				local index = stripBuf[i]
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
			for i = n, 1, -1 do
				stripBuf[i] = nil
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
		-- N52 splash/fallout + N54 bus + N55 isolation (carre SPAWN_RADIUS+3
		-- tout NEUTRAL, meme recette que findSpawn). Chercher plus loin dans
		-- r=6, ne jamais poser un disque partiel colle a un empire.
		local function isClaimable(i: number): boolean
			return self:isLand(i)
				and buffer.readu8(self.owner, i) == NEUTRAL
				and self:isSpawnSafe(i)
				and self:isSpawnIsolated(i)
		end
		local best: number? = if isClaimable(index) then index else nil
		if not best then
			local ox, oy = MapGen.fromIndex(index)
			for r = 1, 6 do
				for dy = -r, r do
					for dx = -r, r do
						local nx, ny = ox + dx, oy + dy
						if MapGen.inBounds(nx, ny) then
							local i = MapGen.toIndex(nx, ny)
							if isClaimable(i) then
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
	function Nukes.detonate(state, missile)
		orig(state, missile)
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
