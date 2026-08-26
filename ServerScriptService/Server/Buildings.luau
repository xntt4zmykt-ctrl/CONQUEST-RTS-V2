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

--=============================================================================
-- Branchement de l'etat serveur sur le resolveur partage
--=============================================================================

function Buildings.contextFor(state: GameState, slot: number): Placement.Context?
	local ps = state.players[slot]
	if not ps then
		return nil
	end

	return {
		slot = slot,
		era = ps.era,
		gold = ps.gold,
		terrain = state.terrain,
		ownerAt = function(index: number): number
			return buffer.readu8(state.owner, index)
		end,
		buildingAt = function(index: number): (number?, number?, number?)
			local building = state.buildings[index]
			if not building then
				return nil, nil, nil
			end
			return building.kind, building.slot, building.level
		end,
	}
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
		local cityPop = Config.CITY_LEVELS[1].popCapBonus
		return `Ville construite : +{cityPop} capacite · +{Config.GOLD_PER_CITY} or/tick.{suffix}`
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
-- N59 : index samsBySlot (recette N57), fallback hash si l'index est nil.
function Buildings.samsOf(state: GameState, slot: number): { number }
	local out = {}
	if state.samsBySlot then
		local set = state.samsBySlot[slot]
		if set then
			for index in set do
				table.insert(out, index)
			end
		end
		return out
	end
	for index, building in state.buildings do
		if building.slot == slot and building.kind == B.SAM then
			table.insert(out, index)
		end
	end
	return out
end

-- N60 : SAM via samsBySlot. Les silos portent aussi un cooldown
-- (Nukes.launch / SILO_COOLDOWN) — la spec N60 « aucun autre cooldown
-- vivant » etait fausse ; sans silosBySlot un silo resterait arme a jamais.
function Buildings.stepCooldowns(state: GameState)
	local sams = state.samsBySlot
	local silos = state.silosBySlot
	if sams == nil and silos == nil then
		for _, building in state.buildings do
			if building.cooldown > 0 then
				building.cooldown -= 1
			end
		end
		return
	end
	if sams then
		for _, set in sams do
			for index in set do
				local building = state.buildings[index]
				if building and building.cooldown > 0 then
					building.cooldown -= 1
				end
			end
		end
	end
	if silos then
		for _, set in silos do
			for index in set do
				local building = state.buildings[index]
				if building and building.cooldown > 0 then
					building.cooldown -= 1
				end
			end
		end
	end
end

return Buildings
