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
local QuickChat = require(ReplicatedStorage.Shared.QuickChat)

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
local SystemsBootstrap = require(script.SystemsBootstrap)
local IntentValidator = require(script.IntentValidator)
local TickMetrics = require(script.TickMetrics)
local MapGen = require(ReplicatedStorage.Shared.MapGen)

SystemsBootstrap.install()
IntentValidator.reset()
TickMetrics.reset()

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
local plunderEvent = Remotes.get("Plunder")

local attackOrder = Remotes.get("AttackOrder")
local retreatOrder = Remotes.get("RetreatOrder")
local setAttackRatio = Remotes.get("SetAttackRatio")
local chooseDoctrine = Remotes.get("ChooseDoctrine")
local buildOrder = Remotes.get("BuildOrder")
local upgradeBuildingOrder = Remotes.get("UpgradeBuildingOrder")
local boatOrder = Remotes.get("BoatOrder")
local nukeOrder = Remotes.get("NukeOrder")
local diplomacyOrder = Remotes.get("DiplomacyOrder")
local researchOrder = Remotes.get("ResearchOrder")
local joinRequest = Remotes.get("JoinRequest")
local requestSnapshot = Remotes.get("RequestSnapshot")
local ownerSnapshot = Remotes.get("OwnerSnapshot")
local intentReject = Remotes.get("IntentReject")

--=============================================================================
-- Etat du serveur
--=============================================================================

local state: GameState
local rng: Random
local slotByPlayer: { [Player]: number } = {}
local resultRecorded: { [Player]: boolean } = {}

local matchPhase = "waiting"
local matchId = "0"
local matchEndsAt = 0
local restartAt = 0
local doctrineLockAt = 0
local combatStartsAt = 0
local winnerSlot: number? = nil
local winnerName: string? = nil
local snapshotCooldown: { [number]: number } = {}
local snapshotCount: { [number]: number } = {}
local joinCooldown: { [number]: number } = {}
local currentMapMeta: any = nil

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

-- StateDelta / UnitSnapshot / explosions : uniquement les commandants deployes.
-- FireAllClients facture aussi les joueurs encore au menu (Place MaxPlayers > 8).
local function fireDeployed(remote, ...)
	for player in slotByPlayer do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end

local function deployedCount(): number
	local n = 0
	for _ in slotByPlayer do
		n += 1
	end
	return n
end

local function broadcastMatchUpdate(stats)
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
		mode = activeMode.id,
		players = deployedCount(),
		maxPlayers = Config.PUBLIC_MATCH_CAPACITY,
		maxHumans = Config.MAX_HUMAN_PLAYERS,
		maxBots = Config.MAX_BOTS,
		maxFactions = Config.MAX_TOTAL_FACTIONS,
		renderMode = Config.RENDER_MODE,
		winner = winnerSlot,
		winnerName = winnerName,
		restartIn = math.max(0, restartAt - os.clock()),
		summary = if matchPhase == "ended" then stats else nil,
	})
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

	--[[
		Butins de mise a mort.

		Diffuse a tous les commandants deployes (pas le menu) : voir une faction
		se faire depouiller est une information strategique — qui s'enrichit,
		donc qui devient dangereux.
	]]
	for _, loot in state.plunders do
		fireDeployed(plunderEvent, loot.tile, loot.slot, loot.gold)
	end
	table.clear(state.plunders)
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
	if humanCount > Config.MAX_HUMAN_PLAYERS then
		warn(`[{Config.GAME_NAME}] trop d'humains ({humanCount}/{Config.MAX_HUMAN_PLAYERS})`)
	end

	local now = os.clock()
	matchPhase = "playing"
	state.tick = 0 -- le temps passe depuis le deploiement, jamais depuis le menu
	matchEndsAt = now + activeMode.duration
	doctrineLockAt = now + Config.DOCTRINE_CHOICE_DURATION
	-- OF : pas de gel des guerres. combatUnlocked des le deploiement.
	state.combatUnlocked = true
	combatStartsAt = now

	-- `botCount` decrit le nombre total de nations du mode. Les humains sont
	-- poses d'abord ; l'IA remplit le reste, plafonne par MAX_BOTS.
	local desiredTotal = math.min(activeMode.botCount, Config.PUBLIC_MATCH_CAPACITY, Config.MAX_TOTAL_FACTIONS)
	local botsToSpawn = math.max(0, math.min(desiredTotal - humanCount, Config.MAX_BOTS))
	Bots.spawnAll(state, rng, botsToSpawn)
	state:notify("Operation lancee. Clique une terre libre pour poser ta capitale.", "good")
	print(`[{Config.GAME_NAME}] operation active — {humanCount} humain(s), {botsToSpawn} bot(s)`)
end

local function startMatch()
	local seed = Random.new():NextInteger(1, 2 ^ 24)
	activeMode = GameModes.get(pendingMode)
	matchId = `{seed}-{os.clock()}`
	IntentValidator.reset()
	TickMetrics.reset()
	table.clear(snapshotCooldown)
	table.clear(snapshotCount)

	state = GameState.new(seed)
	state.mode = activeMode
	state.combatUnlocked = true
	rng = Random.new(seed)
	resultRecorded = {}
	currentMapMeta = MapGen.mapMeta(seed, state.terrain)

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
		mapInit:FireClient(player, seed, slot, roster, capital, profilePacket(profile), currentMapMeta)
		spawnCharacterAt(player, capital)
	end

	print(
		`[{Config.GAME_NAME}] carte prete — seed {seed}, hash {currentMapMeta.terrainHash}, attente du premier deploiement`
	)
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
	if matchPhase == "ended" then
		notify:FireClient(player, "La partie est terminee — attends la relance.", "info")
		return
	end

	local humanCount = 0
	for _ in slotByPlayer do
		humanCount += 1
	end
	if humanCount >= Config.MAX_HUMAN_PLAYERS then
		notify:FireClient(
			player,
			`Salon plein ({Config.MAX_HUMAN_PLAYERS} commandants max).`,
			"bad"
		)
		return
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
	mapInit:FireClient(
		player,
		state.seed,
		ps.slot,
		buildRoster(),
		ps.capitalTile,
		profilePacket(profile),
		currentMapMeta or MapGen.mapMeta(state.seed, state.terrain)
	)
	spawnCharacterAt(player, ps.capitalTile)
	broadcastRoster()
end

joinRequest.OnServerEvent:Connect(function(player: Player, nationId: any, modeId: any)
	if typeof(nationId) ~= "number" then
		return
	end
	local now = os.clock()
	local lastJoin = joinCooldown[player.UserId]
	if lastJoin and now - lastJoin < (Config.JOIN_COOLDOWN_SEC or 2) then
		return
	end
	joinCooldown[player.UserId] = now
	if typeof(modeId) == "string" then
		local requestedMode = GameModes.get(modeId)
		pendingMode = requestedMode.id
		-- Premier deploiement seulement : un second JoinRequest en lobby ne
		-- doit pas changer le mode pour tout le salon.
		if matchPhase == "waiting" and next(slotByPlayer) == nil then
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
	IntentValidator.clearPlayer(player.UserId)
	snapshotCooldown[player.UserId] = nil
	snapshotCount[player.UserId] = nil
	joinCooldown[player.UserId] = nil
	Persistence.release(player.UserId)
end

--=============================================================================
-- Ordres clients — file d'intentions validee
--=============================================================================
-- Le client n'envoie qu'une intention (+ sequence optionnelle). La mutation
-- se fait dans IntentValidator (apply immediat, feel OF).

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

local function refuse(player: Player, reason: string, detail: string?)
	intentReject:FireClient(player, reason, detail)
	if detail then
		notify:FireClient(player, detail, "bad")
	end
end

local function intentContext()
	return {
		state = state,
		matchPhase = matchPhase,
		matchId = matchId,
		slotOf = slotOf,
		doctrineLockAt = doctrineLockAt,
		now = os.clock,
		buildings = Buildings,
		navy = Navy,
		nukes = Nukes,
		diplomacy = Diplomacy,
		research = Research,
		reply = reply,
		refuse = refuse,
		broadcastRoster = broadcastRoster,
	}
end

local function enqueueOrReject(player: Player, actionType: string, sequence: any, payload: { [string]: any })
	local seq = if isInteger(sequence) then sequence else nil
	local ok, reason = IntentValidator.enqueue(intentContext(), player, actionType, seq, payload)
	if not ok and reason then
		refuse(player, reason, nil)
	end
end

attackOrder.OnServerEvent:Connect(function(player: Player, targetIndex: any, sequence: any)
	enqueueOrReject(player, "Attack", sequence, { index = targetIndex })
end)

retreatOrder.OnServerEvent:Connect(function(player: Player, targetIndex: any, sequence: any)
	enqueueOrReject(player, "Retreat", sequence, { index = targetIndex })
end)

setAttackRatio.OnServerEvent:Connect(function(player: Player, ratio: any, sequence: any)
	enqueueOrReject(player, "SetAttackRatio", sequence, { ratio = ratio })
end)

chooseDoctrine.OnServerEvent:Connect(function(player: Player, doctrineId: any, sequence: any)
	enqueueOrReject(player, "ChooseDoctrine", sequence, { doctrineId = doctrineId })
end)

buildOrder.OnServerEvent:Connect(function(player: Player, index: any, kind: any, sequence: any)
	enqueueOrReject(player, "Build", sequence, { index = index, kind = kind })
end)

upgradeBuildingOrder.OnServerEvent:Connect(function(player: Player, index: any, sequence: any)
	enqueueOrReject(player, "Upgrade", sequence, { index = index })
end)

boatOrder.OnServerEvent:Connect(function(player: Player, targetTile: any, sequence: any)
	enqueueOrReject(player, "Boat", sequence, { index = targetTile })
end)

nukeOrder.OnServerEvent:Connect(function(player: Player, targetTile: any, kind: any, sequence: any)
	enqueueOrReject(player, "Nuke", sequence, { index = targetTile, kind = kind })
end)

researchOrder.OnServerEvent:Connect(function(player: Player, sequence: any)
	enqueueOrReject(player, "Research", sequence, {})
end)

diplomacyOrder.OnServerEvent:Connect(function(player: Player, action: any, targetSlot: any, sequence: any)
	enqueueOrReject(player, "Diplomacy", sequence, { action = action, targetSlot = targetSlot })
end)

--=============================================================================
-- Messages rapides
--=============================================================================

--[[
	Un message predefini, jamais de texte libre : le catalogue est la seule
	source, ce qui ferme d'office insultes, liens et contournements de filtre.
]]
local quickChatEvent = Remotes.get("QuickChat")

quickChatEvent.OnServerEvent:Connect(function(player: Player, messageId: any, targetSlot: any, sequence: any)
	-- Compat : ancien client envoie (id, target) ; nouveau (id, target, seq).
	-- Si targetSlot est un nombre et sequence nil, c'est l'ancien format.
	enqueueOrReject(player, "QuickChat", sequence, { messageId = messageId, targetSlot = targetSlot })
end)

--=============================================================================
-- Snapshot de resynchronisation
--=============================================================================

local function structureHash(): number
	local hash = 2166136261
	local indices = {}
	for index in state.buildings do
		table.insert(indices, index)
	end
	table.sort(indices)
	for _, index in indices do
		local b = state.buildings[index]
		hash = bit32.bxor(hash, index)
		hash = (hash * 16777619) % 4294967296
		if b then
			hash = bit32.bxor(hash, b.kind + b.slot * 17 + b.level * 31)
			hash = (hash * 16777619) % 4294967296
		end
	end
	return hash
end

requestSnapshot.OnServerEvent:Connect(function(player: Player)
	if not slotOf(player) or matchPhase == "waiting" then
		return
	end
	local userId = player.UserId
	local now = os.clock()
	local last = snapshotCooldown[userId] or 0
	if now - last < (Config.SNAPSHOT_COOLDOWN_SEC or 5) then
		refuse(player, "RateLimited", "Resynchronisation trop frequente.")
		return
	end
	local used = snapshotCount[userId] or 0
	if used >= (Config.MAX_SNAPSHOTS_PER_MATCH or 12) then
		refuse(player, "RateLimited", "Quota de snapshots epuise.")
		return
	end
	snapshotCooldown[userId] = now
	snapshotCount[userId] = used + 1

	local ownerCopy = buffer.create(Config.TILE_COUNT)
	buffer.copy(ownerCopy, 0, state.owner, 0, Config.TILE_COUNT)
	ownerSnapshot:FireClient(player, ownerCopy, state.tick, structureHash())
end)

--=============================================================================
-- Boucle de simulation
--=============================================================================

local function replicate()
	local ownerDelta = state:flushOwnerDelta()
	local changedTiles = if ownerDelta then buffer.len(ownerDelta) // 5 else 0

	local activeAttacks: { [number]: number } = {}
	local committedTroops: { [number]: number } = {}
	local attackTargets: { [number]: { number } } = {}
	for _, attack in state.attacks do
		activeAttacks[attack.attacker] = (activeAttacks[attack.attacker] or 0) + 1
		committedTroops[attack.attacker] = (committedTroops[attack.attacker] or 0) + math.floor(attack.troops)
		local targets = attackTargets[attack.attacker]
		if not targets then
			targets = {}
			attackTargets[attack.attacker] = targets
		end
		table.insert(targets, attack.target)
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
			attackTargets = attackTargets[slot],
			buildPrices = buildPrices,
			logisticsRoutes = logisticsRoutes,
			logisticsIncome = math.floor(logisticsIncome * 100) / 100,
		}
	end
	fireDeployed(stateDelta, ownerDelta, stats)

	local buildings = state:flushBuildingDelta()
	if buildings then
		fireDeployed(buildingDelta, buildings)
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

	fireDeployed(unitSnapshot, boats, missiles)

	-- La vue diplomatique est propre a chaque joueur, donc envoyee une fois par
	-- seconde seulement — elle change rarement et coute cher a construire.
	if state.tick % Config.TICK_RATE == 0 then
		updateLeaderstats()

		for player, slot in slotByPlayer do
			diplomacyUpdate:FireClient(player, Diplomacy.viewFor(state, slot))
		end

		broadcastMatchUpdate(stats)
	end

	flushEvents()
	return changedTiles, ownerDelta
end

local function onExplosion(x: number, y: number, radius: number)
	fireDeployed(explosion, x, y, radius)
end

local accumulator = 0

local function stepOnce()
	local tickStarted = os.clock()

	if matchPhase == "waiting" then
		-- Carte figee : aucun tick economique, aucune expansion et surtout aucun
		-- bot ne joue derriere le menu de selection.
		state.tick += 1
		-- Lobby vide : MatchUpdate 1 Hz pour le menu, pas de StateDelta 10 Hz.
		if next(slotByPlayer) == nil then
			if state.tick % Config.TICK_RATE == 0 then
				broadcastMatchUpdate(nil)
			end
			TickMetrics.record(state.tick, 0, nil, (os.clock() - tickStarted) * 1000)
			return
		end
		local changed, delta = replicate()
		TickMetrics.record(state.tick, changed, delta, (os.clock() - tickStarted) * 1000)
		return
	elseif matchPhase == "playing" then
		-- 1. Intentions deja appliquees a la reception (feel OF). Flush no-op.
		IntentValidator.flush(intentContext())

		if not state.combatUnlocked then
			state.combatUnlocked = true
		end
		-- 2-5. Systemes puis economie / fronts / victoire.
		Bots.step(state, rng)
		Navy.step(state, rng)
		Nukes.step(state, rng, onExplosion)
		Trade.step(state, rng, function(action, a, b, slot, value)
			fireDeployed(tradeEvent, action, a, b, slot, value)
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
		-- Ecran victoire : plus de sim, replication 1 Hz (summary HUD).
		if state.tick % Config.TICK_RATE ~= 0 then
			TickMetrics.record(state.tick, 0, nil, (os.clock() - tickStarted) * 1000)
			return
		end
	end

	local changed, delta = replicate()
	local tickMs = (os.clock() - tickStarted) * 1000
	TickMetrics.record(state.tick, changed, delta, tickMs)

	-- Rapport periodique : base de mesure avant tout changement de MAX_TILES_PER_TICK.
	if matchPhase == "playing" and state.tick > 0 and state.tick % (Config.TICK_RATE * 30) == 0 then
		print(`[{Config.GAME_NAME}] metrics {TickMetrics.formatReport()}`)
	end
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
