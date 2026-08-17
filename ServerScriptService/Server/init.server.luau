--!strict
-- Point d'entree serveur : cycle de vie des joueurs, boucle de tick, replication.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
-- init.server.luau devient le Script "Server" ; GameState et Bots en sont les
-- enfants, pas les freres.
local GameState = require(script.GameState)
local Bots = require(script.Bots)

local seed = Random.new():NextInteger(1, 2 ^ 24)
local state = GameState.new(seed)
local rng = Random.new(seed)

local slotByPlayer: { [Player]: number } = {}

local mapInit = Remotes.get("MapInit")
local stateDelta = Remotes.get("StateDelta")
local rosterUpdate = Remotes.get("RosterUpdate")
local attackOrder = Remotes.get("AttackOrder")
local setAttackRatio = Remotes.get("SetAttackRatio")

-- Le roster dit au client qui est qui : sans lui les couleurs a l'ecran
-- n'ont pas de nom associe.
local function buildRoster(): { [number]: { name: string, isBot: boolean } }
	local roster = {}
	for slot, ps in state.players do
		roster[slot] = { name = ps.name, isBot = ps.player == nil }
	end
	return roster
end

local function broadcastRoster()
	local roster = buildRoster()
	rosterUpdate:FireAllClients(roster)
end

local function onPlayerAdded(player: Player)
	local ps = state:addPlayer(player, player.DisplayName, rng)
	if not ps then
		warn(`[{Config.GAME_NAME}] aucun emplacement de spawn libre pour {player.Name}`)
		return
	end

	slotByPlayer[player] = ps.slot
	mapInit:FireClient(player, seed, ps.slot, buildRoster())
	broadcastRoster()
end

local function onPlayerRemoving(player: Player)
	local slot = slotByPlayer[player]
	if slot then
		state:removePlayer(slot)
		slotByPlayer[player] = nil
		broadcastRoster()
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Ordres clients. Tout est revalide cote serveur : le client n'envoie qu'une
-- intention, jamais un resultat.
attackOrder.OnServerEvent:Connect(function(player: Player, targetSlot: any)
	local slot = slotByPlayer[player]
	if not slot then
		return
	end
	if typeof(targetSlot) ~= "number" or targetSlot ~= math.floor(targetSlot) then
		return
	end
	if targetSlot < 0 or targetSlot > Config.MAX_PLAYERS then
		return
	end
	state:launchAttack(slot, targetSlot)
end)

setAttackRatio.OnServerEvent:Connect(function(player: Player, ratio: any)
	local slot = slotByPlayer[player]
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

Bots.spawnAll(state, rng)

-- Boucle de simulation a pas fixe. On accumule le temps reel plutot que de se
-- caler sur Heartbeat : la simulation reste identique quel que soit le FPS
-- serveur, ce qui est indispensable pour un equilibrage stable.
local accumulator = 0

RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	local steps = 0
	while accumulator >= Config.TICK_DT and steps < 5 do
		accumulator -= Config.TICK_DT
		steps += 1

		Bots.step(state, rng)
		state:step()

		local delta = state:flushDelta()
		local stats = {}
		for slot, ps in state.players do
			stats[slot] = { troops = math.floor(ps.troops), tiles = ps.tiles }
		end
		stateDelta:FireAllClients(delta, stats)
	end

	if accumulator > Config.TICK_DT * 5 then
		accumulator = 0 -- on a pris trop de retard : on repart proprement
	end
end)

print(`[{Config.GAME_NAME}] partie demarree — seed {seed}`)
