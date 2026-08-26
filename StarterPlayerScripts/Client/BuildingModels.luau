--!strict
--[[
	Modeles 3D procéduraux des batiments.

	Chaque batiment est assemble a partir de Parts plutot que d'un mesh importe :
	aucun asset a uploader, la couleur de faction s'applique directement, et la
	silhouette reste lisible en low-poly — le style qui va avec le terrain
	blocky du reste du monde.

	**Budget strict : au maximum une douzaine de Parts par batiment.** Le
	terrain en consomme deja ~1 300, et une partie compte plusieurs dizaines de
	batiments. Un modele a quarante Parts, multiplie par cent batiments,
	suffirait a faire tomber le framerate sur mobile.

	Chaque modele suit la meme regle de composition : une masse principale aux
	couleurs de la faction, des details en gris neutre, et un accent lumineux.
	C'est ce qui permet de reconnaitre le proprietaire de loin et le type de
	batiment de pres.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local BuildingModels = {}

local B = Config.BUILDING

local CONCRETE = Color3.fromRGB(172, 176, 184)
local DARK = Color3.fromRGB(48, 54, 64)
local GLASS = Color3.fromRGB(150, 220, 255)
local PARK = Color3.fromRGB(86, 186, 122)
local STEEL = Color3.fromRGB(118, 130, 148)
local WARNING = Color3.fromRGB(255, 196, 72)
local MISSILE = Color3.fromRGB(236, 242, 250)

-- Qualité basse : pas de Smoke ni d'ombres de PointLight. pcall : en banc
-- headless UserSettings n'existe pas → on garde le FX (défaut = garder).
local allowFx: boolean? = nil
local function qualityAllowsFx(): boolean
	if allowFx ~= nil then
		return allowFx
	end
	local ok, allow = pcall(function()
		local level = UserSettings():GetService("UserGameSettings").SavedQualityLevel
		if level == Enum.SavedQualitySetting.Automatic then
			return true
		end
		return level.Value >= Enum.SavedQualitySetting.QualityLevel4.Value
	end)
	if not ok then
		allowFx = true
	else
		allowFx = allow == true
	end
	return allowFx
end

--=============================================================================
-- Helpers
--=============================================================================

local function block(
	parent: Instance,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	-- Ne doit jamais intercepter le clic destine au sol : viser une tuile
	-- occupee par un batiment doit rester possible.
	part.CanQuery = false
	-- Les batiments sont peu nombreux par rapport au terrain fusionne. Garder
	-- leurs ombres apporte enormement de volume pour un cout encore raisonnable.
	part.CastShadow = true
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.CFrame = CFrame.new(offset)
	part.Parent = parent
	return part
end

local cylinder: (Instance, Vector3, Vector3, Color3) -> Part

-- Usine : hall metallique, toiture en sheds, cheminees et quai de chargement.
-- La silhouette horizontale la distingue de la ville, tandis que les deux
-- cheminees restent visibles de loin.
local function buildFactory(model: Model, color: Color3, level: number?)
	--[[
		La silhouette suit le niveau, comme celle de la ville.

		Une usine se stacke : cliquer a cote d'une usine existante la fait monter
		d'un palier au lieu d'en poser une seconde, et son debit double. Tant que
		le modele ignorait ce niveau, deux usines de rendement tres different
		etaient strictement identiques a l'ecran — le chiffre flottant au-dessus
		etait le SEUL indice, sur une carte ou l'on lit d'abord les formes.

		La halle grandit et gagne une dent de scie par palier : la lecture reste
		"c'est une usine", en plus imposant.
	]]
	local tier = math.clamp(level or 1, 1, 3)
	local hallHeight = 4.2 + (tier - 1) * 1.6
	local roofY = 0.7 + hallHeight

	block(model, Vector3.new(10, 0.7, 8), Vector3.new(0, 0.35, 0), DARK, Enum.Material.Concrete)
	block(model, Vector3.new(8.8, hallHeight, 6.6), Vector3.new(-0.3, 0.7 + hallHeight / 2, 0), color, Enum.Material.Metal)

	-- Toit industriel en dents de scie : une de plus a chaque palier.
	-- V89 : translation * fromEulerAnglesYXZ (Z=-12° fixe). Plus de
	-- CFrame.Angles a buildFactory toits. Recette feel N140 inline —
	-- ne PAS cuire un roofRot (translations distinctes par `x`, comme
	-- V88 cylinderRot / V86 trunkRot interdits). Distinct de V88
	-- (cylinder helper, Z=90°, même fichier, même buildFactory — ne
	-- PAS retoucher le helper). Distinct de V87 (Rock yaw `phase`
	-- variable, WorldRenderer). Distinct de V86 (TreeTrunk, Z=90°,
	-- WorldRenderer). Distinct de V85 (BuildRing, playConstruction).
	-- Distinct de V84 (OceanGlint yaw `angle` variable). Construction
	-- de modele, pas 60 Hz. block() pose d'abord CFrame.new(x, roofY, 0)
	-- ; la ligne ecrase ensuite. teeth / x / roofY / Size / Color /
	-- Material inchanges. Ne pas editer les cheminees / reservoir.
	-- Portes silo V90 / rampes SAM V91 (check modeles). Ne pas toucher
	-- UnitModels addWake (leftover V92). Ne pas merger feel a8e1.
	local teeth = 1 + tier
	for i = 1, teeth do
		local x = (i - (teeth + 1) / 2) * 2.4 - 0.3
		local roof = block(model, Vector3.new(2.3, 0.35, 7), Vector3.new(x, roofY, 0), STEEL, Enum.Material.Metal)
		roof.CFrame = CFrame.new(x, roofY, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(-12))
	end

	local chimneyA = cylinder(model, Vector3.new(9 + (tier - 1) * 2, 1.15, 1.15), Vector3.new(2.7, roofY + 3.3, -1.8), STEEL)
	chimneyA.Name = "Chimney"
	if qualityAllowsFx() then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(145, 155, 166)
		smoke.Opacity = 0.18
		smoke.RiseVelocity = 2.4
		smoke.Size = 2.6
		smoke.Parent = chimneyA
	end
	local chimneyB = cylinder(model, Vector3.new(7, 0.9, 0.9), Vector3.new(4, 7.5, 1.6), DARK)
	chimneyB.Name = "Chimney"

	-- Quai et convoyeur diriges vers la future route logistique.
	block(model, Vector3.new(2.5, 2.4, 4.8), Vector3.new(-5, 1.55, 0), CONCRETE, Enum.Material.Concrete)
	block(model, Vector3.new(3.8, 0.55, 1.4), Vector3.new(-5.8, 1.1, 0), WARNING, Enum.Material.Metal)
	local output = block(model, Vector3.new(0.3, 1.8, 3.8), Vector3.new(-5.15, 2.1, 0), GLASS)
	output.Name = "FactoryOutput"
	output.Material = Enum.Material.Neon
	local loadingLight = Instance.new("PointLight")
	loadingLight.Color = WARNING
	loadingLight.Brightness = 1.4
	loadingLight.Range = 15
	loadingLight.Shadows = qualityAllowsFx()
	loadingLight.Parent = output

	-- Reservoir et conduite : petits details qui evitent l'effet "gros cube".
	cylinder(model, Vector3.new(3.2, 2.1, 2.1), Vector3.new(3.3, 2, 2.1), CONCRETE)
	block(model, Vector3.new(0.45, 2.8, 0.45), Vector3.new(3.3, 4.4, 2.1), WARNING, Enum.Material.Metal)
end

function cylinder(parent: Instance, size: Vector3, offset: Vector3, color: Color3): Part
	local part = block(parent, size, offset, color)
	part.Shape = Enum.PartType.Cylinder
	-- V88 : translation * fromEulerAnglesYXZ (Z=90° fixe). Le cylindre
	-- Roblox pointe X : on le redresse. Plus de CFrame.Angles dans le
	-- helper mesh. Recette feel N139 inline — ne PAS cuire un
	-- cylinderRot (translations distinctes par `offset`, comme V86
	-- trunkRot interdit). Distinct de V87 (Rock yaw `phase` variable,
	-- WorldRenderer.buildDecorations). Distinct de V86 (TreeTrunk, même
	-- Z=90° mais WorldRenderer). Distinct de V85 (BuildRing,
	-- playConstruction, pas ce helper). Distinct de V84 (OceanGlint yaw
	-- `angle` variable, buildOcean). Construction de modele, pas 60 Hz.
	-- Shape = Cylinder pose AVANT le CFrame. block() pose d'abord
	-- CFrame.new(offset) ; cylinder() ecrase ensuite. Call sites
	-- buildFactory / buildSilo non edites. Toits usine V89 / portes
	-- silo V90 / rampes SAM V91 (check modeles). Ne pas toucher
	-- UnitModels addWake (leftover V92). Ne pas merger feel a8e1.
	part.CFrame = CFrame.new(offset) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))
	return part
end

--=============================================================================
-- Modeles
--=============================================================================

--[[
	Capitale : un donjon central flanque de deux tours, coiffe d'un mat et d'un
	drapeau aux couleurs de la faction. C'est le batiment le plus haut du jeu,
	pour qu'on repere une capitale a l'autre bout de la carte.
]]
local function buildCapital(model: Model, color: Color3, _level: number?)
	block(model, Vector3.new(7, 12, 7), Vector3.new(0, 6, 0), color)
	block(model, Vector3.new(3, 16, 3), Vector3.new(-3.5, 8, -3.5), color)
	block(model, Vector3.new(3, 16, 3), Vector3.new(3.5, 8, 3.5), color)
	block(model, Vector3.new(9, 1.4, 9), Vector3.new(0, 12.6, 0), DARK)

	-- Mat et drapeau
	block(model, Vector3.new(0.5, 9, 0.5), Vector3.new(0, 17.5, 0), DARK, Enum.Material.Metal)
	local flag = block(model, Vector3.new(0.3, 3, 5), Vector3.new(0, 20, 2.6), color)
	flag.Name = "CapitalFlag"
	flag.Material = Enum.Material.Fabric

	-- Base eclairee : rend la capitale visible de nuit et souligne sa couleur.
	local glow = block(model, Vector3.new(7.6, 0.6, 7.6), Vector3.new(0, 0.3, 0), color)
	glow.Material = Enum.Material.Neon
end

--[[
	Ville : une grappe de tours de hauteurs variees. Le desordre est
	deliberement rythme — quatre volumes suffisent a lire "ville" alors qu'un
	seul cube lirait "boite".
]]
local function buildCity(model: Model, color: Color3, level: number?)
	local cityLevel = math.clamp(level or 1, 1, Config.CITY_MAX_LEVEL)
	local towerA = if cityLevel == 1 then 9 elseif cityLevel == 2 then 13 else 17
	local towerB = if cityLevel == 1 then 6.5 elseif cityLevel == 2 then 9 else 12
	local towerC = if cityLevel == 1 then 11 elseif cityLevel == 2 then 16 else 22

	-- Un socle et deux axes donnent une vraie lecture de quartier, meme quand
	-- la ville est vue de tres haut.
	block(model, Vector3.new(8, 0.35, 8), Vector3.new(0, 0.18, 0), DARK)
	block(model, Vector3.new(7.2, 0.12, 0.55), Vector3.new(0, 0.42, 0), CONCRETE)
	block(model, Vector3.new(0.55, 0.12, 7.2), Vector3.new(0, 0.43, 0), CONCRETE)

	block(model, Vector3.new(3, towerA, 3), Vector3.new(-1.8, towerA / 2, -1.8), color)
	block(model, Vector3.new(2.6, towerB, 2.6), Vector3.new(2, towerB / 2, -1.4), color)
	block(model, Vector3.new(2.2, towerC, 2.2), Vector3.new(0.4, towerC / 2, 2.2), color)
	block(model, Vector3.new(2, 4.5, 2), Vector3.new(-2.4, 2.25, 2), CONCRETE)
	block(model, Vector3.new(1.8, 0.25, 1.8), Vector3.new(2.1, 0.58, 2.1), PARK)

	-- Fenetres : peu nombreuses pour rester lisibles et economes en instances.
	local windows = block(model, Vector3.new(2.4, 0.5, 2.4), Vector3.new(0.4, towerC * 0.78, 2.2), GLASS)
	windows.Name = "CityWindows"
	windows.Material = Enum.Material.Neon
	local windowsLow = block(model, Vector3.new(2.8, 0.35, 2.8), Vector3.new(-1.8, towerA * 0.62, -1.8), GLASS)
	windowsLow.Name = "CityWindows"
	windowsLow.Material = Enum.Material.Neon

	-- Deux balises rendent les villes identifiables dans une bataille dense.
	local beaconA = block(model, Vector3.new(0.35, 1.4, 0.35), Vector3.new(3.25, 1.1, 3.25), color)
	beaconA.Name = "CityBeacon"
	beaconA.Material = Enum.Material.Neon
	local beaconB = block(model, Vector3.new(0.35, 1.4, 0.35), Vector3.new(-3.25, 1.1, -3.25), color)
	beaconB.Name = "CityBeacon"
	beaconB.Material = Enum.Material.Neon

	-- La megapole gagne une fleche reconnaissable de toute la carte. Une seule
	-- Part suffit : la progression visuelle reste forte sans exploser le budget.
	if cityLevel >= 3 then
		local spire = block(model, Vector3.new(0.35, 6, 0.35), Vector3.new(0.4, towerC + 3, 2.2), color)
		spire.Material = Enum.Material.Neon
	end
end

--[[
	Port : une jetee, un entrepot et une grue. La grue est ce qui distingue
	instantanement un port d'une ville, meme sans couleur.
]]
local function buildPort(model: Model, color: Color3, level: number?)
	-- Meme regle que l'usine : le niveau se voit. Un port de niveau 3 arme trois
	-- fois plus de convois, sa silhouette doit le dire.
	local tier = math.clamp(level or 1, 1, 3)
	local mast = 8 + (tier - 1) * 2

	block(model, Vector3.new(9, 1, 6), Vector3.new(0, 0.5, 0), CONCRETE)
	block(model, Vector3.new(4, 4, 4), Vector3.new(-2.5, 3, 0), color)

	-- Grue : mat vertical + fleche horizontale + cable
	block(model, Vector3.new(0.7, mast, 0.7), Vector3.new(2.5, 1 + mast / 2, 0), DARK, Enum.Material.Metal)
	local boomY = 1 + mast + 0.6
	local boom = block(model, Vector3.new(6, 0.6, 0.6), Vector3.new(4.2, boomY, 0), DARK, Enum.Material.Metal)
	boom.Name = "PortCraneBoom"
	local cable = block(model, Vector3.new(0.25, 3, 0.25), Vector3.new(6.5, boomY - 1.8, 0), DARK, Enum.Material.Metal)
	cable.Name = "PortCraneCable"

	-- Conteneurs empiles sur le quai : un rang par palier. C'est le detail qui
	-- distingue un port actif d'un ponton vide.
	for i = 1, tier do
		block(
			model,
			Vector3.new(2.2, 1.1, 1.6),
			Vector3.new(-3.2 + (i % 2) * 0.5, 1.55 + (i - 1) * 1.2, 2.1),
			if i % 2 == 0 then WARNING else STEEL,
			Enum.Material.Metal
		)
	end

	local beacon = block(model, Vector3.new(0.8, 0.8, 0.8), Vector3.new(2.5, boomY + 0.6, 0), color)
	beacon.Name = "PortBeacon"
	beacon.Material = Enum.Material.Neon
end

--[[
	Bunker : une masse basse et large, volontairement ecrasee. Sa silhouette
	doit dire "on ne passe pas" a l'oppose de la verticalite des villes.
]]
local function buildDefense(model: Model, color: Color3, _level: number?)
	block(model, Vector3.new(8, 3, 8), Vector3.new(0, 1.5, 0), CONCRETE, Enum.Material.Concrete)
	block(model, Vector3.new(6, 2, 6), Vector3.new(0, 4, 0), color, Enum.Material.Concrete)

	-- Meurtriere
	local slit = block(model, Vector3.new(6.2, 0.6, 0.8), Vector3.new(0, 4.2, 3), DARK)
	slit.Material = Enum.Material.Metal

	-- Sacs de sable aux angles
	block(model, Vector3.new(2, 1.2, 2), Vector3.new(-3.4, 0.6, 3.4), DARK)
	block(model, Vector3.new(2, 1.2, 2), Vector3.new(3.4, 0.6, 3.4), DARK)
end

--[[
	Silo : un tube vertical ouvert, ogive visible a l'interieur. On doit
	comprendre au premier regard qu'il y a une bombe dedans.
]]
local function buildSilo(model: Model, color: Color3, _level: number?)
	block(model, Vector3.new(10, 0.8, 10), Vector3.new(0, 0.4, 0), DARK, Enum.Material.Concrete)
	cylinder(model, Vector3.new(5.5, 6.2, 6.2), Vector3.new(0, 3.2, 0), CONCRETE)
	cylinder(model, Vector3.new(5.7, 4.9, 4.9), Vector3.new(0, 3.35, 0), DARK)

	-- Missile complet, avec corps, etages, ogive et quatre ailettes.
	local body = cylinder(model, Vector3.new(9.5, 1.5, 1.5), Vector3.new(0, 8.3, 0), MISSILE)
	body.Name = "StrategicMissile"
	local band = cylinder(model, Vector3.new(1.1, 1.75, 1.75), Vector3.new(0, 7.1, 0), color)
	band.Material = Enum.Material.Neon
	local tip = block(model, Vector3.new(1.1, 2.4, 1.1), Vector3.new(0, 14.1, 0), Color3.fromRGB(220, 70, 60), Enum.Material.Metal)
	tip.Name = "Warhead"
	tip.Shape = Enum.PartType.Ball
	for i = 0, 3 do
		local angle = i * math.pi / 2
		block(
			model,
			Vector3.new(0.28, 2.2, 1.7),
			Vector3.new(math.cos(angle) * 1.05, 4.9, math.sin(angle) * 1.05),
			color,
			Enum.Material.Metal
		)
	end

	-- Deux portes blindees ouvertes rendent la fonction du silo evidente.
	-- V90 : translation * fromEulerAnglesYXZ (Z=±18° fixe). Plus de
	-- CFrame.Angles a buildSilo portes. Recette feel N141 inline —
	-- ne PAS cuire un doorRot (signes Z opposes + translations
	-- distinctes, comme V89 roofRot / V88 cylinderRot / V86 trunkRot
	-- interdits). Distinct de V89 (toits usine, Z=-12°, même fichier,
	-- buildFactory — ne PAS retoucher les toits). Distinct de V88
	-- (cylinder helper, Z=90°, même buildSilo pour le tube/missile —
	-- ne PAS retoucher le helper). Distinct de V87 (Rock yaw `phase`
	-- variable, WorldRenderer). Distinct de V91 (rampes SAM, pitch
	-- X=-31°, buildSam — ne PAS retoucher les rampes). Distinct de
	-- leftover V92 (UnitModels addWake yaw Y=±11°). Construction de
	-- modele, pas 60 Hz.
	-- block() pose d'abord CFrame.new(±3.6, 1.3, 0) ; la ligne ecrase
	-- ensuite. STEEL / Size 4.4, 0.45, 6.5 / Material Metal / Name
	-- SiloDoor inchanges. Ne pas editer le tube / missile / ogive.
	-- Ne pas merger feel 4885.
	local doorA = block(model, Vector3.new(4.4, 0.45, 6.5), Vector3.new(-3.6, 1.3, 0), STEEL, Enum.Material.Metal)
	doorA.Name = "SiloDoor"
	doorA.CFrame = CFrame.new(-3.6, 1.3, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(18))
	local doorB = block(model, Vector3.new(4.4, 0.45, 6.5), Vector3.new(3.6, 1.3, 0), STEEL, Enum.Material.Metal)
	doorB.Name = "SiloDoor"
	doorB.CFrame = CFrame.new(3.6, 1.3, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(-18))
	local warningStrip = block(model, Vector3.new(9, 0.18, 0.35), Vector3.new(0, 0.86, 4.2), WARNING, Enum.Material.Neon)
	warningStrip.Name = "SiloWarning"
end

--[[
	Batterie SAM : un socle, un radar incline et deux rampes. L'inclinaison est
	ce qui la distingue du silo, strictement vertical.
]]
local function buildSam(model: Model, color: Color3, _level: number?)
	block(model, Vector3.new(9, 0.8, 8), Vector3.new(0, 0.4, 0), DARK, Enum.Material.Concrete)
	block(model, Vector3.new(7.4, 1.1, 1.2), Vector3.new(0, 1.2, -2.5), STEEL, Enum.Material.Metal)
	block(model, Vector3.new(7.4, 1.1, 1.2), Vector3.new(0, 1.2, 2.5), STEEL, Enum.Material.Metal)
	block(model, Vector3.new(3.8, 2.2, 3.8), Vector3.new(0, 2.15, 0), color, Enum.Material.Metal)

	-- Quatre missiles sur deux rampes inclinees.
	-- V91 : translation * fromEulerAnglesYXZ (pitch X=-31° fixe). Plus
	-- de CFrame.Angles a buildSam Interceptor. Recette feel N142 inline
	-- — ne PAS cuire un rampRot (translations side/lane distinctes,
	-- comme V90 doorRot / V89 roofRot / V88 cylinderRot / V86 trunkRot
	-- interdits). Distinct de V90 (portes silo, Z=±18°, même fichier,
	-- buildSilo — ne PAS retoucher les portes). Distinct de V89 (toits
	-- usine, Z=-12°, buildFactory — ne PAS retoucher les toits).
	-- Distinct de V88 (cylinder helper, Z=90° — ne PAS retoucher le
	-- helper). Distinct de leftover V92 (UnitModels addWake, yaw
	-- Y=±11°). Construction de modele, pas 60 Hz. block() pose d'abord
	-- CFrame.new(side * 1.45, 5.1, lane * 0.72) ; la ligne ecrase
	-- ensuite. MISSILE / Size 0.72, 5.8, 0.72 / Material Metal / Name
	-- Interceptor inchanges. Nez Neon inchange. Ne pas editer le radar
	-- / socle / nez. Ne pas merger feel 4885.
	for side = -1, 1, 2 do
		for lane = -1, 1, 2 do
			local launcher = block(model, Vector3.new(0.72, 5.8, 0.72), Vector3.new(side * 1.45, 5.1, lane * 0.72), MISSILE, Enum.Material.Metal)
			launcher.Name = "Interceptor"
			launcher.CFrame = CFrame.new(side * 1.45, 5.1, lane * 0.72) * CFrame.fromEulerAnglesYXZ(math.rad(-31), 0, 0)
			local nose = block(model, Vector3.new(0.82, 0.9, 0.82), Vector3.new(side * 1.45, 7.85, lane * 0.72 - 1.65), color)
			nose.Material = Enum.Material.Neon
		end
	end

	-- Radar motorise : Overlay fait tourner la barre autour de son axe.
	block(model, Vector3.new(0.45, 5.5, 0.45), Vector3.new(0, 5.1, 2.5), DARK, Enum.Material.Metal)
	local radar = block(model, Vector3.new(5.2, 0.35, 1.6), Vector3.new(0, 8, 2.5), MISSILE, Enum.Material.Metal)
	radar.Name = "Radar"
	local light = block(model, Vector3.new(0.65, 0.65, 0.65), Vector3.new(0, 8.65, 2.5), Color3.fromRGB(120, 255, 160))
	light.Material = Enum.Material.Neon
	local radarLight = Instance.new("PointLight")
	radarLight.Color = Color3.fromRGB(120, 255, 160)
	radarLight.Brightness = 1.8
	radarLight.Range = 18
	radarLight.Shadows = qualityAllowsFx()
	radarLight.Parent = light
end

--[[
	Laboratoire : un dome de verre sur socle, flanque d'une antenne. Le dome est
	la seule forme courbe du jeu — c'est ce qui le distingue instantanement des
	batiments militaires, tous anguleux.
]]
local function buildLab(model: Model, color: Color3, _level: number?)
	block(model, Vector3.new(7, 1.2, 7), Vector3.new(0, 0.6, 0), CONCRETE, Enum.Material.Concrete)
	block(model, Vector3.new(5, 3, 5), Vector3.new(0, 2.7, 0), color)

	local dome = block(model, Vector3.new(5, 5, 5), Vector3.new(0, 5, 0), GLASS, Enum.Material.Glass)
	dome.Name = "Dome"
	dome.Shape = Enum.PartType.Ball
	dome.Transparency = 0.35

	block(model, Vector3.new(0.4, 6, 0.4), Vector3.new(2.8, 6, -2.8), DARK, Enum.Material.Metal)
	local tip = block(model, Vector3.new(0.9, 0.9, 0.9), Vector3.new(2.8, 9.2, -2.8), Color3.fromRGB(140, 220, 255))
	tip.Name = "LabBeacon"
	tip.Material = Enum.Material.Neon
end

local BUILDERS: { [number]: (Model, Color3, number?) -> () } = {
	[B.CAPITAL] = buildCapital,
	[B.CITY] = buildCity,
	[B.FACTORY] = buildFactory,
	[B.PORT] = buildPort,
	[B.DEFENSE] = buildDefense,
	[B.SILO] = buildSilo,
	[B.SAM] = buildSam,
	[B.LAB] = buildLab,
}

-- Hauteur approximative de chaque modele : sert a placer l'etiquette juste
-- au-dessus sans la faire flotter ni la noyer dans la geometrie.
local HEIGHTS: { [number]: number } = {
	[B.CAPITAL] = 23,
	[B.CITY] = 11,
	[B.FACTORY] = 13,
	[B.PORT] = 9.5,
	[B.DEFENSE] = 5.5,
	[B.SILO] = 16,
	[B.SAM] = 9,
	[B.LAB] = 10,
}

--=============================================================================
-- API
--=============================================================================

--[[
	Construit le modele d'un batiment, ancre a `position` (le sol de la tuile).
	Le modele est renvoye non parente : l'appelant decide ou il vit.
]]
function BuildingModels.create(kind: number, color: Color3, position: Vector3, level: number?): Model
	local model = Instance.new("Model")
	model.Name = `Building{kind}`

	local builder = BUILDERS[kind]
	if builder then
		builder(model, color, level)
	else
		block(model, Vector3.new(3, 6, 3), Vector3.new(0, 3, 0), color)
	end

	--[[
		Mise a l'echelle du monde, puis translation.

		Chaque modele est dessine en coordonnees lisibles autour de l'origine, a
		l'echelle d'origine du jeu. On applique le facteur ici, en un seul
		endroit, plutot que de multiplier quatre-vingts nombres dans les
		constructeurs — qui resteraient alors justes uniquement pour une taille
		de tuile donnee.

		L'ordre compte : on met a l'echelle AVANT de translater, sinon la
		position dans le monde serait multipliee elle aussi et le batiment
		partirait a l'autre bout de la carte.
	]]
	local scale = Config.WORLD_SCALE
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			if scale ~= 1 then
				part.Size *= scale
				part.CFrame = (part.CFrame - part.Position) + part.Position * scale
			end
			part.CFrame = part.CFrame + position
			part:SetAttribute("RestCFrame", part.CFrame)
		end
	end

	model:SetAttribute("Level", level or 1)
	return model
end

--[[
	Animation de construction.

	Le batiment sort de terre en montant, chaque bloc avec un leger decalage :
	c'est ce decalage qui donne l'impression d'un chantier plutot que d'un
	objet qui apparait. Une bague de poussiere marque l'emprise au sol pendant
	toute la duree.

	Duree volontairement courte (~2,5 s) : c'est une recompense, pas une
	attente. Le batiment est deja fonctionnel cote serveur des l'ordre valide,
	l'animation n'est que la mise en scene de ce qui a deja eu lieu.
]]
function BuildingModels.playConstruction(model: Model, ground: Vector3, duration: number?)
	local total = duration or 2.8
	model:SetAttribute("ConstructionUntil", os.clock() + total)

	local parts: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end

	table.sort(parts, function(a, b)
		return a.Position.Y < b.Position.Y
	end)

	-- Echafaudage temporaire autour du chantier.
	local scaffold = Instance.new("Model")
	scaffold.Name = "Scaffold"
	scaffold.Parent = model
	local poleColor = Color3.fromRGB(255, 186, 86)
	for angle = 0, 3 do
		local rad = angle * math.pi / 2
		local px = math.cos(rad) * 4.2
		local pz = math.sin(rad) * 4.2
		local pole = block(scaffold, Vector3.new(0.35, 8, 0.35), Vector3.new(px, 4, pz), poleColor, Enum.Material.Metal)
		pole.Material = Enum.Material.Metal
	end
	block(scaffold, Vector3.new(9.5, 0.25, 9.5), Vector3.new(0, 7.8, 0), poleColor, Enum.Material.Metal)

	for i, part in parts do
		local final = part.CFrame
		local drop = part.Size.Y + 5
		part.CFrame = final - Vector3.new(0, drop, 0)
		part.Transparency = 1
		local delay = (i - 1) / #parts * total * 0.5
		local rise = TweenInfo.new(total * 0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
		TweenService:Create(part, rise, { CFrame = final }):Play()
		TweenService:Create(
			part,
			TweenInfo.new(total * 0.22, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay),
			{ Transparency = part.Name == "Dome" and 0.35 or 0 }
		):Play()
	end

	local ring = Instance.new("Part")
	ring.Name = "BuildRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 200, 110)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.5, 4, 4)
	-- V85 : translation * fromEulerAnglesYXZ (Z=90° fixe, cylindre plat).
	-- Plus de CFrame.Angles a playConstruction. Recette feel N136
	-- inline — ne PAS cuire un ringRot (événement unique). Ne PAS
	-- réutiliser Effects.pulseRot (module distinct). Distinct de V84
	-- (OceanGlint yaw `angle` variable). Distinct de V83/V82 (pulseRot
	-- Effects). Distinct de V75 (PlacementPreview.pulseRot, hover).
	-- Événement construction, pas 60 Hz. ground Vector3 inchangé.
	ring.CFrame = CFrame.new(ground) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))
	ring.Parent = model

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 100)
	light.Brightness = 2.2
	light.Range = 22
	light.Parent = ring

	TweenService:Create(ring, TweenInfo.new(total, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, 18, 18),
		Transparency = 1,
	}):Play()

	local dust = Instance.new("Part")
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanTouch = false
	dust.CanQuery = false
	dust.Transparency = 1
	dust.Size = Vector3.new(1, 1, 1)
	dust.CFrame = CFrame.new(ground)
	dust.Parent = model
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(210, 180, 130))
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Lifetime = NumberRange.new(0.6, 1.2)
	particles.Rate = 18
	particles.Speed = NumberRange.new(2, 6)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Parent = dust

	task.delay(total * 0.85, function()
		particles.Enabled = false
	end)

	task.delay(total + 0.3, function()
		if ring.Parent then
			ring:Destroy()
		end
		if dust.Parent then
			dust:Destroy()
		end
		if scaffold.Parent then
			scaffold:Destroy()
		end
	end)
end

-- Mouvement ambiant des pieces mecaniques et des balises. Les transformations
-- repartent toujours de RestCFrame : aucune derive numerique apres dix minutes.
function BuildingModels.animate(model: Model, time: number, _dt: number)
	local constructionUntil = model:GetAttribute("ConstructionUntil") :: number?
	if constructionUntil and time < constructionUntil then
		return
	end

	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local rest = child:GetAttribute("RestCFrame") :: CFrame?
		if not rest then
			continue
		end

		if child.Name == "Radar" then
			-- V70 : translation * yaw. RestCFrame de ces trois pieces
			-- est une translation pure (block() pose CFrame.new(offset),
			-- create ajoute position — rotation identite). Donc
			-- rest * Angles(rx,ry,rz) ≡ CFrame.new(rest.X,Y,Z) *
			-- fromEulerAnglesYXZ(rx,ry,rz). fromEulerAnglesYXZ ≡ Angles
			-- ici : Radar/Boom n'ont que Y ; Flag a ry=0 donc X puis Z.
			-- Plus de CFrame.Angles 60 Hz. Amplitude / frequences
			-- inchangees. Cable Y inchange (V60). Camera focusX inchangee
			-- (V69). Roues camion / roulis navire inchanges.
			child.CFrame = CFrame.new(rest.X, rest.Y, rest.Z)
				* CFrame.fromEulerAnglesYXZ(0, time * 1.45, 0)
		elseif child.Name == "CapitalFlag" then
			child.CFrame = CFrame.new(rest.X, rest.Y, rest.Z)
				* CFrame.fromEulerAnglesYXZ(
					math.sin(time * 2.4) * 0.045,
					0,
					math.sin(time * 1.7) * 0.035
				)
		elseif child.Name == "PortCraneBoom" then
			child.CFrame = CFrame.new(rest.X, rest.Y, rest.Z)
				* CFrame.fromEulerAnglesYXZ(0, math.sin(time * 0.35) * 0.12, 0)
		elseif child.Name == "PortCraneCable" then
			-- V60 : Y en nombres depuis rest. Plus de Vector3.new 60 Hz
			-- (rest + offset). Un CFrame.new. Amplitude 0.35 conservee.
			-- Radar / flag / boom : V70 (rotation, pas translation).
			-- Feuillage / houle / camion / unites inchanges (V59/V58/V57/V56).
			child.CFrame = CFrame.new(
				rest.X,
				rest.Y + math.sin(time * 0.8) * 0.35,
				rest.Z
			)
		elseif child.Name == "CityWindows" then
			-- V98 : phase depuis rest.X. Plus de child.Position.X 60 Hz
			-- (Position reconstruit un Vector3 monde apres create).
			-- rest est deja lu deux lignes plus haut. Amplitude 0.06 /
			-- 0.08, frequence 0.7, * 0.1 inchanges. Recette feel N149
			-- — ne PAS merger c450. Distinct de V70 (Radar CFrame yaw).
			-- Distinct de V60 (cable Y nombres). Distinct de V97
			-- (mesh carrier, UnitModels — autre fichier). Distinct de
			-- V99 (beacons rest.Z, elseif suivant). Distinct de
			-- V100 (trail offset.Z, UnitModels.place — autre fichier).
			-- FactoryOutput / SiloWarning n'ont PAS de Position — ne
			-- pas les toucher. Radar / Flag / Boom (V70) et cable (V60)
			-- inchanges. RestCFrame a la construction inchange.
			child.Transparency = 0.06 + (math.sin(time * 0.7 + rest.X * 0.1) + 1) * 0.08
		elseif child.Name == "CityBeacon" or child.Name == "PortBeacon" or child.Name == "LabBeacon" then
			-- V99 : phase depuis rest.Z. Plus de child.Position.Z 60 Hz
			-- (Position reconstruit un Vector3 monde apres create).
			-- rest est deja lu plus haut. Amplitude 0.05 / 0.18,
			-- frequence 2.8, * 0.05 inchanges. Recette feel N150
			-- — ne PAS merger c450. Distinct de V98 (CityWindows
			-- rest.X, elseif precedent). Distinct de V70 (Radar
			-- CFrame yaw). Distinct de V60 (cable Y nombres). Distinct
			-- de V100 (trail offset.Z, UnitModels.place —
			-- autre fichier). FactoryOutput / SiloWarning n'ont PAS
			-- de Position — ne pas les toucher. Un elseif, trois
			-- noms. Radar / Flag / Boom (V70) et cable (V60)
			-- inchanges. RestCFrame a la construction inchange.
			child.Transparency = 0.05 + (math.sin(time * 2.8 + rest.Z * 0.05) + 1) * 0.18
		elseif child.Name == "FactoryOutput" then
			child.Transparency = 0.12 + (math.sin(time * 3.2) + 1) * 0.12
		elseif child.Name == "SiloWarning" then
			child.Transparency = if math.sin(time * 4.5) > -0.25 then 0.05 else 0.6
		end
	end
end


--[[
	Hauteur du modele, pour poser l'etiquette juste au-dessus.

	Elle suit le niveau pour les trois batiments a paliers. Sans cela,
	l'etiquette d'une usine de niveau 3 se retrouvait plantee au milieu de sa
	propre cheminee — le modele avait grandi, pas la reference.
]]
function BuildingModels.heightOf(kind: number, level: number?): number
	return BuildingModels.authoredHeightOf(kind, level) * Config.WORLD_SCALE
end

-- Hauteur a l'echelle d'origine, avant application du facteur de monde.
function BuildingModels.authoredHeightOf(kind: number, level: number?): number
	local tier = math.clamp(level or 1, 1, 3)
	if kind == B.CITY then
		return if tier == 1 then 11 elseif tier == 2 then 16 else 28
	end
	if kind == B.FACTORY then
		return (HEIGHTS[B.FACTORY] or 13) + (tier - 1) * 3.6
	end
	if kind == B.PORT then
		return (HEIGHTS[B.PORT] or 9.5) + (tier - 1) * 2
	end
	return HEIGHTS[kind] or 8
end

--[[
	Recolore un modele existant. On ne recolore que ce qui portait deja la
	couleur de faction : les details gris et les accents lumineux doivent rester
	tels quels, sinon un port capture devient un bloc uniforme.
]]
function BuildingModels.recolor(model: Model, previous: Color3, color: Color3)
	for _, part in model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end

		if part.Color == previous then
			part.Color = color
		end
	end
end

return BuildingModels
