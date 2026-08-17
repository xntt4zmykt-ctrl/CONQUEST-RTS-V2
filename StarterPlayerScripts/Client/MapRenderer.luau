--!strict
--[[
	Rendu de la carte.

	On peint une EditableImage de 1 pixel par tuile et on l'etire a l'ecran en
	resampling Pixelated. Une tuile = un pixel, donc redessiner une conquete
	coute quelques ecritures memoire au lieu de toucher a des milliers
	d'instances : c'est la seule approche qui tient 40 000 tuiles sur mobile.

	Note d'architecture : ce module ne connait rien de la simulation. Quand on
	passera au rendu 3D (terrain, batiments, unites qui marchent), c'est le seul
	fichier a remplacer — GameState et le reseau ne bougent pas.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT
local NEUTRAL = Config.NEUTRAL_SLOT

local MapRenderer = {}
MapRenderer.__index = MapRenderer

export type MapRenderer = typeof(setmetatable(
	{} :: {
		terrain: buffer,
		owner: buffer,
		pixels: buffer,
		image: EditableImage,
		label: ImageLabel,
		needsUpload: boolean,
		warnedWriteFailure: boolean,
	},
	MapRenderer
))

-- Couleurs pre-converties en octets, pour ne pas refaire le calcul par pixel.
local terrainBytes: { { number } } = {}
for id, color in Config.TERRAIN_COLORS do
	terrainBytes[id] = { math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255) }
end

local playerBytes: { { number } } = {}
local playerBorderBytes: { { number } } = {}
for i, color in Config.PLAYER_COLORS do
	playerBytes[i] = { math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255) }
	-- Les tuiles frontieres sont eclaircies : c'est ce liseré qui rend les
	-- fronts lisibles d'un coup d'oeil quand on est dezoome.
	local lighter = color:Lerp(Color3.new(1, 1, 1), 0.45)
	playerBorderBytes[i] = { math.floor(lighter.R * 255), math.floor(lighter.G * 255), math.floor(lighter.B * 255) }
end

local function colorIndex(slot: number): number
	return ((slot - 1) % #Config.PLAYER_COLORS) + 1
end

local scratch = table.create(4, 0)

--[[
	Rattache l'EditableImage a l'ImageLabel.

	L'API a change au fil des versions de Roblox : la forme actuelle passe par
	`ImageLabel.ImageContent = Content.fromObject(image)`, l'ancienne consistait
	a parenter l'EditableImage directement. On essaie les deux plutot que de
	supposer la version du moteur, et on renvoie le message d'erreur si aucune
	ne marche — un echec silencieux ici donne un ecran vide sans explication,
	qui est le pire symptome possible a diagnostiquer.
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
		local legacyOk = pcall(function()
			image.Parent = label
		end)
		if legacyOk then
			return true, nil
		end
		return false, tostring(err)
	end

	local ok, err = pcall(function()
		image.Parent = label
	end)
	return ok, if ok then nil else tostring(err)
end

-- Banniere d'erreur plein ecran : sans elle, toute panne de rendu se presente
-- au joueur comme un fond bleu sans le moindre indice.
local function showFailure(parent: GuiObject, message: string)
	local box = Instance.new("TextLabel")
	box.Name = "RendererFailure"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(560, 120)
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

function MapRenderer.new(seed: number, parent: GuiObject): MapRenderer?
	local self = setmetatable({}, MapRenderer) :: MapRenderer

	self.terrain = MapGen.generate(seed)
	self.owner = buffer.create(W * H)
	self.pixels = buffer.create(W * H * 4)
	self.needsUpload = true
	self.warnedWriteFailure = false

	local created, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
	end)

	if not created or not image then
		showFailure(
			parent,
			`AssetService:CreateEditableImage a echoue — {tostring(image)}`
		)
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

	-- Peinture initiale : tout le terrain, aucun proprietaire.
	for index = 0, W * H - 1 do
		self:paint(index)
	end
	self:flush()

	return self
end

-- Recalcule la couleur d'un pixel a partir de l'etat courant de la tuile.
function MapRenderer.paint(self: MapRenderer, index: number)
	local slot = buffer.readu8(self.owner, index)
	local r, g, b

	if slot == NEUTRAL then
		local rgb = terrainBytes[buffer.readu8(self.terrain, index)]
		r, g, b = rgb[1], rgb[2], rgb[3]
	else
		local isBorder = false
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			if buffer.readu8(self.owner, scratch[i]) ~= slot then
				isBorder = true
				break
			end
		end
		local rgb = if isBorder then playerBorderBytes[colorIndex(slot)] else playerBytes[colorIndex(slot)]
		r, g, b = rgb[1], rgb[2], rgb[3]
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
function MapRenderer.applyDelta(self: MapRenderer, delta: buffer)
	local count = buffer.len(delta) // 5

	for i = 0, count - 1 do
		local offset = i * 5
		local index = buffer.readu32(delta, offset)
		if index < W * H then
			buffer.writeu8(self.owner, index, buffer.readu8(delta, offset + 4))
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

function MapRenderer.ownerAt(self: MapRenderer, index: number): number
	return buffer.readu8(self.owner, index)
end

--[[
	Convertit une position ecran en index de tuile, ou nil hors carte.
]]
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
