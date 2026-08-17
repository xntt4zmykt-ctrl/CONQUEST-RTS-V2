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

--=============================================================================
-- Mise en place
--=============================================================================

function Bots.spawnAll(state: GameState, rng: Random, count: number?)
	table.clear(botSlots)
	for i = 1, count or Config.BOT_COUNT do
		local name = BOT_NAMES[((i - 1) % #BOT_NAMES) + 1]
		local ps = state:addPlayer(nil, name, rng, 0)
		if ps then
			ps.attackRatio = rng:NextNumber(0.2, 0.45)
			ps.doctrine = Doctrines.LIST[rng:NextInteger(1, #Doctrines.LIST)].id
			table.insert(botSlots, ps.slot)
		end
	end
end

--=============================================================================
-- Perception
--=============================================================================

-- Factions au contact terrestre, avec la longueur du front partage.
local function neighborFactions(state: GameState, slot: number): { [number]: number }
	local ps = state.players[slot]
	local contacts: { [number]: number } = {}
	if not ps then
		return contacts
	end

	for index in ps.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if state:isLand(nb) then
				local other = buffer.readu8(state.owner, nb)
				if other ~= slot then
					contacts[other] = (contacts[other] or 0) + 1
				end
			end
		end
	end

	return contacts
end

-- Puissance percue d'une faction : ce que le bot compare avant d'attaquer.
local function strengthOf(state: GameState, slot: number): number
	local ps = state.players[slot]
	if not ps then
		return 0
	end
	return ps.troops + ps.tiles * 6
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

	if kind == B.PORT then
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

	-- Les compteurs sont plafonnes explicitement : sans plafond, un bot riche
	-- retire indefiniment le meme batiment (315 batteries pour 8 silos).
	local wanted: number
	local roll = rng:NextNumber()

	if nukesUp and ps.siloCount < 1 then
		wanted = B.SILO
		reserve = 0 -- le silo est lui-meme l'objectif de l'epargne
	elseif ps.buildingCounts[B.CITY] == nil or (ps.buildingCounts[B.CITY] or 0) < 8 then
		-- Les villes sont la condition d'ere la plus exigeante : les prioriser
		-- evite que le bot reste bloque a un palier faute d'un seul batiment.
		wanted = B.CITY
		reserve = 0
	elseif (ps.buildingCounts[B.DEFENSE] or 0) < 2 and ps.era >= 2 then
		wanted = B.DEFENSE
		reserve = 0
	elseif ps.portCount == 0 then
		-- Le tout premier port passe avant le reste : c'est lui qui ouvre les
		-- routes commerciales, et donc qui rend l'embargo jouable. Laisse en
		-- priorite basse, la simulation ne produisait que deux ports sur toute
		-- la carte et la diplomatie economique restait lettre morte.
		wanted = B.PORT
	elseif nukesUp and ps.samCount < 2 and roll < 0.5 then
		wanted = B.SAM
	elseif ps.portCount < 3 and roll < 0.45 then
		wanted = B.PORT
	elseif roll < 0.78 then
		wanted = B.CITY
	else
		wanted = B.DEFENSE
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

	local allies = state.alliances[slot] or {}

	-- Trahison : le bot rompt quand son allie est devenu nettement plus faible
	-- que lui et qu'ils partagent une frontiere. C'est exactement le calcul
	-- qu'un humain fait, rendu visible.
	for ally in allies do
		local mine = strengthOf(state, slot)
		local theirs = strengthOf(state, ally)
		if theirs > 0 and mine > theirs * 2.2 and rng:NextNumber() < 0.25 then
			local contacts = neighborFactions(state, slot)
			if contacts[ally] and contacts[ally] > 4 then
				Diplomacy.breakAlliance(state, slot, ally)
				return
			end
		end
	end

	-- Proposer une alliance a un voisin plus fort : la peur cree les pactes.
	if rng:NextNumber() < 0.3 then
		local contacts = neighborFactions(state, slot)
		for other in contacts do
			if other ~= NEUTRAL and not allies[other] then
				if strengthOf(state, other) > strengthOf(state, slot) * 1.3 then
					Diplomacy.request(state, slot, other)
					return
				end
			end
		end
	end
end

local function decideNavy(state: GameState, ps: GameState.PlayerState, rng: Random)
	if ps.troops < Config.MIN_BOAT_TROOPS * 4 then
		return
	end

	local contacts = neighborFactions(state, ps.slot)
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

	local kind = if ps.gold >= Config.NUKE_STATS[Config.NUKE.HYDROGEN].cost
		then Config.NUKE.HYDROGEN
		else Config.NUKE.ATOM

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
		if slot ~= ps.slot and not state:areAllied(ps.slot, slot) and other.tiles > bestTiles then
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

	-- Une tuile quelconque du territoire vise, tiree depuis sa frontiere.
	for index in target.border do
		if rng:NextNumber() < 0.25 then
			Nukes.launch(state, ps.slot, index, kind)
			return
		end
	end
end

local function decideAttack(state: GameState, ps: GameState.PlayerState, rng: Random)
	if ps.troops < Config.MIN_ATTACK_TROOPS * 3 then
		return -- on laisse remonter la reserve
	end

	local contacts = neighborFactions(state, ps.slot)
	local bestTarget: number? = nil
	local bestScore = -math.huge

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
			-- Cible d'autant plus attirante qu'elle est faible par tuile.
			local density = target.troops / math.max(1, target.tiles)
			score = 100 / (1 + density) + contactTiles * 0.5
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
		decideNavy(state, ps, rng)
		decideNuke(state, ps, rng)
	end
end

return Bots
