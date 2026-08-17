--!strict
--[[
	Diplomatie.

	C'est le vrai differenciateur du jeu, donc les traites ne sont pas
	declaratifs : ils sont mecaniques. Une alliance empeche reellement l'attaque
	au niveau du moteur. Pour frapper un allie, il faut d'abord rompre le pacte
	publiquement — ce qui laisse a la victime le temps de reagir et inscrit la
	trahison au compteur permanent du traitre.

	L'embargo, lui, donne a la diplomatie un poids economique : couper les
	routes commerciales d'un rival lui coute de l'or a chaque tick.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState

local Diplomacy = {}

local function ensure(map: { [number]: { [number]: any } }, slot: number)
	if not map[slot] then
		map[slot] = {}
	end
end

--=============================================================================
-- Alliances
--=============================================================================

function Diplomacy.request(state: GameState, from: number, to: number): (boolean, string?)
	if from == to then
		return false, "Cible invalide."
	end
	local a, b = state.players[from], state.players[to]
	if not a or not b then
		return false, "Cette faction n'existe plus."
	end
	if state:areAllied(from, to) then
		return false, "Vous etes deja allies."
	end

	ensure(state.requests, from)

	-- Si l'autre nous avait deja demande, la demande croisee vaut acceptation.
	local theirs = state.requests[to]
	if theirs and theirs[from] then
		return Diplomacy.accept(state, to, from)
	end

	state.requests[from][to] = state.tick + Config.ALLIANCE_REQUEST_TIMEOUT
	state:notify(`{a.name} te propose une alliance.`, "info", to)
	return true, `Proposition envoyee a {b.name}.`
end

function Diplomacy.accept(state: GameState, from: number, to: number): (boolean, string?)
	-- `from` est l'auteur de la demande, `to` celui qui accepte.
	local requests = state.requests[from]
	if not requests or not requests[to] then
		return false, "Aucune proposition en cours."
	end
	requests[to] = nil

	local a, b = state.players[from], state.players[to]
	if not a or not b then
		return false, "Cette faction n'existe plus."
	end

	ensure(state.alliances, from)
	ensure(state.alliances, to)
	state.alliances[from][to] = true
	state.alliances[to][from] = true

	-- Une alliance annule automatiquement les offensives en cours entre les
	-- deux camps : sinon on signe la paix pendant que ses troupes avancent.
	for i = #state.attacks, 1, -1 do
		local atk = state.attacks[i]
		if (atk.attacker == from and atk.target == to) or (atk.attacker == to and atk.target == from) then
			local attacker = state.players[atk.attacker]
			if attacker then
				attacker.troops += math.max(0, atk.troops)
			end
			table.remove(state.attacks, i)
		end
	end

	state:notifyBetween(`\u{1F91D} {a.name} et {b.name} ont signe une alliance.`, "info", from, to)
	return true, nil
end

function Diplomacy.decline(state: GameState, from: number, to: number): (boolean, string?)
	local requests = state.requests[from]
	if requests then
		requests[to] = nil
	end
	return true, nil
end

--[[
	Rompre une alliance est une trahison publique et permanente. C'est le
	moment le plus important du jeu : il doit couter quelque chose que le
	joueur emporte hors de la partie.
]]
function Diplomacy.breakAlliance(state: GameState, from: number, to: number): (boolean, string?)
	if not state:areAllied(from, to) then
		return false, "Vous n'etes pas allies."
	end

	local a, b = state.players[from], state.players[to]
	if not a or not b then
		return false, "Cette faction n'existe plus."
	end

	state.alliances[from][to] = nil
	state.alliances[to][from] = nil

	a.betrayals += Config.BETRAYAL_REPUTATION_COST
	a.traitorUntil = state.tick + Config.TRAITOR_MARK_DURATION

	state:notifyBetween(`\u{26A0} {a.name} a TRAHI {b.name} !`, "alert", from, to)

	return true, "Alliance rompue. Ta reputation en portera la marque."
end

--=============================================================================
-- Embargos
--=============================================================================

function Diplomacy.setEmbargo(state: GameState, from: number, to: number, active: boolean): (boolean, string?)
	if from == to then
		return false, "Cible invalide."
	end
	local b = state.players[to]
	if not b then
		return false, "Cette faction n'existe plus."
	end

	ensure(state.embargoes, from)
	state.embargoes[from][to] = if active then true else nil

	if active then
		state:notify(`Embargo declare contre {b.name}.`, "info", from)
		state:notify(`{state.players[from] and state.players[from].name} t'a impose un embargo.`, "info", to)
	end

	return true, nil
end

--=============================================================================
-- Tick
--=============================================================================

function Diplomacy.step(state: GameState)
	-- Expiration des propositions non traitees.
	for from, targets in state.requests do
		for to, expiry in targets do
			if state.tick >= expiry then
				targets[to] = nil
			end
		end
	end
end

--[[
	Vue diplomatique d'un joueur donne : ce module est le seul a connaitre la
	structure interne des relations, le reseau n'en voit qu'une projection.
]]
function Diplomacy.viewFor(state: GameState, slot: number)
	local allies: { [number]: boolean } = {}
	local incoming: { [number]: boolean } = {}
	local outgoing: { [number]: boolean } = {}
	local embargoes: { [number]: boolean } = {}
	local traitors: { [number]: boolean } = {}

	local allySet = state.alliances[slot]
	if allySet then
		for other in allySet do
			allies[other] = true
		end
	end

	local myRequests = state.requests[slot]
	if myRequests then
		for other in myRequests do
			outgoing[other] = true
		end
	end

	for other, targets in state.requests do
		if targets[slot] then
			incoming[other] = true
		end
	end

	local myEmbargoes = state.embargoes[slot]
	if myEmbargoes then
		for other in myEmbargoes do
			embargoes[other] = true
		end
	end

	for otherSlot, ps in state.players do
		if ps.traitorUntil > state.tick then
			traitors[otherSlot] = true
		end
	end

	return {
		allies = allies,
		incoming = incoming,
		outgoing = outgoing,
		embargoes = embargoes,
		traitors = traitors,
	}
end

return Diplomacy
