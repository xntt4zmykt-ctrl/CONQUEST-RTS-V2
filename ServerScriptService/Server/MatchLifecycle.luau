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

return MatchLifecycle
