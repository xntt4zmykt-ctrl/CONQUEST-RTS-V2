--!strict
--[[
	Avancement technologique + hooks chantier D/F/G/H + BoatFront + Tribes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BuildingDefs = require(ReplicatedStorage.Shared.BuildingDefs)
local Eras = require(ReplicatedStorage.Shared.Eras)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameState = require(script.Parent.GameState)
local Nukes = require(script.Parent.Nukes)
local Navy = require(script.Parent.Navy)
local ChantierB = require(ReplicatedStorage.Shared.ChantierB)
local AimFront = require(ReplicatedStorage.Shared.AimFront)
local BoatFront = require(ReplicatedStorage.Shared.BoatFront)
local Tribes = require(script.Parent.Tribes)
ChantierB.install(GameState, Nukes)
BoatFront.install(GameState)

-- Tribus PvE (OF TribeExecution) branchées sur Bots
do
	local Bots = require(script.Parent.Bots)
	local origSpawn = Bots.spawnAll
	function Bots.spawnAll(state, rng, count)
		origSpawn(state, rng, count)
		Tribes.spawnAll(state, rng, Config.TRIBE_COUNT or 6)
	end
	local origStep = Bots.step
	function Bots.step(state, rng)
		origStep(state, rng)
		Tribes.step(state, rng)
	end
end

Config.MAX_BOATS_PER_PLAYER = 3
Config.BOAT_TROOP_RATIO = 0.2
Config.BOAT_RETREAT_LOSS = 0.25

do
	local origNew = GameState.new
	function GameState.new(seed: number)
		local self = origNew(seed)
		GameState.active = self
		return self
	end

	local origLaunch = GameState.launchAttack
	function GameState.launchAttack(self, attackerSlot, targetSlot)
		local ps = self.players[attackerSlot]
		if ps and ps.justClaimed then
			ps.justClaimed = false
			return true, nil
		end

		local already = false
		for _, atk in self.attacks do
			if atk.attacker == attackerSlot and atk.target == targetSlot and atk.sourceTile == nil then
				already = true
				break
			end
		end

		local aim = if ps then ps.aimTile else nil
		if ps then
			ps.aimTile = nil
		end

		local ok, message = origLaunch(self, attackerSlot, targetSlot)
		if ok and typeof(aim) == "number" and not already then
			for _, atk in self.attacks do
				if atk.attacker == attackerSlot and atk.target == targetSlot and atk.sourceTile == nil then
					AimFront.focus(self, atk, math.floor(aim))
					break
				end
			end
		end
		return ok, message
	end

	local origRetreat = GameState.retreatAttack
	function GameState.retreatAttack(self, attackerSlot, targetSlot)
		local ok, message = origRetreat(self, attackerSlot, targetSlot)
		local n = Navy.retreatBoats(self, attackerSlot, targetSlot)
		if n > 0 then
			return true, `Retraite : front terrestre et {n} transport(s).`
		end
		return ok, message
	end

	Remotes.get("AttackOrder").OnServerEvent:Connect(function(player, index)
		local state = GameState.active
		if not state or typeof(index) ~= "number" then
			return
		end
		local slot = nil
		for s, ps in state.players do
			if ps.player == player then
				slot = s
				break
			end
		end
		if not slot then
			return
		end
		local ps = state.players[slot]
		if not ps then
			return
		end
		ps.aimTile = math.floor(index)
		if ps.awaitingSpawn then
			local ok = state:claimSpawn(slot, math.floor(index))
			if ok then
				ps.justClaimed = true
			end
		end
	end)

	task.defer(function()
		local Bots = require(script.Parent.Bots)
		local origSpawnAll = Bots.spawnAll
		function Bots.spawnAll(state, rng, n)
			state._pendingBots = { rng = rng, n = n }
		end

		local origStep = GameState.step
		function GameState.step(self)
			local deployTicks = math.floor((Config.DEPLOY_DURATION or 15) / Config.TICK_DT)
			if self._pendingBots and self.tick >= deployTicks then
				local pending = self._pendingBots
				self._pendingBots = nil
				if self.autoPlacePending then
					self:autoPlacePending(pending.rng)
				end
				origSpawnAll(self, pending.rng, pending.n)
			end
			return origStep(self)
		end
	end)
end

type GameState = GameState.GameState

local Research = {}

function Research.eraCost(state: GameState, slot: number): number
	local ps = state.players[slot]
	if not ps or ps.era >= Eras.MAX_ID then
		return 0
	end

	local labs = ps.buildingCounts[Config.BUILDING.LAB] or 0
	local discount = math.min(labs * Config.LAB_ERA_DISCOUNT, Config.LAB_DISCOUNT_CAP)
	local modeMultiplier = if state.mode then state.mode.eraCostMultiplier else 1
	return math.floor(Eras.get(ps.era + 1).cost * (1 - discount) * modeMultiplier)
end

function Research.canAdvance(state: GameState, slot: number): (boolean, string?)
	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	if ps.era >= Eras.MAX_ID then
		return false, "Tu as atteint la derniere ere."
	end

	local next = Eras.get(ps.era + 1)

	if ps.tiles < next.requiredTiles then
		return false, `Il te faut {next.requiredTiles} territoires ({ps.tiles} actuellement).`
	end

	for kind, count in next.requiredBuildings do
		local owned = ps.buildingCounts[kind] or 0
		if owned < count then
			local def = BuildingDefs.get(kind)
			local name = if def then def.name else "batiment"
			return false, `Il te faut {count} x {name} ({owned} actuellement).`
		end
	end

	local cost = Research.eraCost(state, slot)
	if ps.gold < cost then
		return false, `Il te faut {cost} d'or ({math.floor(ps.gold)} actuellement).`
	end

	return true, nil
end

function Research.advance(state: GameState, slot: number): (boolean, string?)
	local ok, reason = Research.canAdvance(state, slot)
	if not ok then
		return false, reason
	end

	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	local next = Eras.get(ps.era + 1)
	ps.gold -= Research.eraCost(state, slot)
	ps.era += 1

	if ps.era >= 4 then
		state:notify(`{next.symbol} {ps.name} entre dans l'ere {next.name} !`, "alert")
	else
		state:notify(`{next.symbol} Ere {next.name} atteinte.`, "good", slot)
	end
	state:sound("eraAdvance", slot)

	return true, `Ere {next.name} atteinte.`
end

function Research.goldReserveFor(state: GameState, slot: number): number
	local ps = state.players[slot]
	if not ps or ps.era >= Eras.MAX_ID then
		return 0
	end

	local next = Eras.get(ps.era + 1)

	if ps.tiles < next.requiredTiles then
		return 0
	end
	for kind, count in next.requiredBuildings do
		if (ps.buildingCounts[kind] or 0) < count then
			return 0
		end
	end

	return Research.eraCost(state, slot)
end

function Research.progress(state: GameState, slot: number): number
	local ps = state.players[slot]
	if not ps or ps.era >= Eras.MAX_ID then
		return 1
	end

	local next = Eras.get(ps.era + 1)
	local cost = Research.eraCost(state, slot)
	local ratios = {
		if cost > 0 then ps.gold / cost else 1,
		if next.requiredTiles > 0 then ps.tiles / next.requiredTiles else 1,
	}

	for kind, count in next.requiredBuildings do
		table.insert(ratios, (ps.buildingCounts[kind] or 0) / count)
	end

	local lowest = 1
	for _, ratio in ratios do
		lowest = math.min(lowest, ratio)
	end
	return math.clamp(lowest, 0, 1)
end

return Research
