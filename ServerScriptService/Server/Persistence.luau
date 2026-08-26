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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Persistence = {}

export type Profile = {
	betrayals: number,
	matches: number,
	wins: number,
	xp: number,
	level: number,
}

local DEFAULT: Profile = { betrayals = 0, matches = 0, wins = 0, xp = 0, level = 1 }

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
local dirty: { [number]: boolean } = {}

local function keyFor(userId: number): string
	return `player_{userId}`
end

local function levelForXp(xp: number): number
	-- Courbe douce : les premiers niveaux arrivent vite, puis chaque rang
	-- demande davantage de campagnes sans devenir un mur artificiel.
	return math.max(1, math.floor(math.sqrt(math.max(0, xp) / Config.XP_LEVEL_BASE)) + 1)
end

function Persistence.load(userId: number): Profile
	if cache[userId] then
		return cache[userId]
	end

	local profile: Profile = { betrayals = 0, matches = 0, wins = 0, xp = 0, level = 1 }

	if available and store then
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(userId))
		end)
		if ok and type(result) == "table" then
			profile.betrayals = tonumber(result.betrayals) or 0
			profile.matches = tonumber(result.matches) or 0
			profile.wins = tonumber(result.wins) or 0
			profile.xp = tonumber(result.xp) or 0
			profile.level = levelForXp(profile.xp)
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
					xp = math.max(tonumber(old.xp) or 0, profile.xp),
					level = math.max(tonumber(old.level) or 1, profile.level),
				}
			end
			return profile
		end)
	end)

	if not ok then
		warn(`[CONQUEST RTS] Sauvegarde de reputation echouee pour {userId}`)
	else
		dirty[userId] = nil
	end
end

function Persistence.record(userId: number, betrayals: number, won: boolean, xpGain: number?): (Profile, number)
	local profile = Persistence.load(userId)
	profile.betrayals = math.max(profile.betrayals, betrayals)
	profile.matches += 1
	if won then
		profile.wins += 1
	end
	local gain = math.max(0, math.floor(xpGain or 0))
	profile.xp += gain
	profile.level = levelForXp(profile.xp)
	dirty[userId] = true
	Persistence.save(userId)
	return profile, gain
end

function Persistence.flush()
	local pending: { number } = {}
	for userId in dirty do
		table.insert(pending, userId)
	end
	for _, userId in pending do
		Persistence.save(userId)
	end
end

function Persistence.release(userId: number)
	if dirty[userId] then
		Persistence.save(userId)
	end
	cache[userId] = nil
	dirty[userId] = nil
end

-- Filet de securite a l'arret du serveur : sans ca, les dernieres parties
-- d'une session sont perdues.
game:BindToClose(function()
	Persistence.flush()
end)

Persistence.DEFAULT = DEFAULT
Persistence.levelForXp = levelForXp

return Persistence
