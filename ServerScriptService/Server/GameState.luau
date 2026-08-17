--!strict
--[[
	Etat autoritaire de la partie.

	Le coeur du jeu tient dans deux buffers plats indexes par tuile
	(terrain, owner) plus, par joueur, un ensemble de tuiles frontieres.
	Tout est en O(tuiles capturees) par tick, jamais en O(carte) : c'est ce qui
	permet de tenir 40 000 tuiles a 10 ticks/seconde.

	Modele d'attaque (repris d'OpenFront) : on n'ordonne pas des unites, on
	engage un corps expeditionnaire contre une faction. Chaque tick, ce corps
	depense des troupes pour absorber les tuiles ennemies au contact. Quand il
	est epuise, l'offensive s'arrete la ou elle en est.
]]

local Config = require(game.ReplicatedStorage.Shared.Config)
local MapGen = require(game.ReplicatedStorage.Shared.MapGen)

local NEUTRAL = Config.NEUTRAL_SLOT
local TERRAIN_COST = Config.TERRAIN_COST
local OCEAN = Config.TERRAIN.OCEAN

export type PlayerState = {
	slot: number,
	player: Player?,
	name: string,
	troops: number,
	tiles: number,
	attackRatio: number,
	border: { [number]: true }, -- tuiles possedees ayant au moins un voisin etranger
	alive: boolean,
}

export type Attack = {
	attacker: number,
	target: number,
	troops: number,
	frontier: { [number]: true }, -- tuiles ennemies au contact, candidates a la capture
}

local GameState = {}
GameState.__index = GameState

export type GameState = typeof(setmetatable(
	{} :: {
		seed: number,
		terrain: buffer,
		owner: buffer,
		players: { [number]: PlayerState },
		attacks: { Attack },
		dirty: { [number]: true }, -- tuiles dont le proprietaire a change depuis le dernier envoi
		freeSlots: { number },
	},
	GameState
))

local scratch = table.create(4, 0) -- tampon de voisins reutilise

function GameState.new(seed: number): GameState
	local self = setmetatable({}, GameState) :: GameState

	self.seed = seed
	self.terrain = MapGen.generate(seed)
	self.owner = buffer.create(Config.TILE_COUNT) -- 0 = neutre partout
	self.players = {}
	self.attacks = {}
	self.dirty = {}

	self.freeSlots = {}
	for slot = Config.MAX_PLAYERS, 1, -1 do
		table.insert(self.freeSlots, slot)
	end

	return self
end

function GameState.isLand(self: GameState, index: number): boolean
	return buffer.readu8(self.terrain, index) ~= OCEAN
end

--[[
	Recalcule le statut "frontiere" d'une tuile pour son proprietaire.
	Appele apres chaque capture, sur la tuile prise et ses voisins.
]]
function GameState.refreshBorder(self: GameState, index: number)
	local slot = buffer.readu8(self.owner, index)
	if slot == NEUTRAL then
		return
	end
	local state = self.players[slot]
	if not state then
		return
	end

	local n = MapGen.neighbors(index, scratch)
	local isBorder = false
	for i = 1, n do
		local nb = scratch[i]
		if buffer.readu8(self.owner, nb) ~= slot and self:isLand(nb) then
			isBorder = true
			break
		end
	end

	if isBorder then
		state.border[index] = true
	else
		state.border[index] = nil
	end
end

function GameState.setOwner(self: GameState, index: number, slot: number)
	local previous = buffer.readu8(self.owner, index)
	if previous == slot then
		return
	end

	if previous ~= NEUTRAL then
		local old = self.players[previous]
		if old then
			old.tiles -= 1
			old.border[index] = nil
		end
	end

	buffer.writeu8(self.owner, index, slot)
	self.dirty[index] = true

	if slot ~= NEUTRAL then
		local new = self.players[slot]
		if new then
			new.tiles += 1
		end
	end

	-- La capture peut rendre des tuiles voisines interieures ou frontieres.
	self:refreshBorder(index)
	local n = MapGen.neighbors(index, scratch)
	for i = 1, n do
		self:refreshBorder(scratch[i])
	end
end

--[[
	Cherche une zone de spawn : une tuile de terre dont le disque de rayon
	SPAWN_RADIUS est entierement libre, pour ne pas coller deux joueurs.
]]
function GameState.findSpawn(self: GameState, rng: Random): number?
	local radius = Config.SPAWN_RADIUS
	for _ = 1, 4000 do
		local x = rng:NextInteger(radius, Config.MAP_WIDTH - radius - 1)
		local y = rng:NextInteger(radius, Config.MAP_HEIGHT - radius - 1)
		local center = MapGen.toIndex(x, y)

		if self:isLand(center) and buffer.readu8(self.owner, center) == NEUTRAL then
			local ok = true
			-- Marge de 2 tuiles au-dela du rayon : evite les spawns au contact.
			local check = radius + 2
			for dy = -check, check do
				for dx = -check, check do
					local nx, ny = x + dx, y + dy
					if MapGen.inBounds(nx, ny) then
						if buffer.readu8(self.owner, MapGen.toIndex(nx, ny)) ~= NEUTRAL then
							ok = false
							break
						end
					end
				end
				if not ok then
					break
				end
			end
			if ok then
				return center
			end
		end
	end
	return nil
end

function GameState.addPlayer(self: GameState, player: Player?, name: string, rng: Random): PlayerState?
	local slot = table.remove(self.freeSlots)
	if not slot then
		return nil
	end

	local state: PlayerState = {
		slot = slot,
		player = player,
		name = name,
		troops = Config.START_TROOPS,
		tiles = 0,
		attackRatio = Config.DEFAULT_ATTACK_RATIO,
		border = {},
		alive = true,
	}
	self.players[slot] = state

	local center = self:findSpawn(rng)
	if not center then
		self.players[slot] = nil
		table.insert(self.freeSlots, slot)
		return nil
	end

	local cx, cy = MapGen.fromIndex(center)
	local r = Config.SPAWN_RADIUS
	for dy = -r, r do
		for dx = -r, r do
			if dx * dx + dy * dy <= r * r then
				local nx, ny = cx + dx, cy + dy
				if MapGen.inBounds(nx, ny) then
					local idx = MapGen.toIndex(nx, ny)
					if self:isLand(idx) then
						self:setOwner(idx, slot)
					end
				end
			end
		end
	end

	return state
end

function GameState.removePlayer(self: GameState, slot: number)
	local state = self.players[slot]
	if not state then
		return
	end

	for index in state.border do
		self.dirty[index] = true
	end
	-- Le territoire redevient neutre : balayage complet, mais uniquement au
	-- depart d'un joueur (rare), pas dans la boucle de tick.
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(self.owner, index) == slot then
			buffer.writeu8(self.owner, index, NEUTRAL)
			self.dirty[index] = true
		end
	end

	for i = #self.attacks, 1, -1 do
		local atk = self.attacks[i]
		if atk.attacker == slot or atk.target == slot then
			table.remove(self.attacks, i)
		end
	end

	self.players[slot] = nil
	table.insert(self.freeSlots, slot)
end

--[[
	Engage une offensive. Le corps expeditionnaire est preleve immediatement sur
	la reserve : les troupes engagees ne defendent plus. C'est la decision
	tactique centrale du jeu.
]]
function GameState.launchAttack(self: GameState, attackerSlot: number, targetSlot: number): boolean
	local attacker = self.players[attackerSlot]
	if not attacker or attackerSlot == targetSlot then
		return false
	end
	if targetSlot ~= NEUTRAL and not self.players[targetSlot] then
		return false
	end

	local committed = math.floor(attacker.troops * attacker.attackRatio)
	if committed < Config.MIN_ATTACK_TROOPS then
		return false
	end

	-- Une seule offensive par couple attaquant/cible : relancer renforce.
	for _, atk in self.attacks do
		if atk.attacker == attackerSlot and atk.target == targetSlot then
			attacker.troops -= committed
			atk.troops += committed
			return true
		end
	end

	local frontier: { [number]: true } = {}
	local any = false
	for index in attacker.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if buffer.readu8(self.owner, nb) == targetSlot and self:isLand(nb) then
				frontier[nb] = true
				any = true
			end
		end
	end

	if not any then
		return false -- pas de contact terrestre avec cette faction
	end

	attacker.troops -= committed
	table.insert(self.attacks, {
		attacker = attackerSlot,
		target = targetSlot,
		troops = committed,
		frontier = frontier,
	})
	return true
end

-- Cout en troupes pour absorber une tuile donnee.
function GameState.tileCost(self: GameState, index: number, defender: PlayerState?): number
	local terrain = buffer.readu8(self.terrain, index)
	local cost = Config.TILE_BASE_COST * TERRAIN_COST[terrain]

	if defender then
		-- Un defenseur concentre sur peu de tuiles est bien plus dur a percer
		-- qu'un empire etale : c'est ce qui punit l'expansion incontrolee.
		local density = defender.troops / math.max(1, defender.tiles)
		cost *= 1 + density * Config.DEFENSE_DENSITY_K
	else
		cost *= Config.NEUTRAL_COST_MULT
	end

	return cost
end

function GameState.stepAttacks(self: GameState)
	for i = #self.attacks, 1, -1 do
		local atk = self.attacks[i]
		local attacker = self.players[atk.attacker]
		local defender = if atk.target ~= NEUTRAL then self.players[atk.target] else nil

		if not attacker or (atk.target ~= NEUTRAL and not defender) then
			table.remove(self.attacks, i)
			continue
		end

		local budget = atk.troops * Config.ATTACK_SPEND_RATE
		local captured = 0
		local spent = 0

		-- On absorbe des tuiles tant que le budget du tick le permet.
		while spent < budget and captured < Config.MAX_TILES_PER_TICK do
			local index = next(atk.frontier)
			if not index then
				break
			end
			atk.frontier[index] = nil

			-- La tuile a pu changer de main depuis qu'elle est entree dans le front.
			if buffer.readu8(self.owner, index) ~= atk.target then
				continue
			end

			local cost = self:tileCost(index, defender)
			if cost > atk.troops then
				-- Trop cher pour ce qu'il reste : l'offensive est brisee ici.
				atk.troops = 0
				break
			end

			atk.troops -= cost
			spent += cost
			captured += 1

			if defender then
				defender.troops = math.max(0, defender.troops - cost * Config.DEFENDER_LOSS_RATIO)
			end

			self:setOwner(index, atk.attacker)

			-- La tuile prise ouvre de nouveaux contacts avec la meme cible.
			local n = MapGen.neighbors(index, scratch)
			for k = 1, n do
				local nb = scratch[k]
				if buffer.readu8(self.owner, nb) == atk.target and self:isLand(nb) then
					atk.frontier[nb] = true
				end
			end
		end

		if atk.troops <= 0 or next(atk.frontier) == nil then
			-- Les survivants rentrent dans la reserve.
			attacker.troops += math.max(0, atk.troops)
			table.remove(self.attacks, i)
		end
	end
end

function GameState.stepGrowth(self: GameState)
	for _, state in self.players do
		local maxTroops = Config.BASE_MAX_TROOPS + state.tiles * Config.MAX_TROOPS_PER_TILE
		if state.troops < maxTroops then
			local gain = math.max(Config.MIN_GROWTH, (maxTroops - state.troops) * Config.GROWTH_RATE)
			state.troops = math.min(maxTroops, state.troops + gain)
		end
	end
end

function GameState.step(self: GameState)
	self:stepGrowth()
	self:stepAttacks()
end

--[[
	Serialise les changements de proprietaire depuis le dernier appel, au format
	[u32 index][u8 slot] repete. On n'envoie jamais la carte entiere : sur une
	partie calme c'est quelques dizaines d'octets par tick.
	Renvoie nil s'il n'y a rien a envoyer.
]]
function GameState.flushDelta(self: GameState): buffer?
	local indices = {}
	for index in self.dirty do
		table.insert(indices, index)
	end
	table.clear(self.dirty)

	local count = #indices
	if count == 0 then
		return nil
	end

	local buf = buffer.create(count * 5)
	for i, index in indices do
		local offset = (i - 1) * 5
		buffer.writeu32(buf, offset, index)
		buffer.writeu8(buf, offset + 4, buffer.readu8(self.owner, index))
	end
	return buf
end

return GameState
