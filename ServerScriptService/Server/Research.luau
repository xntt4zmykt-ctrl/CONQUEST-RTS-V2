--!strict
--[[
	Avancement technologique.

	L'ere d'un joueur est le seul verrou de progression du jeu : elle decide ce
	qu'il peut construire, et notamment quand il accede a l'arme nucleaire.

	L'ancien systeme deverrouillait le nucleaire quand 55 % des terres etaient
	colonisees. C'etait une erreur : avec douze factions, ce seuil tombait en
	moins d'une minute, et la course technologique n'existait pas. Ici, chaque
	joueur paye et developpe son propre avancement, donc le rythme depend de ce
	qu'il fait et non de ce que font les autres.

	Les conditions ne sont volontairement pas que monetaires : exiger des villes
	et des bunkers force a construire un empire, pas seulement a accumuler.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BuildingDefs = require(ReplicatedStorage.Shared.BuildingDefs)
local Eras = require(ReplicatedStorage.Shared.Eras)
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState

local Research = {}

--[[
	Cout reel de la prochaine ere pour un joueur, remise des laboratoires
	comprise. C'est ce que la Science apporte : elle ne debloque rien par
	elle-meme, elle raccourcit la course technologique — donc investir tot dans
	des laboratoires est un pari sur la duree de la partie.
]]
function Research.eraCost(state: GameState, slot: number): number
	local ps = state.players[slot]
	if not ps or ps.era >= Eras.MAX_ID then
		return 0
	end

	local labs = ps.buildingCounts[Config.BUILDING.LAB] or 0
	local discount = math.min(labs * Config.LAB_ERA_DISCOUNT, Config.LAB_DISCOUNT_CAP)
	local modeMultiplier = if state.mode then state.mode.eraCostMultiplier else 1
	return math.floor(Eras.get(ps.era + 1).cost * (1 - discount) * modeMultiplier)
end

--[[
	Renvoie (possible, raison). La raison est affichee telle quelle au joueur,
	donc elle doit toujours indiquer ce qui manque exactement — "conditions non
	remplies" n'aide personne a savoir quoi faire.
]]
function Research.canAdvance(state: GameState, slot: number): (boolean, string?)
	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	if ps.era >= Eras.MAX_ID then
		return false, "Tu as atteint la derniere ere."
	end

	local next = Eras.get(ps.era + 1)

	if ps.tiles < next.requiredTiles then
		return false, `Il te faut {next.requiredTiles} territoires ({ps.tiles} actuellement).`
	end

	for kind, count in next.requiredBuildings do
		local owned = ps.buildingCounts[kind] or 0
		if owned < count then
			local def = BuildingDefs.get(kind)
			local name = if def then def.name else "batiment"
			return false, `Il te faut {count} x {name} ({owned} actuellement).`
		end
	end

	local cost = Research.eraCost(state, slot)
	if ps.gold < cost then
		return false, `Il te faut {cost} d'or ({math.floor(ps.gold)} actuellement).`
	end

	return true, nil
end

function Research.advance(state: GameState, slot: number): (boolean, string?)
	local ok, reason = Research.canAdvance(state, slot)
	if not ok then
		return false, reason
	end

	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	local next = Eras.get(ps.era + 1)
	ps.gold -= Research.eraCost(state, slot)
	ps.era += 1

	-- Franchir le seuil atomique est un evenement public : les voisins doivent
	-- pouvoir reagir avant que le premier missile parte, sinon la menace
	-- nucleaire n'a aucune valeur diplomatique.
	if ps.era >= 4 then
		state:notify(`{next.symbol} {ps.name} entre dans l'ere {next.name} !`, "alert")
	else
		state:notify(`{next.symbol} Ere {next.name} atteinte.`, "good", slot)
	end
	state:sound("eraAdvance", slot)

	return true, `Ere {next.name} atteinte.`
end

--[[
	Somme a mettre de cote pour la prochaine ere quand **seul l'or manque**.

	Sans cette notion, un bot depense chaque piece des qu'il peut s'offrir un
	batiment et n'atteint jamais un palier a cinq chiffres : la simulation ne
	produisait plus aucun silo. Renvoie 0 tant qu'une autre condition bloque —
	epargner avant d'avoir le territoire requis serait du gaspillage.
]]
function Research.goldReserveFor(state: GameState, slot: number): number
	local ps = state.players[slot]
	if not ps or ps.era >= Eras.MAX_ID then
		return 0
	end

	local next = Eras.get(ps.era + 1)

	if ps.tiles < next.requiredTiles then
		return 0
	end
	for kind, count in next.requiredBuildings do
		if (ps.buildingCounts[kind] or 0) < count then
			return 0
		end
	end

	return Research.eraCost(state, slot)
end

--[[
	Progression vers l'ere suivante, entre 0 et 1, pour la barre d'interface.
	On prend le minimum des trois criteres : c'est celui qui bloque, et donc le
	seul chiffre utile a afficher.
]]
function Research.progress(state: GameState, slot: number): number
	local ps = state.players[slot]
	if not ps or ps.era >= Eras.MAX_ID then
		return 1
	end

	local next = Eras.get(ps.era + 1)
	local cost = Research.eraCost(state, slot)
	local ratios = {
		if cost > 0 then ps.gold / cost else 1,
		if next.requiredTiles > 0 then ps.tiles / next.requiredTiles else 1,
	}

	for kind, count in next.requiredBuildings do
		table.insert(ratios, (ps.buildingCounts[kind] or 0) / count)
	end

	local lowest = 1
	for _, ratio in ratios do
		lowest = math.min(lowest, ratio)
	end
	return math.clamp(lowest, 0, 1)
end

return Research
