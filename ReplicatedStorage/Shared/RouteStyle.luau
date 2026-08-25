--!strict
--[[
	Style des routes logistiques (2 Parts/tronçon).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))

local RouteStyle = {}

function RouteStyle.makeLayers(
	routePart: (Instance, string, Vector3, Color3, Enum.Material) -> Part,
	model: Instance,
	frame: CFrame,
	length: number,
	slot: number
): { any }
	local k = Config.WORLD_SCALE
	local faction = Theme.factionColor(slot)
	local ballastColor = Color3.fromRGB(48, 52, 58)
	local deckColor = Color3.new(
		math.clamp(0.22 + faction.R * 0.28, 0, 1),
		math.clamp(0.24 + faction.G * 0.28, 0, 1),
		math.clamp(0.26 + faction.B * 0.28, 0, 1)
	)
	local ballast = routePart(model, "Ballast", Vector3.new(3.2 * k, 0.12 * k, length), ballastColor, Enum.Material.Concrete)
	ballast.CFrame = frame
	local deck = routePart(model, "Deck", Vector3.new(2.2 * k, 0.15 * k, length), deckColor, Enum.Material.Metal)
	deck.CFrame = frame + Vector3.new(0, 0.09 * k, 0)
	return {
		{ part = ballast, width = 3.2 * k, thickness = 0.12 * k, lift = 0, ratio = 1 },
		{ part = deck, width = 2.2 * k, thickness = 0.15 * k, lift = 0.09 * k, ratio = 1 },
	}
end

return RouteStyle
