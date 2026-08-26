--[[
	Bouchons des API d'interface et de scene Roblox.

	Ils existent pour une raison precise : tout le code client etait jusqu'ici
	livre sans jamais avoir ete execute une seule fois. Les erreurs de
	chargement d'un module d'interface (propriete mal nommee, methode absente,
	nil indexe) ne se voyaient qu'au lancement dans Studio, et se presentaient au
	joueur comme un ecran noir sans explication.

	Ces bouchons ne simulent pas le rendu. Ils simulent juste assez d'API pour
	que les modules se construisent et que leurs methodes s'executent : c'est
	suffisant pour attraper la quasi-totalite de cette classe de bugs.
]]

--=============================================================================
-- Signaux
--=============================================================================

local function makeSignal()
	local signal = { handlers = {} }
	function signal:Connect(fn)
		table.insert(self.handlers, fn)
		local conn = { Connected = true }
		-- N170 : Disconnect doit retirer le handler. Un no-op laissait
		-- Fire appeler toutes les Activated accumulees au reuse chat
		-- (double-fire QuickChat, test messages rapides rouge).
		function conn.Disconnect()
			if not conn.Connected then
				return
			end
			conn.Connected = false
			for i, handler in signal.handlers do
				if handler == fn then
					table.remove(signal.handlers, i)
					break
				end
			end
		end
		return conn
	end
	function signal:Once(fn)
		return self:Connect(fn)
	end
	function signal:Wait()
		return nil
	end
	--[[
		Utilise par les tests pour declencher un evenement a la main.

		On itere une copie : un gestionnaire qui se connecte ou se deconnecte
		pendant la diffusion mutait la liste en cours de parcours, et le banc
		pouvait alors appeler un gestionnaire pose une microseconde plus tot.
		Roblox ne se comporte pas ainsi, donc le bouchon ne doit pas non plus.
	]]
	function signal:Fire(...)
		local snapshot = table.clone(self.handlers)
		for _, fn in snapshot do
			fn(...)
		end
	end
	return signal
end

-- Evenements exposes par les instances. Les lire doit toujours renvoyer un
-- signal, meme si personne ne les declenche.
local INSTANCE_EVENTS = {
	"Activated",
	"MouseEnter",
	"MouseLeave",
	"MouseButton1Down",
	"MouseButton1Click",
	"Changed",
	"Completed",
	"InputBegan",
	"InputChanged",
	"InputEnded",
	"OnClientEvent",
	"OnServerEvent",
	"CharacterAdded",
	"ChildAdded",
	"AncestryChanged",
}

--=============================================================================
-- Bruit
--=============================================================================
-- Le bundler reecrit math.noise en __noise (la table math est en lecture seule
-- dans Luau). Le banc client genere de vraies cartes, il lui faut donc la meme
-- implementation que le banc serveur.

local function hash2(x, y)
	local h = bit32.bxor(bit32.band(x * 73856093, 0xFFFFFFFF), bit32.band(y * 19349663, 0xFFFFFFFF))
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = bit32.band(h * 1274126177, 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296 - 0.5
end

local function smoothStep(t)
	return t * t * (3 - 2 * t)
end

__noise = function(x, y, z)
	y = y or 0
	local _ = z

	local x0 = math.floor(x)
	local y0 = math.floor(y)
	local fx = smoothStep(x - x0)
	local fy = smoothStep(y - y0)

	local v00 = hash2(x0, y0)
	local v10 = hash2(x0 + 1, y0)
	local v01 = hash2(x0, y0 + 1)
	local v11 = hash2(x0 + 1, y0 + 1)

	local top = v00 + (v10 - v00) * fx
	local bottom = v01 + (v11 - v01) * fx
	return top + (bottom - top) * fy
end

--=============================================================================
-- Instances
--=============================================================================

local GUI_CLASSES = {
	Frame = true,
	CanvasGroup = true,
	TextLabel = true,
	TextButton = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
	ScreenGui = true,
	BillboardGui = true,
	SurfaceGui = true,
}

local PART_CLASSES = { Part = true, MeshPart = true, WedgePart = true }

local InstanceMT = {}

local function newInstance(className)
	local self = {
		ClassName = className,
		Name = className,
		_children = {},
		_attributes = {},
		_parent = nil,
	}

	for _, event in INSTANCE_EVENTS do
		self[event] = makeSignal()
	end

	return setmetatable(self, InstanceMT)
end

InstanceMT.__index = function(t, key)
	local method = InstanceMT.methods[key]
	if method then
		return method
	end
	if key == "Parent" then
		return rawget(t, "_parent")
	end
	--[[
		AbsoluteSize a une valeur par defaut, contrairement aux autres.

		C'est une propriete calculee par le moteur de rendu : elle n'est jamais
		ecrite par le code, mais elle n'est jamais nil non plus. La laisser a nil
		faisait planter tout code qui borne une position a l'ecran — un cas
		parfaitement legitime que le banc devait pouvoir exercer.
	]]
	--[[
		Le lien CFrame/Position ne vaut QUE pour les objets 3D.

		Sur un objet d'interface, `Position` est un UDim2 — dont le champ `X`
		est un UDim, pas un nombre. Intercepter la clef pour tout le monde
		transformait donc les positions d'interface en vecteurs et cassait
		toute lecture de `Position.X.Offset`.
	]]
	if PART_CLASSES[rawget(t, "ClassName")] then
		if key == "CFrame" then
			return rawget(t, "_cframe")
		end
		if key == "Position" then
			local cf = rawget(t, "_cframe")
			return if cf then Vector3.new(cf.X, cf.Y, cf.Z) else nil
		end
	end
	if key == "AbsoluteSize" then
		return Vector2.new(1280, 720)
	end
	if key == "AbsolutePosition" then
		return Vector2.new(0, 0)
	end
	-- Les autres proprietes jamais ecrites valent nil, comme une valeur par
	-- defaut non pertinente pour le test.
	return nil
end

InstanceMT.__newindex = function(t, key, value)
	-- BasePart n'a pas de propriete Visible. L'accepter ici a masque une erreur
	-- qui interrompait MapInit dans Studio alors que tout le banc client passait.
	-- La visibilite 3D se controle avec Transparency.
	if key == "Visible" and PART_CLASSES[rawget(t, "ClassName")] then
		error(`Visible is not a valid member of {rawget(t, "ClassName")}`)
	end

	if key == "Parent" then
		local previous = rawget(t, "_parent")
		if previous then
			local siblings = rawget(previous, "_children")
			for i, child in siblings do
				if child == t then
					table.remove(siblings, i)
					break
				end
			end
		end
		rawset(t, "_parent", value)
		if value and rawget(value, "_children") then
			table.insert(rawget(value, "_children"), t)
		end
		return
	end

	--[[
		Position et CFrame sont liees dans Roblox : ecrire l'une met l'autre a
		jour. On les range sous une clef privee et JAMAIS sous leur nom public.

		La raison est un piege du langage : `__newindex` ne se declenche que si
		la clef est absente de la table. La version precedente posait `CFrame`
		par rawset, donc la deuxieme ecriture sur un meme objet contournait ce
		bloc et laissait `Position` fige sur sa valeur initiale — silencieusement.

		Consequence : tout test qui deplacait un objet APRES sa creation ne
		mesurait plus rien. Il lisait la position de depart et la comparait a une
		attente calculee sur cette meme position de depart, donc il passait quoi
		que fasse le code teste. C'est exactement la panne qu'un banc est cense
		rendre impossible.
	]]
	if PART_CLASSES[rawget(t, "ClassName")] and type(value) == "table" and value.X ~= nil then
		if key == "CFrame" then
			rawset(t, "_cframe", value)
			return
		elseif key == "Position" then
			rawset(t, "_cframe", CFrame.new(value.X, value.Y, value.Z))
			return
		end
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

	--[[
		Boite englobante d'un modele, calculee sur ses BaseParts.

		Le banc en a besoin pour exercer la normalisation des modeles importes :
		sans elle, tout le chemin d'import etait injouable hors de Studio et donc
		livre sans qu'une seule ligne n'ait jamais ete executee.
	]]
	GetBoundingBox = function(self)
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		local found = false

		local function visit(node)
			for _, child in rawget(node, "_children") do
				local size = rawget(child, "Size")
				local position = child.Position
				if size and position and size.X then
					found = true
					minX = math.min(minX, position.X - size.X / 2)
					minY = math.min(minY, position.Y - size.Y / 2)
					minZ = math.min(minZ, position.Z - size.Z / 2)
					maxX = math.max(maxX, position.X + size.X / 2)
					maxY = math.max(maxY, position.Y + size.Y / 2)
					maxZ = math.max(maxZ, position.Z + size.Z / 2)
				end
				visit(child)
			end
		end
		visit(self)

		if not found then
			return CFrame.new(Vector3.new(0, 0, 0)), Vector3.new(0, 0, 0)
		end
		return CFrame.new(Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)),
			Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	end,

	GetDescendants = function(self)
		local out = {}
		local function walk(node)
			for _, child in rawget(node, "_children") do
				table.insert(out, child)
				walk(child)
			end
		end
		walk(self)
		return out
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

	FindFirstChildWhichIsA = function(self, className)
		for _, child in rawget(self, "_children") do
			if InstanceMT.methods.IsA(child, className) then
				return child
			end
		end
		return nil
	end,

	-- N189 : VisualDirector.apply Terrain. Distinct de WhichIsA
	-- (heritage). WorldCamera Humanoid aussi. Pas Destroy.
	FindFirstChildOfClass = function(self, className)
		for _, child in rawget(self, "_children") do
			if rawget(child, "ClassName") == className then
				return child
			end
		end
		return nil
	end,

	IsA = function(self, className)
		local own = rawget(self, "ClassName")
		if own == className then
			return true
		end
		if className == "GuiObject" or className == "GuiBase2d" then
			return GUI_CLASSES[own] == true and own ~= "ScreenGui"
		end
		if className == "BasePart" then
			return PART_CLASSES[own] == true
		end
		if className == "Instance" then
			return true
		end
		return false
	end,

	Destroy = function(self)
		local parent = rawget(self, "_parent")
		if parent then
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

	Play = function() end,
	Pause = function() end,
	Stop = function() end,
	--[[
		Copie profonde, comme le vrai Clone.

		Il renvoyait une coquille vide : ni enfants, ni proprietes, ni attributs.
		Tout test portant sur du code qui clone un modele passait donc quoi que
		fasse ce code — le clone etant vide, la boucle qui le parcourt ne
		s'executait simplement jamais. C'est le meme piege qu'un Instance.new
		qui avale ce qu'on lui ecrit.
	]]
	Clone = function(self)
		local copy = newInstance(rawget(self, "ClassName"))

		for key, value in pairs(self) do
			local internal = key == "_children" or key == "_parent" or key == "_attributes"
			-- Les signaux sont recrees par newInstance : les recopier ferait
			-- partager les abonnes entre l'original et sa copie.
			local isSignal = type(value) == "table" and rawget(value, "handlers") ~= nil
			if not internal and not isSignal then
				rawset(copy, key, value)
			end
		end

		local attributes = rawget(self, "_attributes")
		if attributes then
			local copied = rawget(copy, "_attributes")
			for key, value in attributes do
				copied[key] = value
			end
		end

		for _, child in rawget(self, "_children") do
			local childCopy = InstanceMT.methods.Clone(child)
			childCopy.Parent = copy
		end

		return copy
	end,
	GetPropertyChangedSignal = function()
		return makeSignal()
	end,
	VectorToWorldSpace = function(_, v)
		return v
	end,
	Lerp = function(a, b, t)
		return a
	end,
	WritePixelsBuffer = function() end,
	Raycast = function()
		return nil
	end,
	ViewportPointToRay = function()
		return { Origin = Vector3.new(), Direction = Vector3.new(0, -1, 0) }
	end,
	ScreenPointToRay = function()
		return { Origin = Vector3.new(), Direction = Vector3.new(0, -1, 0) }
	end,
	FireServer = function() end,
	FireClient = function() end,
	FireAllClients = function() end,
}

Instance = {}
Instance.new = function(className)
	return newInstance(className)
end

--=============================================================================
-- Types de valeur
--=============================================================================

local function valueType(fields, extra)
	local t = setmetatable(fields, {
		__index = extra,
		__add = function(a, b)
			return a
		end,
		__sub = function(a, b)
			return a
		end,
		__mul = function(a, b)
			return a
		end,
		__div = function(a, b)
			return a
		end,
		__unm = function(a)
			return a
		end,
	})
	return t
end

UDim = { new = function(scale, offset)
	return valueType({ Scale = scale or 0, Offset = offset or 0 })
end }

UDim2 = {}
UDim2.new = function(sx, ox, sy, oy)
	return valueType({ X = UDim.new(sx, ox), Y = UDim.new(sy, oy) })
end
UDim2.fromScale = function(x, y)
	return UDim2.new(x, 0, y, 0)
end
UDim2.fromOffset = function(x, y)
	return UDim2.new(0, x, 0, y)
end

local Vector2MT = {}
Vector2 = {}
Vector2.new = function(x, y)
	return setmetatable({ X = x or 0, Y = y or 0, Magnitude = math.sqrt((x or 0) ^ 2 + (y or 0) ^ 2) }, Vector2MT)
end
Vector2MT.__index = function(t, k)
	if k == "Unit" then
		return Vector2.new(0, 1)
	end
	return nil
end
Vector2MT.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
Vector2MT.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
Vector2MT.__mul = function(a, b)
	if type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
Vector2MT.__div = function(a, b)
	if type(b) == "number" then
		return Vector2.new(a.X / b, a.Y / b)
	end
	return Vector2.new(a.X / b.X, a.Y / b.Y)
end
Vector2.zero = Vector2.new(0, 0)

local Vector3MT = {}
Vector3 = {}
Vector3.new = function(x, y, z)
	return setmetatable({
		X = x or 0,
		Y = y or 0,
		Z = z or 0,
		Magnitude = math.sqrt((x or 0) ^ 2 + (y or 0) ^ 2 + (z or 0) ^ 2),
	}, Vector3MT)
end
Vector3MT.__index = function(t, k)
	if k == "Unit" then
		return Vector3.new(0, 1, 0)
	end
	return nil
end
Vector3MT.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3MT.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3MT.__div = function(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X / b, a.Y / b, a.Z / b)
	end
	return a
end
Vector3.zero = Vector3.new(0, 0, 0)

local CFrameMT = {}
CFrame = {}
CFrame.new = function(x, y, z)
	if type(x) == "table" then
		return setmetatable({ X = x.X, Y = x.Y, Z = x.Z, Position = x }, CFrameMT)
	end
	local position = Vector3.new(x or 0, y or 0, z or 0)
	return setmetatable({ X = position.X, Y = position.Y, Z = position.Z, Position = position }, CFrameMT)
end
CFrame.Angles = function()
	return CFrame.new(0, 0, 0)
end
CFrame.fromEulerAnglesYXZ = function()
	return CFrame.new(0, 0, 0)
end
CFrame.lookAt = function(from)
	return CFrame.new(from.X, from.Y, from.Z)
end
CFrameMT.__index = function(t, k)
	if k == "VectorToWorldSpace" then
		return function(_, v)
			return v
		end
	end
	return nil
end
CFrameMT.__mul = function(a)
	return a
end
CFrameMT.__add = function(a, v)
	return CFrame.new(a.X + v.X, a.Y + v.Y, a.Z + v.Z)
end
CFrameMT.__sub = function(a, v)
	return CFrame.new(a.X - v.X, a.Y - v.Y, a.Z - v.Z)
end

local Color3MT = {}
local function makeColor(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, Color3MT)
end
Color3MT.__index = function(t, k)
	if k == "Lerp" then
		return function(a)
			return a
		end
	end
	return nil
end
Color3 = {}
Color3.new = function(r, g, b)
	return makeColor(r or 0, g or 0, b or 0)
end
Color3.fromRGB = function(r, g, b)
	return makeColor(r / 255, g / 255, b / 255)
end
Color3.fromHSV = function(h, s, v)
	return makeColor(v, v, v)
end

ColorSequence = { new = function()
	return {}
end }
NumberSequence = { new = function()
	return {}
end }
NumberSequenceKeypoint = { new = function(time, value, envelope)
	return { Time = time, Value = value, Envelope = envelope }
end }
TweenInfo = { new = function()
	return {}
end }
Font = { fromEnum = function()
	return {}
end }
Content = { fromObject = function()
	return {}
end }

Ray = { new = function()
	return {}
end }
RaycastParams = { new = function()
	return { FilterDescendantsInstances = {} }
end }

--=============================================================================
-- Enums
--=============================================================================
-- Toute lecture Enum.X.Y renvoie un jeton unique et stable.

local enumCategories = {}
Enum = setmetatable({}, {
	__index = function(_, category)
		if not enumCategories[category] then
			enumCategories[category] = setmetatable({}, {
				__index = function(t, item)
					local token = { EnumType = category, Name = item }
					rawset(t, item, token)
					return token
				end,
			})
		end
		return enumCategories[category]
	end,
})

--=============================================================================
-- Services
--=============================================================================

local services = {}

local function service(name, members)
	local s = newInstance(name)
	s.Name = name
	for key, value in members or {} do
		rawset(s, key, value)
	end
	services[name] = s
	return s
end

service("TweenService", {
	Create = function(_, instance, info, goals)
		-- Le tween applique immediatement sa cible : les tests verifient l'etat
		-- final, pas l'animation.
		return {
			Play = function()
				for property, value in goals do
					instance[property] = value
				end
			end,
			Cancel = function() end,
			Completed = makeSignal(),
		}
	end,
})

service("UserInputService", {
	GetMouseLocation = function()
		return Vector2.new(400, 300)
	end,
	IsKeyDown = function()
		return false
	end,
	MouseBehavior = nil,
	-- Le banc simule un poste de travail : la barre d'action tactile ne doit
	-- donc pas se construire toute seule — les tests la forcent a la demande.
	TouchEnabled = false,
	KeyboardEnabled = true,
})

service("ContextActionService", {
	BindAction = function() end,
	UnbindAction = function() end,
})

service("RunService", {
	IsServer = function()
		return false
	end,
	IsClient = function()
		return true
	end,
	Heartbeat = makeSignal(),
	RenderStepped = makeSignal(),
})

service("AssetService", {
	-- Renvoie une EditableImage factice : on teste le chemin nominal. Le chemin
	-- degrade (API absente) est couvert par les pcall du code lui-meme.
	CreateEditableImage = function()
		local image = newInstance("EditableImage")
		return image
	end,
})

service("SoundService", {})
service("Lighting", {})
service("Debris", {})

local workspaceStub = service("Workspace", {
	Raycast = function()
		return nil
	end,
})
rawset(workspaceStub, "CurrentCamera", (function()
	local camera = newInstance("Camera")
	rawset(camera, "ViewportSize", Vector2.new(1280, 720))
	rawset(camera, "CFrame", CFrame.new(0, 0, 0))
	return camera
end)())

local localPlayer = newInstance("Player")
localPlayer.Name = "TestPlayer"
rawset(localPlayer, "DisplayName", "TestPlayer")
rawset(localPlayer, "UserId", 1)
local playerGui = newInstance("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = localPlayer

service("Players", {
	LocalPlayer = localPlayer,
	GetPlayers = function()
		return { localPlayer }
	end,
	CharacterAutoLoads = false,
})

local replicated = service("ReplicatedStorage", {})

game = {
	GetService = function(_, name)
		if not services[name] then
			service(name, {})
		end
		return services[name]
	end,
	BindToClose = function() end,
}
setmetatable(game, {
	__index = function(_, key)
		return game.GetService(nil, key)
	end,
})

script = newInstance("LocalScript")

-- Rappels differes en attente. Voir task.delay et testFlushDelays.
local pendingDelays: { { fn: any, args: any } } = {}

task = {
	spawn = function(fn, ...)
		fn(...)
	end,
	--[[
		`task.delay` MET EN FILE, il n'execute pas.

		Il appelait la fonction immediatement, en ignorant le delai. Consequence :
		tout objet cree puis detruit par un `task.delay` naissait et mourait dans
		le meme appel, et aucun test ne pouvait l'observer — le banc voyait un
		ecran vide la ou le jeu affiche quelque chose pendant une seconde et
		demie.

		Les rappels s'empilent ici et le banc les declenche quand il veut, avec
		`testFlushDelays()`. Un test qui veut observer l'objet ne flushe pas ;
		un test qui veut verifier le nettoyage flushe.
	]]
	delay = function(_, fn, ...)
		if fn then
			table.insert(pendingDelays, { fn = fn, args = table.pack(...) })
		end
	end,
	wait = function() end,
	defer = function(fn, ...)
		if fn then
			fn(...)
		end
	end,
}

warn = function(...)
	print("[warn]", ...)
end

--[[
	Declenche les rappels differes accumules.

	Les nouveaux rappels poses PENDANT le flush sont traites au tour suivant :
	sans cette separation, un nettoyage qui se replanifie boucle indefiniment.
]]
function testFlushDelays()
	local batch = pendingDelays
	pendingDelays = {}
	for _, entry in batch do
		entry.fn(table.unpack(entry.args, 1, entry.args.n))
	end
end

testReplicated = replicated
testPlayerGui = playerGui
