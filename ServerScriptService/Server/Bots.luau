--!strict
--[[
	IA des factions non humaines.

	Objectif de design : un bot doit produire des situations racontables, pas
	jouer optimalement. Il s'allie, il construit, il debarque et surtout il
	trahit quand l'occasion est trop belle — parce qu'une partie ou seuls les
	humains trahissent n'apprend rien aux nouveaux joueurs.

	Chaque bot ne decide qu'un tick sur DECISION_INTERVAL, avec un decalage
	dependant de son slot : sinon toutes les factions agissent au meme tick et
	la carte convulse par a-coups.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Doctrines = require(ReplicatedStorage.Shared.Doctrines)
local GameState = require(script.Parent.GameState)
local Buildings = require(script.Parent.Buildings)
local Navy = require(script.Parent.Navy)
local Nukes = require(script.Parent.Nukes)
local Diplomacy = require(script.Parent.Diplomacy)
local Research = require(script.Parent.Research)
local BuildingDefs = require(ReplicatedStorage.Shared.BuildingDefs)

type GameState = GameState.GameState

local Bots = {}

local DECISION_INTERVAL = 14
local NEUTRAL = Config.NEUTRAL_SLOT
local B = Config.BUILDING

local BOT_NAMES = {
	"Aurelia",
	"Kessrin",
	"Vodark",
	"Meridia",
	"Tarnhold",
	"Ozmark",
	"Cindral",
	"Halvern",
	"Ruskaya",
	"Belmoro",
	"Ysgard",
	"Corvane",
	"Drakmoor",
	"Selvane",
	"Norwich",
	"Ateshka",
}

local botSlots: { number } = {}
local scratch = table.create(4, 0)
-- V35 : contacts frontaliers recycles. Appels sequentiels (decideDiplomacy
-- x2, decideNavy, decideAttack) — jamais imbriques. Map, pas array :
-- table.clear, pas de truncate. Slot sans joueur / sans frontiere → vide.
-- Recette feel N80. Pas reentrant — ne pas appeler pendant qu'un
-- appelant itere encore.
local contactBuf: { [number]: number } = {}
-- V27 : flatten buildingsBySlot une fois par visee (pas × 90 tuiles).
-- Arrays paralleles, pas un spatial hash. Non reentrant — decideNuke
-- est unique par bot par tick. blastValue (banc V22) reutilise le meme pool.
local blastX: { number } = table.create(48)
local blastY: { number } = table.create(48)
local blastLevel: { number } = table.create(48)
local blastN = 0

--=============================================================================
-- Mise en place
--=============================================================================

function Bots.spawnAll(state: GameState, rng: Random, count: number?)
	table.clear(botSlots)
	for i = 1, count or Config.BOT_COUNT do
		local name = BOT_NAMES[((i - 1) % #BOT_NAMES) + 1]
		local ps = state:addPlayer(nil, name, rng, 0)
		if ps then
			ps.attackRatio = rng:NextNumber(Config.BOT_ATTACK_RATIO_MIN, Config.BOT_ATTACK_RATIO_MAX)
			ps.doctrine = Doctrines.LIST[rng:NextInteger(1, #Doctrines.LIST)].id
			table.insert(botSlots, ps.slot)
		end
	end
end

--=============================================================================
-- Perception
--=============================================================================

-- Factions au contact terrestre, avec la longueur du front partage.
-- V35 : Bots.neighborFactions + contactBuf (recette samsOf / N68 / N80).
function Bots.neighborFactions(state: GameState, slot: number): { [number]: number }
	table.clear(contactBuf)
	local ps = state.players[slot]
	if not ps then
		return contactBuf
	end

	for index in ps.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if state:isLand(nb) then
				local other = buffer.readu8(state.owner, nb)
				if other ~= slot then
					contactBuf[other] = (contactBuf[other] or 0) + 1
				end
			end
		end
	end

	return contactBuf
end

-- Puissance percue d'une faction : ce que le bot compare avant d'attaquer.
local function strengthOf(state: GameState, slot: number): number
	local ps = state.players[slot]
	if not ps then
		return 0
	end
	return ps.troops + ps.tiles * 6
end

-- Pression de l'IA : douce pendant l'apprentissage, complete seulement quand
-- le joueur a eu le temps de coloniser et de construire un vrai centre.
local function botPressure(state: GameState): number
	local elapsed = state.tick / Config.TICK_RATE
	return math.clamp(elapsed / Config.BOT_FULL_PRESSURE_AFTER, 0, 1)
end

local function humanTargetProtected(
	state: GameState,
	attacker: GameState.PlayerState,
	target: GameState.PlayerState
): boolean
	if target.isBot then
		return false
	end

	local elapsed = state.tick / Config.TICK_RATE
	if elapsed < Config.BOT_HUMAN_GRACE_DURATION then
		return true
	end

	-- Apres la grace, on evite encore qu'un empire deja installe efface un
	-- petit joueur qui termine son onboarding. La protection tombe des que le
	-- joueur controle un territoire suffisant ou prend lui-meme de l'avance.
	return target.tiles < Config.BOT_HUMAN_PROTECTION_TILES and attacker.tiles > target.tiles
end

Bots.humanTargetProtected = humanTargetProtected

-- Le leader ne doit pas seulement etre "la meilleure cible" : quand il a
-- deja pris une avance nette, les factions secondaires doivent comprendre
-- qu'une guerre entre elles lui laisse la partie. Les constantes de coalition
-- vivent dans Config pour que le comportement reste reglable sans toucher a
-- la logique de selection de cible.
local function dominantLeader(state: GameState): (number?, boolean)
	local leader: number? = nil
	local leaderTiles = 0
	local othersTiles = 0
	local others = 0

	for slot, ps in state.players do
		if ps.tiles > leaderTiles then
			if leader then
				othersTiles += leaderTiles
				others += 1
			end
			leader = slot
			leaderTiles = ps.tiles
		else
			othersTiles += ps.tiles
			others += 1
		end
	end

	if not leader or leaderTiles < Config.COALITION_MIN_LEADER_TILES or others == 0 then
		return leader, false
	end

	local averageOthers = othersTiles / others
	return leader, averageOthers > 0 and leaderTiles / averageOthers >= Config.COALITION_LEADER_RATIO
end

--=============================================================================
-- Decisions
--=============================================================================

--[[
	Rassemble des emplacements plausibles pour un type de batiment donne.

	Un port ne peut aller que sur la cote : parcourir betement les 60 premieres
	tuiles frontieres ne marche pas, car l'ordre de parcours d'une table est
	stable et un bot dont ces 60 tuiles sont a l'interieur des terres ne
	construit alors *jamais* de port. On filtre donc sur le critere reel.
]]
local function gatherSites(state: GameState, ps: GameState.PlayerState, kind: number, rng: Random): { number }
	local sites: { number } = {}

	if kind == B.PORT or kind == B.NAVAL_BASE then
		for index in ps.coast do
			table.insert(sites, index)
			if #sites >= 40 then
				break
			end
		end
	elseif kind == B.DEFENSE then
		for index in ps.border do
			table.insert(sites, index)
			if #sites >= 60 then
				break
			end
		end
	else
		-- Villes, silos et batteries vont a l'interieur : un tirage aleatoire
		-- sur la carte coute un temps constant quelle que soit la taille de
		-- l'empire, contrairement a un balayage du territoire.
		for _ = 1, 45 do
			local x = rng:NextInteger(0, Config.MAP_WIDTH - 1)
			local y = rng:NextInteger(0, Config.MAP_HEIGHT - 1)
			local index = MapGen.toIndex(x, y)
			if buffer.readu8(state.owner, index) == ps.slot then
				table.insert(sites, index)
			end
		end
	end

	return sites
end

local function lowestUpgradable(state: GameState, slot: number): number?
	local bestIndex: number? = nil
	local bestLevel = math.huge
	if state.buildingsBySlot then
		local set = state.buildingsBySlot[slot]
		if set then
			for index in set do
				local building = state.buildings[index]
				if
					building
					and BuildingDefs.isUpgradable(building.kind)
					and building.level < BuildingDefs.maxLevel(building.kind)
					and building.level < bestLevel
				then
					bestIndex = index
					bestLevel = building.level
				end
			end
		end
		return bestIndex
	end
	for index, building in state.buildings do
		if
			building.slot == slot
			and BuildingDefs.isUpgradable(building.kind)
			and building.level < BuildingDefs.maxLevel(building.kind)
			and building.level < bestLevel
		then
			bestIndex = index
			bestLevel = building.level
		end
	end
	return bestIndex
end

-- V27 : flatten buildingsBySlot dans blastBuf. Index present + set nil
-- = buffer vide, score 0 (contrat V22 : pas de fallback hash).
local function fillBlastBuf(state: GameState, slot: number)
	local n = 0
	if state.buildingsBySlot then
		local set = state.buildingsBySlot[slot]
		if set then
			for other in set do
				local building = state.buildings[other]
				if building then
					n += 1
					local bx, by = MapGen.fromIndex(other)
					blastX[n] = bx
					blastY[n] = by
					blastLevel[n] = building.level
				end
			end
		end
	else
		for other, building in state.buildings do
			if building.slot == slot then
				n += 1
				local bx, by = MapGen.fromIndex(other)
				blastX[n] = bx
				blastY[n] = by
				blastLevel[n] = building.level
			end
		end
	end
	for i = #blastX, n + 1, -1 do
		blastX[i] = nil
		blastY[i] = nil
		blastLevel[i] = nil
	end
	blastN = n
end

local function scoreBlast(tile: number, blast2: number): number
	local x, y = MapGen.fromIndex(tile)
	local value = 0
	for i = 1, blastN do
		local dx, dy = blastX[i] - x, blastY[i] - y
		if dx * dx + dy * dy <= blast2 then
			value += blastLevel[i]
		end
	end
	return value
end

-- V22 : score d'emprise dans le rayon, via buildingsBySlot (plus le hash).
-- V27 : fill unique ; le banc unitaire passe encore par cette API.
local function blastValue(state: GameState, slot: number, tile: number, blast2: number): number
	fillBlastBuf(state, slot)
	return scoreBlast(tile, blast2)
end

local function tryUpgradeBuilding(state: GameState, ps: GameState.PlayerState, reserve: number, rng: Random): boolean
	if ps.era < 2 or rng:NextNumber() > 0.32 then
		return false
	end

	-- On ameliore d'abord le batiment le moins developpe : les empires bots
	-- produisent ainsi plusieurs centres regionaux au lieu d'une seule tour
	-- geante et d'une couronne de villages.
	--
	-- Tous les types a paliers sont candidats, pas seulement la ville : un port
	-- ou une usine de niveau 3 valent trois exemplaires sans occuper trois
	-- emplacements, et sans cette boucle les niveaux resteraient du contenu mort
	-- dans toutes les parties contre l'IA.
	local bestIndex = lowestUpgradable(state, ps.slot)
	if not bestIndex then
		return false
	end

	local price = Buildings.upgradePrice(state, ps.slot, bestIndex)
	if ps.gold - reserve < price then
		return false
	end
	local ok = Buildings.upgradeAt(state, ps.slot, bestIndex)
	return ok
end

local function decideBuild(state: GameState, ps: GameState.PlayerState, rng: Random)
	if ps.tiles < 25 then
		return
	end

	local nukesUp = Buildings.nukesUnlocked(state, ps.slot)

	-- Une fois l'arsenal ouvert, le bot garde en permanence de quoi tirer une
	-- bombe. Sans cette reserve il redepense tout en villes des qu'il atteint
	-- 180 d'or et la phase nucleaire n'arrive jamais — la simulation ne
	-- produisait qu'un seul silo et aucune frappe en dix minutes.
	local reserve = if nukesUp and ps.siloCount > 0 then Config.NUKE_STATS[Config.NUKE.ATOM].cost else 0

	-- Epargne pour la prochaine ere des que seul l'or manque encore. C'est la
	-- difference entre un bot qui plafonne a l'age industriel et un bot qui
	-- atteint l'atome.
	reserve = math.max(reserve, Research.goldReserveFor(state, ps.slot))

	local cityCount = ps.buildingCounts[B.CITY] or 0
	local enoughCitiesForEra = (ps.era == 2 and cityCount >= 3) or (ps.era >= 3 and cityCount >= 6)
	if enoughCitiesForEra and tryUpgradeBuilding(state, ps, reserve, rng) then
		return
	end

	--[[
		Que construire ? Le plus gros manque, rapporte a son prix.

		Voir Config.BOT_STRUCTURE_PLAN pour le pourquoi de la table de ratios.
		Ici on ne fait que la parcourir et garder le meilleur rapport
		manque / cout percu.
	]]
	--[[
		Le nombre de villes visees est SOUS-lineaire, comme le plafond de troupes.

		Une courbe lineaire (tuiles / 190) reintroduirait tout droit la boucle
		d'emballement cassee ailleurs : plus de terres, plus de villes, donc plus
		de troupes et d'or, donc plus de terres. Le meme exposant que le plafond
		de troupes garde les deux courbes coherentes — un empire dix fois plus
		grand ne vaut ni dix fois plus d'armee, ni dix fois plus de villes.
	]]
	local desiredCities = math.max(1, ps.tiles ^ Config.MAX_TROOPS_TILE_EXPONENT / Config.BOT_CITY_DIVISOR)

	local wanted: number? = nil
	local bestScore = 0

	for _, plan in Config.BOT_STRUCTURE_PLAN do
		if ps.era < plan.minEra then
			continue
		end

		local owned = ps.buildingCounts[plan.kind] or 0
		-- Les villes se calent sur le territoire ; tout le reste se cale sur les
		-- villes, qui sont le vrai coeur d'un empire.
		local target = if plan.kind == B.CITY then desiredCities else cityCount * plan.perCity

		--[[
			Penchant stable, propre a chaque bot.

			Tire du slot et du type de batiment, donc identique du debut a la fin
			de la partie : c'est ce qui produit un voisin marchand et un voisin
			militariste la ou la cascade donnait douze jumeaux.
		]]
		local leaning = 0.75 + ((ps.slot * 37 + plan.kind * 11) % 50) / 100
		local deficit = target * leaning - owned
		if deficit <= 0 then
			continue
		end

		--[[
			On compare des RETARDS RELATIFS, pas des manques rapportes au prix.

			Premiere version : `manque / prix`. Le rapport est dimensionnellement
			biaise vers le pas cher — mesure sur un bot d'ere 3 : la base navale
			a 323 d'or l'emportait a 0,0044 contre l'usine a 1 768 d'or, notee
			0,0018, alors que l'usine lui manquait davantage. Resultat : zero
			usine sur toute la carte.

			Ici le score dit "a quel point suis-je en retard sur cet axe", ce qui
			est comparable d'un batiment a l'autre quel que soit son prix. Le
			cout n'intervient plus que comme frein a la repetition (costBias) et
			comme condition d'achat, verifiee plus bas.
		]]
		local score = (deficit / target) / (1 + plan.costBias * owned)

		if score > bestScore then
			bestScore = score
			wanted = plan.kind
		end
	end

	--[[
		La ville passe avant tout le reste.

		C'est une regle explicite CONQUEST, et l'avoir omise a coute
		une phase entiere. Le score `manque / prix` favorise mecaniquement le pas
		cher : une ville vaut huit bunkers, donc le bunker gagne meme avec un
		manque bien plus faible. Mesure sans cette regle : 22 ports et 30 bunkers
		pour 76 villes, et PLUS AUCUNE faction n'atteignait l'ere atomique —
		donc zero silo, zero frappe, la fin de partie disparaissait.

		La ville n'est pas un batiment parmi d'autres : c'est elle qui porte la
		population, l'or, et les conditions d'ere. On la construit des qu'il en
		manque une et qu'on peut se la payer ; le reste se partage l'excedent.
	]]
	if wanted ~= B.CITY then
		local cities = ps.buildingCounts[B.CITY] or 0
		if cities < desiredCities then
			local cityPrice = Buildings.priceFor(state, ps.slot, B.CITY)
			if ps.gold - reserve >= cityPrice then
				wanted = B.CITY
			end
		end
	end

	--[[
		Le premier silo echappe a la regle.

		Il n'est pas un investissement parmi d'autres : c'est lui qui ouvre toute
		la phase nucleaire. Le laisser au jeu des ratios revient a ne jamais le
		construire, son prix ecrasant le manque d'un seul exemplaire.
	]]
	if nukesUp and ps.siloCount < 1 then
		wanted = B.SILO
		reserve = 0
	end

	if not wanted then
		return
	end

	local price = Buildings.priceFor(state, ps.slot, wanted)
	if ps.gold - reserve < price then
		return -- on epargne plutot que de depenser au coup par coup
	end

	for _, index in gatherSites(state, ps, wanted, rng) do
		if Buildings.build(state, ps.slot, index, wanted) then
			return
		end
	end
end

local function decideDiplomacy(state: GameState, ps: GameState.PlayerState, rng: Random)
	local slot = ps.slot

	-- Repondre aux propositions recues : un bot accepte plus volontiers quand
	-- il est en position de faiblesse.
	for other, targets in state.requests do
		if targets[slot] then
			local mine = strengthOf(state, slot)
			local theirs = strengthOf(state, other)
			local acceptChance = if mine < theirs then 0.75 else 0.35
			if rng:NextNumber() < acceptChance then
				Diplomacy.accept(state, other, slot)
			else
				Diplomacy.decline(state, other, slot)
			end
		end
	end

	local allies = {}
	for other in state.players do
		if other ~= slot and state:areAllied(slot, other) then
			allies[other] = true
		end
	end
	local leader, coalitionActive = dominantLeader(state)
	local threatened = coalitionActive and leader ~= slot

	--[[
		Coalition anti-leader.

		Ces deux comportements etaient decrits dans Config depuis le debut mais
		n'avaient jamais ete branches : COALITION_ALLY_CHANCE et
		COALITION_EMBARGO_CHANCE etaient des constantes mortes, et seul le choix
		de cible d'attaque tenait compte du leader. Resultat, rien n'organisait
		les faibles entre eux — chacun se contentait de proposer un pacte au plus
		fort, c'est-a-dire souvent au leader lui-meme, ce qui le protegeait au
		lieu de le contenir.
	]]
	if threatened and leader then
		-- L'embargo est le seul levier qui coute au leader sans exposer de
		-- troupes : c'est ce qui rend la coalition jouable pour un petit.
		local myEmbargoes = state.embargoes[slot]
		if not (myEmbargoes and myEmbargoes[leader]) and rng:NextNumber() < Config.COALITION_EMBARGO_CHANCE then
			Diplomacy.setEmbargo(state, slot, leader, true)
		end

		if rng:NextNumber() < Config.COALITION_ALLY_CHANCE then
			for other, ps2 in state.players do
				if other ~= slot and other ~= leader and not allies[other] then
					Diplomacy.request(state, slot, other)
					return
				end
			end
		end
	end

	-- Trahison : le bot rompt quand son allie est devenu nettement plus faible
	-- que lui et qu'ils partagent une frontiere. C'est exactement le calcul
	-- qu'un humain fait, rendu visible.
	--
	-- Sauf pendant une coalition : trahir un compagnon d'infortune pendant qu'un
	-- geant occupe la moitie de la carte n'est pas un calcul, c'est un suicide.
	for ally in allies do
		local mine = strengthOf(state, slot)
		local theirs = strengthOf(state, ally)
		local protectedByCoalition = threatened and ally ~= leader
		if
			not protectedByCoalition
			and theirs > 0
			and mine > theirs * 2.2
			and rng:NextNumber() < 0.25
		then
			local contacts = Bots.neighborFactions(state, slot)
			if contacts[ally] and contacts[ally] > 4 then
				Diplomacy.breakAlliance(state, slot, ally)
				return
			end
		end
	end

	-- Proposer une alliance a un voisin plus fort : la peur cree les pactes.
	-- Jamais au leader quand une coalition est active : s'abriter derriere le
	-- geant revient a lui offrir la partie.
	if rng:NextNumber() < 0.3 then
		local contacts = Bots.neighborFactions(state, slot)
		for other in contacts do
			if other ~= NEUTRAL and not allies[other] and not (threatened and other == leader) then
				if strengthOf(state, other) > strengthOf(state, slot) * 1.3 then
					Diplomacy.request(state, slot, other)
					return
				end
			end
		end
	end
end

--[[
	Le bot parle.

	C'est le levier de ressenti le moins cher du jeu : onze factions muettes sur
	douze donnent l'impression d'un tableur qui bouge, pas d'une partie. Le
	catalogue de messages existait deja et seul un humain pouvait s'en servir.

	L'ordre compte, et il est celui de l'urgence : un bot qui se fait demolir
	appelle a l'aide avant de faire de la politique, et fait de la politique
	avant de dire bonjour. Sans cet ordre, l'anti-spam laisserait passer la
	politesse et avalerait l'appel au secours.

	Rien n'est dit gratuitement : chaque message est declenche par un fait de
	jeu verifiable, jamais par un simple tirage. Un bot qui bavarde sans raison
	se repere en deux minutes et devient du bruit.
]]
local function decideChat(state: GameState, ps: GameState.PlayerState, rng: Random)
	if rng:NextNumber() > Config.BOT_CHAT_CHANCE then
		return
	end

	local slot = ps.slot

	-- 1. A l'aide : on se fait prendre du territoire par quelqu'un, maintenant.
	local worst, worstUntil = nil, 0
	for other, until_ in ps.grudges do
		if until_ > worstUntil and state.players[other] then
			worst, worstUntil = other, until_
		end
	end
	if worst then
		local hasAlly = false
		for other in state.players do
			if other ~= slot and state:areAllied(slot, other) then
				hasAlly = true
				break
			end
		end
		-- Avec des allies on demande du renfort, seul on designe la menace a
		-- toute la carte : dans les deux cas on cherche a ne pas mourir seul.
		if hasAlly then
			if Diplomacy.sendQuickChat(state, slot, "help_defend", worst) then
				return
			end
		elseif Diplomacy.sendQuickChat(state, slot, "attack_target", worst) then
			return
		end
	end

	-- 2. Denoncer un traitre : la reputation est une arme, et elle ne coute rien.
	for other, target in state.players do
		if other ~= slot and target.traitorUntil > state.tick then
			if Diplomacy.sendQuickChat(state, slot, "warn_traitor", other) then
				return
			end
			break
		end
	end

	-- 3. Designer le leader. Un bot ne previent pas quand c'est LUI le leader —
	-- ce serait se denoncer soi-meme.
	local leader = dominantLeader(state)
	if leader and leader ~= slot then
		if Diplomacy.sendQuickChat(state, slot, "warn_big", leader) then
			return
		end
	end

	-- 4. Politesse d'ouverture, tant que personne n'a encore de vrai territoire.
	if state.tick < Config.BOT_CHAT_GREETING_TICKS then
		Diplomacy.sendQuickChat(state, slot, "social_luck", nil)
	end
end

local function decideNavy(state: GameState, ps: GameState.PlayerState, rng: Random)
	if ps.troops < Config.MIN_BOAT_TROOPS * 4 then
		return
	end

	local contacts = Bots.neighborFactions(state, ps.slot)
	local hasLandTarget = false
	for other in contacts do
		if other ~= NEUTRAL or contacts[NEUTRAL] then
			hasLandTarget = true
			break
		end
	end

	-- Un bot enferme tente la mer beaucoup plus volontiers qu'un bot qui a
	-- encore de la place au sol.
	local chance = if hasLandTarget then 0.12 else 0.6
	if rng:NextNumber() > chance then
		return
	end

	-- Cible : une cote qui ne nous appartient pas, tiree au hasard.
	for _ = 1, 25 do
		local x = rng:NextInteger(0, Config.MAP_WIDTH - 1)
		local y = rng:NextInteger(0, Config.MAP_HEIGHT - 1)
		local index = MapGen.toIndex(x, y)

		if not state:isLand(index) then
			continue
		end
		local owner = buffer.readu8(state.owner, index)
		if owner == ps.slot then
			continue
		end
		local target = if owner ~= NEUTRAL then state.players[owner] else nil
		if target and humanTargetProtected(state, ps, target) then
			continue
		end
		if owner ~= NEUTRAL and state:areAllied(ps.slot, owner) then
			continue
		end
		if not MapGen.isCoastal(state.terrain, index) then
			continue
		end

		local ok = Navy.launchInvasion(state, ps.slot, index)
		if ok then
			return
		end
	end
end

local function decideNuke(state: GameState, ps: GameState.PlayerState, rng: Random)
	if ps.siloCount == 0 or not Buildings.nukesUnlocked(state, ps.slot) then
		return
	end

	-- Le bot prend l'arme la plus puissante qu'il peut payer : le MIRV est
	-- l'aboutissement de toute sa phase economique, pas un luxe inemploye.
	local kind = Config.NUKE.ATOM
	if ps.gold >= Config.NUKE_STATS[Config.NUKE.MIRV].cost then
		kind = Config.NUKE.MIRV
	elseif ps.gold >= Config.NUKE_STATS[Config.NUKE.HYDROGEN].cost then
		kind = Config.NUKE.HYDROGEN
	end

	if ps.gold < Config.NUKE_STATS[kind].cost then
		return
	end
	if rng:NextNumber() > 0.35 then
		return
	end

	-- On vise le plus gros rival non allie : le nucleaire sert a casser un
	-- leader, pas a achever un mourant.
	local bestSlot: number? = nil
	local bestTiles = 0
	for slot, other in state.players do
		if
			slot ~= ps.slot
			and not state:areAllied(ps.slot, slot)
			and not humanTargetProtected(state, ps, other)
			and other.tiles > bestTiles
		then
			bestTiles = other.tiles
			bestSlot = slot
		end
	end

	if not bestSlot then
		return
	end

	local target = state.players[bestSlot]
	if not target then
		return
	end

	--[[
		Choisir OU frapper, au lieu de tirer sur une tuile de frontiere au hasard.

		Deux regles, dans cet ordre :

		  1. **Ne pas tirer dans le vide.** Une frappe qui atterrit sous un SAM
		     ennemi est de l'or jete : le missile est intercepte et le bot
		     recommencera au prochain tour, indefiniment. On verifie donc la
		     couverture AVANT de payer.
		  2. **Viser ce qui fait mal.** Une tuile entouree de batiments vaut bien
		     plus qu'un bout de frontiere vide. Le bot compte les batiments dans
		     le rayon de l'explosion et garde la meilleure tuile trouvee.

		Si tout le territoire vise est couvert, on ne renonce pas : on frappe la
		batterie elle-meme. C'est la suppression avant l'assaut — le SAM tombe,
		et la vraie frappe passera au tour suivant.
	]]
	local sams = Buildings.samsOf(state, bestSlot)

	local function coveredBy(index: number): number?
		local x, y = MapGen.fromIndex(index)
		for _, samIndex in sams do
			local building = state.buildings[samIndex]
			local range = Nukes.samRange(if building then (building.level or 1) else 1)
			local sx, sy = MapGen.fromIndex(samIndex)
			local dx, dy = sx - x, sy - y
			if dx * dx + dy * dy <= range * range then
				return samIndex
			end
		end
		return nil
	end

	--[[
		Emprise reelle de l'arme choisie.

		Le MIRV declare un rayon de zero : il ne creuse pas un cratere unique, il
		se scinde en ogives dispersees. Prendre son `radius` tel quel donnait un
		score d'impact nul sur l'arme la plus chere du jeu — le bot la lancait
		donc sur la premiere tuile venue. Son emprise, c'est sa dispersion plus
		le rayon d'une ogive.
	]]
	local stats = Config.NUKE_STATS[kind]
	local blastRadius = stats.radius
	if blastRadius <= 0 then
		blastRadius = (stats.spread or 0) + (stats.warheadRadius or 0)
	end
	local blast2 = blastRadius * blastRadius

	-- V27 : un flatten, 90 scores. Pas blastValue × 90 (re-scan index).
	fillBlastBuf(state, bestSlot)

	local bestTile: number? = nil
	local bestValue = -1
	local shielded: number? = nil
	local examined = 0

	for index in target.border do
		-- La frontiere d'un grand empire compte des milliers de tuiles : on en
		-- echantillonne assez pour choisir, pas assez pour couter un tick.
		examined += 1
		if examined > 90 then
			break
		end

		local guard = coveredBy(index)
		if guard then
			shielded = shielded or guard
			continue
		end

		local value = scoreBlast(index, blast2)

		if value > bestValue then
			bestValue = value
			bestTile = index
		end
	end

	if bestTile then
		Nukes.launch(state, ps.slot, bestTile, kind)
	elseif shielded then
		-- Tout est couvert : on abat le parapluie avant d'essayer la ville.
		Nukes.launch(state, ps.slot, shielded, kind)
	end
end

local function decideAttack(state: GameState, ps: GameState.PlayerState, rng: Random)
	if ps.troops < Config.MIN_ATTACK_TROOPS * 3 then
		return -- on laisse remonter la reserve
	end

	local pressure = botPressure(state)
	local attackChance = Config.BOT_ATTACK_CHANCE_EARLY
		+ (Config.BOT_ATTACK_CHANCE_LATE - Config.BOT_ATTACK_CHANCE_EARLY) * pressure
	if rng:NextNumber() > attackChance then
		return
	end

	local contacts = Bots.neighborFactions(state, ps.slot)
	local bestTarget: number? = nil
	local bestScore = -math.huge
	local leader, coalitionActive = dominantLeader(state)

	for other, contactTiles in contacts do
		if other ~= NEUTRAL and state:areAllied(ps.slot, other) then
			continue
		end

		local score: number
		if other == NEUTRAL then
			-- Le terrain vierge est prioritaire tant qu'il en reste : c'est le
			-- comportement humain naturel en debut de partie.
			score = 1000 + contactTiles
		else
			local target = state.players[other]
			if not target then
				continue
			end
			if humanTargetProtected(state, ps, target) then
				continue
			end
			-- Cible d'autant plus attirante qu'elle est faible par tuile.
			local density = target.troops / math.max(1, target.tiles)
			score = 100 / (1 + density) + contactTiles * 0.5

			--[[
				La riposte passe avant le calcul d'opportunite.

				Sans ce terme, un bot qui vient de perdre deux cents tuiles
				repartait a la recherche de la cible la plus rentable — souvent
				quelqu'un d'autre. Le joueur ne faisait alors jamais le lien entre
				son agression et ce qui lui tombait dessus, et la partie ne
				racontait rien.

				Le poids est volontairement superieur a l'ecart de score entre
				deux voisins ordinaires : une rancune fraiche doit l'emporter,
				pas juste peser.
			]]
			if state:holdsGrudge(ps.slot, other) then
				score += Config.GRUDGE_ATTACK_BONUS
			end

			if coalitionActive then
				if other == leader and other ~= ps.slot then
					-- Une attaque contre le leader devient une decision collective,
					-- meme si sa densite le rend plus difficile a percer.
					score += Config.COALITION_ATTACK_BONUS
				elseif other ~= ps.slot then
					-- Les puissances secondaires evitent de s'epuiser entre elles
					-- tant qu'une menace commune domine la carte.
					score *= Config.COALITION_NON_LEADER_DAMPING
				end
			end
		end

		score += rng:NextNumber(0, 15)
		if score > bestScore then
			bestScore = score
			bestTarget = other
		end
	end

	if bestTarget then
		state:launchAttack(ps.slot, bestTarget)
	end
end

--=============================================================================
-- Tick
--=============================================================================

function Bots.step(state: GameState, rng: Random)
	for i = #botSlots, 1, -1 do
		local slot = botSlots[i]
		local ps = state.players[slot]
		if not ps then
			table.remove(botSlots, i)
			continue
		end

		if (state.tick + slot * 3) % DECISION_INTERVAL ~= 0 then
			continue
		end

		-- La recherche passe avant tout : un bot qui n'avance pas d'ere reste
		-- bloque a l'age de pierre pendant que les autres passent a l'atome.
		Research.advance(state, ps.slot)

		decideAttack(state, ps, rng)
		decideBuild(state, ps, rng)
		decideDiplomacy(state, ps, rng)
		decideChat(state, ps, rng)
		decideNavy(state, ps, rng)
		decideNuke(state, ps, rng)
	end
end

Bots.lowestUpgradable = lowestUpgradable
Bots.blastValue = blastValue

return Bots
