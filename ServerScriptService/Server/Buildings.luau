--!strict
--[[
	Validation et pose des batiments.

	Toute la validation est ici et nulle part ailleurs : le client propose, ce
	module dispose. Une regle ajoutee ici est automatiquement appliquee aux
	joueurs comme aux bots.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local BuildingDefs = require(ReplicatedStorage.Shared.BuildingDefs)
local Eras = require(ReplicatedStorage.Shared.Eras)
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState

local Buildings = {}

local B = Config.BUILDING

--[[
	Prix courant d'un batiment pour un joueur donne.

	Le cout croit avec le nombre deja possede : le dixieme bunker coute bien
	plus cher que le premier. C'est ce qui empeche un empire riche de saturer la
	carte, et ce qui rend l'expansion economique reellement couteuse a soutenir.
]]
function Buildings.priceFor(state: GameState, slot: number, kind: number): number
	local def = BuildingDefs.get(kind)
	if not def then
		return math.huge
	end

	local ps = state.players[slot]
	local owned = if ps then (ps.buildingCounts[kind] or 0) else 0
	local inflation = 1 + owned * Config.BUILD_COST_SCALING

	return math.floor(def.cost * inflation * state:doctrineOf(slot).buildCost)
end

--[[
	Renvoie (autorise, raison). La raison est renvoyee telle quelle au joueur,
	donc elle doit etre exploitable — jamais un simple "impossible".
]]
function Buildings.canBuild(state: GameState, slot: number, index: number, kind: number): (boolean, string?)
	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	local def = BuildingDefs.get(kind)
	if not def then
		return false, "Batiment inconnu."
	end

	-- La capitale est posee par le moteur au spawn : elle ne doit jamais etre
	-- accessible depuis un ordre client, meme forge a la main.
	if not def.buildable then
		return false, "Ce batiment ne se construit pas."
	end

	if index < 0 or index >= Config.TILE_COUNT then
		return false, "Position hors carte."
	end

	if buffer.readu8(state.owner, index) ~= slot then
		return false, "Tu ne controles pas ce territoire."
	end

	if not state:isLand(index) then
		return false, "Impossible de construire en mer."
	end

	if state.buildings[index] then
		return false, "Il y a deja un batiment ici."
	end

	if def.coastalOnly and not MapGen.isCoastal(state.terrain, index) then
		return false, "Un port doit etre construit sur la cote."
	end

	local requiredEra = Eras.requiredFor(kind)
	if ps.era < requiredEra then
		local era = Eras.get(requiredEra)
		return false, `Necessite l'ere {era.name}.`
	end

	local price = Buildings.priceFor(state, slot, kind)
	if ps.gold < price then
		return false, `Il te faut {price} d'or ({math.floor(ps.gold)} disponible).`
	end

	-- Espacement minimal : evite les grappes de villes sur une seule tuile de
	-- large et force a repartir ses investissements sur le territoire.
	local cx, cy = MapGen.fromIndex(index)
	local spacing = Config.BUILD_MIN_SPACING
	for dy = -spacing, spacing do
		for dx = -spacing, spacing do
			if dx * dx + dy * dy <= spacing * spacing then
				local nx, ny = cx + dx, cy + dy
				if MapGen.inBounds(nx, ny) then
					local other = state.buildings[MapGen.toIndex(nx, ny)]
					if other and other.kind == kind then
						return false, `Trop proche d'un autre batiment du meme type.`
					end
				end
			end
		end
	end

	return true, nil
end

function Buildings.build(state: GameState, slot: number, index: number, kind: number): (boolean, string?)
	local ok, reason = Buildings.canBuild(state, slot, index, kind)
	if not ok then
		return false, reason
	end

	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	ps.gold -= Buildings.priceFor(state, slot, kind)
	state:placeBuilding(index, kind, slot)
	state:sound("buildPlace", slot)

	local def = BuildingDefs.get(kind)
	return true, if def then `{def.name} construit.` else nil
end

-- Le nucleaire depend desormais de l'ere du joueur, pas de l'etat de la carte.
function Buildings.nukesUnlocked(state: GameState, slot: number): boolean
	local ps = state.players[slot]
	return ps ~= nil and ps.era >= Eras.requiredForNuke(Config.NUKE.ATOM)
end

-- Batteries SAM du joueur, utilisees par le systeme d'interception.
function Buildings.samsOf(state: GameState, slot: number): { number }
	local out = {}
	for index, building in state.buildings do
		if building.slot == slot and building.kind == B.SAM then
			table.insert(out, index)
		end
	end
	return out
end

function Buildings.stepCooldowns(state: GameState)
	for _, building in state.buildings do
		if building.cooldown > 0 then
			building.cooldown -= 1
		end
	end
end

return Buildings
