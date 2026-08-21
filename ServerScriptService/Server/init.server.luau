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
local Nations = require(ReplicatedStorage.Shared.Nations)
local GameModes = require(ReplicatedStorage.Shared.GameModes)
local WorldSpace = require(ReplicatedStorage.Shared.WorldSpace)
local BuildingDefs = require(ReplicatedStorage.Shared.BuildingDefs)

-- init.server.luau devient le Script "Server" ; les modules voisins en sont
-- les enfants, pas les freres.
local GameState = require(script.GameState)
local Buildings = require(script.Buildings)
local Navy = require(script.Navy)
local Nukes = require(script.Nukes)
local Diplomacy = require(script.Diplomacy)
local Leaderstats = require(script.Leaderstats)
local Persistence = require(script.Persistence)
local Research = require(script.Research)
local WorldBuilder = require(script.WorldBuilder)
local Bots = require(script.Bots)
local Trade = require(script.Trade)

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
local profileUpdate = Remotes.get("ProfileUpdate")
local notify = Remotes.get("Notify")
local explosion = Remotes.get("Explosion")
local sfx = Remotes.get("Sfx")
local tradeEvent = Remotes.get("TradeEvent")

local attackOrder = Remotes.get("AttackOrder")
local setAttackRatio = Remotes.get("SetAttackRatio")
local chooseDoctrine = Remotes.get("ChooseDoctrine")
local buildOrder = Remotes.get("BuildOrder")
local upgradeBuildingOrder = Remotes.get("UpgradeBuildingOrder")
local boatOrder = Remotes.get("BoatOrder")
local nukeOrder = Remotes.get("NukeOrder")
local diplomacyOrder = Remotes.get("DiplomacyOrder")
local researchOrder = Remotes.get("ResearchOrder")
local joinRequest = Remotes.get("JoinRequest")

--=============================================================================
-- Etat du serveur
--=============================================================================

local state: GameState
local rng: Random
local slotByPlayer: { [Player]: number } = {}
local resultRecorded: { [Player]: boolean } = {}

local matchPhase = "waiting"
local matchEndsAt = 0
local restartAt = 0
local doctrineLockAt = 0
local combatStartsAt = 0
local winnerSlot: number? = nil
local winnerName: string? = nil

-- Nation choisie au menu, par joueur. Elle sert de nom de faction : un joueur
-- se reconnait a son pays, pas a son pseudo Roblox.
local nationByPlayer: { [Player]: number } = {}

-- Mode demande au menu. Il ne peut pas s'appliquer en cours de partie, donc il
-- attend la suivante — le menu le dit explicitement au joueur.
local pendingMode = GameModes.DEFAULT
local activeMode = GameModes.get(GameModes.DEFAULT)

local function profilePacket(profile, lastGain: number?)
	return {
		betrayals = profile.betrayals,
		matches = profile.matches,
		wins = profile.wins,
		xp = profile.xp,
		level = profile.level,
		lastGain = lastGain,
	}
end

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

--[[
	Fait apparaitre le personnage sur sa capitale.

	Le chargement est manuel (CharacterAutoLoads desactive) : charger a la
	connexion ferait naitre le joueur a l'origine du monde, c'est-a-dire au
	milieu de l'ocean, avant meme qu'il ait un territoire.
]]
local function spawnCharacterAt(player: Player, tile: number?)
	if not tile then
		return
	end

	task.spawn(function()
		local character = player.Character
		if not character then
			player:LoadCharacter()
			character = player.Character or player.CharacterAdded:Wait()
		end

		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") then
			root.CFrame = WorldSpace.spawnCFrame(state.terrain, tile)
		end
	end)
end

--[[
	Classement Roblox natif.

	La logique vit dans le module Leaderstats : les contraintes de l'API Roblox
	y sont documentees, et le module est couvert par le banc d'essai, alors que
	ce fichier-ci en est exclu.
]]
local function updateLeaderstats()
	Leaderstats.publish(state, slotByPlayer)
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

-- Le chrono et les bots ne commencent qu'apres le premier deploiement humain.
-- Avant ce verrou, le temps passe dans le menu pendant que l'IA colonise deja
-- la carte : le joueur arrivait donc dans une partie pratiquement perdue.
local function activateMatch()
	if matchPhase ~= "waiting" then
		return
	end

	local humanCount = 0
	for _ in slotByPlayer do
		humanCount += 1
	end
	if humanCount == 0 then
		return
	end

	local now = os.clock()
	matchPhase = "playing"
	state.tick = 0 -- le temps passe depuis le deploiement, jamais depuis le menu
	matchEndsAt = now + activeMode.duration
	doctrineLockAt = now + Config.DOCTRINE_CHOICE_DURATION
	combatStartsAt = now + Config.PREPARATION_DURATION

	-- `botCount` decrit maintenant le nombre total de nations affiche dans le
	-- menu. Les humains sont poses d'abord et obtiennent donc un vrai choix de
	-- spawn ; l'IA remplit seulement les places restantes.
	local botsToSpawn = math.max(0, activeMode.botCount - humanCount)
	Bots.spawnAll(state, rng, botsToSpawn)
	state:notify(
		`Operation lancee : {Config.PREPARATION_DURATION} secondes pour coloniser et construire avant les guerres.`,
		"good"
	)
	print(`[{Config.GAME_NAME}] operation active — {humanCount} humain(s), {botsToSpawn} bot(s)`)
end

local function startMatch()
	local seed = Random.new():NextInteger(1, 2 ^ 24)
	activeMode = GameModes.get(pendingMode)

	state = GameState.new(seed)
	state.mode = activeMode
	state.combatUnlocked = false
	rng = Random.new(seed)
	resultRecorded = {}

	matchPhase = "waiting"
	winnerSlot = nil
	winnerName = nil
	matchEndsAt = 0
	doctrineLockAt = 0
	combatStartsAt = 0

	-- Seuls les joueurs ayant deja franchi le menu sont reintegres : les autres
	-- entreront quand ils auront choisi leur nation.
	local previous = slotByPlayer
	slotByPlayer = {}
	for player in previous do
		if player.Parent then
			local profile = Persistence.load(player.UserId)
			local nation = Nations.get(nationByPlayer[player] or 1)
			local ps = state:addPlayer(player, nation.name, rng, profile.betrayals)
			if ps then
				slotByPlayer[player] = ps.slot
			end
		end
	end
	activateMatch()

	-- Le relief ne change pas de la partie : la collision est batie une fois.
	WorldBuilder.clearDefaultScene()
	WorldBuilder.build(state.terrain)

	local roster = buildRoster()
	for player, slot in slotByPlayer do
		local ps = state.players[slot]
		local capital = if ps then ps.capitalTile else nil
		local profile = Persistence.load(player.UserId)
		mapInit:FireClient(player, seed, slot, roster, capital, profilePacket(profile))
		spawnCharacterAt(player, capital)
	end

	print(`[{Config.GAME_NAME}] carte prete — seed {seed}, attente du premier deploiement`)
end

local function experienceFor(ps, won: boolean): number
	return Config.XP_PER_MATCH
		+ (if won then Config.XP_PER_WIN else 0)
		+ math.floor(ps.capturedTiles / Config.XP_TILE_DIVISOR)
		+ ps.capitalsCaptured * Config.XP_PER_CAPITAL
		+ ps.buildingsBuilt * Config.XP_PER_BUILDING
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
			local gain = experienceFor(ps, slot == winnerSlot)
			local profile = Persistence.record(player.UserId, ps.betrayals, slot == winnerSlot, gain)
			resultRecorded[player] = true
			profileUpdate:FireClient(player, profilePacket(profile, gain))
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

--[[
	Deploiement depuis le menu principal. C'est ici, et non a la connexion, que
	le joueur entre reellement en partie : il doit d'abord avoir choisi sa
	nation.
]]
local function deployPlayer(player: Player, nationId: number)
	if slotByPlayer[player] then
		return -- deja en jeu
	end

	nationByPlayer[player] = nationId
	local nation = Nations.get(nationId)
	local profile = Persistence.load(player.UserId)

	local ps = state:addPlayer(player, nation.name, rng, profile.betrayals)
	if not ps then
		warn(`[{Config.GAME_NAME}] aucun emplacement de spawn libre pour {player.Name}`)
		return
	end

	slotByPlayer[player] = ps.slot
	activateMatch()
	mapInit:FireClient(player, state.seed, ps.slot, buildRoster(), ps.capitalTile, profilePacket(profile))
	spawnCharacterAt(player, ps.capitalTile)
	broadcastRoster()
end

joinRequest.OnServerEvent:Connect(function(player: Player, nationId: any, modeId: any)
	if typeof(nationId) ~= "number" then
		return
	end
	if typeof(modeId) == "string" then
		local requestedMode = GameModes.get(modeId)
		pendingMode = requestedMode.id
		-- Tant que personne n'est deploye, ce n'est pas encore une partie : le
		-- mode choisi peut donc s'appliquer immediatement au lieu d'attendre le
		-- match suivant.
		if matchPhase == "waiting" then
			activeMode = requestedMode
			state.mode = activeMode
		end
	end
	deployPlayer(player, math.clamp(math.floor(nationId), 1, #Nations.LIST))
end)

local function onPlayerRemoving(player: Player)
	local slot = slotByPlayer[player]
	if slot then
		local ps = state.players[slot]
		if ps and not resultRecorded[player] then
			Persistence.record(player.UserId, ps.betrayals, false)
		end
		state:removePlayer(slot)
		slotByPlayer[player] = nil
		broadcastRoster()
	end
	nationByPlayer[player] = nil
	resultRecorded[player] = nil
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

attackOrder.OnServerEvent:Connect(function(player: Player, targetIndex: any)
	local slot = slotOf(player)
	if not slot or matchPhase ~= "playing" then
		warn(`[CONQUEST ATTACK] requete ignoree player={player.Name} slot={slot} phase={matchPhase}`)
		return
	end
	if not isInteger(targetIndex) or targetIndex < 0 or targetIndex >= Config.TILE_COUNT then
		reply(player, false, "Cible hors de la carte.")
		warn(`[CONQUEST ATTACK] index invalide player={player.Name} value={targetIndex}`)
		return
	end
	if not state:isLand(targetIndex) then
		reply(player, false, "Impossible d'attaquer l'ocean. Choisis une terre.")
		return
	end

	-- La faction cible vient de l'etat serveur autoritaire. Le client peut
	-- avoir un delta de retard au moment exact du clic ; son ancien owner ne
	-- doit jamais faire partir l'offensive au mauvais endroit.
	local targetSlot = buffer.readu8(state.owner, targetIndex)
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

upgradeBuildingOrder.OnServerEvent:Connect(function(player: Player, index: any)
	local slot = slotOf(player)
	if not slot or matchPhase ~= "playing" then
		return
	end
	if not isInteger(index) then
		return
	end
	local ok, message = Buildings.upgradeAt(state, slot, index)
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

researchOrder.OnServerEvent:Connect(function(player: Player)
	local slot = slotOf(player)
	if not slot or matchPhase ~= "playing" then
		return
	end
	local ok, message = Research.advance(state, slot)
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

	local activeAttacks: { [number]: number } = {}
	local committedTroops: { [number]: number } = {}
	for _, attack in state.attacks do
		activeAttacks[attack.attacker] = (activeAttacks[attack.attacker] or 0) + 1
		committedTroops[attack.attacker] = (committedTroops[attack.attacker] or 0) + math.floor(attack.troops)
	end

	local stats = {}
	for slot, ps in state.players do
		local logisticsRoutes, logisticsIncome = state:logisticsFor(slot)
		local buildPrices = {}
		for _, def in BuildingDefs.BUILDABLE do
			buildPrices[def.id] = Buildings.priceFor(state, slot, def.id)
		end
		stats[slot] = {
			troops = math.floor(ps.troops),
			tiles = ps.tiles,
			gold = math.floor(ps.gold),
			maxTroops = math.floor(state:maxTroops(ps)),
			era = ps.era,
			eraProgress = Research.progress(state, slot),
			capturedTiles = ps.capturedTiles,
			lostTiles = ps.lostTiles,
			capitalsCaptured = ps.capitalsCaptured,
			buildingsBuilt = ps.buildingsBuilt,
			attacksLaunched = ps.attacksLaunched,
			activeAttacks = activeAttacks[slot] or 0,
			committedTroops = committedTroops[slot] or 0,
			buildPrices = buildPrices,
			logisticsRoutes = logisticsRoutes,
			logisticsIncome = math.floor(logisticsIncome * 100) / 100,
		}
	end
	stateDelta:FireAllClients(ownerDelta, stats)

	local buildings = state:flushBuildingDelta()
	if buildings then
		buildingDelta:FireAllClients(buildings)
	end

	-- Unites : peu nombreuses, donc envoyees en clair. L'instantane vide est
	-- important lui aussi : c'est lui qui retire le dernier navire du client et
	-- declenche son animation d'arrivee au lieu de laisser un fantome en mer.
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

	-- La vue diplomatique est propre a chaque joueur, donc envoyee une fois par
	-- seconde seulement — elle change rarement et coute cher a construire.
	if state.tick % Config.TICK_RATE == 0 then
		updateLeaderstats()

		for player, slot in slotByPlayer do
			diplomacyUpdate:FireClient(player, Diplomacy.viewFor(state, slot))
		end

		matchUpdate:FireAllClients({
			phase = matchPhase,
			stage = if matchPhase == "waiting"
				then "waiting"
				elseif matchPhase == "ended"
				then "ended"
				elseif state.combatUnlocked
				then "combat"
				else "preparation",
			combatIn = if matchPhase == "waiting"
				then Config.PREPARATION_DURATION
				else math.max(0, combatStartsAt - os.clock()),
			timeLeft = if matchPhase == "waiting"
				then activeMode.duration
				else math.max(0, matchEndsAt - os.clock()),
			winner = winnerSlot,
			winnerName = winnerName,
			restartIn = math.max(0, restartAt - os.clock()),
			summary = if matchPhase == "ended" then stats else nil,
		})
	end

	flushEvents()
end

local function onExplosion(x: number, y: number, radius: number)
	explosion:FireAllClients(x, y, radius)
end

local accumulator = 0

local function stepOnce()
	if matchPhase == "waiting" then
		-- Carte figee : aucun tick economique, aucune expansion et surtout aucun
		-- bot ne joue derriere le menu de selection.
		state.tick += 1 -- cadence uniquement la replication du lobby
		replicate()
		return
	elseif matchPhase == "playing" then
		if not state.combatUnlocked and os.clock() >= combatStartsAt then
			state.combatUnlocked = true
			state:notify("⚔ Les frontieres sont ouvertes. Les guerres peuvent commencer.", "alert")
		end
		Bots.step(state, rng)
		Navy.step(state, rng)
		Nukes.step(state, rng, onExplosion)
		Trade.step(state, rng, function(action, a, b, slot, value)
			tradeEvent:FireAllClients(action, a, b, slot, value)
		end)
		Diplomacy.step(state)
		state:step()
		checkVictory()
	else -- ended
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

-- Le personnage n'est jamais charge automatiquement : il doit attendre de
-- savoir ou est sa capitale.
Players.CharacterAutoLoads = false

startMatch()

-- Aucun branchement sur PlayerAdded : l'entree en partie passe uniquement par
-- JoinRequest, c'est-a-dire par le menu principal.
Players.PlayerRemoving:Connect(onPlayerRemoving)

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
