--!strict
-- Types echanges sur le reseau, partages par le serveur et le client pour que
-- les deux cotes ne puissent pas diverger silencieusement.

export type RosterEntry = {
	name: string,
	isBot: boolean,
}

export type Roster = { [number]: RosterEntry }

export type PlayerStats = {
	troops: number,
	tiles: number,
}

export type Stats = { [number]: PlayerStats }

return {}
