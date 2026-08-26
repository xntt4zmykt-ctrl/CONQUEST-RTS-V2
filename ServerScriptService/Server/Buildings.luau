--!strict
--[[
	Pose et amelioration des batiments, cote autoritaire.

	Toute la *regle* de placement vit dans Shared/Placement : ce module ne fait
	que brancher l'etat serveur dessus et executer le resultat. C'est
	deliberement mince — client et serveur doivent evaluer la meme fonction sur
	les memes donnees, sinon le fantome de placement et la realite divergent, ce
	qui a ete une source de bugs pendant toute la vie du projet.

	Le contrat a change : un ordre de construction ne se refuse plus parce que la
	tuile visee est occupee, trop proche ou mal orientee. Il s'accroche a la
	meilleure tuile valide du voisinage, ou bascule en amelioration si un
	batiment du meme type est deja la.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BuildingDefs = require(ReplicatedStorage.Shared.BuildingDefs)
local Placement = require(ReplicatedStorage.Shared.Placement)
local Eras = require(ReplicatedStorage.Shared.Eras)
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState

local Buildings = {}

local B = Config.BUILDING

-- V30 : prix HUD par slot (recette feel N75 / factoryBuf). Pas de dirty
-- flag : buildingCounts bouge souvent en combat ; clear+refill suffit.
-- Pas reentrant — un seul replicate() par tick. Slot inconnu →
-- emptyPriceBuf, pas math.huge. GameState ne doit pas require Buildings
-- (cycle).
local priceBuf: { [number]: { [number]: number } } = {}
local emptyPriceBuf: { [number]: number } = {}

-- V40 : ctx de placement recycle (recette feel N85). Record unique +
-- closures module qui lisent ctxState. Pas reentrant — resolve est
-- synchrone et unique. Slot inconnu → nil SANS muter ctxBuf. Ne pas
-- table.clone. Ne pas stocker au-dela de Placement.resolve. Le client
-- (PlacementPreview / init.client) construit SES closures — ce buffer
-- n'existe pas cote Overlay.
local ctxState: GameState? = nil

local function ownerAt(index: number): number
	local state = ctxState :: GameState
	return buffer.readu8(state.owner, index)
end

local function buildingAt(index: number): (number?, number?, number?)
	local state = ctxState :: GameState
	local building = state.buildings[index]
	if not building then
		return nil, nil, nil
	end
	return building.kind, building.slot, building.level
end

local ctxBuf: Placement.Context = {
	slot = 0,
	era = 0,
	gold = 0,
	terrain = buffer.create(1),
	ownerAt = ownerAt,
	buildingAt = buildingAt,
}

--=============================================================================
-- Branchement de l'etat serveur sur le resolveur partage
--=============================================================================

function Buildings.contextFor(state: GameState, slot: number): Placement.Context?
	local ps = state.players[slot]
	if not ps then
		return nil
	end

	ctxState = state
	ctxBuf.slot = slot
	ctxBuf.era = ps.era
	ctxBuf.gold = ps.gold
	ctxBuf.terrain = state.terrain
	ctxBuf.ownerAt = ownerAt
	ctxBuf.buildingAt = buildingAt
	return ctxBuf
end

--[[
	Prix courant d'un batiment pour un joueur donne.

	Doublement borne, avec compteur partage entre le port et l'usine : voir
	Config.BUILD_COST_CAP_MULT et Config.BUILD_COST_GROUPS.
]]
function Buildings.priceFor(state: GameState, slot: number, kind: number): number
	local ps = state.players[slot]
	if not ps then
		return math.huge
	end
	return Placement.priceFor(ps.buildingCounts, kind, state:doctrineOf(slot).buildCost)
end

--[[
	V30 : map des prix BUILDABLE pour un slot, recyclee. Wire inchange
	`{ [kind]: number }`. Ne duplique pas Placement.priceFor. Appeler
	depuis init.server — pas depuis GameState (cycle require).
]]
function Buildings.pricesFor(state: GameState, slot: number): { [number]: number }
	if not state.players[slot] then
		table.clear(emptyPriceBuf)
		return emptyPriceBuf
	end
	local buf = priceBuf[slot]
	if buf == nil then
		buf = {}
		priceBuf[slot] = buf
	else
		table.clear(buf)
	end
	for _, def in BuildingDefs.BUILDABLE do
		buf[def.id] = Buildings.priceFor(state, slot, def.id)
	end
	return buf
end

--[[
	Que ferait un clic sur cette tuile ? Renvoie la resolution ou une raison.

	Les seules raisons possibles sont l'ere, l'or, le territoire etranger et
	l'absence totale de place a portee. Aucune n'est un probleme de precision de
	visee, et c'est tout l'interet.
]]
function Buildings.resolve(state: GameState, slot: number, index: number, kind: number): (Placement.Resolution?, string?)
	local ctx = Buildings.contextFor(state, slot)
	if not ctx then
		return nil, "Faction inconnue."
	end
	local ps = state.players[slot]
	if not ps then
		return nil, "Faction inconnue."
	end
	return Placement.resolve(ctx, index, kind, ps.buildingCounts, state:doctrineOf(slot).buildCost)
end

--=============================================================================
-- Execution
--=============================================================================

local function describeBuild(state: GameState, slot: number, index: number, kind: number, snapped: boolean): string
	local def = BuildingDefs.get(kind)
	local name = if def then def.name else "Batiment"
	-- Le mot "reporte" est important : sans lui le joueur croit avoir mal
	-- clique alors que le moteur a fait exactement ce qu'il voulait.
	local suffix = if snapped then " (reporte sur la case libre la plus proche)" else ""

	if kind == B.CITY then
		return `Ville construite : +900 capacite · +{Config.GOLD_PER_CITY} or/tick.{suffix}`
	elseif kind == B.FACTORY then
		local routes, income = state:logisticsFor(slot)
		return `Usine raccordee : reseau de {routes} liaison(s) · +{string.format("%.1f", income * Config.TICK_RATE)} or/s.{suffix}`
	elseif kind == B.PORT then
		return `Port ouvert : debarquements et routes commerciales.{suffix}`
	end
	return `{name} construit.{suffix}`
end

local function describeUpgrade(state: GameState, slot: number, index: number, kind: number, level: number): string
	if kind == B.CITY then
		local city = Config.CITY_LEVELS[level]
		return `{city.name} niveau {level} : {city.popCapBonus} population max · +{city.goldBonus} or/tick.`
	elseif kind == B.FACTORY then
		local routes, income = state:logisticsFor(slot)
		return `Usine niveau {level} : reseau de {routes} liaison(s) · +{string.format("%.1f", income * Config.TICK_RATE)} or/s.`
	elseif kind == B.PORT then
		return `Port niveau {level} : +{string.format("%.2f", Config.GOLD_PER_PORT)} or/tick supplementaire.`
	end
	local def = BuildingDefs.get(kind)
	return `{if def then def.name else "Batiment"} niveau {level}.`
end

--[[
	Execute un ordre de construction.

	Un seul point d'entree pour poser et pour ameliorer : c'est ce qui permet a
	l'interface de n'avoir qu'un bouton par type de batiment. Le moteur decide,
	le joueur n'a pas de mode a choisir.
]]
function Buildings.build(state: GameState, slot: number, index: number, kind: number): (boolean, string?)
	local resolution, reason = Buildings.resolve(state, slot, index, kind)
	if not resolution then
		return false, reason
	end

	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	ps.gold -= resolution.price
	ps.buildingsBuilt += 1
	state:sound("buildPlace", slot)

	if resolution.action == "upgrade" then
		local level = state:upgradeBuilding(resolution.tile)
		if not level then
			-- Ne devrait pas arriver : la resolution vient d'etre calculee sur
			-- cet etat. On rembourse plutot que de facturer dans le vide.
			ps.gold += resolution.price
			ps.buildingsBuilt -= 1
			return false, "Ce batiment n'a pas pu evoluer."
		end
		return true, describeUpgrade(state, slot, resolution.tile, kind, level)
	end

	state:placeBuilding(resolution.tile, kind, slot)
	return true, describeBuild(state, slot, resolution.tile, kind, resolution.tile ~= index)
end

--[[
	Conserve pour les appelants qui ne connaissent qu'une amelioration : la fiche
	de territoire, qui vise un batiment precis et non une intention de placement.
]]
function Buildings.upgradeAt(state: GameState, slot: number, index: number): (boolean, string?)
	local building = state.buildings[index]
	if not building then
		return false, "Selectionne un batiment a ameliorer."
	end
	if building.slot ~= slot or buffer.readu8(state.owner, index) ~= slot then
		return false, "Ce batiment ne t'appartient pas."
	end
	if not BuildingDefs.isUpgradable(building.kind) then
		return false, "Ce batiment n'a pas de niveau superieur."
	end
	if building.level >= BuildingDefs.maxLevel(building.kind) then
		return false, "Ce batiment a atteint son niveau maximum."
	end

	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	local modifier = state:doctrineOf(slot).buildCost
	local price = Placement.upgradePriceFor(ps.buildingCounts, building.kind, building.level, modifier)
	if price == math.huge then
		return false, "Ce batiment a atteint son niveau maximum."
	end
	local requiredEra = Placement.upgradeRequiredEra(building.kind, building.level)
	if ps.era < requiredEra then
		return false, `Necessite l'ere {Eras.get(requiredEra).name}.`
	end
	if ps.gold < price then
		return false, `Il te faut {price} d'or ({math.floor(ps.gold)} disponible).`
	end

	local kind = building.kind
	ps.gold -= price
	local level = state:upgradeBuilding(index)
	if not level then
		ps.gold += price
		return false, "Ce batiment n'a pas pu evoluer."
	end
	ps.buildingsBuilt += 1
	state:sound("buildPlace", slot)
	return true, describeUpgrade(state, slot, index, kind, level)
end

-- Anciens noms, conserves parce que le banc d'essai et les bots les utilisent.
Buildings.upgradeCity = Buildings.upgradeAt

function Buildings.upgradePrice(state: GameState, slot: number, index: number): number
	local building = state.buildings[index]
	local ps = state.players[slot]
	if not building or not ps or not BuildingDefs.isUpgradable(building.kind) then
		return math.huge
	end
	if building.level >= BuildingDefs.maxLevel(building.kind) then
		return math.huge
	end
	return Placement.upgradePriceFor(ps.buildingCounts, building.kind, building.level, state:doctrineOf(slot).buildCost)
end

Buildings.cityUpgradePrice = Buildings.upgradePrice

--=============================================================================
-- Interrogations
--=============================================================================

-- Le nucleaire depend de l'ere du joueur, pas de l'etat de la carte.
function Buildings.nukesUnlocked(state: GameState, slot: number): boolean
	local ps = state.players[slot]
	return ps ~= nil and ps.era >= Eras.requiredForNuke(Config.NUKE.ATOM)
end

-- Batteries SAM du joueur, utilisees par le systeme d'interception.
-- Source = index `samsBySlot`. Slot sans SAM = buffer vide (pas de rescan hash).
-- V25 : buffer recycle. Unique appelant synchrone (Bots.decideNuke).
-- Pas reentrant — dupliquer le buffer si un second appelant concurrent apparait.
local samBuf: { number } = table.create(8)

function Buildings.samsOf(state: GameState, slot: number): { number }
	local out = samBuf
	local n = 0
	local bySlot = state.samsBySlot
	if bySlot then
		local set = bySlot[slot]
		if set then
			for index in set do
				n += 1
				out[n] = index
			end
		end
	else
		for index, building in state.buildings do
			if building.slot == slot and building.kind == B.SAM then
				n += 1
				out[n] = index
			end
		end
	end
	for i = #out, n + 1, -1 do
		out[i] = nil
	end
	return out
end

--[[
	Arme un cooldown et inscrit la tuile dans coolingBuildings (V19).
	Unique point d'ecriture : intercept SAM et tir silo. Sans ce flag,
	stepCooldowns (O(actifs)) n'aurait jamais connaissance du compteur.
	SAM-only gelerait SILO_COOLDOWN : les deux kinds passent ici.
]]
function Buildings.armCooldown(state: GameState, index: number, duration: number)
	local building = state.buildings[index]
	if not building then
		return
	end
	building.cooldown = duration
	if duration > 0 and state.coolingBuildings then
		state.coolingBuildings[index] = true
	end
end

function Buildings.stepCooldowns(state: GameState)
	local cooling = state.coolingBuildings
	if cooling then
		-- V19 contrat A : O(actifs), pas O(buildings). SAM et silos.
		for index in cooling do
			local building = state.buildings[index]
			if not building then
				cooling[index] = nil
				continue
			end
			if building.cooldown > 0 then
				building.cooldown -= 1
			end
			if building.cooldown <= 0 then
				cooling[index] = nil
			end
		end
		return
	end
	for _, building in state.buildings do
		if building.cooldown > 0 then
			building.cooldown -= 1
		end
	end
end

return Buildings
