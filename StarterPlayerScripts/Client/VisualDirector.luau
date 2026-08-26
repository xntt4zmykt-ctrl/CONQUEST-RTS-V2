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

-- N189 : parkEffect / takeEffect hoistes pour mismatch Lighting
-- sans Destroy. Skip Parent nil (deja parke). Push effectFree[ClassName]
-- reelle du leftover (map className → { Instance }, pas veilFree
-- TextButton / panelFree Frame / placeRootFree / ghostFree /
-- worldFree). take du ClassName voulu avant Instance.new. Chemin
-- class match inchange (return existing). Recette leftover N188.
-- Pas merger visual. Distinct leftover N152 flame. Overlay non
-- touche. RadialMenu non touche. Minimap non touche. init.client
-- apply() unique — ne pas l'ajouter au rematch. ScreenGui stale
-- = leftover N190, pas ici. Ne pas vider effectFree.
local effectFree: { [string]: { Instance } } = {}
local cloudFree: { Clouds } = {}

local function parkEffect(inst: Instance)
	if not inst.Parent then
		return
	end
	inst.Parent = nil
	local className = inst.ClassName
	local bucket = effectFree[className]
	if not bucket then
		bucket = {}
		effectFree[className] = bucket
	end
	bucket[#bucket + 1] = inst
end

local function takeEffect(className: string): Instance?
	local bucket = effectFree[className]
	if not bucket then
		return nil
	end
	local n = #bucket
	if n == 0 then
		return nil
	end
	local last = bucket[n]
	bucket[n] = nil
	return last
end

local function parkCloud(clouds: Clouds)
	if not clouds.Parent then
		return
	end
	clouds.Parent = nil
	cloudFree[#cloudFree + 1] = clouds
end

local function takeCloud(): Clouds?
	local n = #cloudFree
	if n == 0 then
		return nil
	end
	local last = cloudFree[n]
	cloudFree[n] = nil
	return last
end

-- Leftover Terrain homonyme hors Clouds : park sous sa ClassName
-- reelle (effectFree), jamais cloudFree (take Clouds recevrait un
-- Part). Clouds reels → cloudFree.
local function parkCloudsLeftover(inst: Instance)
	if inst:IsA("Clouds") then
		parkCloud(inst :: Clouds)
		return
	end
	parkEffect(inst)
end

local function effect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		parkEffect(existing)
	end
	local created = takeEffect(className)
	if created == nil then
		created = Instance.new(className)
	end
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
				parkCloudsLeftover(clouds)
			end
			local taken = takeCloud()
			if taken then
				clouds = taken
			else
				clouds = Instance.new("Clouds")
			end
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
