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
local QuickChat = require(ReplicatedStorage.Shared.QuickChat)
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState

local Diplomacy = {}

-- V33 : vue diplomatique recyclee par slot. Un buffer global unique
-- casserait le FireClient precedent (boucle humains sequentielle :
-- clear trop tot). HUD / tests lisent les champs tout de suite.
-- Recette feel N78. Garder requestIsLive / areAllied visuels.
type ViewRec = {
	allies: { [number]: boolean },
	incoming: { [number]: boolean },
	outgoing: { [number]: boolean },
	embargoes: { [number]: boolean },
	traitors: { [number]: boolean },
	marks: { [number]: number },
}

local viewBuf: { [number]: ViewRec } = {}

-- V34 : paires expirees recyclees. Collecter avant de muter alliances[]
-- (parcours + ecriture = comportement indefini). Un record par paire
-- (a < b), pas { a, b } anonyme. Non reentrant — step unique par tick.
-- Recette feel N79. Garder le type-guard visuel : `true` legacy continue ;
-- non-number ou numericExpired → expire. Feel N79 ne purge que
-- typeof == "number" — ne pas copier ca (banc « oops » passe 17).
type ExpiredRec = { a: number, b: number }
local expiredBuf: { ExpiredRec } = table.create(8)
local expiredRecPool: { ExpiredRec } = table.create(8)

local function viewRecFor(slot: number): ViewRec
	local rec = viewBuf[slot]
	if rec == nil then
		rec = {
			allies = {},
			incoming = {},
			outgoing = {},
			embargoes = {},
			traitors = {},
			marks = {},
		}
		viewBuf[slot] = rec
	else
		table.clear(rec.allies)
		table.clear(rec.incoming)
		table.clear(rec.outgoing)
		table.clear(rec.embargoes)
		table.clear(rec.traitors)
		table.clear(rec.marks)
	end
	return rec
end

local function ensure(map: { [number]: { [number]: any } }, slot: number)
	if not map[slot] then
		map[slot] = {}
	end
end

-- Expiry numerique atteinte. `true` legacy (pacte sans date) n'expire pas ici.
local function numericExpired(expiry: any, tick: number): boolean
	return typeof(expiry) == "number" and tick >= expiry
end

local function requestIsLive(expiry: any, tick: number): boolean
	return typeof(expiry) == "number" and tick < expiry
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

	-- Carence apres la fin d'un pacte : sans elle, deux camps resignent au tick
	-- suivant l'expiration et la carte se retrouve a nouveau entierement alliee.
	local cooldown = state.allianceCooldowns[from]
	if cooldown and cooldown[to] and state.tick < cooldown[to] then
		local seconds = math.ceil((cooldown[to] - state.tick) / Config.TICK_RATE)
		return false, `Pacte rompu trop recemment. Attends encore {seconds} s.`
	end

	ensure(state.requests, from)

	-- Si l'autre nous avait deja demande, la demande croisee vaut acceptation.
	-- Une inverse perimee n'est plus une offre : on l'efface et on enfile la notre.
	local theirs = state.requests[to]
	if theirs and theirs[from] then
		local invExpiry = theirs[from]
		if typeof(invExpiry) == "number" and state.tick >= invExpiry then
			theirs[from] = nil
		else
			return Diplomacy.accept(state, to, from)
		end
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
	local requestExpiry = requests[to]
	if typeof(requestExpiry) == "number" and state.tick >= requestExpiry then
		requests[to] = nil
		return false, "Proposition expiree."
	end
	requests[to] = nil

	local a, b = state.players[from], state.players[to]
	if not a or not b then
		return false, "Cette faction n'existe plus."
	end

	ensure(state.alliances, from)
	ensure(state.alliances, to)
	-- Un pacte a une date de fin. Voir Config.ALLIANCE_DURATION : une alliance
	-- permanente gelait completement la fin de partie.
	local expiry = state.tick + Config.ALLIANCE_DURATION
	state.alliances[from][to] = expiry
	state.alliances[to][from] = expiry

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
	state:sound("allianceFormed", to)
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
	-- Les intentions de prolongation meurent avec le pacte.
	local extFrom, extTo = state.allianceExtensions[from], state.allianceExtensions[to]
	if extFrom then
		extFrom[to] = nil
	end
	if extTo then
		extTo[from] = nil
	end
	Diplomacy.startCooldown(state, from, to)

	a.betrayals += Config.BETRAYAL_REPUTATION_COST
	a.traitorUntil = state.tick + Config.TRAITOR_MARK_DURATION

	state:notifyBetween(`\u{26A0} {a.name} a TRAHI {b.name} !`, "alert", from, to)
	state:sound("betrayal", to)

	return true, "Alliance rompue. Ta reputation en portera la marque."
end

function Diplomacy.startCooldown(state: GameState, a: number, b: number)
	ensure(state.allianceCooldowns, a)
	ensure(state.allianceCooldowns, b)
	local until_ = state.tick + Config.ALLIANCE_COOLDOWN
	state.allianceCooldowns[a][b] = until_
	state.allianceCooldowns[b][a] = until_
end

--[[
	Prolonge un pacte avant son terme, regle CONQUEST : la prolongation est
	MUTUELLE. Le premier camp marque son intention ; le pacte n'est repousse
	que quand le second marque la sienne. Une prolongation unilaterale
	permettrait a un camp d'enfermer l'autre dans une alliance dont il ne
	veut plus, sans jamais avoir a se justifier.
]]
function Diplomacy.extend(state: GameState, from: number, to: number): (boolean, string?)
	if not state:areAllied(from, to) then
		return false, "Vous n'etes pas allies."
	end

	ensure(state.allianceExtensions, from)
	ensure(state.allianceExtensions, to)

	-- Les deux camps ont marque leur intention : le pacte repart pour une
	-- duree complete a compter de maintenant.
	if state.allianceExtensions[to][from] then
		local newExpiry = state.tick + Config.ALLIANCE_DURATION
		state.alliances[from][to] = newExpiry
		state.alliances[to][from] = newExpiry
		state.allianceExtensions[from][to] = nil
		state.allianceExtensions[to][from] = nil

		local a, b = state.players[from], state.players[to]
		if a and b then
			state:notifyBetween(`\u{1F91D} Le pacte entre {a.name} et {b.name} est prolonge.`, "good", from, to)
		end
		return true, nil
	end

	state.allianceExtensions[from][to] = true
	local a = state.players[from]
	state:notify(`{a and a.name} propose de prolonger votre alliance.`, "info", to)
	return true, "Prolongation proposee : ton allie doit confirmer."
end

--=============================================================================
-- Dons entre allies
--=============================================================================

--[[
	Envoyer de l'or ou des troupes a un allie. C'est ce qui donne un corps a
	l'alliance : sans dons, un pacte n'est qu'un traite de non-agression ;
	avec eux, le plus riche finance reellement le front du plus pauvre.

	Reserve aux allies, comme toute aide directe : financer un futur ennemi
	serait sans consequence diplomatique, et donc sans interet.
]]
function Diplomacy.donateGold(state: GameState, from: number, to: number, amount: number): (boolean, string?)
	if not state:areAllied(from, to) then
		return false, "Les dons sont reserves aux allies."
	end
	local a, b = state.players[from], state.players[to]
	if not a or not b then
		return false, "Cette faction n'existe plus."
	end
	amount = math.floor(amount)
	if amount < Config.MIN_DONATION then
		return false, `Un don doit valoir au moins {Config.MIN_DONATION} or.`
	end
	if a.gold < amount then
		return false, "Tu n'as pas assez d'or."
	end

	a.gold -= amount
	b.gold += amount
	state:notifyBetween(`\u{1F4B0} {a.name} offre {amount} or a {b.name}.`, "good", from, to)
	return true, nil
end

function Diplomacy.donateTroops(state: GameState, from: number, to: number, amount: number): (boolean, string?)
	if not state:areAllied(from, to) then
		return false, "Les dons sont reserves aux allies."
	end
	local a, b = state.players[from], state.players[to]
	if not a or not b then
		return false, "Cette faction n'existe plus."
	end
	amount = math.floor(amount)
	if amount < Config.MIN_DONATION_TROOPS then
		return false, `Un don doit valoir au moins {Config.MIN_DONATION_TROOPS} troupes.`
	end
	if a.troops < amount then
		return false, "Tu n'as pas assez de troupes."
	end

	a.troops -= amount
	-- Le receveur ne depasse jamais son plafond : l'excedent est perdu, comme
	-- des renforts arrives dans des casernes deja pleines.
	local received = math.min(amount, math.max(0, state:maxTroops(b) - b.troops))
	b.troops += received
	state:notifyBetween(`\u{2694} {a.name} envoie {math.floor(received)} troupes a {b.name}.`, "good", from, to)
	return true, nil
end

--=============================================================================
-- Messages rapides
--=============================================================================

--[[
	Diffuse un message rapide. Renvoie true s'il est effectivement parti.

	Cette fonction vit ici plutot que dans le gestionnaire reseau parce que les
	bots doivent l'emprunter aussi. Tant qu'elle etait enfermee dans le
	gestionnaire, seul un humain pouvait parler — et une carte ou onze factions
	sur douze sont muettes ne ressemble pas a une partie, elle ressemble a un
	tableur qui bouge.

	Le refus est silencieux : un message d'erreur sur un anti-spam serait
	lui-meme du spam.
]]
function Diplomacy.sendQuickChat(state: GameState, slot: number, messageId: string, targetSlot: number?): boolean
	local entry = QuickChat.get(messageId)
	if not entry then
		return false
	end

	local last = state.quickChatSent[slot]
	if last and state.tick - last < QuickChat.COOLDOWN then
		return false
	end

	--[[
		On ne radote pas.

		Le cooldown seul laissait passer la meme phrase sur la meme cible en
		boucle : tant qu'une guerre dure, la raison de la dire reste vraie. Le
		fil se remplissait alors d'un seul message repete, et tout le reste —
		trahisons, alertes, politesse — passait dessous sans etre vu.
	]]
	local key = `{messageId}:{targetSlot or 0}`
	local previous = state.quickChatLast[slot]
	if previous == key and last and state.tick - last < Config.QUICKCHAT_REPEAT_TICKS then
		return false
	end

	local speaker = state.players[slot]
	if not speaker then
		return false
	end

	local targetName: string? = nil
	if entry.needsTarget then
		if not targetSlot or targetSlot == slot then
			return false
		end
		local target = state.players[targetSlot]
		if not target then
			return false
		end
		targetName = target.name
	end

	state.quickChatSent[slot] = state.tick
	state.quickChatLast[slot] = key

	local message = `\u{1F4AC} {speaker.name} : {QuickChat.format(entry, targetName)}`
	if entry.alliesOnly then
		state:notify(message, "info", slot)
		for otherSlot in state.players do
			if otherSlot ~= slot and state:areAllied(slot, otherSlot) then
				state:notify(message, "info", otherSlot)
			end
		end
	else
		state:notify(message, "info")
	end

	-- Un appel a l'attaque designe sa cible pour toute l'alliance : le texte et
	-- la marque ne doivent jamais se contredire.
	if entry.mark and targetSlot then
		Diplomacy.setTargetMark(state, slot, targetSlot)
	end

	return true
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
			if typeof(expiry) ~= "number" or numericExpired(expiry, state.tick) then
				targets[to] = nil
			end
		end
	end

	--[[
		Expiration des pactes.

		Ce n'est pas une trahison : personne n'est marque, aucun compteur ne
		bouge, et les deux camps peuvent resigner apres la carence. C'est ce qui
		empeche la carte de se figer en un graphe complet d'alliances ou plus
		personne n'a de cible legale.

		On collecte avant de retirer : muter les deux tables pendant qu'on les
		parcourt est un comportement indefini. V34 recycle expiredBuf.
	]]
	local n = 0
	for a, set in state.alliances do
		for b, expiry in set do
			-- Une seule fois par paire.
			if a < b then
				-- `true` legacy = pacte vivant sans date (areAllied l'honore).
				-- Toute autre non-number est corrompue : areAllied la refuse deja.
				if expiry == true then
					continue
				end
				if typeof(expiry) ~= "number" or numericExpired(expiry, state.tick) then
					n += 1
					local rec = expiredRecPool[n]
					if rec == nil then
						rec = { a = 0, b = 0 }
						expiredRecPool[n] = rec
					end
					rec.a = a
					rec.b = b
					expiredBuf[n] = rec
				end
			end
		end
	end

	for i = 1, n do
		local pair = expiredBuf[i]
		if pair == nil then
			continue
		end
		local setA, setB = state.alliances[pair.a], state.alliances[pair.b]
		if setA then
			setA[pair.b] = nil
		end
		if setB then
			setB[pair.a] = nil
		end
		local extA, extB = state.allianceExtensions[pair.a], state.allianceExtensions[pair.b]
		if extA then
			extA[pair.b] = nil
		end
		if extB then
			extB[pair.a] = nil
		end
		Diplomacy.startCooldown(state, pair.a, pair.b)

		local first, second = state.players[pair.a], state.players[pair.b]
		if first and second then
			state:notifyBetween(
				`\u{23F3} Le pacte entre {first.name} et {second.name} est arrive a terme.`,
				"info",
				pair.a,
				pair.b
			)
		end
	end
	-- Truncate leftover : un second step sans expiry ne rejoue pas le tour.
	for i = #expiredBuf, 1, -1 do
		expiredBuf[i] = nil
	end

	-- Une marque qui vise un disparu, ou posee par un disparu, ne doit pas
	-- survivre a son auteur : la carte oublierait sinon des cibles fantomes.
	for marker, target in state.targetMarks do
		if not state.players[marker] or not state.players[target] then
			state.targetMarks[marker] = nil
		end
	end
end

--=============================================================================
-- Marquage de cible
--=============================================================================

--[[
	Designe une faction comme cible de l'alliance, modele des coordonnees
	partagees CONQUEST : une offensive a trois n'a de poids que si
	tout le monde frappe au meme endroit. La marque est propre a chaque joueur,
	visible de ses allies, et remplace la precedente — une seule priorite a la
	fois, sinon elle ne priorise plus rien.
]]
function Diplomacy.setTargetMark(state: GameState, from: number, targetSlot: number): (boolean, string?)
	if from == targetSlot then
		return false, "Cible invalide."
	end
	local a, t = state.players[from], state.players[targetSlot]
	if not a or not t then
		return false, "Cette faction n'existe plus."
	end

	if state.targetMarks[from] == targetSlot then
		state.targetMarks[from] = nil
		return true, "Marque retiree."
	end

	state.targetMarks[from] = targetSlot
	local message = `\u{2691} {a.name} designe {t.name} comme cible.`
	state:notify(message, "info", from)
	local allySet = state.alliances[from]
	if allySet then
		for other in allySet do
			if state:areAllied(from, other) then
				state:notify(message, "info", other)
			end
		end
	end
	return true, `{t.name} designee comme cible pour ton alliance.`
end

--[[
	Vue diplomatique d'un joueur donne : ce module est le seul a connaitre la
	structure interne des relations, le reseau n'en voit qu'une projection.
]]
function Diplomacy.viewFor(state: GameState, slot: number)
	local rec = viewRecFor(slot)
	-- Slot sans joueur : maps vides, pas d'erreur. Ne pas scanner
	-- requests/traitors d'un disparu — le HUD n'appelle viewFor que
	-- pour un humain encore dans slotByPlayer.
	if not state.players[slot] then
		return rec
	end

	local allies = rec.allies
	local incoming = rec.incoming
	local outgoing = rec.outgoing
	local embargoes = rec.embargoes
	local traitors = rec.traitors
	local marks = rec.marks

	local allySet = state.alliances[slot]
	if allySet then
		for other in allySet do
			if state:areAllied(slot, other) then
				allies[other] = true
			end
		end
	end

	local myRequests = state.requests[slot]
	if myRequests then
		for other, expiry in myRequests do
			if requestIsLive(expiry, state.tick) then
				outgoing[other] = true
			end
		end
	end

	for other, targets in state.requests do
		local expiry = targets[slot]
		if requestIsLive(expiry, state.tick) then
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

	-- Marquages de cible : les miens et ceux de mes allies. La marque d'un
	-- ennemi est un renseignement qu'on ne livre pas gratuitement.
	local mine = state.targetMarks[slot]
	if mine and state.players[mine] then
		marks[slot] = mine
	end
	for other in allies do
		local theirs = state.targetMarks[other]
		if theirs and state.players[theirs] then
			marks[other] = theirs
		end
	end

	return rec
end

return Diplomacy
