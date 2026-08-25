--!strict
--[[
	Commerce terrestre, modele OpenFront — le pendant routier du commerce
	maritime de Navy.

	Trois regles portent tout le systeme :

	  1. Une usine n'a qu'UN colis en route a la fois. Son debit, c'est sa
	     cadence — pas le nombre de gares dans son cercle, qui ne sert qu'a
	     offrir des destinations.
	  2. Apres chaque livraison, un temps de rechargement : le camion doit
	     faire le retour avant de repartir.
	  3. L'or est verse A L'ARRIVEE, proportionnel a la distance et au niveau
	     de l'usine — jamais au depart. Entre-temps, la gare cible a pu etre
	     detruite ou capturee : on ne paie que ce qui est reellement livre.

	Le destinataire est toujours une gare du meme reseau, donc de la meme
	faction : contrairement aux navires, un colis ne paie qu'un camp. Pas de
	fil de notifications non plus — une usine livre toutes les sept secondes,
	le fil serait sature ; le "+X or" flottant au-dessus de la gare est le
	seul retour, exactement comme dans le jeu de reference.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local GameState = require(script.Parent.GameState)
type GameState = GameState.GameState

local Trade = {}

local B = Config.BUILDING

-- Les gares valides comme destination : tout ce qui appartient au reseau.
local IS_DESTINATION = {
	[B.CITY] = true,
	[B.CAPITAL] = true,
	[B.PORT] = true,
	[B.FACTORY] = true,
}

local function tileDistance(a: number, b: number): number
	local ax, ay = MapGen.fromIndex(a)
	local bx, by = MapGen.fromIndex(b)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

--[[
	Or d'un "train" / colis — port OF TrainExecution (stops multiples).
	Base + distance × niveau × liens + bonus multi-arrêts.
]]
local function deliveryValue(distance: number, level: number, links: number): number
	local base = Config.TRUCK_GOLD_BASE + distance * Config.TRUCK_GOLD_PER_TILE
	local stopBonus = 1 + math.min(0.8, (links - 1) * (Config.TRAIN_STOP_BONUS or 0.12))
	return base * level * math.max(1, links) * stopBonus
end

--[[
	Expedie un colis depuis une usine vers une de ses gares voisines.

	Le tirage est uniforme sur les liaisons : une usine entouree de cinq gares
	entretient tout son reseau au lieu de favoriser toujours la meme.
]]
local function dispatch(state: GameState, rng: Random, index: number, factory: GameState.Building, onEvent: (string, number, number, number, number) -> ())
	local links = factory.links
	if #links == 0 then
		return
	end
	local target = links[rng:NextInteger(1, #links)]
	local distance = tileDistance(index, target)
	local travel = math.max(1, math.ceil(distance / Config.TRUCK_SPEED))

	state.tradeDeliveries[index] = {
		to = target,
		slot = factory.slot,
		level = factory.level,
		links = #links,
		distance = distance,
		arrivalTick = state.tick + travel,
	}
	onEvent("dispatch", index, target, factory.slot, travel)
end

--[[
	Le colis arrive a quai.

	Tout est reverifie ici plutot qu'au depart : entre les deux, l'usine a pu
	changer de main et la gare a pu tomber. Payer sur la foi des conditions de
	depart recompenserait une route qui n'existe plus.
]]
local function resolve(state: GameState, index: number, delivery, onEvent: (string, number, number, number, number) -> ())
	local factory = state.buildings[index]
	if not factory or factory.kind ~= B.FACTORY or factory.slot ~= delivery.slot then
		return
	end
	local target = state.buildings[delivery.to]
	if not target or target.slot ~= delivery.slot or not IS_DESTINATION[target.kind] then
		return
	end

	local ps = state.players[delivery.slot]
	if not ps then
		return
	end

	local gold = deliveryValue(delivery.distance, factory.level, delivery.links)
	ps.gold += gold
	onEvent("arrival", delivery.to, 0, delivery.slot, math.floor(gold))
end

function Trade.step(state: GameState, rng: Random, onEvent: (string, number, number, number, number) -> ())
	-- Menage : une usine detruite ou capturee emporte son colis avec elle.
	for index, delivery in state.tradeDeliveries do
		local factory = state.buildings[index]
		if not factory or factory.kind ~= B.FACTORY or factory.slot ~= delivery.slot then
			state.tradeDeliveries[index] = nil
			state.tradeCooldowns[index] = nil
		end
	end

	-- Iteration triee : sans elle, l'ordre des appels au generateur aleatoire
	-- depend de l'ordre interne de la table, et deux serveurs partis de la
	-- meme graine divergeraient des le premier colis.
	local factories: { number } = {}
	for index, building in state.buildings do
		if building.kind == B.FACTORY then
			table.insert(factories, index)
		end
	end
	table.sort(factories)

	for _, index in factories do
		local factory = state.buildings[index]
		local delivery = state.tradeDeliveries[index]
		if delivery then
			if state.tick >= delivery.arrivalTick then
				resolve(state, index, delivery, onEvent)
				state.tradeDeliveries[index] = nil
				-- Le camion doit faire le retour avant de repartir.
				state.tradeCooldowns[index] = state.tick + Config.TRUCK_COOLDOWN
			end
		elseif state.tick >= (state.tradeCooldowns[index] or 0) then
			dispatch(state, rng, index, factory, onEvent)
		end
	end
end

return Trade
