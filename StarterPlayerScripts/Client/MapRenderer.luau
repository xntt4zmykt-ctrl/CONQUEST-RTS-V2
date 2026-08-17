--!strict
--[[
	Rendu de la carte.

	On peint une EditableImage de 1 pixel par tuile et on l'etire a l'ecran en
	resampling Pixelated. Une tuile = un pixel, donc redessiner une conquete
	coute quelques ecritures memoire au lieu de toucher a des milliers
	d'instances : c'est la seule approche qui tient 40 000 tuiles sur mobile.

	Quatre couches se combinent dans chaque pixel :

	  1. **Relief**      — variation deterministe par tuile, pour que la terre
	                       ait une texture au lieu d'un aplat mort.
	  2. **Profondeur**  — l'ocean fonce en s'eloignant des cotes, ce qui donne
	                       instantanement la lecture d'une carte marine.
	  3. **Frontieres**  — un liseré sombre entre deux factions. C'est lui qui
	                       rend la carte lisible d'un coup d'oeil ; sans lui,
	                       deux territoires voisins bavent l'un dans l'autre.
	  4. **Chaleur**     — les tuiles recemment prises rougeoient puis
	                       refroidissent. Cet effet est purement client : il ne
	                       coute aucune bande passante et montre pourtant
	                       exactement ou la partie se joue.

	Note d'architecture : ce module ne connait rien de la simulation. Quand on
	passera au rendu 3D, c'est le seul fichier a remplacer.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT
local NEUTRAL = Config.NEUTRAL_SLOT
local OCEAN = Config.TERRAIN.OCEAN

local MapRenderer = {}
MapRenderer.__index = MapRenderer

export type MapRenderer = typeof(setmetatable(
	{} :: {
		terrain: buffer,
		owner: buffer,
		pixels: buffer,
		shade: buffer, -- variation de relief, 0..255
		depth: buffer, -- distance a la terre pour l'ocean, 0..MAX_DEPTH
		image: EditableImage,
		label: ImageLabel,
		needsUpload: boolean,
		warnedWriteFailure: boolean,
		hot: { [number]: number }, -- tuiles recemment prises -> chaleur 0..1
		hotCount: number,
	},
	MapRenderer
))

--=============================================================================
-- Palettes precalculees
--=============================================================================

local MAX_DEPTH = 14

-- Bleu cotier -> bleu abyssal.
local SHALLOW = Color3.fromRGB(38, 68, 104)
local DEEP = Color3.fromRGB(12, 22, 42)

-- Couleur du liseré entre factions et de la chaleur de conquete.
local BORDER_INK = Color3.fromRGB(10, 12, 18)
local HEAT = Color3.fromRGB(255, 214, 140)

local function toBytes(color: Color3): { number }
	return { math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255) }
end

local terrainBytes: { { number } } = {}
for id, color in Config.TERRAIN_COLORS do
	terrainBytes[id] = toBytes(color)
end

local playerBytes: { { number } } = {}
for i, color in Config.PLAYER_COLORS do
	playerBytes[i] = toBytes(color)
end

local oceanBytes: { { number } } = {}
for d = 0, MAX_DEPTH do
	oceanBytes[d] = toBytes(SHALLOW:Lerp(DEEP, d / MAX_DEPTH))
end

local BORDER_BYTES = toBytes(BORDER_INK)
local HEAT_BYTES = toBytes(HEAT)

local function colorIndex(slot: number): number
	return ((slot - 1) % #Config.PLAYER_COLORS) + 1
end

local scratch = table.create(4, 0)

--=============================================================================
-- Precalculs de terrain
--=============================================================================

--[[
	Variation de relief par tuile : un hash entier, donc identique chez tous les
	clients et stable d'une frame a l'autre. Un bruit aleatoire non
	deterministe ferait scintiller la carte a chaque repeint.
]]
local function buildShade(): buffer
	local shade = buffer.create(W * H)
	for index = 0, W * H - 1 do
		local n = (index * 374761393 + 668265263) % 2147483647
		n = (n * (n % 97 + 3)) % 251
		buffer.writeu8(shade, index, n)
	end
	return shade
end

--[[
	Distance de chaque tuile d'ocean a la terre la plus proche, par BFS
	multi-source depuis toutes les cotes a la fois. Un seul balayage de la carte
	au chargement, jamais recalcule : le relief ne change pas de la partie.
]]
local function buildDepth(terrain: buffer): buffer
	local depth = buffer.create(W * H)
	local queue = table.create(4096)
	local head = 1

	for index = 0, W * H - 1 do
		if buffer.readu8(terrain, index) ~= OCEAN then
			buffer.writeu8(depth, index, 0)
			table.insert(queue, index)
		else
			buffer.writeu8(depth, index, 255) -- non visite
		end
	end

	while head <= #queue do
		local current = queue[head]
		head += 1
		local currentDepth = buffer.readu8(depth, current)
		if currentDepth >= MAX_DEPTH then
			continue
		end

		local n = MapGen.neighbors(current, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if buffer.readu8(depth, nb) == 255 then
				buffer.writeu8(depth, nb, currentDepth + 1)
				table.insert(queue, nb)
			end
		end
	end

	-- Les poches d'ocean jamais atteintes (isolees au-dela de MAX_DEPTH)
	-- prennent la teinte la plus profonde.
	for index = 0, W * H - 1 do
		if buffer.readu8(depth, index) == 255 then
			buffer.writeu8(depth, index, MAX_DEPTH)
		end
	end

	return depth
end

--=============================================================================
-- Rattachement de l'image
--=============================================================================

--[[
	L'API a change au fil des versions de Roblox : la forme actuelle passe par
	`ImageLabel.ImageContent = Content.fromObject(image)`, l'ancienne consistait
	a parenter l'EditableImage directement. On essaie les deux plutot que de
	supposer la version du moteur — un echec silencieux ici donne un ecran vide
	sans explication, le pire symptome possible a diagnostiquer.
]]
local function attachImage(label: ImageLabel, image: any): (boolean, string?)
	local modern = (Content :: any)
	if modern and modern.fromObject then
		local ok, err = pcall(function()
			label.ImageContent = modern.fromObject(image)
		end)
		if ok then
			return true, nil
		end
		if pcall(function()
			image.Parent = label
		end) then
			return true, nil
		end
		return false, tostring(err)
	end

	local ok, err = pcall(function()
		image.Parent = label
	end)
	return ok, if ok then nil else tostring(err)
end

local function showFailure(parent: GuiObject, message: string)
	local box = Instance.new("TextLabel")
	box.Name = "RendererFailure"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(580, 140)
	box.BackgroundColor3 = Color3.fromRGB(60, 20, 24)
	box.BorderSizePixel = 0
	box.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	box.TextSize = 15
	box.TextColor3 = Color3.fromRGB(255, 200, 200)
	box.TextWrapped = true
	box.Text = `Le rendu de la carte a echoue.\n\n{message}\n\n(details complets dans la fenetre Output)`
	box.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = box

	warn(`[CONQUEST RTS] rendu de la carte indisponible : {message}`)
end

--=============================================================================
-- Construction
--=============================================================================

function MapRenderer.new(seed: number, parent: GuiObject): MapRenderer?
	local self = setmetatable({}, MapRenderer) :: MapRenderer

	self.terrain = MapGen.generate(seed)
	self.owner = buffer.create(W * H)
	self.pixels = buffer.create(W * H * 4)
	self.shade = buildShade()
	self.depth = buildDepth(self.terrain)
	self.needsUpload = true
	self.warnedWriteFailure = false
	self.hot = {}
	self.hotCount = 0

	local created, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
	end)

	if not created or not image then
		showFailure(parent, `AssetService:CreateEditableImage a echoue — {tostring(image)}`)
		return nil
	end
	self.image = image

	local label = Instance.new("ImageLabel")
	label.Name = "MapImage"
	label.BackgroundTransparency = 1
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ScaleType = Enum.ScaleType.Stretch
	label.Size = UDim2.fromOffset(W * 4, H * 4)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Parent = parent
	self.label = label

	local attached, attachError = attachImage(label, image)
	if not attached then
		label:Destroy()
		showFailure(parent, `Impossible d'afficher l'EditableImage — {attachError}`)
		return nil
	end

	for index = 0, W * H - 1 do
		self:paint(index)
	end
	self:flush()

	return self
end

--=============================================================================
-- Peinture
--=============================================================================

--[[
	Recalcule la couleur d'un pixel a partir de l'etat courant de la tuile.

	C'est la fonction la plus appelee du client — plusieurs milliers de fois par
	seconde pendant une offensive. Elle travaille donc en octets bruts, sans
	allocation ni construction de Color3.
]]
function MapRenderer.paint(self: MapRenderer, index: number)
	local slot = buffer.readu8(self.owner, index)
	local terrain = buffer.readu8(self.terrain, index)
	local r, g, b

	if terrain == OCEAN then
		local rgb = oceanBytes[buffer.readu8(self.depth, index)]
		r, g, b = rgb[1], rgb[2], rgb[3]
		-- Legere houle : la meme variation de relief, mais tres attenuee.
		local wobble = (buffer.readu8(self.shade, index) - 128) / 255 * 8
		r = math.clamp(r + wobble, 0, 255)
		g = math.clamp(g + wobble, 0, 255)
		b = math.clamp(b + wobble, 0, 255)
	else
		local rgb
		if slot == NEUTRAL then
			rgb = terrainBytes[terrain]
		else
			rgb = playerBytes[colorIndex(slot)]
		end

		-- Relief : +/- 9 % de luminosite selon la tuile.
		local factor = 0.91 + (buffer.readu8(self.shade, index) / 255) * 0.18
		r = math.clamp(rgb[1] * factor, 0, 255)
		g = math.clamp(rgb[2] * factor, 0, 255)
		b = math.clamp(rgb[3] * factor, 0, 255)

		-- Liseré de frontiere : on assombrit la tuile qui touche un
		-- proprietaire different. Assombrir plutot qu'eclaircir garde la
		-- couleur de faction identifiable tout en tracant un trait net.
		local n = MapGen.neighbors(index, scratch)
		local foreign = false
		for i = 1, n do
			local nb = scratch[i]
			if buffer.readu8(self.terrain, nb) ~= OCEAN and buffer.readu8(self.owner, nb) ~= slot then
				foreign = true
				break
			end
		end

		if foreign and slot ~= NEUTRAL then
			r += (BORDER_BYTES[1] - r) * 0.45
			g += (BORDER_BYTES[2] - g) * 0.45
			b += (BORDER_BYTES[3] - b) * 0.45
		end
	end

	-- Chaleur de conquete : la tuile vient de changer de main.
	local heat = self.hot[index]
	if heat then
		r += (HEAT_BYTES[1] - r) * heat
		g += (HEAT_BYTES[2] - g) * heat
		b += (HEAT_BYTES[3] - b) * heat
	end

	local offset = index * 4
	buffer.writeu8(self.pixels, offset, r)
	buffer.writeu8(self.pixels, offset + 1, g)
	buffer.writeu8(self.pixels, offset + 2, b)
	buffer.writeu8(self.pixels, offset + 3, 255)
end

--[[
	Applique un delta serveur ([u32 index][u8 slot] repete).
	Chaque tuile modifiee force aussi le repeint de ses voisins : leur statut
	frontiere a pu changer meme si leur proprietaire, lui, n'a pas bouge.
]]
function MapRenderer.applyDelta(self: MapRenderer, delta: buffer): number
	local count = buffer.len(delta) // 5

	for i = 0, count - 1 do
		local offset = i * 5
		local index = buffer.readu32(delta, offset)
		if index < W * H then
			buffer.writeu8(self.owner, index, buffer.readu8(delta, offset + 4))
			if self.hot[index] == nil then
				self.hotCount += 1
			end
			self.hot[index] = 1
		end
	end

	for i = 0, count - 1 do
		local index = buffer.readu32(delta, i * 5)
		if index < W * H then
			self:paint(index)
			local n = MapGen.neighbors(index, scratch)
			for k = 1, n do
				self:paint(scratch[k])
			end
		end
	end

	self.needsUpload = true
	return count
end

--[[
	Refroidit les tuiles recemment prises. Appele une fois par frame.

	Le cout est proportionnel au nombre de tuiles chaudes, donc nul quand la
	carte est calme et borne pendant les offensives : une tuile ne reste chaude
	qu'environ une demi-seconde.
]]
function MapRenderer.stepHeat(self: MapRenderer, dt: number)
	if self.hotCount == 0 then
		return
	end

	local decay = math.min(1, dt * 2.2)
	local cooled = {}

	for index, heat in self.hot do
		local next = heat - decay
		if next <= 0.02 then
			table.insert(cooled, index)
		else
			self.hot[index] = next
		end
	end

	for _, index in cooled do
		self.hot[index] = nil
		self.hotCount -= 1
	end

	for index in self.hot do
		self:paint(index)
	end
	for _, index in cooled do
		self:paint(index)
	end

	self.needsUpload = true
end

-- Un seul upload GPU par frame, quel que soit le nombre de tuiles changees.
function MapRenderer.flush(self: MapRenderer)
	if not self.needsUpload then
		return
	end
	self.needsUpload = false

	-- Un echec d'ecriture ne doit pas tuer la boucle de rendu : on previent une
	-- fois et on laisse le reste de l'interface fonctionner.
	local ok, err = pcall(function()
		self.image:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), self.pixels)
	end)
	if not ok and not self.warnedWriteFailure then
		self.warnedWriteFailure = true
		warn(`[CONQUEST RTS] ecriture de l'EditableImage impossible : {tostring(err)}`)
	end
end

--=============================================================================
-- Requetes
--=============================================================================

function MapRenderer.ownerAt(self: MapRenderer, index: number): number
	return buffer.readu8(self.owner, index)
end

function MapRenderer.isLand(self: MapRenderer, index: number): boolean
	return buffer.readu8(self.terrain, index) ~= OCEAN
end

-- Convertit une position ecran en index de tuile, ou nil hors carte.
function MapRenderer.tileAtScreen(self: MapRenderer, screenPos: Vector2): number?
	local origin = self.label.AbsolutePosition
	local size = self.label.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end

	local u = (screenPos.X - origin.X) / size.X
	local v = (screenPos.Y - origin.Y) / size.Y
	if u < 0 or u >= 1 or v < 0 or v >= 1 then
		return nil
	end

	local x = math.clamp(math.floor(u * W), 0, W - 1)
	local y = math.clamp(math.floor(v * H), 0, H - 1)
	return MapGen.toIndex(x, y)
end

return MapRenderer
