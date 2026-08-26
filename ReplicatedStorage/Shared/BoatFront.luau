--!strict
--[[
	Chantier 5 — isolation des fronts bateau (CONQUEST AttackExecution).

	OF : si sourceTile != null, l'attaque ne se combine jamais avec un front terre.
	seedBeachhead créait / renforçait le même Attack que le land → bug.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Heap = require(ReplicatedStorage.Shared.Heap)

local BoatFront = {}

local priorityScratch = table.create(4, 0)
-- Distinct de priorityScratch : enqueueFront l'ecrase via frontPriority.
local neighborScratch = table.create(4, 0)
-- N68 : wrap launchAttack recycle parkedBuf (recette collapsingBuf N67,
-- feel 07c6 N87). Liste d'Attack live (identite), pas des copies.
-- Truncate leftover AVANT origLaunch — un leftover reinserait un pont
-- fantome. Non reentrant — launchAttack synchrone. Distinct de N29
-- (fusion beachhead, ouvert) et de N5 (cap, ouvert).
local parkedBuf: { any } = table.create(8)
BoatFront.parkedBuf = parkedBuf

local function frontPriority(state, index: number, attackerSlot: number): number
	local n = MapGen.neighbors(index, priorityScratch)
	local owned = 0
	for i = 1, n do
		if buffer.readu8(state.owner, priorityScratch[i]) == attackerSlot then
			owned += 1
		end
	end
	local terrain = buffer.readu8(state.terrain, index)
	local roughness = Config.TERRAIN_COST[terrain] or 1
	local noise = (index * 2654435761 + state.tick * 40503) % 8
	return (noise + 10) * (1 - owned * 0.5 + roughness / 2) + state.tick
end

local function enqueueFront(state, atk, index: number)
	if atk.queued[index] then
		return
	end
	atk.queued[index] = true
	Heap.push(atk.frontier, index, frontPriority(state, index, atk.attacker))
end

function BoatFront.install(GameState)
	if GameState.__boatFront then
		return
	end
	GameState.__boatFront = true

	-- Debarquement = Attack separe (isBeachhead). La tuile debarquee est deja
	-- a l'attaquant (setOwner dans Navy.resolveLanding) : l'enfiler comme
	-- frontier ferait skip+heap vide+remboursement le meme tick.
	function GameState.seedBeachhead(self, attackerSlot: number, targetSlot: number, troops: number, tile: number)
		-- N98 : meme helper que launchAttack. Ne pas allouer inline —
		-- leftover pont = debit captures du mauvais camp (banc N68).
		local attack = GameState.acquireAttack(attackerSlot, targetSlot, troops, true, tile, nil)
		local n = MapGen.neighbors(tile, neighborScratch)
		for i = 1, n do
			local nb = neighborScratch[i]
			if self:isLand(nb) and buffer.readu8(self.owner, nb) == targetSlot then
				enqueueFront(self, attack, nb)
			end
		end
		if Heap.isEmpty(attack.frontier) then
			local attacker = self.players[attackerSlot]
			if attacker then
				attacker.troops += math.max(0, troops)
			end
			GameState.freeAttack(attack)
			return
		end
		table.insert(self.attacks, attack)
	end

	-- launchAttack ne doit fusionner qu'avec des fronts terre. On gare les
	-- tetes de pont (isBeachhead), pas les fronts vises (sourceTile = aim).
	local origLaunch = GameState.launchAttack
	function GameState.launchAttack(self, attackerSlot: number, targetSlot: number)
		local n = 0
		for i = #self.attacks, 1, -1 do
			local atk = self.attacks[i]
			if atk.isBeachhead then
				n += 1
				parkedBuf[n] = atk
				-- N98 : gare live, NE PAS releaseAttack (le pont revient).
				table.remove(self.attacks, i)
			end
		end
		for i = n + 1, #parkedBuf do
			parkedBuf[i] = nil
		end

		local ok, message = origLaunch(self, attackerSlot, targetSlot)

		for i = 1, n do
			table.insert(self.attacks, parkedBuf[i])
		end

		return ok, message
	end
end

return BoatFront
