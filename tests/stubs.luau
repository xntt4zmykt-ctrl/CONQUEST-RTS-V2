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

--[[
	Hash entier 2D.

	Ecrit avec bit32 et non en arithmetique flottante : la version precedente
	calculait n^3 * 15731, ce qui depasse largement les 53 bits de mantisse d'un
	double. Le modulo d'un nombre deja fausse ne renvoyait qu'une poignee de
	valeurs distinctes, et le terrain genere dans les tests n'avait plus rien a
	voir avec celui de Roblox — au point de produire des cartes a 3 % de terre.
]]
local function hash2(x, y)
	local h = bit32.bxor(bit32.band(x * 73856093, 0xFFFFFFFF), bit32.band(y * 19349663, 0xFFFFFFFF))
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = bit32.band(h * 1274126177, 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296 - 0.5
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
	local service = {
		Name = name,
		GetPlayers = function()
			return {}
		end,
		BindToClose = function() end,
	}
	-- RunService est interroge au chargement de Remotes (IsServer) : sans ces
	-- methodes, tout module qui tire Remotes fait planter le banc serveur.
	if name == "RunService" then
		service.IsServer = function()
			return true
		end
		service.IsClient = function()
			return false
		end
		service.Heartbeat = { Connect = function() end }
	end
	return service
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

-- Vector3 / CFrame : suffisants pour que les modules se chargent. Le banc
-- d'essai ne mesure que de la geometrie logique, jamais des transformations.
Vector3 = {}
Vector3.new = function(x, y, z)
	return { X = x or 0, Y = y or 0, Z = z or 0 }
end
Vector3.zero = { X = 0, Y = 0, Z = 0 }

CFrame = {}
CFrame.new = function(x, y, z)
	return { X = x or 0, Y = y or 0, Z = z or 0 }
end

--=============================================================================
-- Instances
--=============================================================================
--[[
	Arbre d'instances minimal.

	La version precedente etait un trou noir : toute propriete ecrite etait
	jetee et toute methode appelee ne faisait rien. Cela suffisait tant que le
	banc serveur ne faisait que charger des modules qui touchent des Instances
	sans jamais les relire — mais le classement Roblox, lui, ecrit un arbre puis
	le relit, et un trou noir aurait valide n'importe quoi.

	Le banc client a le sien dans guistubs.luau, plus riche parce qu'il doit
	simuler la mise en page. Les deux restent separes : le serveur n'a pas
	besoin de GuiObject ni de tailles absolues, et un bouchon partage
	obligerait a maintenir les deux besoins au meme endroit.
]]

local INSTANCE_CLASS_PARENTS = {
	-- Seule la parente reellement interrogee par le code serveur est decrite :
	-- IsA doit distinguer une valeur d'un dossier dans les enfants de
	-- `leaderstats`, et reconnaitre une Part.
	StringValue = "ValueBase",
	IntValue = "ValueBase",
	NumberValue = "ValueBase",
	BoolValue = "ValueBase",
	ValueBase = "Instance",
	Folder = "Instance",
	Part = "BasePart",
	MeshPart = "BasePart",
	BasePart = "Instance",
	Player = "Instance",
}

local InstanceMT = {}

local function newInstance(className)
	local inst = setmetatable({
		ClassName = className,
		Name = className,
		_children = {},
		_attributes = {},
		_parent = nil,
	}, InstanceMT)
	-- RemoteEvent : OnServerEvent.Connect est appele au bind des intentions.
	if className == "RemoteEvent" then
		inst.OnServerEvent = {
			Connect = function(_self, _fn)
				return { Disconnect = function() end }
			end,
		}
		inst.OnClientEvent = {
			Connect = function(_self, _fn)
				return { Disconnect = function() end }
			end,
		}
	end
	return inst
end

InstanceMT.__index = function(t, key)
	local method = InstanceMT.methods[key]
	if method then
		return method
	end
	if key == "Parent" then
		return rawget(t, "_parent")
	end
	-- Une propriete jamais ecrite vaut nil, comme une valeur par defaut sans
	-- interet pour le test.
	return nil
end

InstanceMT.__newindex = function(t, key, value)
	if key == "Parent" then
		local previous = rawget(t, "_parent")
		if previous and rawget(previous, "_children") then
			local siblings = rawget(previous, "_children")
			for i, child in siblings do
				if child == t then
					table.remove(siblings, i)
					break
				end
			end
		end
		rawset(t, "_parent", value)
		-- Roblox conserve l'ordre d'insertion des enfants, et c'est exactement
		-- ce dont depend l'ordre des colonnes du classement : GetChildren doit
		-- donc rendre les enfants dans l'ordre ou ils ont ete parentes.
		if value and rawget(value, "_children") then
			table.insert(rawget(value, "_children"), t)
		end
		return
	end
	rawset(t, key, value)
end

InstanceMT.methods = {
	GetChildren = function(self)
		local copy = {}
		for _, child in rawget(self, "_children") do
			table.insert(copy, child)
		end
		return copy
	end,

	FindFirstChild = function(self, name)
		for _, child in rawget(self, "_children") do
			if child.Name == name then
				return child
			end
		end
		return nil
	end,

	WaitForChild = function(self, name)
		return InstanceMT.methods.FindFirstChild(self, name)
	end,

	IsA = function(self, className)
		local own = rawget(self, "ClassName")
		while own do
			if own == className then
				return true
			end
			own = INSTANCE_CLASS_PARENTS[own]
		end
		return className == "Instance"
	end,

	Destroy = function(self)
		local parent = rawget(self, "_parent")
		if parent and rawget(parent, "_children") then
			local siblings = rawget(parent, "_children")
			for i, child in siblings do
				if child == self then
					table.remove(siblings, i)
					break
				end
			end
		end
		rawset(self, "_parent", nil)
		rawset(self, "_children", {})
	end,

	SetAttribute = function(self, name, value)
		rawget(self, "_attributes")[name] = value
	end,

	GetAttribute = function(self, name)
		return rawget(self, "_attributes")[name]
	end,

	FireClient = function() end,
	FireAllClients = function() end,
	Connect = function(_self, _fn)
		return { Disconnect = function() end }
	end,
}

Instance = {}
Instance.new = function(className)
	return newInstance(className)
end

-- Workspace serveur : WorldBuilder.build (N191) relit FindFirstChild /
-- GetChildren / Parent. Terrain:Clear no-op (SmoothTerrain d'une
-- partie precedente). Distinct leftover N192 clearDefaultScene
-- (Baseplate Destroy). Pas de GuiObject.
do
	local workspaceInst = newInstance("Workspace")
	workspaceInst.Name = "Workspace"
	local terrainInst = newInstance("Terrain")
	terrainInst.Name = "Terrain"
	terrainInst.Clear = function() end
	terrainInst.Parent = workspaceInst
	workspaceInst.Terrain = terrainInst
	services["Workspace"] = workspaceInst
end

-- Expose au banc d'essai de quoi fabriquer un faux Player : c'est le seul
-- receptacle du dossier `leaderstats`, et rien dans les modules ne le cree.
__newInstance = newInstance
