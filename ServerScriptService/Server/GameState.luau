--!strict
--[[
	Etat autoritaire de la partie.

	La carte tient dans trois buffers plats indexes par tuile (terrain, owner,
	defense) et tout le travail par tick est en O(tuiles modifiees), jamais en
	O(carte). C'est ce qui permet de tenir 40 000 tuiles a 10 ticks/seconde avec
	48 joueurs.

	Ce module ne contient que le noyau : territoire, population, economie,
	offensives. La marine, le nucleaire et la diplomatie sont des systemes
	separes qui operent sur cet etat — pour qu'on puisse en ajouter un sans
	toucher au reste.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Doctrines = require(ReplicatedStorage.Shared.Doctrines)
local BuildingDefs = require(ReplicatedStorage.Shared.BuildingDefs)

local NEUTRAL = Config.NEUTRAL_SLOT
local OCEAN = Config.TERRAIN.OCEAN
local B = Config.BUILDING

export type PlayerState = {
	slot: number,
	player: Player?,
	name: string,
	isBot: boolean,
	doctrine: number,
	troops: number,
	gold: number,
	tiles: number,
	attackRatio: number,
	border: { [number]: true },
	-- Tuiles possedees touchant l'ocean. Distinct de `border`, qui ne retient
	-- que les tuiles au contact d'une terre etrangere : une cote entouree de
	-- son propre territoire n'est pas une frontiere mais reste le seul endroit
	-- ou poser un port et embarquer des troupes.
	coast: { [number]: true },
	alive: boolean,
	-- Agregats maintenus a l'incrementale plutot que recalcules
	cityPopBonus: number,
	portCount: number,
	siloCount: number,
	samCount: number,
	capitalCount: number,
	capitalTile: number?,
	betrayals: number,
	traitorUntil: number,
}

export type Attack = {
	attacker: number,
	target: number,
	troops: number,
	frontier: { [number]: true },
}

export type Boat = {
	id: number,
	slot: number,
	kind: number, -- 1 = transport, 2 = marchand
	troops: number,
	x: number,
	y: number,
	path: { number },
	step: number,
	targetTile: number,
}

export type Missile = {
	id: number,
	slot: number,
	kind: number,
	x: number,
	y: number,
	sx: number,
	sy: number,
	tx: number,
	ty: number,
	progress: number,
	speed: number,
}

export type Building = {
	kind: number,
	slot: number,
	cooldown: number, -- utilise par les batteries SAM
}

local GameState = {}
GameState.__index = GameState

export type GameState = typeof(setmetatable(
	{} :: {
		seed: number,
		tick: number,
		terrain: buffer,
		owner: buffer,
		defense: buffer,
		landCount: number,
		players: { [number]: PlayerState },
		attacks: { Attack },
		boats: { Boat },
		missiles: { Missile },
		buildings: { [number]: Building },
		alliances: { [number]: { [number]: true } },
		requests: { [number]: { [number]: number } }, -- from -> to -> expiry tick
		embargoes: { [number]: { [number]: true } },
		dirty: { [number]: true },
		buildingDirty: { [number]: true },
		freeSlots: { number },
		nextEntityId: number,
		capitalEvents: number,
		sounds: { { name: string, only: number? } },
		events: { { text: string, kind: string, only: number? } },
	},
	GameState
))

-- Tampons de voisins reutilises pour eviter des milliers d'allocations par
-- tick. Il en faut deux distincts : refreshBorder est appele *pendant* que
-- setOwner itere sur le sien, et un tampon partage serait ecrase en cours de
-- boucle. Toute nouvelle fonction qui appelle refreshBorder en iterant sur des
-- voisins doit utiliser son propre tampon.
local scratch = table.create(4, 0)
local borderScratch = table.create(4, 0)

--=============================================================================
-- Construction
--=============================================================================

function GameState.new(seed: number): GameState
	local self = setmetatable({}, GameState) :: GameState

	self.seed = seed
	self.tick = 0
	self.terrain = MapGen.generate(seed)
	self.owner = buffer.create(Config.TILE_COUNT)
	self.defense = buffer.create(Config.TILE_COUNT)
	self.landCount = MapGen.countLand(self.terrain)

	self.players = {}
	self.attacks = {}
	self.boats = {}
	self.missiles = {}
	self.buildings = {}
	self.alliances = {}
	self.requests = {}
	self.embargoes = {}
	self.dirty = {}
	self.buildingDirty = {}
	self.nextEntityId = 1
	self.capitalEvents = 0
	self.sounds = {}
	self.events = {}

	self.freeSlots = {}
	for slot = Config.MAX_PLAYERS, 1, -1 do
		table.insert(self.freeSlots, slot)
	end

	return self
end

function GameState.nextId(self: GameState): number
	local id = self.nextEntityId
	self.nextEntityId += 1
	return id
end

--[[
	File un message a destination des clients. `only` restreint a un slot, sinon
	c'est diffuse a tout le monde.
]]
function GameState.notify(self: GameState, text: string, kind: string, only: number?)
	table.insert(self.events, { text = text, kind = kind, only = only })
end

--[[
	Message concernant deux factions.

	Diffuse a tout le monde uniquement si un humain est implique. Sinon le
	message n'est envoye qu'aux deux parties — c'est-a-dire a personne, puisque
	ce sont des bots.

	Sans cette regle, douze bots qui s'allient et se trahissent en continu
	noient l'ecran du joueur sous des dizaines de notifications par minute qui
	ne le concernent pas.
]]
--[[
	File un effet sonore. `only` le restreint a un joueur ; sinon tout le monde
	l'entend, avec l'attenuation par distance geree cote client.
]]
function GameState.sound(self: GameState, name: string, only: number?)
	table.insert(self.sounds, { name = name, only = only })
end

function GameState.notifyBetween(self: GameState, text: string, kind: string, a: number, b: number)
	local pa, pb = self.players[a], self.players[b]
	local humanInvolved = (pa ~= nil and not pa.isBot) or (pb ~= nil and not pb.isBot)

	if humanInvolved then
		self:notify(text, kind)
	else
		self:notify(text, kind, a)
		self:notify(text, kind, b)
	end
end

function GameState.doctrineOf(self: GameState, slot: number): Doctrines.Doctrine
	local ps = self.players[slot]
	return Doctrines.get(if ps then ps.doctrine else nil)
end

--=============================================================================
-- Territoire
--=============================================================================

function GameState.isLand(self: GameState, index: number): boolean
	return buffer.readu8(self.terrain, index) ~= OCEAN
end

--[[
	Recalcule le statut "frontiere" d'une tuile pour son proprietaire.
	Une tuile est frontiere si elle touche une terre qui ne lui appartient pas :
	c'est l'ensemble depuis lequel toutes les offensives partent.
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

	local n = MapGen.neighbors(index, borderScratch)
	local isBorder = false
	for i = 1, n do
		local nb = borderScratch[i]
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
			old.coast[index] = nil
		end
	end

	buffer.writeu8(self.owner, index, slot)
	self.dirty[index] = true

	if slot ~= NEUTRAL then
		local new = self.players[slot]
		if new then
			new.tiles += 1
			-- Le relief est fige pour toute la partie : le caractere cotier
			-- d'une tuile ne change jamais, il suffit de le calculer a la
			-- capture.
			if MapGen.isCoastal(self.terrain, index) then
				new.coast[index] = true
			end
		end
	end

	-- Un batiment capture change de camp avec sa tuile : prendre une ville, un
	-- port ou un silo ennemi est un objectif en soi.
	local building = self.buildings[index]
	if building and building.slot ~= slot then
		local wasCapital = building.kind == B.CAPITAL
		local formerOwner = building.slot
		self:transferBuilding(index, slot)
		if wasCapital then
			self:onCapitalCaptured(formerOwner, slot)
		end
	end

	self:refreshBorder(index)
	local n = MapGen.neighbors(index, scratch)
	for i = 1, n do
		self:refreshBorder(scratch[i])
	end
end

--=============================================================================
-- Batiments
--=============================================================================

-- Applique (ou retire) l'aura defensive d'un bunker autour de sa tuile.
function GameState.applyDefenseAura(self: GameState, index: number, sign: number)
	local cx, cy = MapGen.fromIndex(index)
	local radius = Config.DEFENSE_RADIUS

	for dy = -radius, radius do
		for dx = -radius, radius do
			local dist2 = dx * dx + dy * dy
			if dist2 <= radius * radius then
				local nx, ny = cx + dx, cy + dy
				if MapGen.inBounds(nx, ny) then
					local i = MapGen.toIndex(nx, ny)
					-- Degressif du centre vers le bord.
					local falloff = 1 - math.sqrt(dist2) / radius
					local amount = math.floor(Config.DEFENSE_STRENGTH * falloff)
					local current = buffer.readu8(self.defense, i)
					buffer.writeu8(self.defense, i, math.clamp(current + sign * amount, 0, 255))
				end
			end
		end
	end
end

function GameState.countBuilding(self: GameState, slot: number, kind: number, sign: number)
	local ps = self.players[slot]
	if not ps then
		return
	end
	if kind == B.CITY or kind == B.CAPITAL then
		local def = BuildingDefs.get(kind)
		ps.cityPopBonus += sign * (if def then def.popCapBonus else 0)
		if kind == B.CAPITAL then
			ps.capitalCount += sign
		end
	elseif kind == B.PORT then
		ps.portCount += sign
	elseif kind == B.SILO then
		ps.siloCount += sign
	elseif kind == B.SAM then
		ps.samCount += sign
	end
end

--[[
	Chute d'une capitale.

	L'effet est volontairement brutal et immediat : c'est le seul evenement du
	jeu qui retourne un rapport de force en un instant, et donc le seul objectif
	qui justifie une offensive couteuse et ciblee plutot qu'un grignotage de
	frontiere.
]]
function GameState.onCapitalCaptured(self: GameState, formerOwner: number, captor: number)
	local victim = self.players[formerOwner]
	local winner = self.players[captor]

	if victim then
		victim.troops = math.max(0, victim.troops * (1 - Config.CAPITAL_TROOP_LOSS))
	end
	if winner then
		winner.gold += Config.CAPITAL_PLUNDER
	end

	local victimName = if victim then victim.name else "Une faction"
	local captorName = if winner then winner.name else "un assaillant"
	self:notify(`\u{1F3F1} La capitale de {victimName} est tombee aux mains de {captorName} !`, "alert")
	self:sound("capitalFallen")
	self.capitalEvents += 1
end

function GameState.placeBuilding(self: GameState, index: number, kind: number, slot: number)
	if self.buildings[index] then
		return
	end
	self.buildings[index] = { kind = kind, slot = slot, cooldown = 0 }
	self.buildingDirty[index] = true
	self:countBuilding(slot, kind, 1)

	if kind == B.DEFENSE then
		self:applyDefenseAura(index, 1)
	end
end

function GameState.transferBuilding(self: GameState, index: number, newSlot: number)
	local building = self.buildings[index]
	if not building then
		return
	end
	self:countBuilding(building.slot, building.kind, -1)
	building.slot = newSlot
	self:countBuilding(newSlot, building.kind, 1)
	self.buildingDirty[index] = true
end

function GameState.destroyBuilding(self: GameState, index: number)
	local building = self.buildings[index]
	if not building then
		return
	end
	if building.kind == B.DEFENSE then
		self:applyDefenseAura(index, -1)
	end
	self:countBuilding(building.slot, building.kind, -1)
	self.buildings[index] = nil
	self.buildingDirty[index] = true
end

--=============================================================================
-- Cycle de vie des joueurs
--=============================================================================

--[[
	Cherche une zone de spawn : une tuile de terre dont le disque alentour est
	entierement libre, pour ne jamais coller deux joueurs au demarrage.
]]
function GameState.findSpawn(self: GameState, rng: Random): number?
	local radius = Config.SPAWN_RADIUS
	local check = radius + 3

	for _ = 1, 6000 do
		local x = rng:NextInteger(check, Config.MAP_WIDTH - check - 1)
		local y = rng:NextInteger(check, Config.MAP_HEIGHT - check - 1)
		local center = MapGen.toIndex(x, y)

		if self:isLand(center) and buffer.readu8(self.owner, center) == NEUTRAL then
			local ok = true
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

function GameState.addPlayer(
	self: GameState,
	player: Player?,
	name: string,
	rng: Random,
	betrayals: number
): PlayerState?
	local slot = table.remove(self.freeSlots)
	if not slot then
		return nil
	end

	local state: PlayerState = {
		slot = slot,
		player = player,
		name = name,
		isBot = player == nil,
		doctrine = Doctrines.DEFAULT_ID,
		troops = Config.START_TROOPS,
		gold = Config.START_GOLD,
		tiles = 0,
		attackRatio = Config.DEFAULT_ATTACK_RATIO,
		border = {},
		coast = {},
		alive = true,
		cityPopBonus = 0,
		portCount = 0,
		siloCount = 0,
		samCount = 0,
		capitalCount = 0,
		capitalTile = nil,
		betrayals = betrayals,
		traitorUntil = 0,
	}
	self.players[slot] = state
	self.alliances[slot] = {}
	self.requests[slot] = {}
	self.embargoes[slot] = {}

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

	-- La capitale est posee par le moteur, jamais achetee.
	self:placeBuilding(center, B.CAPITAL, slot)
	state.capitalTile = center

	return state
end

function GameState.removePlayer(self: GameState, slot: number)
	local state = self.players[slot]
	if not state then
		return
	end

	-- Balayage complet, mais uniquement au depart d'un joueur (rare), jamais
	-- dans la boucle de tick.
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(self.owner, index) == slot then
			buffer.writeu8(self.owner, index, NEUTRAL)
			self.dirty[index] = true
		end
	end

	for index, building in self.buildings do
		if building.slot == slot then
			self:destroyBuilding(index)
		end
	end

	for i = #self.attacks, 1, -1 do
		local atk = self.attacks[i]
		if atk.attacker == slot or atk.target == slot then
			table.remove(self.attacks, i)
		end
	end
	for i = #self.boats, 1, -1 do
		if self.boats[i].slot == slot then
			table.remove(self.boats, i)
		end
	end
	for i = #self.missiles, 1, -1 do
		if self.missiles[i].slot == slot then
			table.remove(self.missiles, i)
		end
	end

	for other, set in self.alliances do
		set[slot] = nil
		if other == slot then
			self.alliances[other] = {}
		end
	end
	self.alliances[slot] = nil
	self.requests[slot] = nil
	self.embargoes[slot] = nil

	self.players[slot] = nil
	table.insert(self.freeSlots, slot)
end

--=============================================================================
-- Offensives
--=============================================================================

function GameState.areAllied(self: GameState, a: number, b: number): boolean
	local set = self.alliances[a]
	return set ~= nil and set[b] == true
end

-- Cout en troupes pour absorber une tuile donnee.
function GameState.tileCost(self: GameState, index: number, attackerSlot: number, defender: PlayerState?): number
	local terrain = buffer.readu8(self.terrain, index)
	local cost = Config.TILE_BASE_COST * Config.TERRAIN_COST[terrain]

	if defender then
		-- Un defenseur concentre sur peu de tuiles est bien plus dur a percer
		-- qu'un empire etale : c'est ce qui punit l'expansion incontrolee.
		local density = defender.troops / math.max(1, defender.tiles)
		cost *= 1 + density * Config.DEFENSE_DENSITY_K
		cost *= Doctrines.get(defender.doctrine).defense
	else
		cost *= Config.NEUTRAL_COST_MULT
	end

	-- Aura des bunkers.
	cost *= 1 + buffer.readu8(self.defense, index) / 100

	cost /= self:doctrineOf(attackerSlot).attack

	return cost
end

--[[
	Engage une offensive. Le corps expeditionnaire est preleve immediatement sur
	la reserve : les troupes engagees ne defendent plus. C'est la decision
	tactique centrale du jeu.
]]
function GameState.launchAttack(self: GameState, attackerSlot: number, targetSlot: number): (boolean, string?)
	local attacker = self.players[attackerSlot]
	if not attacker or attackerSlot == targetSlot then
		return false, "Cible invalide."
	end
	if targetSlot ~= NEUTRAL and not self.players[targetSlot] then
		return false, "Cette faction n'existe plus."
	end
	if targetSlot ~= NEUTRAL and self:areAllied(attackerSlot, targetSlot) then
		return false, "Tu es allie a cette faction. Romps le pacte d'abord."
	end

	local committed = math.floor(attacker.troops * attacker.attackRatio)
	if committed < Config.MIN_ATTACK_TROOPS then
		return false, "Pas assez de troupes engagees."
	end

	-- Une seule offensive par couple attaquant/cible : relancer la renforce.
	for _, atk in self.attacks do
		if atk.attacker == attackerSlot and atk.target == targetSlot then
			attacker.troops -= committed
			atk.troops += committed
			return true, nil
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
		return false, "Aucun contact terrestre. Passe par la mer."
	end

	attacker.troops -= committed
	table.insert(self.attacks, {
		attacker = attackerSlot,
		target = targetSlot,
		troops = committed,
		frontier = frontier,
	})
	return true, nil
end

--[[
	Cree une tete de pont apres un debarquement : l'offensive demarre depuis une
	tuile isolee, sans contact terrestre prealable.
]]
function GameState.seedBeachhead(self: GameState, attackerSlot: number, targetSlot: number, troops: number, tile: number)
	local frontier: { [number]: true } = { [tile] = true }

	for _, atk in self.attacks do
		if atk.attacker == attackerSlot and atk.target == targetSlot then
			atk.troops += troops
			atk.frontier[tile] = true
			return
		end
	end

	table.insert(self.attacks, {
		attacker = attackerSlot,
		target = targetSlot,
		troops = troops,
		frontier = frontier,
	})
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

			local cost = self:tileCost(index, atk.attacker, defender)
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

			local n = MapGen.neighbors(index, scratch)
			for k = 1, n do
				local nb = scratch[k]
				if buffer.readu8(self.owner, nb) == atk.target and self:isLand(nb) then
					atk.frontier[nb] = true
				end
			end
		end

		if atk.troops <= 0 or next(atk.frontier) == nil then
			attacker.troops += math.max(0, atk.troops) -- les survivants rentrent
			table.remove(self.attacks, i)
		end
	end
end

--=============================================================================
-- Population et economie
--=============================================================================

function GameState.maxTroops(self: GameState, ps: PlayerState): number
	return Config.BASE_MAX_TROOPS + ps.tiles * Config.MAX_TROOPS_PER_TILE + ps.cityPopBonus
end

-- Nombre de factions avec qui le commerce maritime est effectivement ouvert.
function GameState.tradePartners(self: GameState, ps: PlayerState): number
	if ps.portCount == 0 then
		return 0
	end
	local myEmbargoes = self.embargoes[ps.slot]
	local count = 0
	for slot, other in self.players do
		if slot ~= ps.slot and other.portCount > 0 then
			local blockedByMe = myEmbargoes and myEmbargoes[slot]
			local theirEmbargoes = self.embargoes[slot]
			local blockedByThem = theirEmbargoes and theirEmbargoes[ps.slot]
			if not blockedByMe and not blockedByThem then
				count += 1
			end
		end
	end
	return count
end

function GameState.stepEconomy(self: GameState)
	for _, ps in self.players do
		local doctrine = Doctrines.get(ps.doctrine)

		local maxTroops = self:maxTroops(ps)
		if ps.troops < maxTroops then
			local gain = math.max(Config.MIN_GROWTH, (maxTroops - ps.troops) * Config.GROWTH_RATE)
			ps.troops = math.min(maxTroops, ps.troops + gain * doctrine.growth)
		end

		local territorial = ps.tiles ^ Config.GOLD_TILE_EXPONENT * Config.GOLD_TILE_SCALE
		local income = territorial
			+ ps.portCount * Config.GOLD_PER_PORT
			+ ps.capitalCount * Config.GOLD_PER_CAPITAL
			+ self:tradePartners(ps) * Config.TRADE_GOLD_PER_PARTNER
		ps.gold += income * doctrine.goldRate
	end
end

function GameState.landControlled(self: GameState, slot: number): number
	local ps = self.players[slot]
	if not ps or self.landCount == 0 then
		return 0
	end
	return ps.tiles / self.landCount
end

-- Part des terres deja colonisee, toutes factions confondues. Sert de horloge
-- naturelle a la partie : c'est elle qui debloque le nucleaire.
function GameState.colonizedRatio(self: GameState): number
	if self.landCount == 0 then
		return 0
	end
	local owned = 0
	for _, ps in self.players do
		owned += ps.tiles
	end
	return owned / self.landCount
end

--=============================================================================
-- Replication
--=============================================================================

--[[
	Serialise les changements de proprietaire depuis le dernier appel, au format
	[u32 index][u8 slot] repete. On n'envoie jamais la carte entiere.
]]
function GameState.flushOwnerDelta(self: GameState): buffer?
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

function GameState.flushBuildingDelta(self: GameState): { any }?
	local out = {}
	for index in self.buildingDirty do
		local building = self.buildings[index]
		table.insert(out, {
			index = index,
			kind = if building then building.kind else 0,
			slot = if building then building.slot else 0,
		})
	end
	table.clear(self.buildingDirty)
	return if #out > 0 then out else nil
end

--[[
	Elimination des factions sans territoire.

	Une faction n'est vaincue que si elle n'a plus rien *et* plus rien en cours :
	un joueur dont toutes les troupes sont dans une offensive ou sur un
	transport en mer a encore une chance de reprendre pied, et l'eliminer a cet
	instant supprimerait le retournement le plus spectaculaire du jeu.

	Renvoie la liste des slots elimines pour que l'appelant previenne les
	joueurs concernes.
]]
function GameState.stepElimination(self: GameState): { number }
	local doomed: { number } = {}

	for slot, ps in self.players do
		if ps.tiles > 0 then
			continue
		end

		local hasPendingAttack = false
		for _, atk in self.attacks do
			if atk.attacker == slot then
				hasPendingAttack = true
				break
			end
		end
		if hasPendingAttack then
			continue
		end

		local hasBoat = false
		for _, boat in self.boats do
			if boat.slot == slot then
				hasBoat = true
				break
			end
		end
		if hasBoat then
			continue
		end

		table.insert(doomed, slot)
	end

	-- On collecte avant de supprimer : removePlayer mute self.players, et le
	-- muter en cours d'iteration est un comportement indefini.
	for _, slot in doomed do
		local ps = self.players[slot]
		if ps then
			-- Seules les eliminations de joueurs humains sont publiques : voir
			-- douze bots mourir un par un n'apprend rien et sature le fil.
			if not ps.isBot then
				self:notify(`\u{1F480} {ps.name} a ete elimine.`, "alert")
			end
			self:removePlayer(slot)
		end
	end

	return doomed
end

function GameState.step(self: GameState): { number }
	self.tick += 1
	self:stepEconomy()
	self:stepAttacks()
	return self:stepElimination()
end

return GameState
