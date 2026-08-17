--!strict
--[[
	Point d'entree serveur.

	Responsabilites : cycle de vie des joueurs, validation des ordres, boucle de
	tick a pas fixe, replication, et cycle de match (victoire puis relance).

	Regle : aucune logique de jeu ici. Ce fichier orchestre les systemes, il ne
	simule rien lui-meme.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Doctrines = require(ReplicatedStorage.Shared.Doctrines)

-- init.server.luau devient le Script "Server" ; les modules voisins en sont
-- les enfants, pas les freres.
local GameState = require(script.GameState)
local Buildings = require(script.Buildings)
local Navy = require(script.Navy)
local Nukes = require(script.Nukes)
local Diplomacy = require(script.Diplomacy)
local Persistence = require(script.Persistence)
local Bots = require(script.Bots)

type GameState = GameState.GameState

--=============================================================================
-- Remotes
--=============================================================================

local mapInit = Remotes.get("MapInit")
local stateDelta = Remotes.get("StateDelta")
local rosterUpdate = Remotes.get("RosterUpdate")
local buildingDelta = Remotes.get("BuildingDelta")
local unitSnapshot = Remotes.get("UnitSnapshot")
local diplomacyUpdate = Remotes.get("DiplomacyUpdate")
local matchUpdate = Remotes.get("MatchUpdate")
local notify = Remotes.get("Notify")
local explosion = Remotes.get("Explosion")
local sfx = Remotes.get("Sfx")

local attackOrder = Remotes.get("AttackOrder")
local setAttackRatio = Remotes.get("SetAttackRatio")
local chooseDoctrine = Remotes.get("ChooseDoctrine")
local buildOrder = Remotes.get("BuildOrder")
local boatOrder = Remotes.get("BoatOrder")
local nukeOrder = Remotes.get("NukeOrder")
local diplomacyOrder = Remotes.get("DiplomacyOrder")

--=============================================================================
-- Etat du serveur
--=============================================================================

local state: GameState
local rng: Random
local slotByPlayer: { [Player]: number } = {}

local matchPhase = "playing"
local matchEndsAt = 0
local restartAt = 0
local doctrineLockAt = 0
local winnerSlot: number? = nil
local winnerName: string? = nil

--=============================================================================
-- Helpers de replication
--=============================================================================

local function buildRoster()
	local roster = {}
	for slot, ps in state.players do
		roster[slot] = {
			name = ps.name,
			isBot = ps.isBot,
			doctrine = ps.doctrine,
			betrayals = ps.betrayals,
		}
	end
	return roster
end

local function broadcastRoster()
	rosterUpdate:FireAllClients(buildRoster())
end

local function playerForSlot(slot: number): Player?
	local ps = state.players[slot]
	return if ps then ps.player else nil
end

-- Vide la file d'evenements du moteur vers les clients concernes.
local function flushEvents()
	for _, event in state.events do
		if event.only then
			local target = playerForSlot(event.only)
			if target then
				notify:FireClient(target, event.text, event.kind)
			end
		else
			notify:FireAllClients(event.text, event.kind)
		end
	end
	table.clear(state.events)

	for _, event in state.sounds do
		if event.only then
			local target = playerForSlot(event.only)
			if target then
				sfx:FireClient(target, event.name)
			end
		else
			sfx:FireAllClients(event.name)
		end
	end
	table.clear(state.sounds)
end

--=============================================================================
-- Cycle de match
--=============================================================================

local function startMatch()
	local seed = Random.new():NextInteger(1, 2 ^ 24)
	state = GameState.new(seed)
	rng = Random.new(seed)

	matchPhase = "playing"
	winnerSlot = nil
	winnerName = nil
	matchEndsAt = os.clock() + Config.MATCH_DURATION
	doctrineLockAt = os.clock() + 90

	Bots.spawnAll(state, rng)

	-- Les joueurs deja connectes sont reintegres dans la nouvelle partie.
	table.clear(slotByPlayer)
	for _, player in Players:GetPlayers() do
		local profile = Persistence.load(player.UserId)
		local ps = state:addPlayer(player, player.DisplayName, rng, profile.betrayals)
		if ps then
			slotByPlayer[player] = ps.slot
		end
	end

	local roster = buildRoster()
	for player, slot in slotByPlayer do
		local ps = state.players[slot]
		mapInit:FireClient(player, seed, slot, roster, if ps then ps.capitalTile else nil)
	end

	print(`[{Config.GAME_NAME}] nouvelle partie — seed {seed}`)
end

local function endMatch(slot: number?)
	winnerSlot = slot
	matchPhase = "ended"
	restartAt = os.clock() + Config.POST_MATCH_DELAY

	winnerName = if winnerSlot and state.players[winnerSlot]
		then state.players[winnerSlot].name
		else nil

	if winnerName then
		state:notify(`\u{1F3C6} {winnerName} remporte la partie !`, "alert")
	else
		state:notify("Fin de partie — aucune domination decisive.", "alert")
	end

	-- On grave la reputation et le resultat de chaque joueur humain.
	for player, slot in slotByPlayer do
		local ps = state.players[slot]
		if ps then
			Persistence.record(player.UserId, ps.betrayals, slot == winnerSlot)
		end
	end
end

--[[
	Deux conditions de fin : la domination territoriale, et l'expiration du
	chrono (auquel cas le plus grand empire l'emporte). La derniere faction
	debout compte aussi comme domination.
]]
local function checkVictory()
	local leader: number? = nil
	local leaderTiles = 0
	local aliveHumans = 0

	for slot, ps in state.players do
		if ps.tiles > leaderTiles then
			leaderTiles = ps.tiles
			leader = slot
		end
		if not ps.isBot then
			aliveHumans += 1
		end
	end

	if leader and state:landControlled(leader) >= Config.VICTORY_LAND_RATIO then
		endMatch(leader)
		return
	end

	if os.clock() >= matchEndsAt then
		endMatch(leader)
		return
	end

	local _ = aliveHumans
end

--=============================================================================
-- Cycle de vie des joueurs
--=============================================================================

local function onPlayerAdded(player: Player)
	local profile = Persistence.load(player.UserId)

	local ps = state:addPlayer(player, player.DisplayName, rng, profile.betrayals)
	if not ps then
		warn(`[{Config.GAME_NAME}] aucun emplacement de spawn libre pour {player.Name}`)
		return
	end

	slotByPlayer[player] = ps.slot
	mapInit:FireClient(player, state.seed, ps.slot, buildRoster(), ps.capitalTile)
	broadcastRoster()
end

local function onPlayerRemoving(player: Player)
	local slot = slotByPlayer[player]
	if slot then
		local ps = state.players[slot]
		if ps then
			Persistence.record(player.UserId, ps.betrayals, false)
		end
		state:removePlayer(slot)
		slotByPlayer[player] = nil
		broadcastRoster()
	end
	Persistence.release(player.UserId)
end

--=============================================================================
-- Ordres clients
--=============================================================================
-- Tout est revalide ici : le client n'envoie qu'une intention, jamais un
-- resultat. Chaque handler verifie le type avant de toucher a la simulation.

local function isInteger(value: any): boolean
	return typeof(value) == "number" and value == value and value == math.floor(value)
end

local function slotOf(player: Player): number?
	local slot = slotByPlayer[player]
	if not slot or not state.players[slot] then
		return nil
	end
	return slot
end

local function reply(player: Player, ok: boolean, message: string?)
	if message then
		notify:FireClient(player, message, if ok then "good" else "bad")
	end
end

attackOrder.OnServerEvent:Connect(function(player: Player, targetSlot: any)
	local slot = slotOf(player)
	if not slot or matchPhase ~= "playing" then
		return
	end
	if not isInteger(targetSlot) or targetSlot < 0 or targetSlot > Config.MAX_PLAYERS then
		return
	end
	local ok, message = state:launchAttack(slot, targetSlot)
	reply(player, ok, message)
end)

setAttackRatio.OnServerEvent:Connect(function(player: Player, ratio: any)
	local slot = slotOf(player)
	if not slot then
		return
	end
	if typeof(ratio) ~= "number" or ratio ~= ratio then
		return
	end
	local ps = state.players[slot]
	if ps then
		ps.attackRatio = math.clamp(ratio, 0.05, 1)
	end
end)

chooseDoctrine.OnServerEvent:Connect(function(player: Player, doctrineId: any)
	local slot = slotOf(player)
	if not slot or not isInteger(doctrineId) then
		return
	end
	-- La doctrine se verrouille passe l'ouverture : c'est un engagement, pas
	-- un curseur qu'on ajuste selon la situation.
	if os.clock() > doctrineLockAt then
		reply(player, false, "Ta doctrine est deja engagee.")
		return
	end
	local ps = state.players[slot]
	if ps then
		ps.doctrine = Doctrines.get(doctrineId).id
		broadcastRoster()
		reply(player, true, `Doctrine {Doctrines.get(doctrineId).name} adoptee.`)
	end
end)

buildOrder.OnServerEvent:Connect(function(player: Player, index: any, kind: any)
	local slot = slotOf(player)
	if not slot or matchPhase ~= "playing" then
		return
	end
	if not isInteger(index) or not isInteger(kind) then
		return
	end
	local ok, message = Buildings.build(state, slot, index, kind)
	reply(player, ok, message)
end)

boatOrder.OnServerEvent:Connect(function(player: Player, targetTile: any)
	local slot = slotOf(player)
	if not slot or matchPhase ~= "playing" then
		return
	end
	if not isInteger(targetTile) then
		return
	end
	local ok, message = Navy.launchInvasion(state, slot, targetTile)
	reply(player, ok, message)
end)

nukeOrder.OnServerEvent:Connect(function(player: Player, targetTile: any, kind: any)
	local slot = slotOf(player)
	if not slot or matchPhase ~= "playing" then
		return
	end
	if not isInteger(targetTile) or not isInteger(kind) then
		return
	end
	local ok, message = Nukes.launch(state, slot, targetTile, kind)
	reply(player, ok, message)
end)

diplomacyOrder.OnServerEvent:Connect(function(player: Player, action: any, targetSlot: any)
	local slot = slotOf(player)
	if not slot or matchPhase ~= "playing" then
		return
	end
	if typeof(action) ~= "string" or not isInteger(targetSlot) then
		return
	end
	if targetSlot < 1 or targetSlot > Config.MAX_PLAYERS then
		return
	end

	local ok, message
	if action == "request" then
		ok, message = Diplomacy.request(state, slot, targetSlot)
	elseif action == "accept" then
		ok, message = Diplomacy.accept(state, targetSlot, slot)
	elseif action == "decline" then
		ok, message = Diplomacy.decline(state, targetSlot, slot)
	elseif action == "break" then
		ok, message = Diplomacy.breakAlliance(state, slot, targetSlot)
	elseif action == "embargo" then
		ok, message = Diplomacy.setEmbargo(state, slot, targetSlot, true)
	elseif action == "unembargo" then
		ok, message = Diplomacy.setEmbargo(state, slot, targetSlot, false)
	else
		return
	end

	reply(player, ok, message)
end)

--=============================================================================
-- Boucle de simulation
--=============================================================================

local function replicate()
	local ownerDelta = state:flushOwnerDelta()

	local stats = {}
	for slot, ps in state.players do
		stats[slot] = {
			troops = math.floor(ps.troops),
			tiles = ps.tiles,
			gold = math.floor(ps.gold),
			maxTroops = math.floor(state:maxTroops(ps)),
		}
	end
	stateDelta:FireAllClients(ownerDelta, stats)

	local buildings = state:flushBuildingDelta()
	if buildings then
		buildingDelta:FireAllClients(buildings)
	end

	-- Unites : peu nombreuses, donc envoyees en clair. Le client interpole
	-- entre deux instantanes pour un mouvement fluide malgre les 10 Hz.
	if #state.boats > 0 or #state.missiles > 0 then
		local boats = {}
		for _, boat in state.boats do
			table.insert(boats, {
				id = boat.id,
				slot = boat.slot,
				x = boat.x,
				y = boat.y,
				troops = math.floor(boat.troops),
				kind = boat.kind,
			})
		end

		local missiles = {}
		for _, missile in state.missiles do
			table.insert(missiles, {
				id = missile.id,
				slot = missile.slot,
				x = missile.x,
				y = missile.y,
				tx = missile.tx,
				ty = missile.ty,
				kind = missile.kind,
			})
		end

		unitSnapshot:FireAllClients(boats, missiles)
	end

	-- La vue diplomatique est propre a chaque joueur, donc envoyee une fois par
	-- seconde seulement — elle change rarement et coute cher a construire.
	if state.tick % Config.TICK_RATE == 0 then
		for player, slot in slotByPlayer do
			diplomacyUpdate:FireClient(player, Diplomacy.viewFor(state, slot))
		end

		matchUpdate:FireAllClients({
			phase = matchPhase,
			timeLeft = math.max(0, matchEndsAt - os.clock()),
			nukesUnlocked = Buildings.nukesUnlocked(state),
			winner = winnerSlot,
			winnerName = winnerName,
			restartIn = math.max(0, restartAt - os.clock()),
		})
	end

	flushEvents()
end

local function onExplosion(x: number, y: number, radius: number)
	explosion:FireAllClients(x, y, radius)
end

local accumulator = 0

local function stepOnce()
	if matchPhase == "playing" then
		Bots.step(state, rng)
		Navy.step(state, rng)
		Nukes.step(state, rng, onExplosion)
		Diplomacy.step(state)
		state:step()
		checkVictory()
	else
		state.tick += 1
		if os.clock() >= restartAt then
			startMatch()
			return
		end
	end

	replicate()
end

--=============================================================================
-- Demarrage
--=============================================================================

startMatch()

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Pas fixe : la simulation reste identique quel que soit le FPS serveur, ce qui
-- est indispensable pour que l'equilibrage soit stable.
RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	local steps = 0
	while accumulator >= Config.TICK_DT and steps < 5 do
		accumulator -= Config.TICK_DT
		steps += 1
		stepOnce()
	end

	if accumulator > Config.TICK_DT * 5 then
		accumulator = 0 -- on a pris trop de retard : on repart proprement
	end
end)
