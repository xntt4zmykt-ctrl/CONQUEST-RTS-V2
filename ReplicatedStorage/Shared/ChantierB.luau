--!strict
--[[
	Chantier B : attaque + socle de troupes + defense + nucleaire + doomsday.

	S'installe tout seul depuis GameState (voir install). Mutate Config en place
	pour que Nukes / Bots / tests lisent les memes chiffres.
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
local scratch = table.create(4, 0)

function ChantierB.apply(cfg)
	cfg.START_TROOPS = 2800
	cfg.BASE_MAX_TROOPS = 4500
	cfg.HUMAN_START_TROOPS = 4800
	cfg.GROWTH_RATE = 0.010

	cfg.TILE_BASE_COST = 18
	cfg.NEUTRAL_COST_MULT = 0.88
	cfg.DEFENSE_DENSITY_K = 1.15
	cfg.MAX_TILES_PER_TICK = 56
	cfg.FRONT_TILES_PER_CONTACT = 2.4

	cfg.DEFENSE_RADIUS = 8
	cfg.DEFENSE_STRENGTH = 200
	cfg.DEFENSE_COST_DIVISOR = 42

	cfg.RETREAT_LOSS = 0

	cfg.MISSILE_SPEED = 14
	cfg.SAM_RANGE = 70
	cfg.SAM_INTERCEPT_CHANCE = 1
	cfg.NUKE_STATS[1] = { radius = 12, troopKill = 0.38, cost = 550, name = "Bombe atomique" }
	cfg.NUKE_STATS[2] = { radius = 32, troopKill = 0.62, cost = 1400, name = "Bombe H" }
	cfg.NUKE_STATS[3].warheads = 8
	cfg.NUKE_STATS[3].warheadRadius = 6
	cfg.NUKE_STATS[3].warheadTroopKill = 0.14

	cfg.DOOMSDAY.WARN_SECONDS = 30
	cfg.DOOMSDAY.ROT_DEATH_SECONDS = 120
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

function ChantierB.install(GameState)
	ChantierB.apply(Config)

	local origNew = GameState.new
	function GameState.new(seed: number)
		local self = origNew(seed)
		self.doomWarnedAt = {}
		self.doomUnderSince = {}
		return self
	end

	function GameState.tileCost(self, index: number, attackerSlot: number, defender: any): number
		local terrain = buffer.readu8(self.terrain, index)
		local cost = Config.TILE_BASE_COST * (Config.TERRAIN_COST[terrain] or 1)

		if defender then
			local density = defender.troops / math.max(1, defender.tiles)
			cost *= 1 + density * Config.DEFENSE_DENSITY_K
			cost *= Doctrines.get(defender.doctrine).defense
			cost *= Eras.accumulate(defender.era).defense
			cost *= self:sizeDefenseFactor(defender)
		else
			cost *= Config.NEUTRAL_COST_MULT
		end

		local aura = buffer.readu8(self.defense, index)
		cost *= 1 + aura / Config.DEFENSE_COST_DIVISOR
		cost /= self:doctrineOf(attackerSlot).attack

		local attacker = self.players[attackerSlot]
		if attacker then
			local _, costFactor = self:sizeAttackFactors(attacker)
			cost *= costFactor
		end
		return cost
	end

	local origStepAttacks = GameState.stepAttacks
	function GameState.stepAttacks(self)
		ChantierB.cancelOpposingFronts(self)

		local collapsing = {}

		for i = #self.attacks, 1, -1 do
			local atk = self.attacks[i]
			local attacker = self.players[atk.attacker]
			local defender = if atk.target ~= NEUTRAL then self.players[atk.target] else nil

			if not attacker or (atk.target ~= NEUTRAL and not defender) then
				table.remove(self.attacks, i)
				continue
			end

			if atk.retreatAt and self.tick >= atk.retreatAt then
				local returned = math.max(0, atk.troops) * (1 - (Config.RETREAT_LOSS or 0))
				attacker.troops += returned
				table.remove(self.attacks, i)
				continue
			end

			local speedFactor = select(1, self:sizeAttackFactors(attacker))
			local budget = atk.troops * Config.ATTACK_SPEND_RATE * speedFactor
			local frontWidth = math.max(1, atk.frontier.size)
			local tileLimit = math.clamp(
				math.floor(frontWidth * Config.FRONT_TILES_PER_CONTACT * speedFactor),
				1,
				Config.MAX_TILES_PER_TICK
			)
			local captured = 0
			local spent = 0

			while spent < budget and captured < tileLimit do
				local index = Heap.pop(atk.frontier)
				if not index then
					break
				end
				atk.queued[index] = nil

				if buffer.readu8(self.owner, index) ~= atk.target then
					continue
				end

				local cost = self:tileCost(index, atk.attacker, defender)
				if cost > atk.troops then
					atk.troops = 0
					break
				end

				atk.troops -= cost
				spent += cost
				captured += 1

				if defender then
					defender.troops = math.max(0, defender.troops - cost * Config.DEFENDER_LOSS_RATIO)
					defender.grudges[atk.attacker] = self.tick + Config.GRUDGE_DURATION
				end

				self:setOwner(index, atk.attacker)

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
		local leaderSlot = nil
		local leaderTiles = 0
		for slot, ps in self.players do
			if ps.tiles > leaderTiles then
				leaderTiles = ps.tiles
				leaderSlot = slot
			end
		end

		for slot, ps in self.players do
			if slot == leaderSlot then
				self.doomWarnedAt[slot] = nil
				self.doomUnderSince[slot] = nil
				continue
			end
			if ps.tiles >= required then
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

			local ripped = 0
			local toStrip: { number } = {}
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
end

return ChantierB
