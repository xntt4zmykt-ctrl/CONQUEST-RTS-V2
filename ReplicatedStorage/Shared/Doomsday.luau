--!strict
--[[
	Cadran de la fin du monde, modele OpenFront : l'anti-impasse.

	Chaque faction doit tenir une part de la carte qui monte par vagues, comme
	la zone d'un battle-royale : une grace initiale a 0 % (le combat decide le
	debut de partie, pas le cadran), puis des paliers qui montent lineairement
	avec une pause entre chaque. Une faction sous la barre est marquee, puis
	saigne ses troupes vers un plancher qui s'effondre, puis le ROT territorial
	l'emporte dans un delai garanti. Sans le rot, une impasse survivrait a la
	derniere vague avec tous les challengers estropes mais intouchables.

	Le leader n'est jamais condamne : le cadran tond les challengers vers le
	leader, ce qui garantit un vainqueur unique sans jamais figer la partie
	avec tous les camps affaiblis.

	Ce module ne contient que des fonctions pures : le serveur (execution) et
	le client (affichage) lisent les memes courbes, donc les deux ne derivent
	jamais.
]]

local Doomsday = {}

-- Paliers des vagues, en pourcents de la carte. Empruntes au jeu de
-- reference : mesures sur des tournois reels, le second n'a jamais depasse
-- 21.6 % en fin de partie — une barre au-dela de ~35 % condamnerait le
-- leader lui-meme.
Doomsday.LEVELS = { 2, 4, 7, 11, 17, 25, 35 }

-- Part de la duree du mode passee en grace : le cadran est un brise-impasse,
-- pas un ecremage de debut de partie.
Doomsday.GRACE_SHARE = 0.4

-- Chaque vague monte pendant 75 % de sa fenetre puis tient son palier.
Doomsday.RAMP_SHARE = 0.75

export type WaveState = {
	current: number, -- part requise en ce moment, en pourcents
	target: number, -- palier vise par la rampe courante (ou la prochaine)
	growing: boolean, -- vrai pendant la montee
	armed: boolean, -- faux pendant la grace initiale
	done: boolean, -- vrai une fois le dernier palier atteint
}

--[[
	Part de la carte qu'une faction doit tenir a `elapsed` secondes de jeu,
	pour un mode d'une duree `duration` secondes. 0 pendant la grace, puis une
	montee lineaire par vague avec pause entre chaque.
]]
function Doomsday.requiredShare(duration: number, elapsed: number): number
	local grace = duration * Doomsday.GRACE_SHARE
	if elapsed <= grace then
		return 0
	end

	local window = duration - grace
	local waveLen = window / #Doomsday.LEVELS
	local ramp = waveLen * Doomsday.RAMP_SHARE
	local pause = waveLen - ramp

	local t = elapsed - grace
	local prev = 0
	for _, target in Doomsday.LEVELS do
		if t < ramp then
			return prev + (target - prev) * (t / ramp)
		end
		t -= ramp
		if t < pause then
			return target
		end
		t -= pause
		prev = target
	end
	return Doomsday.LEVELS[#Doomsday.LEVELS]
end

-- Nombre minimal de tuiles a tenir : une seule conversion arrondie, pour que
-- serveur et client tombent sur le meme entier.
function Doomsday.requiredTiles(duration: number, landCount: number, elapsed: number): number
	if landCount <= 0 then
		return 0
	end
	return math.floor((Doomsday.requiredShare(duration, elapsed) / 100) * landCount)
end

-- Etat d'affichage pour le HUD : ou en est la vague courante.
function Doomsday.waveState(duration: number, elapsed: number): WaveState
	local current = Doomsday.requiredShare(duration, elapsed)
	local grace = duration * Doomsday.GRACE_SHARE
	if elapsed <= grace then
		return {
			current = 0,
			target = Doomsday.LEVELS[1],
			growing = false,
			armed = false,
			done = false,
		}
	end

	local window = duration - grace
	local waveLen = window / #Doomsday.LEVELS
	local ramp = waveLen * Doomsday.RAMP_SHARE
	local pause = waveLen - ramp

	local t = elapsed - grace
	for i, target in Doomsday.LEVELS do
		local isLast = i == #Doomsday.LEVELS
		if t < ramp then
			return { current = current, target = target, growing = true, armed = true, done = false }
		end
		t -= ramp
		if t < pause then
			return {
				current = current,
				target = if isLast then target else Doomsday.LEVELS[i + 1],
				growing = false,
				armed = true,
				done = isLast,
			}
		end
		t -= pause
	end
	local last = Doomsday.LEVELS[#Doomsday.LEVELS]
	return { current = last, target = last, growing = false, armed = true, done = true }
end

--=============================================================================
-- Saignee et rot (constantes calibre cote serveur, courbes lues des deux cotes)
--=============================================================================

--[[
	Plancher de troupes, en pourcent du maximum : il decroit lineairement du
	niveau initial vers le plancher final, laissant une fenetre de retournement
	— la saignee estropie, elle n'execute pas.
]]
function Doomsday.troopFloor(maxTroops: number, secondsPastWarn: number, cfg): number
	local t = math.max(0, secondsPastWarn)
	local pct = cfg.DRAIN_FLOOR_PERCENT
	if t < cfg.FLOOR_DECAY_SECONDS then
		local span = cfg.FLOOR_START_PERCENT - cfg.DRAIN_FLOOR_PERCENT
		pct = cfg.FLOOR_START_PERCENT - (span * (t / cfg.FLOOR_DECAY_SECONDS))
	end
	return math.floor((maxTroops * pct) / 100)
end

--[[
	Troupes perdues cette seconde : un pourcentage du MAXIMUM (pas du stock),
	pour que la saignee depasse le revenu des la premiere seconde. Rampe
	lineaire du taux initial au taux maximal.
]]
function Doomsday.drain(maxTroops: number, secondsPastWarn: number, cfg): number
	local t = math.max(0, secondsPastWarn)
	local pct = cfg.DRAIN_MAX_PERCENT
	if t < cfg.DRAIN_RAMP_SECONDS then
		local span = cfg.DRAIN_MAX_PERCENT - cfg.DRAIN_START_PERCENT
		pct = cfg.DRAIN_START_PERCENT + span * (t / cfg.DRAIN_RAMP_SECONDS)
	end
	return math.max(1, math.floor((maxTroops * pct) / 100))
end

--[[
	Tuiles que le rot prend par seconde : le quota ceil(tuiles / secondes
	restantes) est auto-correctif, donc le delai de mort tient quelle que soit
	la taille de l'empire et le retard de demarrage du rot.
]]
function Doomsday.rotQuota(tilesLeft: number, secondsUnder: number, cfg): number
	if tilesLeft <= 0 or cfg.ROT_DEATH_SECONDS <= 0 then
		return 0
	end
	local secondsLeft = math.max(1, cfg.ROT_DEATH_SECONDS - secondsUnder)
	return math.ceil(tilesLeft / secondsLeft)
end

return Doomsday
