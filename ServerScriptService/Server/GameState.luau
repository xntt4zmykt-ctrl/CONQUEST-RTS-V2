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
local Heap = require(ReplicatedStorage.Shared.Heap)

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
	-- Somme des niveaux des ports. Distincte de `portCount`, qui reste un
	-- decompte d'unites : c'est elle qui pilote le revenu, pour qu'un port de
	-- niveau 3 rapporte comme trois ports sans compter comme trois pour les
	-- conditions d'ere.
	portLevels: number,
	siloCount: number,
	samCount: number,
	capitalCount: number,
	capitalTile: number?,
	-- Reseau ferroviaire, recalcule a chaque changement de batiment et jamais
	-- dans la boucle de tick.
	railRoutes: number,
	railIncome: number,
	-- Ere technologique atteinte, et compte par type de batiment. Le second
	-- sert a la fois aux conditions d'ere et a l'inflation des couts.
	era: number,
	buildingCounts: { [number]: number },
	betrayals: number,
	traitorUntil: number,
	-- Qui nous a frappe recemment : slot -> tick d'expiration de la rancune.
	-- C'est la seule memoire qu'une faction garde d'une autre.
	grudges: { [number]: number },
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
	-- File de priorite des tuiles au contact, pas un ensemble : c'est elle qui
	-- decide de la FORME que prend l'avancee. Voir enqueueFront.
	frontier: Heap.Heap,
	-- Tuiles deja dans la file. Une meme tuile est atteinte par plusieurs
	-- voisins ; sans ce garde elle serait empilee autant de fois.
	queued: { [number]: true },
	-- Tick a partir duquel le front se degage, si la retraite a ete ordonnee.
	retreatAt: number?,
	-- Ancre de visee (AimFront) ou tuile debarquee (BoatFront). Nil = front terre non vise.
	sourceTile: number?,
	aimX: number?,
	aimY: number?,
	-- True seulement pour une tete de pont navale : ne se fusionne jamais avec un front terre.
	isBeachhead: boolean?,
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
	-- Ogive issue d'une scission de MIRV : porte sa propre puissance, car
	-- NUKE_STATS decrit le missile lance, pas les ogives qu'il libere.
	warhead: boolean?,
	radius: number?,
	troopKill: number?,
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
		-- Valeur = tick d'expiration du pacte. Les alliances ne sont pas
		-- permanentes : voir Config.ALLIANCE_DURATION.
		alliances: { [number]: { [number]: number } },
		-- Fin de la carence apres la rupture ou l'expiration d'un pacte.
		allianceCooldowns: { [number]: { [number]: number } },
		requests: { [number]: { [number]: number } }, -- from -> to -> expiry tick
		embargoes: { [number]: { [number]: true } },
		-- Cibles designees pour l'alliance : marqueur -> faction marquee.
		targetMarks: { [number]: number },
		quickChatSent: { [number]: number },
		-- Dernier message emis par faction, pour ne pas radoter le meme.
		quickChatLast: { [number]: string },
		dirty: { [number]: true },
		buildingDirty: { [number]: true },
		freeSlots: { number },
		nextEntityId: number,
		capitalEvents: number,
		sounds: { { name: string, only: number? } },
		-- Butins de mise a mort en attente d'envoi : le client en fait un
		-- "+X or" flottant sur le dernier territoire de la victime.
		plunders: { { tile: number, slot: number, gold: number } },
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
-- Troisieme tampon : frontPriority est appele depuis la boucle de stepAttacks,
-- qui itere deja sur `scratch`. Le partager ecraserait la liste en cours.
local priorityScratch = table.create(4, 0)

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
	self.allianceCooldowns = {}
	-- Intentions de prolongation, marquees par chaque camp : le pacte n'est
	-- repousse que quand les deux directions sont presentes.
	self.allianceExtensions = {}
	self.requests = {}
	self.embargoes = {}
	-- Cibles designees pour l'alliance : marqueur -> faction marquee. Voir
	-- Diplomacy.setTargetMark et le message rapide "Attaquez {target}".
	self.targetMarks = {}
	-- Anti-spam des messages rapides : dernier tick d'envoi par faction.
	self.quickChatSent = {}
	self.quickChatLast = {}
	self.dirty = {}
	self.buildingDirty = {}
	self.nextEntityId = 1
	self.capitalEvents = 0
	self.sounds = {}
	self.plunders = {}
	self.events = {}
	-- Commerce terrestre : un colis en route par usine, et le tick de reprise
	-- apres livraison. Cles : index de tuile de l'usine. Voir Trade.luau.
	self.tradeDeliveries = {}
	self.tradeCooldowns = {}
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
		ps.portLevels += sign * (level or 1)
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

--[[
	Recalcule le reseau ferroviaire d'une faction.

	Ce qui a change, et pourquoi c'est le changement le plus profond de ce
	systeme : une usine ne desservait qu'une liste de villes, en etoile. Poser
	une usine ajoutait k liaisons independantes, et le placement se resumait a
	compter les villes dans un cercle.

	Maintenant les usines, villes, capitales et ports sont des **gares**, et deux
	gares a portee l'une de l'autre sont reliees. Les liaisons forment des
	grappes connexes ; une grappe ne produit que si elle contient au moins une
	usine. Consequence en jeu : une usine posee au bon endroit **fusionne deux
	grappes** et debloque d'un coup toutes leurs destinations. Le placement
	devient une lecture de carte au lieu d'une optimisation locale.

	Cout : O(gares^2) par recalcul, avec quelques dizaines de gares au plus, et
	uniquement quand un batiment change de main, apparait ou disparait. La
	boucle de tick ne recalcule plus rien — elle lit `ps.railRoutes` et
	`ps.railIncome`.
]]
function GameState.refreshRailNetwork(self: GameState, slot: number)
	local ps = self.players[slot]
	if not ps then
		return
	end

	-- 1. Collecte des gares.
	local stations: { number } = {}
	for index, building in self.buildings do
		if
			building.slot == slot
			and (
				building.kind == B.CITY
				or building.kind == B.CAPITAL
				or building.kind == B.PORT
				or building.kind == B.FACTORY
			)
		then
			table.insert(stations, index)
		end
	end
	-- L'ordre d'iteration d'une table Luau n'est pas garanti : sans tri, la
	-- composition des grappes et donc les liens repliques changeraient a chaque
	-- recalcul et satureraient la replication.
	table.sort(stations)

	local count = #stations
	local range2 = Config.RAIL_RANGE * Config.RAIL_RANGE

	-- 2. Union-find sur les gares a portee. `parent` indexe la position dans
	-- `stations`, pas la tuile : les indices de tuile sont trop epars.
	local parent = table.create(count, 0)
	for i = 1, count do
		parent[i] = i
	end

	local function find(i: number): number
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end

	local xs = table.create(count, 0)
	local ys = table.create(count, 0)
	for i, index in stations do
		xs[i], ys[i] = MapGen.fromIndex(index)
	end

	-- Liens par gare, pour l'affichage des voies cote client.
	local neighborsOf: { { number } } = table.create(count)
	for i = 1, count do
		neighborsOf[i] = {}
	end

	for i = 1, count do
		for j = i + 1, count do
			local dx, dy = xs[i] - xs[j], ys[i] - ys[j]
			if dx * dx + dy * dy <= range2 then
				table.insert(neighborsOf[i], stations[j])
				table.insert(neighborsOf[j], stations[i])
				local ri, rj = find(i), find(j)
				if ri ~= rj then
					parent[ri] = rj
				end
			end
		end
	end

	-- 3. Taille de la grappe, et usines qu'elle contient : une grappe ne
	-- produit que si elle contient au moins une usine.
	local clusterStations: { [number]: number } = {}
	local clusterFactoryCount: { [number]: number } = {}
	for i = 1, count do
		local root = find(i)
		clusterStations[root] = (clusterStations[root] or 0) + 1
		local building = self.buildings[stations[i]]
		if building and building.kind == B.FACTORY then
			clusterFactoryCount[root] = (clusterFactoryCount[root] or 0) + 1
		end
	end

	--[[
		4. Revenu ESTIME. L'or reel n'est plus verse au tick : il arrive colis
		par colis, voir Trade. Ce qui suit n'est que l'esperance mathematique
		du debit de chaque usine, pour que le "+x/s" du HUD reste honnete.

		Le nombre de liaisons d'une grappe reste son arbre couvrant (gares - 1)
		et non ses paires possibles : sinon dix gares compteraient quarante-cinq
		routes et l'affichage mentirait autant que l'ancienne economie.
	]]
	local routes = 0
	for root, stationCount in clusterStations do
		if (clusterFactoryCount[root] or 0) > 0 and stationCount > 1 then
			routes += stationCount - 1
		end
	end

	local income = 0
	for i = 1, count do
		local building = self.buildings[stations[i]]
		local links = neighborsOf[i]
		if building and building.kind == B.FACTORY and #links > 0 then
			-- Esperance par colis : tirage uniforme sur les liaisons, distance
			-- ponderee par le niveau, chargement proportionnel au reseau.
			-- Periode : trajet + rechargement.
			local goldSum = 0
			local periodSum = 0
			local fx, fy = MapGen.fromIndex(stations[i])
			for _, other in links do
				local ox, oy = MapGen.fromIndex(other)
				local dx, dy = fx - ox, fy - oy
				local d = math.sqrt(dx * dx + dy * dy)
				goldSum += Config.TRUCK_GOLD_BASE + d * Config.TRUCK_GOLD_PER_TILE
				periodSum += math.max(1, math.ceil(d / Config.TRUCK_SPEED)) + Config.TRUCK_COOLDOWN
			end
			local n = #links
			income += (goldSum * building.level) / (periodSum / n)
		end
	end

	ps.railRoutes = routes
	ps.railIncome = income

	-- 5. Liens repliques. Seules les usines portent des voies visibles : dessiner
	-- chaque arete deux fois doublerait la geometrie pour rien.
	for i = 1, count do
		local index = stations[i]
		local building = self.buildings[index]
		if building and building.kind == B.FACTORY then
			local links = neighborsOf[i]
			table.sort(links)

			local changed = #links ~= #building.links
			if not changed then
				for k, other in links do
					if building.links[k] ~= other then
						changed = true
						break
					end
				end
			end

			if changed then
				building.links = links
				self.buildingDirty[index] = true
			end
		end
	end
end

-- Ancien nom, conserve : les appelants ne savent pas qu'un reseau a remplace
-- des routes en etoile, et n'ont pas besoin de le savoir.
GameState.refreshFactoryLinks = GameState.refreshRailNetwork

--[[
	Etat courant du reseau : (liaisons, or par tick).

	Simple lecture d'un cache. Avant, cette fonction balayait tous les batiments
	a chaque appel — et elle etait appelee une fois par joueur et par tick dans
	l'economie, plus une fois par joueur dans la replication.
]]
function GameState.logisticsFor(self: GameState, slot: number): (number, number)
	local ps = self.players[slot]
	if not ps then
		return 0, 0
	end
	return ps.railRoutes, ps.railIncome
end

-- Types de batiments qui font partie du reseau ferroviaire. Toute modification
-- de l'un d'eux invalide les grappes du proprietaire.
local IS_STATION = {
	[B.CITY] = true,
	[B.CAPITAL] = true,
	[B.PORT] = true,
	[B.FACTORY] = true,
}

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
	if IS_STATION[kind] then
		self:refreshRailNetwork(slot)
	end
end

--[[
	Fait monter un batiment d'un niveau.

	Generique : la ville a ses paliers nommes, le port et l'usine un simple
	multiplicateur. Les autres types n'ont pas de niveau superieur — cliquer a
	cote d'un bunker existant pose un second bunker, ce qui est le comportement
	attendu pour un batiment dont l'effet est une aire et non une intensite.
]]
function GameState.upgradeBuilding(self: GameState, index: number): number?
	local building = self.buildings[index]
	if not building or not BuildingDefs.isUpgradable(building.kind) then
		return nil
	end
	if building.level >= BuildingDefs.maxLevel(building.kind) then
		return nil
	end

	self:countBuilding(building.slot, building.kind, -1, building.level)
	building.level += 1
	self:countBuilding(building.slot, building.kind, 1, building.level)
	self.buildingDirty[index] = true

	-- Le niveau d'une usine pese sur le rendement de sa grappe.
	if building.kind == B.FACTORY then
		self:refreshRailNetwork(building.slot)
	end
	return building.level
end

-- Ancien nom : le banc d'essai et les bots l'appellent encore.
GameState.upgradeCity = GameState.upgradeBuilding

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
	if IS_STATION[building.kind] then
		self:refreshRailNetwork(previousSlot)
		self:refreshRailNetwork(newSlot)
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
	if IS_STATION[previousKind] then
		self:refreshRailNetwork(previousSlot)
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
		portLevels = 0,
		siloCount = 0,
		samCount = 0,
		capitalCount = 0,
		capitalTile = nil,
		railRoutes = 0,
		railIncome = 0,
		era = 1,
		buildingCounts = {},
		betrayals = betrayals,
		traitorUntil = 0,
		grudges = {},
		capturedTiles = 0,
		lostTiles = 0,
		capitalsCaptured = 0,
		buildingsBuilt = 0,
		attacksLaunched = 0,
	}
	self.players[slot] = state
	self.alliances[slot] = {}
	self.allianceCooldowns[slot] = {}
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

	-- Detruire d'abord les structures : setOwner transfere sinon vers NEUTRAL.
	for index, building in self.buildings do
		if building.slot == slot then
			self:destroyBuilding(index)
		end
	end

	-- Passer par setOwner pour rafraichir border/coast des voisins. Rare
	-- (deconnexion), jamais dans la boucle de tick.
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(self.owner, index) == slot then
			self:setOwner(index, NEUTRAL)
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
	for _, other in self.players do
		other.grudges[slot] = nil
	end
	for _, set in self.allianceCooldowns do
		set[slot] = nil
	end
	self.allianceCooldowns[slot] = nil
	self.requests[slot] = nil
	self.embargoes[slot] = nil

	self.players[slot] = nil
	table.insert(self.freeSlots, slot)
end

--=============================================================================
-- Offensives
--=============================================================================

--[[
	Cette faction en veut-elle encore a celle-la ?

	La lecture purge au passage : une rancune expiree est retiree plutot que
	laissee a trainer. Sans cela la table ne se viderait jamais, et un bot
	garderait rancune a une faction disparue depuis longtemps.
]]
function GameState.holdsGrudge(self: GameState, slot: number, against: number): boolean
	local ps = self.players[slot]
	if not ps then
		return false
	end
	local until_ = ps.grudges[against]
	if not until_ then
		return false
	end
	if self.tick >= until_ then
		ps.grudges[against] = nil
		return false
	end
	return true
end

function GameState.areAllied(self: GameState, a: number, b: number): boolean
	local ab = self.alliances[a]
	local ba = self.alliances[b]
	return ab ~= nil and ab[b] ~= nil and ba ~= nil and ba[a] ~= nil
end

--=============================================================================
-- Frein a l'emballement
--=============================================================================

--[[
	Taille a partir de laquelle un empire compte comme "grand", en tuiles.

	Exprimee en part des terres et non en valeur absolue : la meme regle doit
	fonctionner sur une carte a 15 000 tuiles de terre et sur une carte deux fois
	plus grande.
]]
function GameState.largeEmpireMidpoint(self: GameState): number
	return math.max(1, self.landCount * Config.LARGE_EMPIRE_MIDPOINT_RATIO)
end

local function sigmoid(x: number, k: number, midpoint: number): number
	return 1 / (1 + math.exp(-k * (x - midpoint)))
end

--[[
	Multiplicateur de defense d'une faction selon sa taille.

	Vaut 1 pour un petit empire et descend vers LARGE_DEFENDER_FLOOR pour un
	empire immense. C'est la piece maitresse du frein a l'emballement : le geant
	n'est pas empeche de grossir, il devient **une cible**. Un empire qui tient
	la moitie de la carte defend chaque tuile 30 % moins bien que son voisin a
	trois cents tuiles, ce qui donne enfin une raison mecanique de l'attaquer.

	La transition est une sigmoide, donc continue : aucun palier a partir duquel
	un joueur "bascule", rien a optimiser en restant juste en dessous d'un seuil.
]]
function GameState.sizeDefenseFactor(self: GameState, ps: PlayerState): number
	local midpoint = self:largeEmpireMidpoint()
	local k = math.log(2) / math.max(1, midpoint * Config.LARGE_EMPIRE_SPREAD)
	local small = 1 - sigmoid(ps.tiles, k, midpoint)
	local floor = Config.LARGE_DEFENDER_FLOOR
	return floor + (1 - floor) * small
end

--[[
	Ralentissement de conquete d'un gros attaquant, et sa compensation.

	Renvoie (facteur de vitesse, facteur de cout), tous deux dans ]0, 1].

	Le second point est ce qui rend la regle jouable. Punir le geant sur les deux
	tableaux — plus lent *et* plus cher — reviendrait a faire du jeu une course a
	rester deuxieme, et un joueur qui prend l'avantage n'aurait plus qu'a subir.
	Ici il conquiert moins cher en troupes mais nettement moins vite : son
	avance se paie en temps, pas en impuissance, et ce temps est exactement ce
	qu'il faut aux autres pour reagir.
]]
function GameState.sizeAttackFactors(self: GameState, ps: PlayerState): (number, number)
	local threshold = self:largeEmpireMidpoint() * Config.LARGE_ATTACKER_THRESHOLD_RATIO
	if ps.tiles <= threshold then
		return 1, 1
	end

	local ratio = threshold / ps.tiles
	local speed = math.max(Config.LARGE_ATTACKER_SPEED_FLOOR, ratio ^ Config.LARGE_ATTACKER_SPEED_EXPONENT)
	local cost = ratio ^ Config.LARGE_ATTACKER_COST_EXPONENT
	return speed, cost
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
		cost *= Eras.accumulate(defender.era).defense
		-- Un empire immense defend moins bien chaque tuile : voir
		-- sizeDefenseFactor. C'est ce qui fait du leader une cible.
		cost *= self:sizeDefenseFactor(defender)
	else
		cost *= Config.NEUTRAL_COST_MULT
	end

	-- Aura des bunkers.
	cost *= 1 + buffer.readu8(self.defense, index) / 100

	cost /= self:doctrineOf(attackerSlot).attack

	-- Compensation du gros attaquant : il paie moins par tuile, mais il avance
	-- beaucoup plus lentement (applique dans stepAttacks).
	local attacker = self.players[attackerSlot]
	if attacker then
		local _, costFactor = self:sizeAttackFactors(attacker)
		cost *= costFactor
	end

	return cost
end

--[[
	Ordre d'attaque d'une tuile — c'est ici que se joue la FORME du front.

	Le probleme corrige : la file etait un ensemble, et le moteur piochait dedans
	avec `next()`, dont l'ordre est arbitraire. Une offensive grignotait donc des
	cases sans rapport les unes avec les autres, partout le long du contact — ce
	qui donne l'impression que le jeu prend des blocs au hasard, parce que c'est
	exactement ce qu'il faisait.

	Trois termes, propres a CONQUEST, et chacun produit un comportement
	que le joueur peut lire sur la carte :

	  - **`+ tick`** — une tuile entree tot dans la file passe avant une tuile
	    entree tard. A lui seul ce terme transforme le grignotage en VAGUE : le
	    front avance de proche en proche au lieu de sauter.

	  - **`- voisinsAMoi * 0.5`** — une tuile deja entouree passe en premier. Les
	    poches et les enclaves sont donc avalees avant que le front ne pousse
	    plus loin, ce qui donne des territoires d'un seul tenant plutot qu'une
	    dentelle.

	  - **`+ rugosite / 2`** — le relief difficile est conquis en dernier. Une
	    offensive contourne naturellement une montagne au lieu de s'y jeter.

	Le bruit deterministe (0 a 7) casse les egalites. Sans lui, des tuiles de
	meme score seraient depilees dans l'ordre d'insertion et le front avancerait
	en ligne parfaitement droite, ce qui se voit tout autant.
]]
local function frontPriority(self: GameState, index: number, attackerSlot: number): number
	local n = MapGen.neighbors(index, priorityScratch)
	local owned = 0
	for i = 1, n do
		if buffer.readu8(self.owner, priorityScratch[i]) == attackerSlot then
			owned += 1
		end
	end

	local terrain = buffer.readu8(self.terrain, index)
	local roughness = Config.TERRAIN_COST[terrain] or 1

	-- Bruit tire de la tuile et du tick plutot que d'un generateur partage : la
	-- valeur reste identique sur deux serveurs partis de la meme graine, sans
	-- avoir a faire circuler un etat aleatoire jusqu'ici.
	local noise = (index * 2654435761 + self.tick * 40503) % 8

	return (noise + 10) * (1 - owned * 0.5 + roughness / 2) + self.tick
end

--[[
	Ajoute une tuile au front, si elle n'y est pas deja.
]]
local function enqueueFront(self: GameState, atk: Attack, index: number)
	if atk.queued[index] then
		return
	end
	atk.queued[index] = true
	Heap.push(atk.frontier, index, frontPriority(self, index, atk.attacker))
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

	local attack: Attack = {
		attacker = attackerSlot,
		target = targetSlot,
		troops = committed,
		frontier = Heap.new(),
		queued = {},
	}

	for index in attacker.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if buffer.readu8(self.owner, nb) == targetSlot and self:isLand(nb) then
				enqueueFront(self, attack, nb)
			end
		end
	end

	if Heap.isEmpty(attack.frontier) then
		return false, "Aucun contact terrestre. Passe par la mer."
	end

	attacker.troops -= committed
	table.insert(self.attacks, attack)
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
	Rappelle une offensive en cours, regle CONQUEST : l'ordre n'est pas
	honore immediatement mais apres un delai (RETREAT_DELAY ticks), pendant
	lequel le front continue de se battre. Une retraite instantanee ferait de
	chaque engagement un essai sans risque ; le delai rend la decision
	couteuse a prendre, et les survivants rentrent ensuite au pays.
]]
function GameState.retreatAttack(self: GameState, attackerSlot: number, targetSlot: number): (boolean, string?)
	for _, atk in self.attacks do
		if atk.attacker == attackerSlot and atk.target == targetSlot then
			if atk.retreatAt then
				return false, "La retraite est deja ordonnee."
			end
			atk.retreatAt = self.tick + Config.RETREAT_DELAY
			return true, "Retraite ordonnee : le front se degage."
		end
	end
	return false, "Aucune offensive sur ce front."
end

--[[
	Cree une tete de pont apres un debarquement : l'offensive demarre depuis une
	tuile isolee, sans contact terrestre prealable.
]]
function GameState.seedBeachhead(self: GameState, attackerSlot: number, targetSlot: number, troops: number, tile: number)
	for _, atk in self.attacks do
		if atk.attacker == attackerSlot and atk.target == targetSlot then
			atk.troops += troops
			enqueueFront(self, atk, tile)
			return
		end
	end

	local attack: Attack = {
		attacker = attackerSlot,
		target = targetSlot,
		troops = troops,
		frontier = Heap.new(),
		queued = {},
	}
	enqueueFront(self, attack, tile)
	table.insert(self.attacks, attack)
end

--[[
	Seuil d'effondrement, en tuiles.

	Sous ce seuil une faction attaquee ne se defend plus : elle est repartie
	entre ses voisins. Sans cette regle la carte se termine avec des factions a
	trois tuiles qui ne peuvent plus rien faire mais ne meurent jamais — la
	simulation en produisait quatre a la fois, et c'est exactement ce qui vidait
	le milieu de partie.
]]
function GameState.collapseThreshold(self: GameState): number
	return math.max(Config.COLLAPSE_MIN_TILES, self.landCount * Config.COLLAPSE_TILE_RATIO)
end

--[[
	Demantele une faction agonisante.

	Les tuiles au contact de l'assaillant lui reviennent ; celles qui ne
	touchent que d'autres voisins hostiles vont a ces voisins. On repete jusqu'a
	ce que plus rien ne bouge : une poche isolee au milieu du territoire d'un
	tiers lui revient donc, ce qui evite les enclaves fantomes.

	Un balayage complet de la carte, mais une seule fois dans la vie d'une
	faction : c'est le seul endroit du moteur ou l'on n'a pas de liste de tuiles
	par joueur, et en construire une en permanence couterait bien plus cher que
	ce balayage ponctuel.
]]
function GameState.collapseFaction(self: GameState, victimSlot: number, captorSlot: number)
	local remaining: { number } = {}
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(self.owner, index) == victimSlot then
			table.insert(remaining, index)
		end
	end
	if #remaining == 0 then
		return
	end

	--[[
		Le butin se prend AVANT le demantelement.

		Une fois les tuiles redistribuees, la victime n'a plus de territoire ou
		afficher le "+X or" — et `stepElimination` peut l'avoir supprimee du
		tableau des joueurs au meme tick. On saisit donc l'or et le lieu pendant
		qu'ils existent encore.
	]]
	local victim = self.players[victimSlot]
	local captor = self.players[captorSlot]
	if victim and captor and victim.gold > 0 then
		local share = if victim.isBot then Config.CONQUEST_PLUNDER_BOT else Config.CONQUEST_PLUNDER_HUMAN
		local loot = math.floor(victim.gold * share)
		if loot > 0 then
			victim.gold -= loot
			captor.gold += loot
			-- La capitale si elle tient encore, sinon n'importe quelle tuile
			-- restante : l'important est que le chiffre apparaisse SUR la
			-- depouille, pas au milieu de nulle part.
			local where = victim.capitalTile
			if not where or buffer.readu8(self.owner, where) ~= victimSlot then
				where = remaining[1]
			end
			table.insert(self.plunders, { tile = where, slot = captorSlot, gold = loot })
		end
	end

	local collapseScratch = table.create(4, 0)

	for _ = 1, Config.COLLAPSE_MAX_PASSES do
		local leftovers: { number } = {}
		local progressed = false

		for _, index in remaining do
			if buffer.readu8(self.owner, index) ~= victimSlot then
				continue
			end

			local n = MapGen.neighbors(index, collapseScratch)
			local heir = NEUTRAL
			for i = 1, n do
				local nb = collapseScratch[i]
				local owner = buffer.readu8(self.owner, nb)
				if owner == captorSlot then
					heir = captorSlot
					break
				end
				if
					heir == NEUTRAL
					and owner ~= NEUTRAL
					and owner ~= victimSlot
					and self.players[owner]
					and not self:areAllied(owner, victimSlot)
				then
					heir = owner
				end
			end

			if heir ~= NEUTRAL then
				self:setOwner(index, heir)
				progressed = true
			else
				table.insert(leftovers, index)
			end
		end

		remaining = leftovers
		if #remaining == 0 or not progressed then
			break
		end
	end

	-- Ce qui n'a aucun voisin hostile — une ile, une enclave alliee — retourne
	-- au neutre plutot que de rester la propriete d'un mort.
	for _, index in remaining do
		if buffer.readu8(self.owner, index) == victimSlot then
			self:setOwner(index, NEUTRAL)
		end
	end
end

function GameState.stepAttacks(self: GameState)
	local collapsing: { { victim: number, captor: number } } = {}

	for i = #self.attacks, 1, -1 do
		local atk = self.attacks[i]
		local attacker = self.players[atk.attacker]
		local defender = if atk.target ~= NEUTRAL then self.players[atk.target] else nil

		if not attacker or (atk.target ~= NEUTRAL and not defender) then
			table.remove(self.attacks, i)
			continue
		end

		-- Le delai de retraite est ecoule : les survivants rentrent au pays,
		-- comme lorsqu'un front s'epuise naturellement.
		if atk.retreatAt and self.tick >= atk.retreatAt then
			attacker.troops += math.max(0, atk.troops)
			table.remove(self.attacks, i)
			continue
		end

		-- Un empire immense avance beaucoup plus lentement : son avance se paie
		-- en temps. Voir sizeAttackFactors.
		local speedFactor = select(1, self:sizeAttackFactors(attacker))
		local budget = atk.troops * Config.ATTACK_SPEND_RATE * speedFactor
		local tileLimit = math.max(1, math.floor(Config.MAX_TILES_PER_TICK * speedFactor))
		local captured = 0
		local spent = 0

		while spent < budget and captured < tileLimit do
			local index = Heap.pop(atk.frontier)
			if not index then
				break
			end
			atk.queued[index] = nil

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
				--[[
					La victime retient qui l'a frappee.

					Ecrit a chaque tuile prise plutot qu'une fois par offensive :
					c'est une seule ecriture dans une table de moins de douze
					entrees, et cela garde la rancune fraiche tant que le front
					avance — une offensive longue ne doit pas s'oublier en cours
					de route.
				]]
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

		-- Effondrement : des que le defenseur passe sous le seuil, il cesse
		-- d'exister comme puissance. On enregistre pour traiter apres la boucle,
		-- parce que collapseFaction appelle setOwner en masse et invaliderait
		-- les frontieres qu'on est en train de parcourir.
		if defender and defender.tiles > 0 and defender.tiles < self:collapseThreshold() then
			table.insert(collapsing, { victim = atk.target, captor = atk.attacker })
		end

		if atk.troops <= 0 or Heap.isEmpty(atk.frontier) then
			attacker.troops += math.max(0, atk.troops) -- les survivants rentrent
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
end

--=============================================================================
-- Population et economie
--=============================================================================

--[[
	Plafond de troupes.

	La part territoriale est sous-lineaire, la part urbaine ne l'est pas : c'est
	ce couple qui decide de la forme des empires. Voir Config.MAX_TROOPS_TILE_EXPONENT.
]]
function GameState.maxTroops(self: GameState, ps: PlayerState): number
	local fromLand = Config.MAX_TROOPS_TILE_SCALE * ps.tiles ^ Config.MAX_TROOPS_TILE_EXPONENT
	return Config.BASE_MAX_TROOPS + fromLand + ps.cityPopBonus
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

		local territorial = ps.tiles ^ Config.GOLD_TILE_EXPONENT * Config.GOLD_TILE_SCALE
		local income = territorial
			+ ps.cityGoldBonus
			+ ps.portLevels * Config.GOLD_PER_PORT
			+ ps.capitalCount * Config.GOLD_PER_CAPITAL
		-- L'or du commerce n'apparait pas ici : le maritime est verse a
		-- l'arrivee de chaque convoi dans Navy, le terrestre a l'arrivee de
		-- chaque colis dans Trade. Les compter aussi au tick les paierait deux
		-- fois et rendrait piraterie et sabotage sans effet sur le tresor.
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
