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

-- N88 : gravure fin de match recyclee (leftover N84/N86). Porteuse +
-- records + hash seen. stats = reference live (N37 lookupStats), pas un
-- clone. table.clear vu au debut — un leftover seen d'un Player recycle
-- = skip XP. Semantique N37 inchangee (vivant + elimines, bots ignores,
-- resultRecorded saute). Distinct de rosterBuf (N84) et matchUpdateBuf
-- (N86). Ne pas require GameState (cycle).
local recordBuf: { RecordTarget } = {}
local recordRecPool: { RecordTarget } = {}
local seenBuf: { [Player]: boolean } = {}

function MatchLifecycle.endMatchRecords(
	slotByPlayer: { [Player]: number }?,
	players: any,
	settledHumans: any,
	resultRecorded: { [Player]: boolean }?
): { RecordTarget }
	table.clear(recordBuf)
	table.clear(seenBuf)
	local n = 0
	if slotByPlayer then
		for player, slot in slotByPlayer do
			if player and not (resultRecorded and resultRecorded[player]) then
				local stats = MatchLifecycle.lookupStats(players, settledHumans, slot)
				if stats then
					n += 1
					local rec = recordRecPool[n]
					if rec == nil then
						rec = { player = player, slot = slot, stats = stats }
						recordRecPool[n] = rec
					else
						rec.player = player
						rec.slot = slot
						rec.stats = stats
					end
					recordBuf[n] = rec
					seenBuf[player] = true
				end
			end
		end
	end
	if settledHumans then
		for slot, stats in settledHumans do
			local player = stats and stats.player
			if player and not seenBuf[player] and not (resultRecorded and resultRecorded[player]) then
				n += 1
				local rec = recordRecPool[n]
				if rec == nil then
					rec = { player = player, slot = slot, stats = stats }
					recordRecPool[n] = rec
				else
					rec.player = player
					rec.slot = slot
					rec.stats = stats
				end
				recordBuf[n] = rec
			end
		end
	end
	return recordBuf
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
-- Banc N88 : rawequal porteuse + record [1]. Pas replique.
MatchLifecycle.recordBuf = recordBuf
MatchLifecycle.recordRecPool = recordRecPool

export type ProfilePacket = {
	betrayals: number,
	matches: number,
	wins: number,
	xp: number,
	level: number,
	lastGain: number?,
}

-- N90 : packet HUD join / endMatch recycle (leftover N88). Un record,
-- six champs. profile + lastGain en argument — ne pas require GameState
-- ni Persistence (cycle / hors bundle). lastGain nil ecrase un leftover
-- de gain. Profile nil / {} → zeros + lastGain nil (recette N86). Distinct
-- de matchUpdateBuf (N86, salon 1 Hz) et de recordBuf (N88, gravure).
-- Ne pas pooler Persistence.record / UpdateAsync (N6, possession DataStore).
local profileBuf: ProfilePacket = {
	betrayals = 0,
	matches = 0,
	wins = 0,
	xp = 0,
	level = 1,
	lastGain = nil,
}

local function resetProfilePacket(rec: ProfilePacket)
	rec.betrayals = 0
	rec.matches = 0
	rec.wins = 0
	rec.xp = 0
	rec.level = 1
	rec.lastGain = nil
end

function MatchLifecycle.buildProfilePacket(profile: any, lastGain: number?, buf: ProfilePacket?): ProfilePacket
	local rec = buf or profileBuf
	if profile == nil or next(profile) == nil then
		resetProfilePacket(rec)
		return rec
	end
	rec.betrayals = profile.betrayals or 0
	rec.matches = profile.matches or 0
	rec.wins = profile.wins or 0
	rec.xp = profile.xp or 0
	rec.level = profile.level or 1
	rec.lastGain = lastGain
	return rec
end

-- Banc N90 : rawequal packet. Pas replique.
MatchLifecycle.profileBuf = profileBuf

return MatchLifecycle
