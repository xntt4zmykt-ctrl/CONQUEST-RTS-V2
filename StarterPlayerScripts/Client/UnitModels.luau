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
	-- V92 : translation * fromEulerAnglesYXZ (yaw Y=±11° fixe). Plus
	-- de CFrame.Angles a addWake. Recette feel N143 inline — ne PAS
	-- cuire un wakeRot (signes Y opposes + translations side distinctes,
	-- comme V91 rampRot / V90 doorRot / V89 roofRot / V88 cylinderRot /
	-- V86 trunkRot interdits). Distinct de V91 (rampes SAM, pitch
	-- X=-31°, BuildingModels — ne PAS retoucher les Interceptor).
	-- Distinct de V93 (Bow yaw Y=π, carrier + transport — ne PAS
	-- retoucher les Bow). Distinct de V94 (LandingRamp pitch X=-8°,
	-- kind==1 — ne PAS retoucher la rampe). Distinct de V95
	-- (MissileBody yaw Y=90°, cylindre — ne PAS retoucher le
	-- corps). Distinct de V100 (trail offset.Z,
	-- UnitModels.place). Distinct de V106 (wake Transparency
	-- offset.X, UnitModels.place — 60 Hz, pas ce helper). Distinct
	-- de V78 (LaunchWake Overlay, wakeRot cuit, Y = OCEAN+0.12 —
	-- autre objet). Construction de modele, pas 60 Hz.
	-- addPart pose part.CFrame = offset ; Overlay place compose
	-- frame * offset ensuite. Size 1.15, 0.08, 6.5 / FOAM / Neon /
	-- Transparency 0.62 / role wake / Name Wake inchanges. Call sites
	-- createBoat kind==3 (carrier) et kind==1/2 (ligne apres pont)
	-- non edites hors ce helper. Ne pas merger feel c62f.
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
		-- V97 : insert dans visual.pieces (pas visual.parts). Visual
		-- n'exporte que pieces. Overlay place itere pieces — le mesh
		-- serait invisible meme sans crash. Recette feel N148 —
		-- ne PAS merger 7dff. CARRIER_MESH_ID reste "".
		-- CARRIER_MESH_SCALE / MeshPart Name CarrierMesh / Size /
		-- CFrame identite / role hull inchanges. Distinct de V96
		-- (Fin roll Z=axis·π/2 — ne PAS retoucher les ailettes).
		-- Distinct de V95 (MissileBody yaw Y=90°). Distinct de V93
		-- (Bow yaw Y=π, meme buildCarrier — ne PAS retoucher les
		-- Bow). Distinct de V92 (Wake, addWake apres buildCarrier).
		-- Distinct de V100 (trail offset.Z,
		-- UnitModels.place). Chemin mort tant
		-- que CARRIER_MESH_ID == "". Ne pas activer l'ID au banc
		-- (stub MeshPart n'importe pas le mesh).
		table.insert(visual.pieces, { part = mesh, offset = CFrame.new(), role = "hull" })
		return
	end

	-- Coque longue et pont d'envol : deux volumes portent l'essentiel de la
	-- lecture, le reste n'est que detail.
	addPart(visual, "Part", "Hull", Vector3.new(5.6, 1.6, 18), NAVY_DARK, CFrame.new(0, -0.2, 0), Enum.Material.Metal)
	-- V93 : translation * fromEulerAnglesYXZ (yaw Y=π fixe). Plus
	-- de CFrame.Angles a Bow. Recette feel N144 inline — ne PAS
	-- cuire un bowRot (translations Y/Z distinctes carrier vs
	-- transport/cargo, comme V92 wakeRot / V91 rampRot / V90 doorRot /
	-- V89 roofRot / V88 cylinderRot / V86 trunkRot interdits).
	-- Distinct de V92 (sillages, yaw Y=±11°, addWake — ne PAS
	-- retoucher les Wake). Distinct de V94 (LandingRamp pitch
	-- X=-8°, kind==1 — ne PAS retoucher la rampe). Distinct de
	-- V95 (MissileBody yaw Y=90°, cylindre — ne PAS retoucher
	-- le corps). Distinct de V100 (trail offset.Z,
	-- UnitModels.place).
	-- Distinct de V78 (LaunchWake Overlay — autre objet).
	-- Construction de modele, pas 60 Hz.
	-- addPart pose part.CFrame = offset ; Overlay place compose
	-- frame * offset ensuite. Size 5.6, 1.6, 3.6 / NAVY / Metal /
	-- Name Bow / WedgePart inchanges. Call site buildCarrier
	-- (kind==3). Ne pas merger feel c62f.
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
	-- V93 : meme recette, translation Y=0.05 / Z=-5.9. Size 4.8,
	-- 1.65, 3.3 / NAVY / Metal / Name Bow / WedgePart inchanges.
	-- Call site createBoat kind==1/2 (avant pont). Ne pas merger
	-- feel c62f. Ne PAS retoucher LandingRamp (V94 deja). Ne PAS
	-- retoucher MissileBody (V95 deja). Ne PAS retoucher Fin
	-- (V96 deja). Ne PAS retoucher le mesh carrier (V97 deja).
	-- V98 CityWindows rest.X (BuildingModels.animate). V99 beacons rest.Z (BuildingModels.animate). V100 trail offset.Z (UnitModels.place). V101 dirtyHead (WorldRenderer.stepRebuilds).
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
		-- V94 : translation * fromEulerAnglesYXZ (pitch X=-8° fixe).
		-- Plus de CFrame.Angles a LandingRamp. Recette feel N145
		-- inline — ne PAS cuire un rampRot (un seul site, kind==1
		-- amphibie, comme V93 bowRot / V92 wakeRot / V91 rampRot
		-- SAM interdits). Distinct de V93 (Bow yaw Y=π, carrier +
		-- transport/cargo — ne PAS retoucher les Bow). Distinct de
		-- V92 (Wake yaw Y=±11°, addWake — ne PAS retoucher les
	-- Wake). Distinct de V95 (MissileBody yaw Y=90°, cylindre
	-- — ne PAS retoucher le corps). Distinct de V100
	-- (trail offset.Z, UnitModels.place). Distinct de V91
		-- (rampes SAM, pitch X=-31°, BuildingModels — autre
		-- fichier). Distinct de V78 (LaunchWake Overlay — autre
		-- objet). Construction de modele, pas 60 Hz. addPart pose
		-- part.CFrame = offset ; Overlay place compose frame *
		-- offset ensuite. Size 3.25, 0.28, 2.9 / NAVY_DARK puis
		-- Color = faction / DiamondPlate / Name LandingRamp /
		-- WedgePart inchanges. Call site createBoat kind==1
		-- seulement (cargo kind==2 et carrier kind==3 n'ont pas
		-- de rampe). Ne pas merger feel 95ed.
		local ramp = addPart(visual, "WedgePart", "LandingRamp", Vector3.new(3.25, 0.28, 2.9), NAVY_DARK, CFrame.new(0, 0.72, -4.45) * CFrame.fromEulerAnglesYXZ(math.rad(-8), 0, 0), Enum.Material.DiamondPlate)
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

	-- V95 : translation * fromEulerAnglesYXZ (yaw Y=90° fixe).
	-- Plus de CFrame.Angles a MissileBody. Recette feel N146
	-- inline — ne PAS cuire un bodyRot (un seul site, cylindre
	-- Roblox pointe X, on aligne l'axe du missile, comme V94
	-- rampRot / V93 bowRot / V92 wakeRot / V91 rampRot SAM /
	-- V88 cylinderRot interdits). Distinct de V94 (LandingRamp
	-- pitch X=-8°, kind==1 amphibie — ne PAS retoucher la
	-- rampe). Distinct de V93 (Bow yaw Y=π). Distinct de V92
	-- (Wake yaw Y=±11°, addWake). Distinct de V96 (Fin roll
	-- Z=axis·π/2 — ne PAS retoucher les ailettes). Distinct de
	-- V100 (trail offset.Z, UnitModels.place). Distinct
	-- de V88 (cylinder() helper, Z=90°, BuildingModels — autre
	-- fichier). Distinct de V78 (LaunchWake Overlay — autre
	-- objet). Construction de modele, pas 60 Hz. addPart pose
	-- part.CFrame = offset ; Overlay place compose frame *
	-- offset ensuite. Size 6.2, 1.05, 1.05 / WHITE / Metal /
	-- Name MissileBody / Part + Shape Cylinder pose apres
	-- inchanges. Call site createMissile seulement (un site).
	-- Ne pas merger feel 95ed.
	local body = addPart(visual, "Part", "MissileBody", Vector3.new(6.2, 1.05, 1.05), WHITE, CFrame.new(0, 0, 0) * CFrame.fromEulerAnglesYXZ(0, math.rad(90), 0), Enum.Material.Metal)
	body.Shape = Enum.PartType.Cylinder
	local nose = addPart(visual, "Part", "Warhead", Vector3.new(1.35, 1.35, 1.65), faction, CFrame.new(0, 0, -3.45), Enum.Material.Metal)
	nose.Shape = Enum.PartType.Ball
	addPart(visual, "Part", "GuidanceBand", Vector3.new(1.18, 1.3, 0.42), faction, CFrame.new(0, 0, -1.9), Enum.Material.Neon)
	-- V96 : translation * fromEulerAnglesYXZ (roll Z=axis·π/2).
	-- Plus de CFrame.Angles a Fin. Recette feel N147 inline —
	-- ne PAS cuire un finRot (quatre sites, axis ∈ {0,1,2,3},
	-- memes translations, comme V95 bodyRot / V94 rampRot /
	-- V93 bowRot / V92 wakeRot interdits). Distinct de V95
	-- (MissileBody yaw Y=90°, cylindre — ne PAS retoucher le
	-- corps). Distinct de V94 (LandingRamp pitch X=-8°,
	-- kind==1). Distinct de V93 (Bow yaw Y=π). Distinct de V92
	-- (Wake yaw Y=±11°, addWake). Distinct de V100
	-- (trail offset.Z, UnitModels.place — fermee ici). Distinct de V78
	-- (LaunchWake Overlay — autre objet). Construction de
	-- modele, pas 60 Hz. addPart pose part.CFrame = offset ;
	-- Overlay place compose frame * offset ensuite. Size 0.22,
	-- 1.65, 1.4 / NAVY_DARK / Metal / Name Fin / WedgePart
	-- inchanges. Call site createMissile seulement (boucle
	-- for axis = 0, 3). Ne pas merger feel 7dff.
	for axis = 0, 3 do
		addPart(
			visual,
			"WedgePart",
			"Fin",
			Vector3.new(0.22, 1.65, 1.4),
			NAVY_DARK,
			CFrame.new(0, 0, 2.45) * CFrame.fromEulerAnglesYXZ(0, 0, axis * math.pi / 2),
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
			-- V73 : offset * yaw. Plus de CFrame.Angles 60 Hz.
			-- fromEulerAnglesYXZ(0, time*2.2, 0) ≡ Angles(0, yaw, 0)
			-- (rx=0, rz=0 → Y seul). Frequence 2.2 inchangee.
			-- Flag : fromEulerAnglesYXZ(sin(time*5+offset.X*0.1)*0.06, 0, 0)
			-- ≡ Angles(pitch, 0, 0) (ry=0, rz=0 → X seul). Amplitude
			-- 0.06 / frequence 5 inchangees. Overlay roulis inchange
			-- (V71). Roues camion inchangees (V72). BuildingModels
			-- Radar/Flag/Boom inchanges (V70). Flame Size API
			-- (V74) + phase frame.X (V111, elseif flame). Trail
			-- offset.Z inchange (V100). Feux offset.X (V105). Wake
			-- offset.X (V106, elseif plus bas). Flag offset.X
			-- (V107, elseif suivant). CapitalFlag fermee (V108,
			-- BuildingModels). PortCraneBoom fermee (V109).
			-- PortCraneCable fermee (V110).
			localFrame = localFrame * CFrame.fromEulerAnglesYXZ(0, time * 2.2, 0)
		elseif piece.role == "flag" then
			-- V107 : phase depuis offset.X. Plus de lockstep
			-- sin(time * 5) sans phase. offset est deja un CFrame
			-- pose a createBoat / buildCarrier. Carrier Flag
			-- X == 3.05 / transport/cargo X == 0. Amplitude 0.06,
			-- frequence 5, * 0.1 inchanges (famille V98/V105/V106).
			-- Pas de Position. Recette analogique V106 — ne PAS
			-- merger c450 / ee71. Distinct de V106 (wake
			-- Transparency, elseif suivant). Distinct de V73
			-- (fromEulerAnglesYXZ deja, pas CFrame.Angles). Distinct
			-- de V108 (CapitalFlag, BuildingModels, fermee). Distinct
			-- de V109 (PortCraneBoom, fermee). Distinct
			-- de V110 (PortCraneCable, fermee). Distinct
			-- de V111 (flame Size, elseif plus bas). Un
			-- elseif, role == "flag" inchange. Name Flag inchange.
			-- Construction Flag inchangee. Pas de flagPhase.
			localFrame = localFrame * CFrame.fromEulerAnglesYXZ(math.sin(time * 5 + piece.offset.X * 0.1) * 0.06, 0, 0)
		elseif piece.role == "wake" then
			-- V106 : phase depuis offset.X. Plus de lockstep
			-- sin(time * 5) sans phase. offset est deja un CFrame
			-- pose a addWake. Wake X=±2.15 (side ∈ {-1,1}), meme Z
			-- 5.5 — ne PAS user offset.Z (resterait lockstep).
			-- Amplitude 0.06, frequence 5, clamp [0.48, 0.82],
			-- base 0.76, speed * 0.08, * 0.1 inchanges (famille
			-- V98/V104/V105). Pas de Position. Recette analogique
			-- V105 — ne PAS merger c450 / ee71. Distinct de V105
			-- (feux offset.X, elseif plus bas). Distinct de V100
			-- (trail offset.Z). Distinct de V107 (flag pitch, pas
			-- Transparency). Un elseif, role == "wake" inchange.
			-- Name Wake inchange. Construction addWake inchangee
			-- (V92).
			piece.part.Transparency = math.clamp(0.76 - speed * 0.08 + math.sin(time * 5 + piece.offset.X * 0.1) * 0.06, 0.48, 0.82)
		elseif piece.role == "flame" then
			-- V111 : phase depuis frame.X. Plus de lockstep
			-- sin(time * 18) sans phase spatiale. frame est le
			-- CFrame monde Overlay (translation * yaw). Offset
			-- local EngineFlame Vector3.new(0, 0, 4.15) — X == 0
			-- pour TOUTES les flammes : offset.X resterait
			-- lockstep (comme V106 interdit offset.Z pour Wake).
			-- Overlay passe deja now+unit.phase (id % 31) : deux
			-- missiles id ≡ 0 mod 31 resteraient lockstep sans
			-- frame.X. Amplitude 0.45, frequence 18, * 0.1
			-- inchanges (famille V98). Size = Vector3.new API
			-- (V74 Option A) inchange. Pulse Z vivant. Pas de
			-- Position. Recette analogique V110 — ne PAS merger
			-- c450 / ee71. Distinct de V74 (API Size). Distinct
			-- de V100 (trail offset.Z, elseif suivant). Distinct
			-- de V110 (PortCraneCable, BuildingModels.animate —
			-- autre fichier). Distinct de V76 (Preview Size
			-- rayon constant). Un elseif, role == "flame"
			-- inchange. Name EngineFlame inchange. Construction
			-- createMissile inchangee. Pas de flamePhase.
			-- Ne pas inventer un pool Vector3. Distinct de V112
			-- (recycle Ground/Border, WorldRenderer — autre fichier).
			-- Distinct de V113 (recycle Blast, Overlay — autre fichier).
			-- Distinct de V114 (recycle BlastSmoke, Overlay — autre fichier).
			-- Distinct de V115 (recycle Shockwave, Overlay — autre fichier).
			-- Distinct de V116 (recycle DeliveryPulse, Overlay — autre fichier).
			-- Distinct de V117 (recycle LandingSplash, Overlay — autre fichier).
			-- Distinct de V118 (recycle LaunchWake, Overlay — autre fichier).
			-- Distinct de V119 (recycle goldPopup, Overlay — autre fichier).
			-- Distinct de V120 (recycle floatingText, Effects — autre fichier).
			-- Distinct de V121 (recycle tileFlash, Effects — autre fichier).
			-- Distinct de V122 (recycle conquestPulse, Effects — autre fichier).
			-- Distinct de V123 (recycle BuildRing, BuildingModels — autre fichier).
			-- Distinct de V124 (recycle HUD notify feedFree — autre fichier).
			piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18 + frame.X * 0.1) * 0.45)
		elseif piece.role == "trail" then
			-- V100 : phase depuis offset.Z. Plus de offset.Position.Z
			-- 60 Hz (Position reconstruit un Vector3). offset est deja
			-- un CFrame pose a createMissile. Amplitude 0.035,
			-- frequence 9, clamp [0.25, 0.9] inchanges. Formule
			-- ajoute au Transparency courant. Recette feel N151 —
			-- ne PAS merger. Distinct de V99 (beacons rest.Z,
			-- BuildingModels.animate — autre fichier). Distinct de
			-- V74 (flame Size API). Distinct de V111 (flame
			-- phase frame.X, elseif precedent). Distinct de V73
			-- (radar/flag).
			-- Distinct de V98 (CityWindows rest.X). Distinct de V104
			-- (FactoryOutput rest.X / SiloWarning rest.Z,
			-- BuildingModels.animate — autre fichier). Distinct de
			-- V105 (feux navire offset.X, elseif suivant). Distinct de
			-- V106 (wake Transparency, elseif wake). Trois Parts Exhaust
			-- par missile. Construction createMissile inchangee.
			piece.part.Transparency = math.clamp(piece.part.Transparency + math.sin(time * 9 + piece.offset.Z) * 0.035, 0.25, 0.9)
		elseif piece.role == "light" then
			-- V105 : phase depuis offset.X. Plus de lockstep
			-- sin(time * 3) sans phase. offset est deja un CFrame
			-- pose a createBoat. PortLight X=-2.16 / StarboardLight
			-- X=2.16 (meme Z -3.3 — ne PAS user offset.Z). Seuil
			-- -0.2 / 0 / 0.45, frequence 3, * 0.1 inchanges
			-- (famille V98/V104). Pas de Position. Recette
			-- analogique V104 SiloWarning — ne PAS merger c450 /
			-- ee71. Distinct de V100 (trail offset.Z, elseif
			-- precedent). Distinct de V104 (FactoryOutput /
			-- SiloWarning, BuildingModels.animate — autre fichier).
			-- Distinct de V106 (wake Transparency). Distinct de V107
			-- (flag pitch). Un elseif, role == "light" inchange.
			-- Names PortLight / StarboardLight inchanges.
			piece.part.Transparency = if math.sin(time * 3 + piece.offset.X * 0.1) > -0.2 then 0 else 0.45
		end
		piece.part.CFrame = frame * localFrame
	end
end

return UnitModels
