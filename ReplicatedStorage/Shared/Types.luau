--!strict
-- Types echanges sur le reseau, partages par le serveur et le client pour que
-- les deux cotes ne puissent pas diverger silencieusement.

export type RosterEntry = {
	name: string,
	isBot: boolean,
	doctrine: number,
	betrayals: number,
}

export type Roster = { [number]: RosterEntry }

export type PlayerStats = {
	troops: number,
	tiles: number,
	gold: number,
	maxTroops: number,
}

export type Stats = { [number]: PlayerStats }

-- Relations vues par le client local : qui est allie, qui m'a demande une
-- alliance, qui je bloque commercialement.
export type Diplomacy = {
	allies: { [number]: boolean },
	incoming: { [number]: boolean },
	outgoing: { [number]: boolean },
	embargoes: { [number]: boolean },
	traitors: { [number]: boolean },
}

export type BoatSnapshot = {
	id: number,
	slot: number,
	x: number,
	y: number,
	troops: number,
	kind: number, -- 1 = transport de troupes, 2 = navire marchand
}

export type MissileSnapshot = {
	id: number,
	slot: number,
	x: number,
	y: number,
	tx: number,
	ty: number,
	kind: number,
}

export type BuildingSnapshot = {
	index: number,
	kind: number, -- 0 = detruit
	slot: number,
}

export type MatchInfo = {
	phase: string, -- "playing" | "ended"
	timeLeft: number,
	nukesUnlocked: boolean,
	winner: number?,
	winnerName: string?,
	restartIn: number?,
}

return {}
