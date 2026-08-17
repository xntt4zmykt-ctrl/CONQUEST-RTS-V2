--[[
	Bouchons des API Roblox, pour faire tourner la simulation serveur dans le
	Luau standard (hors de Studio).

	Seules les API reellement utilisees par les modules partages et serveur sont
	implementees. Random et math.noise sont reecrits a l'identique en
	comportement — deterministes et bornes pareil — pour que la carte generee
	ici soit representative de celle de Studio, meme si elle n'est pas
	bit-a-bit la meme.

	Ce fichier n'est jamais synchronise vers Roblox : le dossier tests/ n'est
	pas monte dans default.project.json.
]]

--=============================================================================
-- Color3 / Vector2
--=============================================================================

Color3 = {}
Color3.fromRGB = function(r, g, b)
	return { R = r / 255, G = g / 255, B = b / 255 }
end
Color3.new = function(r, g, b)
	return { R = r or 0, G = g or 0, B = b or 0 }
end

Vector2 = {}
Vector2.new = function(x, y)
	return { X = x, Y = y }
end
Vector2.zero = { X = 0, Y = 0 }

--=============================================================================
-- Random
--=============================================================================
-- Generateur congruentiel lineaire : deterministe pour une seed donnee, ce qui
-- est la seule propriete dont les tests ont besoin.

local RandomClass = {}
RandomClass.__index = RandomClass

function RandomClass:_next()
	self.seed = (self.seed * 1103515245 + 12345) % 2147483648
	return self.seed / 2147483648
end

function RandomClass:NextNumber(min, max)
	local value = self:_next()
	if min and max then
		return min + value * (max - min)
	end
	return value
end

function RandomClass:NextInteger(min, max)
	return math.floor(min + self:_next() * (max - min + 1 - 1e-9))
end

Random = {}
Random.new = function(seed)
	return setmetatable({ seed = (seed or os.time()) % 2147483648 }, RandomClass)
end

--=============================================================================
-- math.noise
--=============================================================================
-- Bruit de valeur interpole, deterministe. Ce n'est pas le Perlin de Roblox,
-- mais il a la meme signature, la meme plage approximative (-0.5..0.5) et la
-- meme continuite spatiale — suffisant pour valider que le generateur de carte
-- produit des continents coherents.

local function hash2(x, y)
	local n = x * 374761393 + y * 668265263
	n = (n % 2147483648)
	n = ((n * (n * n * 15731 + 789221) + 1376312589) % 2147483648)
	return n / 2147483648 - 0.5
end

local function smooth(t)
	return t * t * (3 - 2 * t)
end

-- La table `math` est en lecture seule dans Luau : on expose un global dedie,
-- et le bundler reecrit les appels math.noise(...) vers celui-ci.
__noise = function(x, y, z)
	y = y or 0
	local _ = z

	local x0 = math.floor(x)
	local y0 = math.floor(y)
	local fx = smooth(x - x0)
	local fy = smooth(y - y0)

	local v00 = hash2(x0, y0)
	local v10 = hash2(x0 + 1, y0)
	local v01 = hash2(x0, y0 + 1)
	local v11 = hash2(x0 + 1, y0 + 1)

	local top = v00 + (v10 - v00) * fx
	local bottom = v01 + (v11 - v01) * fx
	return top + (bottom - top) * fy
end

--=============================================================================
-- Services et instances
--=============================================================================

local function makeService(name)
	return {
		Name = name,
		GetPlayers = function()
			return {}
		end,
		BindToClose = function() end,
	}
end

local services = {}

game = {
	GetService = function(_, name)
		if not services[name] then
			services[name] = makeService(name)
		end
		return services[name]
	end,
	BindToClose = function() end,
}

-- Les chemins de require sont reecrits par le bundler, donc ces tables ne
-- servent qu'a ne pas faire planter l'indexation au chargement.
setmetatable(game, {
	__index = function(_, key)
		return makeService(key)
	end,
})

script = {}

task = {
	spawn = function(fn, ...)
		fn(...)
	end,
	delay = function(_, fn, ...)
		fn(...)
	end,
	wait = function() end,
}

warn = function(...)
	print("[warn]", ...)
end

-- Complement de palette : Config genere ses couleurs au-dela des 16 teintes
-- ecrites a la main, il faut donc aussi ce constructeur.
Color3.fromHSV = function(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	local r, g, b
	local m = i % 6
	if m == 0 then r, g, b = v, t, p
	elseif m == 1 then r, g, b = q, v, p
	elseif m == 2 then r, g, b = p, v, t
	elseif m == 3 then r, g, b = p, q, v
	elseif m == 4 then r, g, b = t, p, v
	else r, g, b = v, p, q end
	return { R = r, G = g, B = b }
end
