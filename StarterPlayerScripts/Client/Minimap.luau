--!strict
--[[
	Minimap.

	Astuce centrale : elle ne redessine rien. Une EditableImage peut alimenter
	plusieurs ImageLabel a la fois, donc la minimap affiche exactement le meme
	contenu que la grande carte, mis a jour par le meme unique upload GPU. Son
	cout de rendu est donc nul — seul le rectangle de visee est calcule.

	Sans minimap, une carte de 256x160 zoomee a 8x oblige a naviguer a l'aveugle
	pour retrouver son propre territoire.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local MapGen = require(Shared:WaitForChild("MapGen"))

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT

local Minimap = {}
Minimap.__index = Minimap

export type Minimap = typeof(setmetatable({} :: any, Minimap))

local WIDTH = 232
local HEIGHT = math.floor(WIDTH * H / W)

--[[
	`onJump` est appele avec un index de tuile quand le joueur clique la
	minimap : c'est init.client qui decide comment y deplacer la camera.
]]
function Minimap.new(parent: GuiObject, mapLabel: ImageLabel, onJump: (number) -> ()): Minimap
	local self = setmetatable({}, Minimap) :: any

	local panel = Theme.panel("Minimap", parent)
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -Theme.space.md, 1, -Theme.space.md)
	panel.Size = UDim2.fromOffset(WIDTH + Theme.space.sm * 2, HEIGHT + Theme.space.sm * 2)
	self.panel = panel

	local view = Instance.new("ImageLabel")
	view.Name = "View"
	view.Position = UDim2.fromOffset(Theme.space.sm, Theme.space.sm)
	view.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	view.BackgroundColor3 = Theme.color.void
	view.BorderSizePixel = 0
	view.ResampleMode = Enum.ResamplerMode.Pixelated
	view.ScaleType = Enum.ScaleType.Stretch
	-- Meme contenu que la grande carte : aucune peinture supplementaire.
	view.ImageContent = mapLabel.ImageContent
	view.Parent = panel
	Theme.corner(view, Theme.radius.sm)
	self.view = view

	-- Rectangle de visee : montre quelle portion de la carte est a l'ecran.
	local frame = Instance.new("Frame")
	frame.Name = "Viewport"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = view
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.color.text
	stroke.Thickness = 1.5
	stroke.Transparency = 0.25
	stroke.Parent = frame
	self.frame = frame

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

	return self
end

--[[
	Recalcule le rectangle de visee a partir de la geometrie reelle de la
	grande carte : on projette la fenetre visible dans l'espace normalise de la
	carte. Passer par les positions absolues evite de dupliquer ici la logique
	de camera de init.client.
]]
function Minimap.sync(self: Minimap, mapLabel: ImageLabel, viewport: GuiObject)
	local mapPos = mapLabel.AbsolutePosition
	local mapSize = mapLabel.AbsoluteSize
	if mapSize.X <= 0 or mapSize.Y <= 0 then
		return
	end

	local screenPos = viewport.AbsolutePosition
	local screenSize = viewport.AbsoluteSize

	local u0 = math.clamp((screenPos.X - mapPos.X) / mapSize.X, 0, 1)
	local v0 = math.clamp((screenPos.Y - mapPos.Y) / mapSize.Y, 0, 1)
	local u1 = math.clamp((screenPos.X + screenSize.X - mapPos.X) / mapSize.X, 0, 1)
	local v1 = math.clamp((screenPos.Y + screenSize.Y - mapPos.Y) / mapSize.Y, 0, 1)

	self.frame.Position = UDim2.fromScale(u0, v0)
	self.frame.Size = UDim2.fromScale(math.max(u1 - u0, 0.01), math.max(v1 - v0, 0.01))
end

function Minimap.setContent(self: Minimap, mapLabel: ImageLabel)
	self.view.ImageContent = mapLabel.ImageContent
end

function Minimap.destroy(self: Minimap)
	self.panel:Destroy()
end

return Minimap
