--!strict
--[[
	Installe les extensions de simulation (combat, spawn, tribus, fronts).

	Separe de Research : ce module a des effets de bord volontaires au chargement
	de la partie, alors que Research doit rester une API pure d'avancement d'ere
	(sinon le banc headless qui charge Bots -> Research tire Remotes et casse).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ChantierB = require(ReplicatedStorage.Shared.ChantierB)
local AimFront = require(ReplicatedStorage.Shared.AimFront)
local BoatFront = require(ReplicatedStorage.Shared.BoatFront)
local GameState = require(script.Parent.GameState)
local Nukes = require(script.Parent.Nukes)
local Navy = require(script.Parent.Navy)
local Tribes = require(script.Parent.Tribes)
local Bots = require(script.Parent.Bots)

local SystemsBootstrap = {}

local installed = false
local deferredSpawnAll: ((any, Random, number?) -> ())? = nil

function SystemsBootstrap.flushPendingBots(state: any)
	if not state._pendingBots or not deferredSpawnAll then
		return
	end
	local pending = state._pendingBots
	state._pendingBots = nil
	if state.autoPlacePending then
		state:autoPlacePending(pending.rng)
	end
	deferredSpawnAll(state, pending.rng, pending.n)
end

function SystemsBootstrap.install()
	if installed then
		return
	end
	installed = true

	ChantierB.install(GameState, Nukes)
	BoatFront.install(GameState)

	do
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

	Config.MAX_BOATS_PER_PLAYER = Config.MAX_BOATS_PER_PLAYER or 3
	Config.BOAT_TROOP_RATIO = Config.BOAT_TROOP_RATIO or 0.2
	Config.BOAT_RETREAT_LOSS = Config.BOAT_RETREAT_LOSS or 0.25

	do
		local origNew = GameState.new
		function GameState.new(seed: number)
			local self = origNew(seed)
			GameState.active = self
			return self
		end

		local origLaunch = GameState.launchAttack
		function GameState.launchAttack(self, attackerSlot, targetSlot)
			-- Le clic de spawn est deja distingue dans IntentValidator
			-- (awaitingSpawn -> claimSpawn). Ne pas avaler l'offensive suivante.
			local ps = self.players[attackerSlot]

			-- Un front terre existe deja (vise ou non) : on renforce, on ne
			-- recree pas le tas. Les tetes de pont restent a part.
			local already = false
			for _, atk in self.attacks do
				if atk.attacker == attackerSlot and atk.target == targetSlot and not atk.isBeachhead then
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
					if atk.attacker == attackerSlot and atk.target == targetSlot and not atk.isBeachhead then
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

		local tribesSpawnAll = Bots.spawnAll
		deferredSpawnAll = tribesSpawnAll
		function Bots.spawnAll(state, rng, n)
			state._pendingBots = { rng = rng, n = n }
		end

		local origStep = GameState.step
		function GameState.step(self)
			local deployTicks = math.floor((Config.DEPLOY_DURATION or 15) / Config.TICK_DT)
			if self._pendingBots and self.tick >= deployTicks then
				SystemsBootstrap.flushPendingBots(self)
			end
			return origStep(self)
		end
	end
end

return SystemsBootstrap
