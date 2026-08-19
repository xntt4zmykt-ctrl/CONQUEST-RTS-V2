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
local Eras = require(ReplicatedStorage.Shared.Eras)

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
	cityGoldBonus: number,
	portCount: number,
	siloCount: number,
	samCount: number,
	capitalCount: number,
	capitalTile: number?,
	-- Centres de ravitaillement (capitale et villes). Ils definissent jusqu'ou
	-- l'empire peut conquerir a cout normal.
	hubs: { number },
	-- Ere technologique atteinte, et compte par type de batiment. Le second
	-- sert a la fois aux conditions d'ere et a l'inflation des couts.
	era: number,
	buildingCounts: { [number]: number },
	betrayals: number,
	traitorUntil: number,
	capturedTiles: number,
	lostTiles: number,
	capitalsCaptured: number,
	buildingsBuilt: number,
	attacksLaunched: number,
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
	-- Porte-avions uniquement : base d'attache et angle d'orbite.
	homeTile: number?,
	angle: number?,
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
	level: number,
	-- Usine : toutes les villes desservies. Une usine bien placee au centre
	-- d'un bassin en alimente plusieurs, c'est tout son interet.
	links: { number },
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
		mode: any,
		events: { { text: string, kind: string, only: number? } },
		combatUnlocked: boolean,
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
	self.mode = nil
	-- L'etat brut reste immediatement jouable pour les simulations et les
	-- tests. Le serveur de match le passe explicitement a false pendant son
	-- compte a rebours de preparation.
	self.combatUnlocked = true

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
	File un effet sonore. `only` le restreint a un joueur ; sinon tout le monde
	l'entend, avec l'attenuation par distance geree cote client.
]]
function GameState.sound(self: GameState, name: string, only: number?)
	table.insert(self.sounds, { name = name, only = only })
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
			if self.tick > 0 then
				old.lostTiles += 1
			end
		end
	end

	buffer.writeu8(self.owner, index, slot)
	self.dirty[index] = true

	if slot ~= NEUTRAL then
		local new = self.players[slot]
		if new then
			new.tiles += 1
			if self.tick > 0 then
				new.capturedTiles += 1
			end
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

function GameState.countBuilding(self: GameState, slot: number, kind: number, sign: number, level: number?)
	local ps = self.players[slot]
	if not ps then
		return
	end

	ps.buildingCounts[kind] = (ps.buildingCounts[kind] or 0) + sign
	if kind == B.CITY then
		local city = Config.CITY_LEVELS[level or 1] or Config.CITY_LEVELS[1]
		ps.cityPopBonus += sign * city.popCapBonus
		ps.cityGoldBonus += sign * city.goldBonus
	elseif kind == B.CAPITAL then
		local def = BuildingDefs.get(kind)
		ps.cityPopBonus += sign * (if def then def.popCapBonus else 0)
		ps.capitalCount += sign
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
		winner.capitalsCaptured += 1
	end

	local victimName = if victim then victim.name else "Une faction"
	local captorName = if winner then winner.name else "un assaillant"
	self:notifyBetween(
		`\u{1F3F1} La capitale de {victimName} est tombee aux mains de {captorName} !`,
		"alert",
		formerOwner,
		captor
	)
	local humanInvolved = (victim ~= nil and not victim.isBot) or (winner ~= nil and not winner.isBot)
	if humanInvolved then
		self:sound("capitalFallen")
	end
	self.capitalEvents += 1
end

-- Reconnecte toutes les usines d'une faction a leur ville la plus proche.
-- Cette operation n'arrive qu'a la construction/capture/destruction d'un
-- batiment : aucun balayage de la carte n'est effectue a chaque tick.
--[[
	Recalcule les routes logistiques d'un joueur.

	Une usine dessert **toutes** les villes a portee, pas seulement la plus
	proche : c'est ce qui recompense une implantation au centre d'un bassin de
	villes plutot qu'un placement au hasard. Trois villes dans le rayon font
	trois routes.
]]
function GameState.refreshFactoryLinks(self: GameState, slot: number)
	if not self.players[slot] then
		return
	end

	local cities = {}
	local factories = {}
	for index, building in self.buildings do
		if building.slot == slot then
			if building.kind == B.CITY then
				table.insert(cities, index)
			elseif building.kind == B.FACTORY then
				table.insert(factories, index)
			end
		end
	end

	local maxDistance2 = Config.FACTORY_ROUTE_RANGE * Config.FACTORY_ROUTE_RANGE
	for _, factoryIndex in factories do
		local factory = self.buildings[factoryIndex]
		if not factory then
			continue
		end

		local fx, fy = MapGen.fromIndex(factoryIndex)
		local links = {}
		for _, cityIndex in cities do
			local cx, cy = MapGen.fromIndex(cityIndex)
			local dx, dy = cx - fx, cy - fy
			if dx * dx + dy * dy <= maxDistance2 then
				table.insert(links, cityIndex)
			end
		end

		-- L'ordre doit etre stable, sinon la comparaison ci-dessous signale un
		-- changement a chaque recalcul et sature la replication.
		table.sort(links)

		local changed = #links ~= #factory.links
		if not changed then
			for i, cityIndex in links do
				if factory.links[i] ~= cityIndex then
					changed = true
					break
				end
			end
		end

		if changed then
			factory.links = links
			self.buildingDirty[factoryIndex] = true
		end
	end
end

function GameState.logisticsFor(self: GameState, slot: number): (number, number)
	local routes = 0
	local income = 0
	for index, building in self.buildings do
		if building.slot ~= slot or building.kind ~= B.FACTORY then
			continue
		end

		local fx, fy = MapGen.fromIndex(index)
		for _, cityIndex in building.links do
			local city = self.buildings[cityIndex]
			if not city or city.slot ~= slot or city.kind ~= B.CITY then
				continue
			end
			local cx, cy = MapGen.fromIndex(cityIndex)
			local distance = math.sqrt((cx - fx) ^ 2 + (cy - fy) ^ 2)
			-- Une ville proche est mieux desservie qu'une ville en limite de
			-- portee : le placement compte, pas seulement le compte.
			local efficiency = 0.7 + 0.3 * (1 - math.clamp(distance / Config.FACTORY_ROUTE_RANGE, 0, 1))
			routes += 1
			income += Config.GOLD_PER_FACTORY_ROUTE * efficiency
		end
	end
	return routes, income
end

--[[
	Recalcule les centres de ravitaillement d'un joueur.

	Balayage complet des batiments, mais uniquement quand l'un d'eux change de
	main ou apparait — jamais dans la boucle de tick.
]]
function GameState.refreshSupplyHubs(self: GameState, slot: number)
	local ps = self.players[slot]
	if not ps then
		return
	end

	table.clear(ps.hubs)
	for index, building in self.buildings do
		if building.slot == slot and (building.kind == B.CITY or building.kind == B.CAPITAL) then
			table.insert(ps.hubs, index)
		end
	end
end

function GameState.placeBuilding(self: GameState, index: number, kind: number, slot: number)
	if self.buildings[index] then
		return
	end
	self.buildings[index] = { kind = kind, slot = slot, level = 1, links = {}, cooldown = 0 }
	self.buildingDirty[index] = true
	self:countBuilding(slot, kind, 1, 1)

	if kind == B.DEFENSE then
		self:applyDefenseAura(index, 1)
	end
	if kind == B.CITY or kind == B.FACTORY then
		self:refreshFactoryLinks(slot)
	end
	if kind == B.CITY or kind == B.CAPITAL then
		self:refreshSupplyHubs(slot)
	end
end

function GameState.upgradeCity(self: GameState, index: number): number?
	local building = self.buildings[index]
	if not building or building.kind ~= B.CITY or building.level >= Config.CITY_MAX_LEVEL then
		return nil
	end

	self:countBuilding(building.slot, building.kind, -1, building.level)
	building.level += 1
	self:countBuilding(building.slot, building.kind, 1, building.level)
	self.buildingDirty[index] = true
	return building.level
end

function GameState.transferBuilding(self: GameState, index: number, newSlot: number)
	local building = self.buildings[index]
	if not building then
		return
	end
	local previousSlot = building.slot
	self:countBuilding(previousSlot, building.kind, -1, building.level)
	building.slot = newSlot
	self:countBuilding(newSlot, building.kind, 1, building.level)
	self.buildingDirty[index] = true
	if building.kind == B.CITY or building.kind == B.FACTORY then
		self:refreshFactoryLinks(previousSlot)
		self:refreshFactoryLinks(newSlot)
	end
	if building.kind == B.CITY or building.kind == B.CAPITAL then
		self:refreshSupplyHubs(previousSlot)
		self:refreshSupplyHubs(newSlot)
	end
end

function GameState.destroyBuilding(self: GameState, index: number)
	local building = self.buildings[index]
	if not building then
		return
	end
	local previousSlot = building.slot
	local previousKind = building.kind
	if building.kind == B.DEFENSE then
		self:applyDefenseAura(index, -1)
	end
	self:countBuilding(building.slot, building.kind, -1, building.level)
	self.buildings[index] = nil
	self.buildingDirty[index] = true
	if previousKind == B.CITY or previousKind == B.FACTORY then
		self:refreshFactoryLinks(previousSlot)
	end
	if previousKind == B.CITY or previousKind == B.CAPITAL then
		self:refreshSupplyHubs(previousSlot)
	end
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
	local isBot = player == nil

	local state: PlayerState = {
		slot = slot,
		player = player,
		name = name,
		isBot = isBot,
		doctrine = Doctrines.DEFAULT_ID,
		troops = if isBot then Config.START_TROOPS else Config.HUMAN_START_TROOPS,
		gold = if isBot then Config.START_GOLD else Config.HUMAN_START_GOLD,
		tiles = 0,
		attackRatio = Config.DEFAULT_ATTACK_RATIO,
		border = {},
		coast = {},
		alive = true,
		cityPopBonus = 0,
		cityGoldBonus = 0,
		portCount = 0,
		siloCount = 0,
		samCount = 0,
		capitalCount = 0,
		capitalTile = nil,
		hubs = {},
		era = 1,
		buildingCounts = {},
		betrayals = betrayals,
		traitorUntil = 0,
		capturedTiles = 0,
		lostTiles = 0,
		capitalsCaptured = 0,
		buildingsBuilt = 0,
		attacksLaunched = 0,
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
--[[
	Penalite de ravitaillement : multiplicateur du cout de conquete selon la
	distance au centre de ravitaillement le plus proche de l'assaillant.

	C'est le frein systemique a l'emballement. Sans lui, plus un empire est
	gros, plus il lui est facile de grossir, et la partie se decide dans les
	premieres minutes. Avec, chaque conquete lointaine coute de plus en plus
	cher jusqu'a devenir impossible — a moins d'investir dans une ville qui
	deplace la frontiere du ravitaillement.

	Le cout est en O(centres), soit une poignee d'iterations : la liste est
	maintenue a l'incrementale et ne contient que capitales et villes.
]]
function GameState.supplyPenalty(self: GameState, slot: number, index: number): number
	local ps = self.players[slot]
	if not ps then
		return 1
	end

	-- Plus aucun centre : l'empire est decapite, il ne conquiert plus rien
	-- au-dela de ce qu'il tient deja.
	if #ps.hubs == 0 then
		return Config.SUPPLY_MAX_PENALTY
	end

	local x, y = MapGen.fromIndex(index)
	local closest = math.huge

	for _, hub in ps.hubs do
		local hx, hy = MapGen.fromIndex(hub)
		local dx, dy = hx - x, hy - y
		local distance = dx * dx + dy * dy
		if distance < closest then
			closest = distance
		end
	end

	local beyond = math.sqrt(closest) - Config.SUPPLY_FREE_RANGE
	if beyond <= 0 then
		return 1
	end

	local penalty = 1 + (beyond / Config.SUPPLY_FALLOFF) ^ Config.SUPPLY_EXPONENT
	return math.min(penalty, Config.SUPPLY_MAX_PENALTY)
end

function GameState.tileCost(self: GameState, index: number, attackerSlot: number, defender: PlayerState?): number
	local terrain = buffer.readu8(self.terrain, index)
	local cost = Config.TILE_BASE_COST * Config.TERRAIN_COST[terrain]

	if defender then
		-- Un defenseur concentre sur peu de tuiles est bien plus dur a percer
		-- qu'un empire etale : c'est ce qui punit l'expansion incontrolee.
		local density = defender.troops / math.max(1, defender.tiles)
		cost *= 1 + density * Config.DEFENSE_DENSITY_K
		cost *= Doctrines.get(defender.doctrine).defense
		cost *= Eras.accumulate(defender.era).defense
	else
		cost *= Config.NEUTRAL_COST_MULT
	end

	-- Aura des bunkers.
	cost *= 1 + buffer.readu8(self.defense, index) / 100

	cost /= self:doctrineOf(attackerSlot).attack

	-- Eloignement du ravitaillement : applique en dernier, apres tous les
	-- modificateurs, pour qu'il plafonne bien le cout total.
	cost *= self:supplyPenalty(attackerSlot, index)

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
	if targetSlot ~= NEUTRAL and not self.combatUnlocked then
		return false, "Les frontieres sont protegees pendant la preparation. Colonise ou construis d'abord."
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
			return true, `Front renforce : {committed} troupes supplementaires.`
		end
	end

	local active = 0
	for _, atk in self.attacks do
		if atk.attacker == attackerSlot then
			active += 1
		end
	end
	if active >= Config.MAX_ACTIVE_ATTACKS_PER_PLAYER then
		return false, `Tu diriges deja {active} offensives. Termine ou renforce un front existant.`
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
	attacker.attacksLaunched += 1

	-- L'assaillant voit la confirmation via la reponse a son ordre. La victime
	-- humaine, elle, doit etre avertie immediatement : attendre la premiere
	-- perte de tuile rendait les guerres impossibles a anticiper.
	local defender = self.players[targetSlot]
	if targetSlot ~= NEUTRAL and defender and not defender.isBot then
		self:notify(`⚔ {attacker.name} ouvre un front contre toi !`, "bad", targetSlot)
		self:sound("attackLaunch", targetSlot)
	end
	return true, `Offensive lancee : {committed} troupes engagees.`
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
		local era = Eras.accumulate(ps.era)

		local maxTroops = self:maxTroops(ps)
		if ps.troops < maxTroops then
			local gain = math.max(Config.MIN_GROWTH, (maxTroops - ps.troops) * Config.GROWTH_RATE)
			local humanGrowth = if ps.isBot then 1 else Config.HUMAN_GROWTH_MULTIPLIER
			ps.troops = math.min(maxTroops, ps.troops + gain * doctrine.growth * era.growth * humanGrowth)
		end

		local _, logisticsIncome = self:logisticsFor(ps.slot)
		local territorial = ps.tiles ^ Config.GOLD_TILE_EXPONENT * Config.GOLD_TILE_SCALE
		local income = territorial
			+ ps.cityGoldBonus
			+ logisticsIncome
			+ ps.portCount * Config.GOLD_PER_PORT
			+ ps.capitalCount * Config.GOLD_PER_CAPITAL
			+ self:tradePartners(ps) * Config.TRADE_GOLD_PER_PARTNER
		local modeGold = if self.mode then self.mode.goldMultiplier else 1
		local humanGold = if ps.isBot then 1 else Config.HUMAN_GOLD_MULTIPLIER
		ps.gold += income * doctrine.goldRate * era.gold * modeGold * humanGold
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
			level = if building then building.level else 0,
			links = if building then building.links else nil,
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
