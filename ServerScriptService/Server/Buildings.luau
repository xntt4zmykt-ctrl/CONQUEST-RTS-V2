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
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState

local Buildings = {}

local B = Config.BUILDING

function Buildings.priceFor(state: GameState, slot: number, kind: number): number
	local def = BuildingDefs.get(kind)
	if not def then
		return math.huge
	end
	return math.floor(def.cost * state:doctrineOf(slot).buildCost)
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

	if kind == B.SILO or kind == B.SAM then
		if not Buildings.nukesUnlocked(state) then
			return false, "Technologie nucleaire pas encore disponible."
		end
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

	local def = BuildingDefs.get(kind)
	return true, if def then `{def.name} construit.` else nil
end

-- Le nucleaire ne s'ouvre qu'une fois la carte largement partagee, pour qu'il
-- soit un climax de fin de partie et pas une strategie d'ouverture.
function Buildings.nukesUnlocked(state: GameState): boolean
	return state:colonizedRatio() >= Config.NUKE_UNLOCK_LAND_RATIO
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
