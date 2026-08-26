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
	-- True une fois qu'un SAM a choisi ce missile (exclusivite de cible).
	engaged: boolean?,
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
		-- Index O(1) des bunkers par camp. attackLogic (hot path) ne scanne
		-- plus le hash buildings entier (ISSUE-N36 / feel N42). Le buffer
		-- `defense` reste alloue (HUD / tileCost hors install) mais n'est
		-- plus ecrit a la pose (Option A).
		bunkersBySlot: { [number]: { [number]: true } },
		-- Grille spatiale bunkers (ISSUE-N41) : slot -> cellKey -> tuiles.
		-- cell = DEFENSE_RADIUS ; lookup 3x3 par capture, pas le scan lineaire
		-- du camp. Source de verite pose/destroy = bunkersBySlot ; cette grille
		-- est un index. Pas le buffer `defense` (plus ecrit).
		bunkerCells: { [number]: { [number]: { [number]: true } } },
		-- Index PORT (ISSUE-N40) : spawnTradeShips n'a plus a parcourir
		-- buildings. Distinct de `_carriersDirty` (NAVAL_BASE seulement).
		portsByTile: { [number]: { slot: number, level: number } },
		-- Index SAM par camp (ISSUE-N42 / feel N57). tryIntercept et samsOf
		-- n'iterent plus le hash buildings. Pose/destroy/transfer seulement.
		samsBySlot: { [number]: { [number]: true } },
		-- Index SILO par camp (ISSUE-N44 / feel N60). Nukes.launch n'itere plus
		-- le hash buildings. Pose/destroy/transfer seulement. Distinct de
		-- coolingBuildings (N43) : ici c'est le choix du lanceur, pas le tick.
		silosBySlot: { [number]: { [number]: true } },
		-- Index FACTORY (ISSUE-N45). Trade.step n'itere plus buildings a 10 Hz.
		-- Recette portsByTile : pose/destroy/transfer/upgrade FACTORY seulement.
		factoriesByTile: { [number]: { slot: number, level: number } },
		-- Tous les batiments par camp (ISSUE-N46 / feel N62). Bots upgrade
		-- et score nuke n'iterent plus le hash global. Distinct des index
		-- par kind (bunkers/sams/silos/factories) : ici c'est tous kinds.
		buildingsBySlot: { [number]: { [number]: true } },
		-- Index NAVAL_BASE par camp (ISSUE-N48 / feel N65). syncCarriers
		-- spawn n'itere plus le hash buildings. Distinct de portsByTile
		-- (PORT) et de buildingsBySlot (tous kinds). Garde _carriersDirty :
		-- pas un scan 10 Hz.
		navalBasesBySlot: { [number]: { [number]: true } },
		-- Batiments dont cooldown > 0 (ISSUE-N43). stepCooldowns n'itere plus
		-- tout buildings a 10 Hz. SAM et silos seulement en pratique.
		coolingBuildings: { [number]: true },
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
		-- Navy.syncCarriers : leve par place/destroy/transfer NAVAL_BASE
		-- seulement (ISSUE-N34). Pas de scan O(buildings) a 10 Hz a vide.
		_carriersDirty: boolean,
		-- Snapshot humain elimine (removePlayer) pour Persistence.record
		-- a endMatch / disconnect. Sans ca les elimines n'ont ni defaite ni XP
		-- (ISSUE-N37 / feel N40).
		settledHumans: {
			[number]: {
				player: Player?,
				betrayals: number,
				capturedTiles: number,
				capitalsCaptured: number,
				buildingsBuilt: number,
			},
		},
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
-- N51 : UnitSnapshot bateaux recycle (recette factoriesBuf / N45, feel N70).
-- Inner payloads reecrits, pas recrees. Non reentrant — replicate() unique
-- / tick. Pas de champ retreating (feel N56) : Overlay de cette ligne
-- ne le lit pas (Types.BoatSnapshot, client 34/34).
local boatSnapBuf: {
	{
		id: number,
		slot: number,
		x: number,
		y: number,
		troops: number,
		kind: number,
	}
} =
	table.create(48)
-- N52 : UnitSnapshot missiles recycle (recette boatSnapBuf / N51, feel N71).
-- Champs uniquement Types.MissileSnapshot — pas sx/sy/progress/speed.
local missileSnapBuf: {
	{
		id: number,
		slot: number,
		x: number,
		y: number,
		tx: number,
		ty: number,
		kind: number,
	}
} =
	table.create(16)
-- N53 : indices dirty pour flushOwnerDelta. Le buffer outbound reste neuf
-- (RemoteEvent). Early-out dirty vide sans allouer.
local dirtyIndexBuf: { number } = table.create(64)
-- N54 : BuildingDelta recycle (recette missileSnapBuf / N52, feel N73).
-- Inner records reecrits, pas recrees. `links` = reference live (pas clone).
-- Non reentrant — un seul flushBuildingDelta par tick. Early-out dirty
-- vide sans allouer.
local buildingSnapBuf: {
	{
		index: number,
		kind: number,
		slot: number,
		level: number,
		links: { number }?,
	}
} =
	table.create(16)
-- N55 : HUD fronts recycle (recette N52, helper GameState car init.server
-- hors bundle). Slots sans front absents (nil, pas {}). Inner listes via
-- attackTargetPool. Non reentrant — replicate() unique / tick.
local activeAttackBuf: { [number]: number } = {}
local committedTroopBuf: { [number]: number } = {}
local attackTargetBuf: { [number]: { number } } = {}
local attackTargetPool: { [number]: { number } } = {}
-- N57 : records PlayerStats recyclees (recette N55, feel N76). eraProgress /
-- buildPrices restent nil ici — init.server les pose (Research / Buildings
-- require GameState). Slots sans joueur absents. Non reentrant.
type StatsRec = {
	troops: number,
	tiles: number,
	gold: number,
	maxTroops: number,
	era: number,
	eraProgress: number?,
	capturedTiles: number,
	lostTiles: number,
	capitalsCaptured: number,
	buildingsBuilt: number,
	attacksLaunched: number,
	activeAttacks: number,
	committedTroops: number,
	attackTargets: { number }?,
	buildPrices: { [number]: number }?,
	logisticsRoutes: number,
	logisticsIncome: number,
}
local statsBuf: { [number]: StatsRec } = {}
local statsRecPool: { [number]: StatsRec } = {}
-- N63 : slots elimines recycles (recette boatSnapBuf / N51, feel N82).
-- Partage entre toutes les instances GameState — truncate leftover
-- obligatoire. Ne pas nommer `doomed` : removePlayer a deja un snapshot
-- batiments. Non reentrant — step() unique / tick. Ne pas truncate a 0
-- apres return.
local elimBuf: { number } = table.create(8)
-- N65 : porteuses refreshRailNetwork (recette N62 truncate-avant-sort,
-- feel b62d/69f4 N84). Les inners neighborsOf deviennent building.links
-- — uniques, pas poolees. Non reentrant — un seul refresh par mutation.
-- Ne pas referencer IS_STATION (local trop bas, nil au runtime — piege N47).
local stationBuf: { number } = table.create(32)
local railParentBuf: { number } = table.create(32)
local railXsBuf: { number } = table.create(32)
local railYsBuf: { number } = table.create(32)
local clusterStations: { [number]: number } = {}
local clusterFactoryCount: { [number]: number } = {}

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
	self.bunkersBySlot = {}
	self.bunkerCells = {}
	self.portsByTile = {}
	self.samsBySlot = {}
	self.silosBySlot = {}
	self.factoriesByTile = {}
	self.buildingsBySlot = {}
	self.navalBasesBySlot = {}
	self.coolingBuildings = {}
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
	self.settledHumans = {}
	-- Ceinture : premier Navy.step synchronise (buildings encore vide).
	-- Ensuite le flag ne se leve que sur une mutation NAVAL_BASE.
	self._carriersDirty = true

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

-- Aura falloff du buffer `defense`. Morte apres ChantierB.install() :
-- attackLogic lit bunkersBySlot (N36), plus ce buffer. Les appels pose/destroy
-- ont ete retires (Option A / feel N45). Conservee pour tileCost hors install.
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

	-- 1. Collecte des gares. N47 : buildingsBySlot[slot], pas le hash global.
	-- Fallback hash si l'index est nil (tests partiels).
	-- IS_STATION est declare plus bas : on inline les kinds ici.
	-- N65 : stationBuf + truncate leftover AVANT sort (un leftover non
	-- truncate melerait d'anciennes gares dans table.sort). Recette feel N84.
	local n = 0
	if self.buildingsBySlot then
		local set = self.buildingsBySlot[slot]
		if set then
			for index in set do
				local building = self.buildings[index]
				if
					building
					and (
						building.kind == B.CITY
						or building.kind == B.CAPITAL
						or building.kind == B.PORT
						or building.kind == B.FACTORY
					)
				then
					n += 1
					stationBuf[n] = index
				end
			end
		end
	else
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
				n += 1
				stationBuf[n] = index
			end
		end
	end
	for i = #stationBuf, n + 1, -1 do
		stationBuf[i] = nil
	end
	-- L'ordre d'iteration d'une table Luau n'est pas garanti : sans tri, la
	-- composition des grappes et donc les liens repliques changeraient a chaque
	-- recalcul et satureraient la replication.
	table.sort(stationBuf)

	local count = n
	local range2 = Config.RAIL_RANGE * Config.RAIL_RANGE

	-- 2. Union-find sur les gares a portee. `parent` indexe la position dans
	-- `stationBuf`, pas la tuile : les indices de tuile sont trop epars.
	-- Iterer 1..count, pas # (leftover parent/xs/ys hors budget).
	for i = 1, count do
		railParentBuf[i] = i
	end

	local function find(i: number): number
		while railParentBuf[i] ~= i do
			railParentBuf[i] = railParentBuf[railParentBuf[i]]
			i = railParentBuf[i]
		end
		return i
	end

	for i = 1, count do
		railXsBuf[i], railYsBuf[i] = MapGen.fromIndex(stationBuf[i])
	end

	-- Liens par gare, pour l'affichage des voies cote client.
	-- N65 : inners uniques (deviennent building.links). Pas de pool partage.
	local neighborsOf: { { number } } = table.create(count)
	for i = 1, count do
		neighborsOf[i] = {}
	end

	for i = 1, count do
		for j = i + 1, count do
			local dx, dy = railXsBuf[i] - railXsBuf[j], railYsBuf[i] - railYsBuf[j]
			if dx * dx + dy * dy <= range2 then
				table.insert(neighborsOf[i], stationBuf[j])
				table.insert(neighborsOf[j], stationBuf[i])
				local ri, rj = find(i), find(j)
				if ri ~= rj then
					railParentBuf[ri] = rj
				end
			end
		end
	end

	-- 3. Taille de la grappe, et usines qu'elle contient : une grappe ne
	-- produit que si elle contient au moins une usine.
	table.clear(clusterStations)
	table.clear(clusterFactoryCount)
	for i = 1, count do
		local root = find(i)
		clusterStations[root] = (clusterStations[root] or 0) + 1
		local building = self.buildings[stationBuf[i]]
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
		local building = self.buildings[stationBuf[i]]
		local links = neighborsOf[i]
		if building and building.kind == B.FACTORY and #links > 0 then
			-- Esperance par colis : tirage uniforme sur les liaisons, distance
			-- ponderee par le niveau, chargement proportionnel au reseau.
			-- Periode : trajet + rechargement.
			local goldSum = 0
			local periodSum = 0
			local fx, fy = MapGen.fromIndex(stationBuf[i])
			for _, other in links do
				local ox, oy = MapGen.fromIndex(other)
				local dx, dy = fx - ox, fy - oy
				local d = math.sqrt(dx * dx + dy * dy)
				goldSum += Config.TRUCK_GOLD_BASE + d * Config.TRUCK_GOLD_PER_TILE
				periodSum += math.max(1, math.ceil(d / Config.TRUCK_SPEED)) + Config.TRUCK_COOLDOWN
			end
			local nLinks = #links
			income += (goldSum * building.level) / (periodSum / nLinks)
		end
	end

	ps.railRoutes = routes
	ps.railIncome = income

	-- 5. Liens repliques. Seules les usines portent des voies visibles : dessiner
	-- chaque arete deux fois doublerait la geometrie pour rien.
	for i = 1, count do
		local index = stationBuf[i]
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

-- Cellule spatiale bunkers (ISSUE-N41). cell = DEFENSE_RADIUS ; une capture
-- ne consulte que 9 seaux. Doit matcher ChantierB.attackLogic.
local function defenseCellKey(index: number): number
	local r = math.max(1, Config.DEFENSE_RADIUS or 30)
	local x, y = MapGen.fromIndex(index)
	return math.floor(y / r) * 1024 + math.floor(x / r)
end

-- Index bunker : pose / capture / destroy seulement, jamais dans le tick.
local function indexBunker(self: GameState, slot: number, index: number, present: boolean)
	local set = self.bunkersBySlot[slot]
	if present then
		if not set then
			set = {}
			self.bunkersBySlot[slot] = set
		end
		set[index] = true
		local cells = self.bunkerCells[slot]
		if not cells then
			cells = {}
			self.bunkerCells[slot] = cells
		end
		local key = defenseCellKey(index)
		local bucket = cells[key]
		if not bucket then
			bucket = {}
			cells[key] = bucket
		end
		bucket[index] = true
	else
		if set then
			set[index] = nil
		end
		local cells = self.bunkerCells[slot]
		if cells then
			local bucket = cells[defenseCellKey(index)]
			if bucket then
				bucket[index] = nil
			end
		end
	end
end

-- Index PORT : spawnTradeShips (ISSUE-N40). Pas _carriersDirty.
local function indexPort(self: GameState, index: number, slot: number, level: number, present: boolean)
	if present then
		self.portsByTile[index] = { slot = slot, level = level }
	else
		self.portsByTile[index] = nil
	end
end

-- Index SAM : tryIntercept / samsOf (ISSUE-N42). Recette bunkersBySlot, sans grille.
local function indexSam(self: GameState, slot: number, index: number, present: boolean)
	local set = self.samsBySlot[slot]
	if present then
		if not set then
			set = {}
			self.samsBySlot[slot] = set
		end
		set[index] = true
	elseif set then
		set[index] = nil
	end
end

-- Index SILO : Nukes.launch (ISSUE-N44). Recette samsBySlot, sans grille.
local function indexSilo(self: GameState, slot: number, index: number, present: boolean)
	local set = self.silosBySlot[slot]
	if present then
		if not set then
			set = {}
			self.silosBySlot[slot] = set
		end
		set[index] = true
	elseif set then
		set[index] = nil
	end
end

-- Index FACTORY : Trade.step (ISSUE-N45). Recette portsByTile, pas _carriersDirty.
local function indexFactory(self: GameState, index: number, slot: number, level: number, present: boolean)
	if present then
		self.factoriesByTile[index] = { slot = slot, level = level }
	else
		self.factoriesByTile[index] = nil
	end
end

-- Index tous kinds : Bots upgrade + score nuke (ISSUE-N46). Recette samsBySlot.
-- Pas de require(Bots) depuis GameState.
local function indexBuilding(self: GameState, slot: number, index: number, present: boolean)
	local set = self.buildingsBySlot[slot]
	if present then
		if not set then
			set = {}
			self.buildingsBySlot[slot] = set
		end
		set[index] = true
	elseif set then
		set[index] = nil
	end
end

-- Index NAVAL_BASE : syncCarriers spawn (ISSUE-N48). Recette samsBySlot.
-- Pas de require(Navy) depuis GameState.
local function indexNavalBase(self: GameState, slot: number, index: number, present: boolean)
	local set = self.navalBasesBySlot[slot]
	if present then
		if not set then
			set = {}
			self.navalBasesBySlot[slot] = set
		end
		set[index] = true
	elseif set then
		set[index] = nil
	end
end

function GameState.placeBuilding(self: GameState, index: number, kind: number, slot: number)
	if self.buildings[index] then
		return
	end
	self.buildings[index] = { kind = kind, slot = slot, level = 1, links = {}, cooldown = 0 }
	self.buildingDirty[index] = true
	self:countBuilding(slot, kind, 1, 1)
	indexBuilding(self, slot, index, true)

	if kind == B.DEFENSE then
		indexBunker(self, slot, index, true)
	end
	if kind == B.SAM then
		indexSam(self, slot, index, true)
	end
	if kind == B.SILO then
		indexSilo(self, slot, index, true)
	end
	if kind == B.PORT then
		indexPort(self, index, slot, 1, true)
	end
	if kind == B.FACTORY then
		indexFactory(self, index, slot, 1, true)
	end
	if kind == B.NAVAL_BASE then
		indexNavalBase(self, slot, index, true)
		self._carriersDirty = true
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
	if building.kind == B.PORT then
		indexPort(self, index, building.slot, building.level, true)
	end
	if building.kind == B.FACTORY then
		indexFactory(self, index, building.slot, building.level, true)
	end

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
	indexBuilding(self, previousSlot, index, false)
	indexBuilding(self, newSlot, index, true)
	if building.kind == B.NAVAL_BASE then
		indexNavalBase(self, previousSlot, index, false)
		indexNavalBase(self, newSlot, index, true)
		self._carriersDirty = true
	end
	if building.kind == B.DEFENSE then
		indexBunker(self, previousSlot, index, false)
		indexBunker(self, newSlot, index, true)
	end
	if building.kind == B.SAM then
		indexSam(self, previousSlot, index, false)
		indexSam(self, newSlot, index, true)
	end
	if building.kind == B.SILO then
		indexSilo(self, previousSlot, index, false)
		indexSilo(self, newSlot, index, true)
	end
	if building.kind == B.PORT then
		indexPort(self, index, newSlot, building.level, true)
	end
	if building.kind == B.FACTORY then
		indexFactory(self, index, newSlot, building.level, true)
	end
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
	indexBuilding(self, building.slot, index, false)
	if building.kind == B.DEFENSE then
		indexBunker(self, building.slot, index, false)
	end
	if building.kind == B.SAM then
		indexSam(self, building.slot, index, false)
	end
	if building.kind == B.SILO then
		indexSilo(self, building.slot, index, false)
	end
	if building.kind == B.PORT then
		indexPort(self, index, building.slot, building.level, false)
	end
	if building.kind == B.FACTORY then
		indexFactory(self, index, building.slot, building.level, false)
	end
	if building.kind == B.NAVAL_BASE then
		indexNavalBase(self, building.slot, index, false)
	end
	if self.coolingBuildings then
		self.coolingBuildings[index] = nil
	end
	self:countBuilding(building.slot, building.kind, -1, building.level)
	self.buildings[index] = nil
	self.buildingDirty[index] = true
	if previousKind == B.NAVAL_BASE then
		self._carriersDirty = true
	end
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
	self.settledHumans[slot] = nil
	self.alliances[slot] = {}
	self.allianceCooldowns[slot] = {}
	self.requests[slot] = {}
	self.embargoes[slot] = {}
	-- Ceinture : un slot recycle n'herite pas du cadran du predecesseur
	-- meme si removePlayer a ete contourne (spawn rate, tests).
	if self.doomWarnedAt then
		self.doomWarnedAt[slot] = nil
	end
	if self.doomUnderSince then
		self.doomUnderSince[slot] = nil
	end

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

--[[
	Rend les troupes engagees a l'attaquant. Pas de malus de retraite : le
	front meurt sans combat (defenseur disparu, pacte). Met atk.troops a 0
	pour qu'un second appel ne double pas le credit.
]]
function GameState.returnCommittedTroops(self: GameState, atk: Attack)
	local attacker = self.players[atk.attacker]
	if attacker then
		attacker.troops += math.max(0, atk.troops)
	end
	atk.troops = 0
end

function GameState.removePlayer(self: GameState, slot: number)
	local state = self.players[slot]
	if not state then
		return
	end

	-- Humain elimine : graver les stats avant de detruire le PlayerState.
	-- endMatch / onPlayerRemoving lisent settledHumans quand players[slot]
	-- est deja nil (ISSUE-N37).
	if not state.isBot and state.player then
		self.settledHumans[slot] = {
			player = state.player,
			betrayals = state.betrayals,
			capturedTiles = state.capturedTiles,
			capitalsCaptured = state.capitalsCaptured,
			buildingsBuilt = state.buildingsBuilt,
		}
	end

	-- Detruire d'abord les structures : setOwner transfere sinon vers NEUTRAL.
	-- N46 : snapshot buildingsBySlot[slot] (destroy mute l'index). Fallback
	-- hash si l'index est nil (tests partiels). Iterer le hash pendant
	-- destroyBuilding peut sauter des cles.
	local doomed: { number } = {}
	if self.buildingsBySlot and self.buildingsBySlot[slot] then
		for index in self.buildingsBySlot[slot] do
			table.insert(doomed, index)
		end
	else
		for index, building in self.buildings do
			if building.slot == slot then
				table.insert(doomed, index)
			end
		end
	end
	for _, index in doomed do
		self:destroyBuilding(index)
	end

	-- Bateaux AVANT setOwner : un bateau n'a pas de targetSlot, on lit
	-- owner[targetTile]. Apres neutralisation, destOwner==NEUTRAL et on ne
	-- distinguerait plus une invasion / un convoi du disparu d'un trajet
	-- vers une cote vide. kind 1 = transport (restitution 100 %, pas
	-- BOAT_RETREAT_LOSS). kind 2 = convoi (ISSUE-N32) : couler, pas d'or
	-- (le navire n'est pas arrive), pas de malus vendeur. GameState ne
	-- require pas Navy (cycle Navy -> GameState).
	for i = #self.boats, 1, -1 do
		local boat = self.boats[i]
		if boat.slot == slot then
			-- L'attaquant / le marchand qui part : ses bateaux disparaissent.
			table.remove(self.boats, i)
		elseif boat.kind == 1 and not boat.retreating then
			local dest = boat.targetTile
			if typeof(dest) == "number" and dest >= 0 and dest < Config.TILE_COUNT then
				if buffer.readu8(self.owner, dest) == slot then
					local attacker = self.players[boat.slot]
					if attacker then
						attacker.troops += math.max(0, boat.troops)
					end
					boat.troops = 0
					table.remove(self.boats, i)
				end
			end
		elseif boat.kind == 2 then
			-- JoinRequest entre deux ticks recycle le slot, repose un PORT
			-- sur la meme tuile, et resolveTrade verse l'or a l'heritier.
			local dest = boat.targetTile
			if typeof(dest) == "number" and dest >= 0 and dest < Config.TILE_COUNT then
				if buffer.readu8(self.owner, dest) == slot then
					table.remove(self.boats, i)
				end
			end
		end
	end

	-- Missiles AVANT setOwner : la cible est toIndex(floor(tx), floor(ty)).
	-- Apres neutralisation, owner==NEUTRAL et on ne distinguerait plus une
	-- frappe sur le disparu d'une frappe deja visee sur une cote vide.
	-- Contrat B (ISSUE-N30) : annuler les ogives dont la tuile visee
	-- appartenait au disparu. Pas de remboursement (ogive deja payee).
	-- Une frappe visee sur un tiers reste en vol. Le tireur qui part perd
	-- ses missiles (comme ses fronts). GameState ne require pas Nukes.
	for i = #self.missiles, 1, -1 do
		local missile = self.missiles[i]
		if missile.slot == slot then
			table.remove(self.missiles, i)
		else
			local tx = math.floor(missile.tx)
			local ty = math.floor(missile.ty)
			if MapGen.inBounds(tx, ty) then
				local index = MapGen.toIndex(tx, ty)
				if buffer.readu8(self.owner, index) == slot then
					table.remove(self.missiles, i)
				end
			end
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
		if atk.attacker == slot then
			-- La faction disparait : ses troupes engagees disparaissent avec elle.
			table.remove(self.attacks, i)
		elseif atk.target == slot then
			self:returnCommittedTroops(atk)
			table.remove(self.attacks, i)
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
	-- Inbound : sinon un embargo / une proposition / une intention de
	-- prolongation vise encore un slot recycle par le prochain addPlayer.
	for _, set in self.requests do
		set[slot] = nil
	end
	self.requests[slot] = nil
	for _, set in self.embargoes do
		set[slot] = nil
	end
	self.embargoes[slot] = nil
	if self.allianceExtensions then
		for _, set in self.allianceExtensions do
			set[slot] = nil
		end
		self.allianceExtensions[slot] = nil
	end
	if self.quickChatSent then
		self.quickChatSent[slot] = nil
	end
	if self.quickChatLast then
		self.quickChatLast[slot] = nil
	end
	if self.targetMarks then
		self.targetMarks[slot] = nil
		-- Inbound : sinon l'alliance voit encore le slot recycle comme cible.
		for marker, target in self.targetMarks do
			if target == slot then
				self.targetMarks[marker] = nil
			end
		end
	end
	-- Cadran : doomWarnedAt / doomUnderSince sont indexes par slot. Sans
	-- purge, le prochain addPlayer herite warn/drain/rot du predecesseur.
	if self.doomWarnedAt then
		self.doomWarnedAt[slot] = nil
	end
	if self.doomUnderSince then
		self.doomUnderSince[slot] = nil
	end
	-- Colis : indexes par tuile d'usine, mais delivery.slot est le payeur.
	-- Trade.step tourne AVANT stepElimination : un JoinRequest entre deux
	-- ticks peut reposer une usine sur la meme tuile avec le slot recycle
	-- et encaisser le colis du disparu.
	if self.tradeDeliveries then
		for index, delivery in self.tradeDeliveries do
			if delivery.slot == slot then
				self.tradeDeliveries[index] = nil
			end
		end
	end
	if self.tradeCooldowns then
		for index in self.tradeCooldowns do
			if not self.buildings[index] then
				self.tradeCooldowns[index] = nil
			end
		end
	end

	self.bunkersBySlot[slot] = nil
	if self.bunkerCells then
		self.bunkerCells[slot] = nil
	end
	if self.samsBySlot then
		self.samsBySlot[slot] = nil
	end
	if self.silosBySlot then
		self.silosBySlot[slot] = nil
	end
	if self.buildingsBySlot then
		self.buildingsBySlot[slot] = nil
	end
	if self.navalBasesBySlot then
		self.navalBasesBySlot[slot] = nil
	end

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

--[[
	Un pacte n'est honorable que s'il est symetrique ET encore dans son delai.

	flush() tourne avant Diplomacy.step : sans le garde d'expiry, Attack / Boat /
	Nuke / dons voient encore 1 tick de paix fantome (le meme bug que viewFor
	sur les propositions). Une valeur non numerique (`true` dans les tests)
	reste un pacte vivant — la production n'ecrit que des ticks d'echeance.
]]
local function pactStillLive(self: GameState, expiry: any): boolean
	if expiry == nil then
		return false
	end
	if typeof(expiry) == "number" then
		return self.tick < expiry
	end
	return expiry == true
end

function GameState.areAllied(self: GameState, a: number, b: number): boolean
	local ab = self.alliances[a]
	local ba = self.alliances[b]
	if not ab or not ba then
		return false
	end
	return pactStillLive(self, ab[b]) and pactStillLive(self, ba[a])
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

	L'ordre vise le couple (attaquant, cible), pas le premier front du tableau :
	terre + tete de pont (`isBeachhead`) coexistents apres BoatFront. Un return
	au premier match laissait l'autre se battre, et le second geste refusait
	"deja ordonnee".
]]
function GameState.retreatAttack(self: GameState, attackerSlot: number, targetSlot: number): (boolean, string?)
	local found = false
	local ordered = false
	for _, atk in self.attacks do
		if atk.attacker == attackerSlot and atk.target == targetSlot then
			found = true
			if not atk.retreatAt then
				atk.retreatAt = self.tick + Config.RETREAT_DELAY
				ordered = true
			end
		end
	end
	if not found then
		return false, "Aucune offensive sur ce front."
	end
	if not ordered then
		return false, "La retraite est deja ordonnee."
	end
	return true, "Retraite ordonnee : le front se degage."
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

		if not attacker then
			table.remove(self.attacks, i)
			continue
		end
		if atk.target ~= NEUTRAL and not defender then
			self:returnCommittedTroops(atk)
			table.remove(self.attacks, i)
			continue
		end

		-- Le delai de retraite est ecoule : les survivants rentrent au pays,
		-- comme lorsqu'un front s'epuise naturellement.
		if atk.retreatAt and self.tick >= atk.retreatAt then
			attacker.troops += math.max(0, atk.troops) * (1 - (Config.RETREAT_LOSS or 0))
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
	Payload UnitSnapshot bateaux (10 Hz). Pas de path / homeTile (intention +
	bandwidth). Pas de retreating (feel N56) : Overlay de cette ligne n'en a
	pas besoin. init.server est hors bundle : ce helper est le contrat testable.
	N51 : recycle boatSnapBuf + inner records. Truncate apres remplissage.
]]
function GameState.snapshotBoats(self: GameState): {
	{
		id: number,
		slot: number,
		x: number,
		y: number,
		troops: number,
		kind: number,
	}
}
	local n = 0
	for _, boat in self.boats do
		n += 1
		local rec = boatSnapBuf[n]
		if rec == nil then
			boatSnapBuf[n] = {
				id = boat.id,
				slot = boat.slot,
				x = boat.x,
				y = boat.y,
				troops = math.floor(boat.troops),
				kind = boat.kind,
			}
		else
			rec.id = boat.id
			rec.slot = boat.slot
			rec.x = boat.x
			rec.y = boat.y
			rec.troops = math.floor(boat.troops)
			rec.kind = boat.kind
		end
	end
	for i = #boatSnapBuf, n + 1, -1 do
		boatSnapBuf[i] = nil
	end
	return boatSnapBuf
end

--[[
	Payload UnitSnapshot missiles (10 Hz). Pas de sx/sy/progress/speed
	(Types.MissileSnapshot). Overlay interpolé via tx/ty seulement.
	init.server est hors bundle : ce helper est le contrat testable.
	N52 : recycle missileSnapBuf + inner records. Truncate apres remplissage.
]]
function GameState.snapshotMissiles(self: GameState): {
	{
		id: number,
		slot: number,
		x: number,
		y: number,
		tx: number,
		ty: number,
		kind: number,
	}
}
	local n = 0
	for _, missile in self.missiles do
		n += 1
		local rec = missileSnapBuf[n]
		if rec == nil then
			missileSnapBuf[n] = {
				id = missile.id,
				slot = missile.slot,
				x = missile.x,
				y = missile.y,
				tx = missile.tx,
				ty = missile.ty,
				kind = missile.kind,
			}
		else
			rec.id = missile.id
			rec.slot = missile.slot
			rec.x = missile.x
			rec.y = missile.y
			rec.tx = missile.tx
			rec.ty = missile.ty
			rec.kind = missile.kind
		end
	end
	for i = #missileSnapBuf, n + 1, -1 do
		missileSnapBuf[i] = nil
	end
	return missileSnapBuf
end

--[[
	Serialise les changements de proprietaire depuis le dernier appel, au format
	[u32 index][u8 slot] repete. On n'envoie jamais la carte entiere.
	N53 : recycle dirtyIndexBuf. Early-out dirty vide sans allouer. Le buffer
	outbound reste neuf (RemoteEvent) — ne pas le recycler.
]]
function GameState.flushOwnerDelta(self: GameState): buffer?
	if next(self.dirty) == nil then
		table.clear(self.dirty)
		return nil
	end

	local n = 0
	for index in self.dirty do
		n += 1
		dirtyIndexBuf[n] = index
	end
	for i = #dirtyIndexBuf, n + 1, -1 do
		dirtyIndexBuf[i] = nil
	end
	table.clear(self.dirty)

	local buf = buffer.create(n * 5)
	for i = 1, n do
		local index = dirtyIndexBuf[i]
		local offset = (i - 1) * 5
		buffer.writeu32(buf, offset, index)
		buffer.writeu8(buf, offset + 4, buffer.readu8(self.owner, index))
	end
	return buf
end

--[[
	N54 : recycle buildingSnapBuf + inner records. Truncate apres remplissage.
	Early-out dirty vide sans allouer. Destruction : kind/slot/level = 0,
	links = nil. `links` reste la table live de l'usine (Overlay lit les
	champs tout de suite, pas l'identite de `out`).
]]
function GameState.flushBuildingDelta(self: GameState): { any }?
	if next(self.buildingDirty) == nil then
		table.clear(self.buildingDirty)
		return nil
	end

	local n = 0
	for index in self.buildingDirty do
		n += 1
		local building = self.buildings[index]
		local rec = buildingSnapBuf[n]
		if rec == nil then
			buildingSnapBuf[n] = {
				index = index,
				kind = if building then building.kind else 0,
				slot = if building then building.slot else 0,
				level = if building then building.level else 0,
				links = if building then building.links else nil,
			}
		else
			rec.index = index
			rec.kind = if building then building.kind else 0
			rec.slot = if building then building.slot else 0
			rec.level = if building then building.level else 0
			rec.links = if building then building.links else nil
		end
	end
	for i = #buildingSnapBuf, n + 1, -1 do
		buildingSnapBuf[i] = nil
	end
	table.clear(self.buildingDirty)
	return if n > 0 then buildingSnapBuf else nil
end

--[[
	N55 : HUD fronts pour StateDelta (activeAttacks / committedTroops /
	attackTargets). Trois maps recyclees. Pas de stats / buildPrices (N2).
	Chaque tas compte (terre et isBeachhead separes). Slots sans front :
	absents des trois maps — replicate() garde `or 0` et attackTargets nil.
]]
function GameState.frontHudForReplicate(self: GameState): (
	{ [number]: number },
	{ [number]: number },
	{ [number]: { number } }
)
	table.clear(activeAttackBuf)
	table.clear(committedTroopBuf)
	table.clear(attackTargetBuf)

	for _, attack in self.attacks do
		local slot = attack.attacker
		activeAttackBuf[slot] = (activeAttackBuf[slot] or 0) + 1
		committedTroopBuf[slot] = (committedTroopBuf[slot] or 0) + math.floor(attack.troops)
		local targets = attackTargetBuf[slot]
		if not targets then
			targets = attackTargetPool[slot]
			if not targets then
				targets = {}
				attackTargetPool[slot] = targets
			else
				table.clear(targets)
			end
			attackTargetBuf[slot] = targets
		end
		table.insert(targets, attack.target)
	end

	return activeAttackBuf, committedTroopBuf, attackTargetBuf
end

--[[
	N57 : map stats pour StateDelta. Recycle la porteuse + les records.
	Appelle frontHudForReplicate une fois (N55). Ne require pas Buildings
	ni Research. eraProgress / buildPrices = nil — l'orchestrateur les
	ecrit ensuite. attackTargets = liste N55, pas un clone.
]]
function GameState.playerStatsForReplicate(self: GameState): { [number]: StatsRec }
	table.clear(statsBuf)
	local activeAttacks, committedTroops, attackTargets = self:frontHudForReplicate()

	for slot, ps in self.players do
		local rec = statsRecPool[slot]
		if rec == nil then
			rec = {
				troops = 0,
				tiles = 0,
				gold = 0,
				maxTroops = 0,
				era = 0,
				eraProgress = nil,
				capturedTiles = 0,
				lostTiles = 0,
				capitalsCaptured = 0,
				buildingsBuilt = 0,
				attacksLaunched = 0,
				activeAttacks = 0,
				committedTroops = 0,
				attackTargets = nil,
				buildPrices = nil,
				logisticsRoutes = 0,
				logisticsIncome = 0,
			}
			statsRecPool[slot] = rec
		end
		local logisticsRoutes, logisticsIncome = self:logisticsFor(slot)
		rec.troops = math.floor(ps.troops)
		rec.tiles = ps.tiles
		rec.gold = math.floor(ps.gold)
		rec.maxTroops = math.floor(self:maxTroops(ps))
		rec.era = ps.era
		rec.eraProgress = nil
		rec.capturedTiles = ps.capturedTiles
		rec.lostTiles = ps.lostTiles
		rec.capitalsCaptured = ps.capitalsCaptured
		rec.buildingsBuilt = ps.buildingsBuilt
		rec.attacksLaunched = ps.attacksLaunched
		rec.activeAttacks = activeAttacks[slot] or 0
		rec.committedTroops = committedTroops[slot] or 0
		rec.attackTargets = attackTargets[slot]
		rec.buildPrices = nil
		rec.logisticsRoutes = logisticsRoutes
		rec.logisticsIncome = math.floor(logisticsIncome * 100) / 100
		statsBuf[slot] = rec
	end

	return statsBuf
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
	local n = 0

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

		n += 1
		elimBuf[n] = slot
	end

	for i = #elimBuf, n + 1, -1 do
		elimBuf[i] = nil
	end

	-- On collecte avant de supprimer : removePlayer mute self.players, et le
	-- muter en cours d'iteration est un comportement indefini.
	for i = 1, n do
		local slot = elimBuf[i]
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

	return elimBuf
end

function GameState.step(self: GameState): { number }
	self.tick += 1
	self:stepEconomy()
	self:stepAttacks()
	return self:stepElimination()
end

return GameState
