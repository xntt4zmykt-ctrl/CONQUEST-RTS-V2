--!strict
--[[
	Lecture sonore.

	Trois responsabilites, toutes destinees a empecher le son de devenir du
	bruit :

	1. **Bridage** — chaque son a un intervalle minimal. Une vague de conquete
	   capture des centaines de tuiles par seconde ; sans bridage le jeu emet
	   des centaines de sons par seconde.
	2. **Variation de hauteur** — un son repete a hauteur identique est percu
	   comme un defaut technique. Une variation aleatoire le transforme en
	   texture.
	3. **Recyclage** — les instances Sound sont reutilisees plutot que creees
	   et detruites en continu.

	Un identifiant vide ou invalide n'est jamais fatal : le son est ignore.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))

local SoundManager = {}

local POOL_SIZE = 12

local container = Instance.new("Folder")
container.Name = "ConquestSounds"
container.Parent = SoundService

local pool: { Sound } = {}
local poolCursor = 1
local lastPlayed: { [string]: number } = {}
local failed: { [string]: boolean } = {}

for i = 1, POOL_SIZE do
	local sound = Instance.new("Sound")
	sound.Name = `Voice{i}`
	sound.Parent = container
	pool[i] = sound
end

local function nextVoice(): Sound
	local sound = pool[poolCursor]
	poolCursor += 1
	if poolCursor > POOL_SIZE then
		poolCursor = 1
	end
	return sound
end

--[[
	Joue un son du catalogue.

	`intensity` (0..1, defaut 1) module le volume : il sert a rendre une frappe
	nucleaire lointaine plus discrete qu'une frappe sur son propre territoire,
	sans multiplier les entrees du catalogue.
]]
function SoundManager.play(name: string, intensity: number?)
	local def = Audio.SOUNDS[name]
	if not def or def.id == "" or failed[name] then
		return
	end

	local now = os.clock()
	local last = lastPlayed[name]
	if last and now - last < def.throttle then
		return
	end
	lastPlayed[name] = now

	local categoryVolume = Audio.categoryVolume[def.category] or 1
	local volume = def.volume * categoryVolume * Audio.masterVolume * (intensity or 1)
	if volume <= 0.001 then
		return
	end

	local sound = nextVoice()
	sound.SoundId = def.id
	sound.Volume = volume

	-- La hauteur varie en demi-tons : une variation lineaire du PlaybackSpeed
	-- serait perceptiblement asymetrique vers le grave.
	if def.pitchRange > 0 then
		local semitones = (math.random() * 2 - 1) * def.pitchRange
		sound.PlaybackSpeed = 2 ^ (semitones / 12)
	else
		sound.PlaybackSpeed = 1
	end

	-- Un identifiant absent du client leve a la lecture : on le retire du
	-- catalogue au lieu de reessayer a chaque declenchement.
	local ok = pcall(function()
		sound:Play()
	end)
	if not ok then
		failed[name] = true
		warn(`[CONQUEST RTS] son indisponible, desactive : {name} ({def.id})`)
	end
end

--[[
	Variante spatiale : le volume decroit avec la distance a l'ecran entre
	l'evenement et le centre de la vue. Une bombe a l'autre bout de la carte
	doit s'entendre, mais en arriere-plan.
]]
function SoundManager.playAt(name: string, tileDistance: number, falloff: number?)
	local range = falloff or 90
	local intensity = math.clamp(1 - tileDistance / range, 0.15, 1)
	SoundManager.play(name, intensity)
end

function SoundManager.setMasterVolume(volume: number)
	Audio.masterVolume = math.clamp(volume, 0, 1)
end

return SoundManager
