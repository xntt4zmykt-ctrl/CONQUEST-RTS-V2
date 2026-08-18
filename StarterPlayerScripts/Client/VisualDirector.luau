--!strict
--[[
	Direction visuelle globale du client.

	Les effets sont crees par nom et reutilises : une reconnexion ou un nouveau
	MapInit ne doit jamais empiler plusieurs Bloom/Atmosphere. Les reglages sont
	volontairement contenus pour conserver la lisibilite d'un RTS vu du ciel.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local VisualDirector = {}

local function effect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

function VisualDirector.apply()
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.28
	Lighting.Brightness = 2.65
	Lighting.ExposureCompensation = 0.08
	Lighting.EnvironmentDiffuseScale = 0.38
	Lighting.EnvironmentSpecularScale = 0.72
	Lighting.Ambient = Color3.fromRGB(75, 85, 105)
	Lighting.OutdoorAmbient = Color3.fromRGB(126, 139, 158)
	Lighting.ClockTime = 15.35
	Lighting.GeographicLatitude = 22
	Lighting.FogEnd = 100000

	local atmosphere = effect("Atmosphere", "ConquestAtmosphere") :: Atmosphere
	atmosphere.Color = Color3.fromRGB(207, 220, 232)
	atmosphere.Decay = Color3.fromRGB(85, 112, 145)
	atmosphere.Density = 0.22
	atmosphere.Glare = 0.12
	atmosphere.Haze = 0.9
	atmosphere.Offset = 0.05

	local color = effect("ColorCorrectionEffect", "ConquestGrade") :: ColorCorrectionEffect
	color.Brightness = 0.015
	color.Contrast = 0.11
	color.Saturation = -0.04
	color.TintColor = Color3.fromRGB(255, 248, 237)

	local bloom = effect("BloomEffect", "ConquestBloom") :: BloomEffect
	bloom.Intensity = 0.26
	bloom.Size = 32
	bloom.Threshold = 1.25

	local rays = effect("SunRaysEffect", "ConquestSunRays") :: SunRaysEffect
	rays.Intensity = 0.035
	rays.Spread = 0.78

	local depth = effect("DepthOfFieldEffect", "ConquestDepth") :: DepthOfFieldEffect
	depth.FarIntensity = 0.06
	depth.FocusDistance = 220
	depth.InFocusRadius = 180
	depth.NearIntensity = 0.02

	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local clouds = terrain:FindFirstChild("ConquestClouds")
		if not clouds or not clouds:IsA("Clouds") then
			if clouds then
				clouds:Destroy()
			end
			clouds = Instance.new("Clouds")
			clouds.Name = "ConquestClouds"
			clouds.Parent = terrain
		end
		local typed = clouds :: Clouds
		typed.Color = Color3.fromRGB(226, 231, 238)
		typed.Cover = 0.28
		typed.Density = 0.34
	end
end

return VisualDirector
