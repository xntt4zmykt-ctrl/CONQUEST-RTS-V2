--!strict
--[[
	Choix « qui grave » a endMatch / disconnect.

	init.server est hors bundle : cette fonction pure est le seul contrat
	testable pour Persistence.record des elimines (ISSUE-N37). Ne require
	pas GameState (cycle).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MatchLifecycle = {}

export type SettledStats = {
	player: Player?,
	betrayals: number,
	capturedTiles: number?,
	capitalsCaptured: number?,
	buildingsBuilt: number?,
}

export type RecordTarget = {
	player: Player,
	slot: number,
	stats: SettledStats,
}

function MatchLifecycle.lookupStats(players: any, settledHumans: any, slot: number): SettledStats?
	if players and players[slot] then
		return players[slot]
	end
	if settledHumans then
		return settledHumans[slot]
	end
	return nil
end

function MatchLifecycle.experienceFor(ps: SettledStats?, won: boolean): number
	if not ps then
		return 0
	end
	return Config.XP_PER_MATCH
		+ (if won then Config.XP_PER_WIN else 0)
		+ math.floor((ps.capturedTiles or 0) / Config.XP_TILE_DIVISOR)
		+ (ps.capitalsCaptured or 0) * Config.XP_PER_CAPITAL
		+ (ps.buildingsBuilt or 0) * Config.XP_PER_BUILDING
end

--[[
	Humains encore dans slotByPlayer (vivants ou elimines restes) PLUS les
	elimines partis avant l'ecran. Ignore resultRecorded (disconnect / endMatch
	deja grave). Ne liste pas les bots.
]]
function MatchLifecycle.endMatchRecords(
	slotByPlayer: { [Player]: number }?,
	players: any,
	settledHumans: any,
	resultRecorded: { [Player]: boolean }?
): { RecordTarget }
	local out: { RecordTarget } = {}
	local seen: { [Player]: boolean } = {}
	if slotByPlayer then
		for player, slot in slotByPlayer do
			if player and not (resultRecorded and resultRecorded[player]) then
				local stats = MatchLifecycle.lookupStats(players, settledHumans, slot)
				if stats then
					table.insert(out, { player = player, slot = slot, stats = stats })
					seen[player] = true
				end
			end
		end
	end
	if settledHumans then
		for slot, stats in settledHumans do
			local player = stats and stats.player
			if player and not seen[player] and not (resultRecorded and resultRecorded[player]) then
				table.insert(out, { player = player, slot = slot, stats = stats })
			end
		end
	end
	return out
end

export type RosterRec = {
	name: string,
	isBot: boolean,
	doctrine: number,
	betrayals: number,
}

-- N84 : roster 1 Hz recycle (recette playerStatsForReplicate N57).
-- players en argument — ne pas require GameState (cycle). Slot disparu
-- absent (table.clear puis refill). Slot 99 / map vide = table vide
-- recyclee. Quatre champs seulement : pas gold / troops / tiles.
local rosterBuf: { [number]: RosterRec } = {}
local rosterRecPool: { [number]: RosterRec } = {}

function MatchLifecycle.buildRoster(players: any): { [number]: RosterRec }
	table.clear(rosterBuf)
	if players then
		for slot, ps in players do
			if ps then
				local rec = rosterRecPool[slot]
				if rec == nil then
					rec = {
						name = ps.name,
						isBot = ps.isBot,
						doctrine = ps.doctrine,
						betrayals = ps.betrayals,
					}
					rosterRecPool[slot] = rec
				else
					rec.name = ps.name
					rec.isBot = ps.isBot
					rec.doctrine = ps.doctrine
					rec.betrayals = ps.betrayals
				end
				rosterBuf[slot] = rec
			end
		end
	end
	return rosterBuf
end

-- Banc N84 : rawequal porteuse + record slot. Pas replique.
MatchLifecycle.rosterBuf = rosterBuf
MatchLifecycle.rosterRecPool = rosterRecPool

export type MatchUpdateRec = {
	phase: string?,
	stage: string?,
	combatIn: number,
	timeLeft: number,
	mode: any,
	players: number,
	maxPlayers: number,
	maxHumans: number,
	maxBots: number,
	maxFactions: number,
	renderMode: any,
	winner: number?,
	winnerName: string?,
	restartIn: number,
	summary: any,
}

-- N86 : packet salon/chrono 1 Hz recycle (leftover N84). Un record,
-- pas une map par slot. args en argument — ne pas require GameState
-- (cycle). summary = reference live ou nil (pas un clone de statsBuf).
-- Args nil / vides = scalaires a 0 / nil. Distinct de rosterBuf (N84)
-- et de playerStatsForReplicate (N57).
local matchUpdateBuf: MatchUpdateRec = {
	phase = nil,
	stage = nil,
	combatIn = 0,
	timeLeft = 0,
	mode = nil,
	players = 0,
	maxPlayers = 0,
	maxHumans = 0,
	maxBots = 0,
	maxFactions = 0,
	renderMode = nil,
	winner = nil,
	winnerName = nil,
	restartIn = 0,
	summary = nil,
}

local function resetMatchUpdate(rec: MatchUpdateRec)
	rec.phase = nil
	rec.stage = nil
	rec.combatIn = 0
	rec.timeLeft = 0
	rec.mode = nil
	rec.players = 0
	rec.maxPlayers = 0
	rec.maxHumans = 0
	rec.maxBots = 0
	rec.maxFactions = 0
	rec.renderMode = nil
	rec.winner = nil
	rec.winnerName = nil
	rec.restartIn = 0
	rec.summary = nil
end

function MatchLifecycle.buildMatchUpdate(args: any, buf: MatchUpdateRec?): MatchUpdateRec
	local rec = buf or matchUpdateBuf
	if args == nil or next(args) == nil then
		resetMatchUpdate(rec)
		return rec
	end
	rec.phase = args.phase
	rec.stage = args.stage
	rec.combatIn = args.combatIn or 0
	rec.timeLeft = args.timeLeft or 0
	rec.mode = args.mode
	rec.players = args.players or 0
	rec.maxPlayers = args.maxPlayers or 0
	rec.maxHumans = args.maxHumans or 0
	rec.maxBots = args.maxBots or 0
	rec.maxFactions = args.maxFactions or 0
	rec.renderMode = args.renderMode
	rec.winner = args.winner
	rec.winnerName = args.winnerName
	rec.restartIn = args.restartIn or 0
	rec.summary = args.summary
	return rec
end

-- Banc N86 : rawequal packet. Pas replique.
MatchLifecycle.matchUpdateBuf = matchUpdateBuf

return MatchLifecycle
