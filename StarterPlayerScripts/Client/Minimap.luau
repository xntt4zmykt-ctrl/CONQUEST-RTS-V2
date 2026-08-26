--!strict
--[[
	Minimap.

	Le monde est desormais de la geometrie 3D, donc la minimap ne peut plus se
	contenter de reafficher la texture de la carte : elle peint sa propre image,
	un pixel par tuile, a partir des memes donnees de propriete.

	Elle est **facultative**. Si le moteur ne fournit pas les EditableImage, elle
	ne s'affiche simplement pas — le jeu reste entierement jouable. C'est
	deliberé : la lecon de la version precedente est qu'aucune fonction de
	confort ne doit pouvoir emporter l'ecran entier avec elle.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))
local Theme = require(Shared:WaitForChild("Theme"))

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT
local OCEAN = Config.TERRAIN.OCEAN
local NEUTRAL = Config.NEUTRAL_SLOT

local Minimap = {}
Minimap.__index = Minimap

export type Minimap = typeof(setmetatable({} :: any, Minimap))

-- N187 : parkPanel / takePanel hoistes pour destroy() + new()
-- sans Destroy du Frame Minimap rematch. Skip Parent nil (deja
-- parke par un second destroy()). Push panelFree (Frame, pas
-- placeRootFree / ghostFree / worldFree / previewFree MainMenu).
-- take n'importe quel Frame, Name Minimap, Parent parent.
-- View / Focus FindFirstChild reuse, sinon construction
-- inchangee. CreateEditableImage seulement si pas de leftover
-- View+image. Recette leftover N186. Pas merger visual V69.
-- Distinct leftover N152 flame. Distinct leftover N123 setFocus.
-- Overlay non touche. PlacementPreview non touche.
-- WorldRenderer non touche. setFocus N123 inchange.
-- init.client minimap:destroy() deja. Ne pas vider panelFree.
-- Pas de delay. Distinct leftover N188 RadialMenu.destroy.
local panelFree: { Frame } = {}

local function parkPanel(panel: Frame)
	if not panel.Parent then
		return
	end
	panel.Parent = nil
	panelFree[#panelFree + 1] = panel
end

local function takePanel(): Frame?
	local n = #panelFree
	if n == 0 then
		return nil
	end
	local last = panelFree[n]
	panelFree[n] = nil
	return last
end

-- La minimap est le troisieme element permanent : elle doit rester lisible
-- sans manger le coin de l'ecran. 176 px suffisent pour situer un front.
local WIDTH = 176
local HEIGHT = math.floor(WIDTH * H / W)

local function toBytes(color: Color3): { number }
	return { math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255) }
end

local terrainBytes: { { number } } = {}
for id, color in Config.TERRAIN_COLORS do
	terrainBytes[id] = toBytes(color)
end

local factionBytes: { { number } } = {}
for i = 1, Config.MAX_PLAYERS do
	factionBytes[i] = toBytes(Theme.factionColor(i))
end

--[[
	`onJump` recoit un index de tuile quand le joueur clique : c'est
	init.client qui decide comment y deplacer la camera.
	Renvoie nil si le rendu d'image n'est pas disponible.
]]
function Minimap.new(parent: GuiObject, terrain: buffer, onJump: (number) -> ()): Minimap?
	-- N187 : peek leftover AVANT CreateEditableImage. Take seulement
	-- une fois l'image assuree (fail Create sans take = candidate
	-- reste dans panelFree). Name Minimap / Parent parent reposes
	-- au reuse (rematch init.client). View / Focus reuse si
	-- presents. CreateEditableImage seulement si pas de leftover
	-- View+image. Second Create au reuse = fuite GPU.
	local leftoverView: ImageLabel? = nil
	local leftoverImage = nil
	local candidate = if #panelFree > 0 then panelFree[#panelFree] else nil
	if candidate then
		local existingView = candidate:FindFirstChild("View")
		if existingView and existingView:IsA("ImageLabel") then
			leftoverView = existingView
			leftoverImage = existingView:FindFirstChildWhichIsA("EditableImage")
		end
	end

	local image = leftoverImage
	if not image then
		local created, img = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
		end)
		if not created or not img then
			warn(`[CONQUEST RTS] minimap indisponible (EditableImage) : {tostring(img)}`)
			return nil
		end
		image = img
	end

	local leftover = takePanel()

	local self = setmetatable({}, Minimap) :: any
	self.terrain = terrain
	self.image = image
	self.pixels = buffer.create(W * H * 4)
	self.needsUpload = true

	-- N187 : take Frame leftover avant create. Ne pas Theme.panel
	-- au reuse (UICorner + UIStroke dupliques). AnchorPoint /
	-- Position / Size reecrits (valeurs construction inchangees).
	local panel: Frame
	if leftover then
		panel = leftover
		panel.Name = "Minimap"
		panel.Parent = parent
	else
		panel = Theme.panel("Minimap", parent)
	end
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -Theme.space.md, 1, -Theme.space.md)
	panel.Size = UDim2.fromOffset(WIDTH + Theme.space.sm * 2, HEIGHT + Theme.space.sm * 2 + 24)
	self.panel = panel

	if not panel:FindFirstChildWhichIsA("TextLabel") then
		local title = Theme.label(panel, "TACTICAL MAP", Theme.textSize.tiny, Theme.color.accent)
		title.Position = UDim2.fromOffset(Theme.space.sm, 5)
		title.Size = UDim2.new(1, -Theme.space.sm * 2, 0, 14)
		title.FontFace = Theme.font.medium
	end

	local view: ImageLabel
	if leftoverView then
		view = leftoverView
	else
		view = Instance.new("ImageLabel")
		view.Name = "View"
		view.Position = UDim2.fromOffset(Theme.space.sm, Theme.space.sm + 18)
		view.Size = UDim2.fromOffset(WIDTH, HEIGHT)
		view.BackgroundColor3 = Theme.color.void
		view.BorderSizePixel = 0
		view.ResampleMode = Enum.ResamplerMode.Pixelated
		view.ScaleType = Enum.ScaleType.Stretch
		view.Parent = panel
		Theme.corner(view, Theme.radius.sm)
	end
	self.view = view

	if image.Parent ~= view then
		local attached = pcall(function()
			view.ImageContent = (Content :: any).fromObject(image)
		end)
		if not attached then
			pcall(function()
				image.Parent = view
			end)
		end
		-- Parent meme si Content.fromObject a reussi : le rematch
		-- FindFirstChildWhichIsA recupere l'EditableImage. Sans
		-- ca, leftover View sans enfant → second Create = fuite.
		if image.Parent ~= view then
			image.Parent = view
		end
	end

	-- Marqueur de camera : montre ou on regarde sur la carte.
	local existingFocus = view:FindFirstChild("Focus")
	local marker: Frame
	if existingFocus and existingFocus:IsA("Frame") then
		marker = existingFocus
	else
		marker = Instance.new("Frame")
		marker.Name = "Focus"
		marker.AnchorPoint = Vector2.new(0.5, 0.5)
		marker.Size = UDim2.fromOffset(10, 10)
		marker.BackgroundTransparency = 1
		marker.Parent = view
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.color.text
		stroke.Thickness = 1.5
		stroke.Transparency = 0.2
		stroke.Parent = marker
		Theme.corner(marker, Theme.radius.sm)
	end
	self.marker = marker

	-- Hit leftover : ne pas reconnecter (double-fire jump).
	if not view:FindFirstChildWhichIsA("TextButton") then
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.AutoButtonColor = false
		hit.Parent = view

		hit.MouseButton1Down:Connect(function(x: number, y: number)
			local origin = view.AbsolutePosition
			local size = view.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				return
			end
			local u = math.clamp((x - origin.X) / size.X, 0, 0.999)
			local v = math.clamp((y - origin.Y) / size.Y, 0, 0.999)
			onJump(MapGen.toIndex(math.floor(u * W), math.floor(v * H)))
		end)
	end

	-- Peinture initiale : tout le terrain, aucun proprietaire.
	for index = 0, W * H - 1 do
		self:paint(index, NEUTRAL)
	end
	self:flush()

	return self
end

function Minimap.paint(self: Minimap, index: number, slot: number)
	local terrain = buffer.readu8(self.terrain, index)
	local rgb

	if terrain == OCEAN then
		rgb = { 20, 34, 56 }
	elseif slot == NEUTRAL then
		rgb = terrainBytes[terrain]
	else
		rgb = factionBytes[((slot - 1) % Config.MAX_PLAYERS) + 1]
	end

	local offset = index * 4
	buffer.writeu8(self.pixels, offset, rgb[1])
	buffer.writeu8(self.pixels, offset + 1, rgb[2])
	buffer.writeu8(self.pixels, offset + 2, rgb[3])
	buffer.writeu8(self.pixels, offset + 3, 255)
end

function Minimap.applyDelta(self: Minimap, delta: buffer)
	local count = buffer.len(delta) // 5
	for i = 0, count - 1 do
		local offset = i * 5
		local index = buffer.readu32(delta, offset)
		if index < W * H then
			self:paint(index, buffer.readu8(delta, offset + 4))
		end
	end
	self.needsUpload = true
end

-- Un seul upload par frame, quel que soit le nombre de tuiles changees.
function Minimap.flush(self: Minimap)
	if not self.needsUpload then
		return
	end
	self.needsUpload = false
	pcall(function()
		self.image:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), self.pixels)
	end)
end

-- Repositionne le marqueur sur le point de mire courant de la camera.
-- N123 : (x, y, z) nombres. y ignore pour u/v (comme .Y avant).
-- Plus de Vector3 60 Hz au lecteur. Axes : X→u, Z→v.
-- Recette visual V69 leftover minimap, portee pas mergee.
function Minimap.setFocus(self: Minimap, x: number, _y: number, z: number)
	local u = math.clamp((x + Config.WORLD_WIDTH / 2) / Config.WORLD_WIDTH, 0, 1)
	local v = math.clamp((z + Config.WORLD_DEPTH / 2) / Config.WORLD_DEPTH, 0, 1)
	self.marker.Position = UDim2.fromScale(u, v)
end

function Minimap.destroy(self: Minimap)
	-- N187 : rematch park Frame existant. Pas Destroy. Enfants
	-- laisses (new() View/Focus reuse + leftover image enfant).
	-- Skip Parent nil (parkPanel). Pas take (new() deja).
	-- Pas setFocus. Pas Overlay. Pas PlacementPreview. Pas
	-- WorldRenderer. Pas init.client. Recette leftover N186.
	-- Pas merger visual V69. Distinct leftover N152 flame.
	-- Distinct leftover N188 RadialMenu.destroy.
	parkPanel(self.panel)
end

return Minimap
