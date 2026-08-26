--!strict
--[[
	Modeles proceduraux des unites mobiles.

	Une unite est un Model compose de pieces ancrees. L'Overlay applique la
	transformation de l'unite a chaque piece : cela permet le roulis, le tangage,
	les sillages et la trainee sans welds ni physique reseau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local UnitModels = {}

export type Piece = {
	part: BasePart,
	offset: CFrame,
	role: string,
}

export type Visual = {
	model: Model,
	pieces: { Piece },
	isMissile: boolean,
	kind: number,
}

local NAVY = Color3.fromRGB(78, 91, 106)
local NAVY_DARK = Color3.fromRGB(27, 38, 50)
local DECK = Color3.fromRGB(130, 142, 151)
local GLASS = Color3.fromRGB(91, 178, 211)
local FOAM = Color3.fromRGB(171, 231, 245)
local WHITE = Color3.fromRGB(232, 238, 242)
local GOLD = Color3.fromRGB(244, 184, 61)

local function addPart(
	visual: Visual,
	className: string,
	name: string,
	size: Vector3,
	color: Color3,
	offset: CFrame,
	material: Enum.Material?,
	role: string?
): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = role ~= "wake" and role ~= "trail"
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Metal
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = offset
	part.Parent = visual.model
	table.insert(visual.pieces, { part = part, offset = offset, role = role or "body" })
	return part
end

local function baseVisual(kind: number, isMissile: boolean): Visual
	local model = Instance.new("Model")
	model.Name = if isMissile then "CruiseMissile" else if kind == 2 then "MerchantShip" else "LandingShip"
	return {
		model = model,
		pieces = {},
		isMissile = isMissile,
		kind = kind,
	}
end

local function addWake(visual: Visual)
	-- N143 : houle addWake. Plus de CFrame.Angles.
	-- fromEulerAnglesYXZ(0, math.rad(side * 11), 0) ≡ Angles(0, ±11°, 0).
	-- Yaw Y=side*11° (side = ±1, ne pas figer). Offset
	-- (side * 2.15, -0.68, 5.5), taille Vector3.new(1.15, 0.08, 6.5),
	-- FOAM, Neon, Transparency = 0.62, Name = "Wake", role "wake"
	-- inchanges. Deux sides ensemble. Distinct LaunchWake Overlay
	-- N130 (Z=90, Y + 0.12). Distinct rampes SAM N142 (pitch -31°).
	-- Distinct proue leftover N144 (Y=π). Distinct radar/flag place
	-- N127/N128. Overlay / BuildingModels / WorldRenderer /
	-- createMissile / Bow inchanges.
	for side = -1, 1, 2 do
		local wake = addPart(
			visual,
			"WedgePart",
			"Wake",
			Vector3.new(1.15, 0.08, 6.5),
			FOAM,
			CFrame.new(side * 2.15, -0.68, 5.5) * CFrame.fromEulerAnglesYXZ(0, math.rad(side * 11), 0),
			Enum.Material.Neon,
			"wake"
		)
		wake.Transparency = 0.62
	end
end

--[[
	Modele importe du porte-avions.

	Roblox ne charge pas un fichier .glb a l'execution : il faut l'importer une
	fois via le 3D Importer de Studio, qui l'uploade et rend un identifiant.
	Coller cet identifiant ici suffit — la coque procedurale de secours reste en
	place tant que le champ est vide, donc le jeu n'attend jamais l'asset.

	Le fichier source est versionne dans assets/models/aircraft-carrier.glb.
]]
UnitModels.CARRIER_MESH_ID = ""
UnitModels.CARRIER_MESH_SCALE = Vector3.new(26, 26, 26)

--[[
	Porte-avions de patrouille : long pont plat, ilot decale sur tribord et
	aeronefs au mouillage. La silhouette doit se distinguer d'un transport meme
	completement dezoome — c'est elle qui dit au joueur qu'une cote est
	defendue.
]]
local function buildCarrier(visual: Visual, faction: Color3)
	if UnitModels.CARRIER_MESH_ID ~= "" then
		local mesh = Instance.new("MeshPart")
		mesh.Name = "CarrierMesh"
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanTouch = false
		mesh.CanQuery = false
		mesh.CastShadow = false
		mesh.Size = UnitModels.CARRIER_MESH_SCALE
		mesh.CFrame = CFrame.new()
		mesh.Parent = visual.model
		table.insert(visual.parts, { part = mesh, offset = CFrame.new(), role = "hull" })
		return
	end

	-- Coque longue et pont d'envol : deux volumes portent l'essentiel de la
	-- lecture, le reste n'est que detail.
	addPart(visual, "Part", "Hull", Vector3.new(5.6, 1.6, 18), NAVY_DARK, CFrame.new(0, -0.2, 0), Enum.Material.Metal)
	-- N144 : proue Bow. Plus de CFrame.Angles.
	-- fromEulerAnglesYXZ(0, math.pi, 0) ≡ Angles(0, π, 0).
	-- Yaw Y=π fixe. Offset (0, -0.2, -10.8) carrier /
	-- (0, 0.05, -5.9) transport, tailles Vector3.new(5.6, 1.6, 3.6) /
	-- Vector3.new(4.8, 1.65, 3.3), NAVY, Name = "Bow" inchanges.
	-- Deux sites ensemble (ici + createBoat). Distinct houle N143
	-- (±11°). Distinct rampe leftover (pitch -8°). Distinct missile
	-- leftover (Y=90). addWake N143 / Overlay / BuildingModels /
	-- place / createMissile inchanges.
	addPart(visual, "WedgePart", "Bow", Vector3.new(5.6, 1.6, 3.6), NAVY, CFrame.new(0, -0.2, -10.8) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0), Enum.Material.Metal)
	addPart(visual, "Part", "FlightDeck", Vector3.new(8.4, 0.35, 19.5), DECK, CFrame.new(0, 0.78, 0), Enum.Material.DiamondPlate)
	addPart(visual, "Part", "DeckLine", Vector3.new(0.35, 0.06, 15), WHITE, CFrame.new(-1.1, 0.98, 0), Enum.Material.SmoothPlastic)

	-- Ilot decale a tribord, comme sur un vrai porte-avions.
	addPart(visual, "Part", "Island", Vector3.new(1.9, 2.6, 4.2), NAVY, CFrame.new(3.05, 2.25, 2.2), Enum.Material.Metal)
	local glass = addPart(visual, "Part", "IslandGlass", Vector3.new(1.96, 0.5, 0.12), GLASS, CFrame.new(3.05, 2.7, 0.12), Enum.Material.Glass)
	glass.Transparency = 0.1
	addPart(visual, "Part", "FactionStripe", Vector3.new(8.5, 0.12, 2.4), faction, CFrame.new(0, 0.99, 7.4), Enum.Material.SmoothPlastic)

	-- Aeronefs au mouillage : de simples croix suffisent a la lecture.
	for i = -1, 1 do
		addPart(visual, "Part", "Jet", Vector3.new(0.5, 0.28, 2.1), WHITE, CFrame.new(2.2, 1.1, i * 3.4 - 3), Enum.Material.Metal)
		addPart(visual, "Part", "JetWing", Vector3.new(2.1, 0.2, 0.5), WHITE, CFrame.new(2.2, 1.1, i * 3.4 - 3.2), Enum.Material.Metal)
	end

	addPart(visual, "Part", "Mast", Vector3.new(0.2, 3, 0.2), NAVY_DARK, CFrame.new(3.05, 5, 2.2), Enum.Material.Metal)
	addPart(visual, "Part", "Radar", Vector3.new(2.6, 0.16, 0.5), WHITE, CFrame.new(3.05, 6.2, 2.2), Enum.Material.Metal, "radar")
	addPart(visual, "Part", "Flag", Vector3.new(0.12, 0.8, 1.35), faction, CFrame.new(3.05, 6.6, 2.85), Enum.Material.Fabric, "flag")
end

function UnitModels.createBoat(parent: Instance, slot: number, kind: number): Visual
	local visual = baseVisual(kind, false)
	visual.model.Parent = parent
	local faction = Theme.factionColor(slot)

	if kind == 3 then
		buildCarrier(visual, faction)
		addWake(visual)
		return visual
	end

	-- Coque basse, proue inclinee et pont superieur : trois volumes suffisent a
	-- casser instantanement la silhouette de cube du placeholder historique.
	addPart(visual, "Part", "Keel", Vector3.new(4.8, 1.15, 9.2), NAVY_DARK, CFrame.new(0, -0.15, 0), Enum.Material.Metal)
	-- N144 : proue Bow transport/cargo. Plus de CFrame.Angles.
	-- fromEulerAnglesYXZ(0, math.pi, 0) ≡ Angles(0, π, 0). Couple
	-- avec buildCarrier (yaw π fixe, ne pas splitter). Offset
	-- (0, 0.05, -5.9) inchange. Distinct rampe leftover (pitch -8°).
	addPart(visual, "WedgePart", "Bow", Vector3.new(4.8, 1.65, 3.3), NAVY, CFrame.new(0, 0.05, -5.9) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0), Enum.Material.Metal)
	addPart(visual, "Part", "Deck", Vector3.new(4.25, 0.22, 8.3), DECK, CFrame.new(0, 0.58, 0.3), Enum.Material.DiamondPlate)
	addPart(visual, "Part", "FactionStripe", Vector3.new(4.92, 0.3, 3.2), faction, CFrame.new(0, 0.22, -1.7), Enum.Material.SmoothPlastic)

	if kind == 2 then
		-- Cargo : passerelle a l'arriere et conteneurs colores en piles asymetriques.
		addPart(visual, "Part", "Bridge", Vector3.new(3.7, 2.25, 2.2), WHITE, CFrame.new(0, 1.82, 3.15), Enum.Material.Metal)
		local glass = addPart(visual, "Part", "BridgeGlass", Vector3.new(3.76, 0.52, 0.12), GLASS, CFrame.new(0, 2.08, 1.99), Enum.Material.Glass)
		glass.Transparency = 0.12
		local containerColors = { GOLD, faction, Color3.fromRGB(186, 75, 61), Color3.fromRGB(70, 130, 166) }
		for row = -1, 1 do
			for side = -1, 1, 2 do
				local height = if row == 0 and side == 1 then 2.05 else 1.28
				addPart(
					visual,
					"Part",
					"Container",
					Vector3.new(1.65, height, 1.7),
					containerColors[((row + 1) * 2 + (if side == 1 then 2 else 1) - 1) % #containerColors + 1],
					CFrame.new(side * 0.95, 0.72 + height / 2, row * 1.85 - 1.35),
					Enum.Material.Metal
				)
			end
		end
	else
		-- Transport amphibie : passerelle blindee, rampe avant et deux barges
		-- laterales. La silhouette evoque un vrai LPD miniature.
		addPart(visual, "Part", "Superstructure", Vector3.new(3.45, 2.5, 3.05), NAVY, CFrame.new(0, 1.85, 2.65), Enum.Material.Metal)
		local bridge = addPart(visual, "Part", "BridgeGlass", Vector3.new(3.52, 0.58, 0.13), GLASS, CFrame.new(0, 2.2, 1.08), Enum.Material.Glass)
		bridge.Transparency = 0.1
		local ramp = addPart(visual, "WedgePart", "LandingRamp", Vector3.new(3.25, 0.28, 2.9), NAVY_DARK, CFrame.new(0, 0.72, -4.45) * CFrame.Angles(math.rad(-8), 0, 0), Enum.Material.DiamondPlate)
		ramp.Color = faction
		for side = -1, 1, 2 do
			addPart(visual, "Part", "Lifeboat", Vector3.new(0.62, 0.62, 2.5), GOLD, CFrame.new(side * 2.18, 1.18, 1.15), Enum.Material.Metal)
			addPart(visual, "Part", "DeckRail", Vector3.new(0.12, 0.72, 6.8), WHITE, CFrame.new(side * 2.1, 1.05, -1.05), Enum.Material.Metal)
		end
	end

	-- Mat, antenne, fanion et feux de navigation communs.
	addPart(visual, "Part", "Mast", Vector3.new(0.22, 3.5, 0.22), NAVY_DARK, CFrame.new(0, 4.0, 2.65), Enum.Material.Metal)
	addPart(visual, "Part", "Radar", Vector3.new(2.45, 0.16, 0.5), WHITE, CFrame.new(0, 5.2, 2.65), Enum.Material.Metal, "radar")
	addPart(visual, "Part", "Flag", Vector3.new(0.12, 0.75, 1.25), faction, CFrame.new(0, 5.55, 3.23), Enum.Material.Fabric, "flag")
	local portLight = addPart(visual, "Part", "PortLight", Vector3.new(0.26, 0.26, 0.26), Color3.fromRGB(255, 72, 67), CFrame.new(-2.16, 1.05, -3.3), Enum.Material.Neon, "light")
	portLight.Shape = Enum.PartType.Ball
	local starboardLight = addPart(visual, "Part", "StarboardLight", Vector3.new(0.26, 0.26, 0.26), Color3.fromRGB(65, 255, 144), CFrame.new(2.16, 1.05, -3.3), Enum.Material.Neon, "light")
	starboardLight.Shape = Enum.PartType.Ball
	addWake(visual)
	return visual
end

function UnitModels.createMissile(parent: Instance, slot: number, kind: number): Visual
	local visual = baseVisual(kind, true)
	visual.model.Parent = parent
	local faction = Theme.factionColor(slot)

	local body = addPart(visual, "Part", "MissileBody", Vector3.new(6.2, 1.05, 1.05), WHITE, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Metal)
	body.Shape = Enum.PartType.Cylinder
	local nose = addPart(visual, "Part", "Warhead", Vector3.new(1.35, 1.35, 1.65), faction, CFrame.new(0, 0, -3.45), Enum.Material.Metal)
	nose.Shape = Enum.PartType.Ball
	addPart(visual, "Part", "GuidanceBand", Vector3.new(1.18, 1.3, 0.42), faction, CFrame.new(0, 0, -1.9), Enum.Material.Neon)
	for axis = 0, 3 do
		addPart(
			visual,
			"WedgePart",
			"Fin",
			Vector3.new(0.22, 1.65, 1.4),
			NAVY_DARK,
			CFrame.new(0, 0, 2.45) * CFrame.Angles(0, 0, axis * math.pi / 2),
			Enum.Material.Metal
		)
	end
	local flame = addPart(visual, "Part", "EngineFlame", Vector3.new(0.62, 0.62, 2.3), Color3.fromRGB(255, 166, 48), CFrame.new(0, 0, 4.15), Enum.Material.Neon, "flame")
	flame.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 172, 72)
	light.Brightness = 3
	light.Range = 18
	light.Parent = flame
	for i = 1, 3 do
		local trail = addPart(visual, "Part", "Exhaust", Vector3.new(0.7 + i * 0.35, 0.7 + i * 0.35, 1.8), Color3.fromRGB(255, 216, 145), CFrame.new(0, 0, 4.6 + i * 1.4), Enum.Material.Neon, "trail")
		trail.Shape = Enum.PartType.Ball
		trail.Transparency = 0.35 + i * 0.16
	end
	return visual
end

function UnitModels.place(visual: Visual, frame: CFrame, time: number, speed: number)
	for _, piece in visual.pieces do
		local localFrame = piece.offset
		if piece.role == "radar" then
			-- N127 : offset * yaw. Plus de CFrame.Angles 60 Hz.
			-- fromEulerAnglesYXZ(0, time * 2.2, 0) ≡ Angles(0, yaw, 0)
			-- (rx=0, rz=0 → Y seul). Facteur 2.2 inchange. Garde
			-- role == "radar" inchangee. piece.offset * euler — pas
			-- CFrame.new(offset.X,Y,Z) * euler (recette N124 batiments,
			-- RestCFrame identite). Distinct SAM Radar N124 (time * 1.45).
			-- Distinct roulis Overlay N125. Distinct flag N128. Distinct
			-- roues N126. Recette visual V73 leftover deja sur 9793,
			-- portee pas mergee. Overlay / BuildingModels inchanges.
			localFrame = piece.offset * CFrame.fromEulerAnglesYXZ(0, time * 2.2, 0)
		elseif piece.role == "flag" then
			-- N128 : offset * pitch. Plus de CFrame.Angles 60 Hz.
			-- fromEulerAnglesYXZ(rx, 0, 0) ≡ Angles(rx, 0, 0) (ry=0,
			-- rz=0 → X seul). Amplitude 0.06, frequence 5 inchangees.
			-- Garde role == "flag" inchangee. piece.offset * euler —
			-- pas CFrame.new(offset.X,Y,Z) * euler (recette N124).
			-- Distinct radar N127 (Y, time * 2.2). Distinct CapitalFlag
			-- N124 (deux sin, rest identite). Distinct roulis Overlay
			-- N125. Distinct flamme Size (leftover). Recette visual V73
			-- leftover deja sur 9793, portee pas mergee. Radar N127
			-- inchange. Overlay / BuildingModels inchanges.
			local rx = math.sin(time * 5) * 0.06
			localFrame = piece.offset * CFrame.fromEulerAnglesYXZ(rx, 0, 0)
		elseif piece.role == "wake" then
			piece.part.Transparency = math.clamp(0.76 - speed * 0.08 + math.sin(time * 5) * 0.06, 0.48, 0.82)
		elseif piece.role == "flame" then
			piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
		elseif piece.role == "trail" then
			piece.part.Transparency = math.clamp(piece.part.Transparency + math.sin(time * 9 + piece.offset.Position.Z) * 0.035, 0.25, 0.9)
		elseif piece.role == "light" then
			piece.part.Transparency = if math.sin(time * 3) > -0.2 then 0 else 0.45
		end
		piece.part.CFrame = frame * localFrame
	end
end

return UnitModels
