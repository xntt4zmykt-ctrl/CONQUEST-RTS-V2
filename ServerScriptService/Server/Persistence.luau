--!strict
--[[
	Reputation persistante.

	Le compteur de trahisons suit le joueur d'une partie a l'autre : c'est ce
	qui donne un poids reel a la parole donnee. Sans persistance, trahir est
	gratuit et la diplomatie n'est que du bavardage.

	Tout est encapsule dans des pcall avec repli en memoire : en Studio, les
	DataStores sont indisponibles tant que l'acces API n'est pas active, et le
	jeu doit rester parfaitement jouable dans ce cas.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Persistence = {}

export type Profile = {
	betrayals: number,
	matches: number,
	wins: number,
}

local DEFAULT: Profile = { betrayals = 0, matches = 0, wins = 0 }

local store: DataStore? = nil
local available = false

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("ConquestRTS_Reputation_v1")
	end)
	if ok then
		store = result
		available = true
	else
		warn("[CONQUEST RTS] DataStore indisponible — la reputation ne sera pas sauvegardee cette session.")
	end
end

-- Cache en memoire : fait aussi office de source de verite quand les
-- DataStores ne repondent pas.
local cache: { [number]: Profile } = {}

local function keyFor(userId: number): string
	return `player_{userId}`
end

function Persistence.load(userId: number): Profile
	if cache[userId] then
		return cache[userId]
	end

	local profile: Profile = { betrayals = 0, matches = 0, wins = 0 }

	if available and store then
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(userId))
		end)
		if ok and type(result) == "table" then
			profile.betrayals = tonumber(result.betrayals) or 0
			profile.matches = tonumber(result.matches) or 0
			profile.wins = tonumber(result.wins) or 0
		elseif not ok then
			warn(`[CONQUEST RTS] Lecture de reputation echouee pour {userId}`)
		end
	end

	cache[userId] = profile
	return profile
end

function Persistence.save(userId: number)
	local profile = cache[userId]
	if not profile or not available or not store then
		return
	end

	local ok = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(userId), function(old)
			-- UpdateAsync plutot que SetAsync : deux serveurs peuvent ecrire le
			-- meme profil, on ne veut jamais faire regresser un compteur.
			if type(old) == "table" then
				return {
					betrayals = math.max(tonumber(old.betrayals) or 0, profile.betrayals),
					matches = math.max(tonumber(old.matches) or 0, profile.matches),
					wins = math.max(tonumber(old.wins) or 0, profile.wins),
				}
			end
			return profile
		end)
	end)

	if not ok then
		warn(`[CONQUEST RTS] Sauvegarde de reputation echouee pour {userId}`)
	end
end

function Persistence.record(userId: number, betrayals: number, won: boolean)
	local profile = Persistence.load(userId)
	profile.betrayals = math.max(profile.betrayals, betrayals)
	profile.matches += 1
	if won then
		profile.wins += 1
	end
	Persistence.save(userId)
end

function Persistence.release(userId: number)
	Persistence.save(userId)
	cache[userId] = nil
end

-- Filet de securite a l'arret du serveur : sans ca, les dernieres parties
-- d'une session sont perdues.
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		Persistence.save(player.UserId)
	end
end)

Persistence.DEFAULT = DEFAULT

return Persistence
