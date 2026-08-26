--!strict
--[[
	Direction visuelle globale — eclairage cinematique, atmosphere chaude,
	lisibilite strategique depuis la camera haute.
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
	Lighting.ShadowSoftness = 0.35
	Lighting.Brightness = 2.85
	Lighting.ExposureCompensation = 0.12
	Lighting.EnvironmentDiffuseScale = 0.42
	Lighting.EnvironmentSpecularScale = 0.78
	Lighting.Ambient = Color3.fromRGB(68, 78, 98)
	Lighting.OutdoorAmbient = Color3.fromRGB(138, 152, 172)
	Lighting.ClockTime = 16.2
	Lighting.GeographicLatitude = 18
	Lighting.FogStart = 800
	Lighting.FogEnd = 120000
	Lighting.FogColor = Color3.fromRGB(186, 198, 214)

	local atmosphere = effect("Atmosphere", "ConquestAtmosphere") :: Atmosphere
	atmosphere.Color = Color3.fromRGB(220, 232, 244)
	atmosphere.Decay = Color3.fromRGB(92, 118, 152)
	atmosphere.Density = 0.26
	atmosphere.Glare = 0.18
	atmosphere.Haze = 1.05
	atmosphere.Offset = 0.08

	local color = effect("ColorCorrectionEffect", "ConquestGrade") :: ColorCorrectionEffect
	color.Brightness = 0.02
	color.Contrast = 0.14
	color.Saturation = 0.06
	color.TintColor = Color3.fromRGB(255, 246, 232)

	local bloom = effect("BloomEffect", "ConquestBloom") :: BloomEffect
	bloom.Intensity = 0.34
	bloom.Size = 36
	bloom.Threshold = 1.15

	local rays = effect("SunRaysEffect", "ConquestSunRays") :: SunRaysEffect
	rays.Intensity = 0.05
	rays.Spread = 0.82

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
		typed.Color = Color3.fromRGB(236, 242, 250)
		typed.Cover = 0.32
		typed.Density = 0.38
	end
end

return VisualDirector
