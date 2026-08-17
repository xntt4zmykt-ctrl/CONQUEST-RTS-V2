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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local BuildingModels = {}

local B = Config.BUILDING

local CONCRETE = Color3.fromRGB(158, 160, 165)
local DARK = Color3.fromRGB(62, 66, 74)
local GLASS = Color3.fromRGB(140, 210, 255)

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
	part.CastShadow = false
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.CFrame = CFrame.new(offset)
	part.Parent = parent
	return part
end

local function cylinder(parent: Instance, size: Vector3, offset: Vector3, color: Color3): Part
	local part = block(parent, size, offset, color)
	part.Shape = Enum.PartType.Cylinder
	-- Le cylindre de Roblox pointe le long de X : on le redresse.
	part.CFrame = CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
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
local function buildCapital(model: Model, color: Color3)
	block(model, Vector3.new(7, 12, 7), Vector3.new(0, 6, 0), color)
	block(model, Vector3.new(3, 16, 3), Vector3.new(-3.5, 8, -3.5), color)
	block(model, Vector3.new(3, 16, 3), Vector3.new(3.5, 8, 3.5), color)
	block(model, Vector3.new(9, 1.4, 9), Vector3.new(0, 12.6, 0), DARK)

	-- Mat et drapeau
	block(model, Vector3.new(0.5, 9, 0.5), Vector3.new(0, 17.5, 0), DARK, Enum.Material.Metal)
	local flag = block(model, Vector3.new(0.3, 3, 5), Vector3.new(0, 20, 2.6), color)
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
local function buildCity(model: Model, color: Color3)
	block(model, Vector3.new(3, 9, 3), Vector3.new(-1.8, 4.5, -1.8), color)
	block(model, Vector3.new(2.6, 6.5, 2.6), Vector3.new(2, 3.25, -1.4), color)
	block(model, Vector3.new(2.2, 11, 2.2), Vector3.new(0.4, 5.5, 2.2), color)
	block(model, Vector3.new(2, 4.5, 2), Vector3.new(-2.4, 2.25, 2), CONCRETE)

	-- Fenetres : une seule bande lumineuse par grappe, pas par tour.
	local windows = block(model, Vector3.new(2.4, 0.5, 2.4), Vector3.new(0.4, 8.5, 2.2), GLASS)
	windows.Material = Enum.Material.Neon

	block(model, Vector3.new(8, 0.5, 8), Vector3.new(0, 0.25, 0), DARK)
end

--[[
	Port : une jetee, un entrepot et une grue. La grue est ce qui distingue
	instantanement un port d'une ville, meme sans couleur.
]]
local function buildPort(model: Model, color: Color3)
	block(model, Vector3.new(9, 1, 6), Vector3.new(0, 0.5, 0), CONCRETE)
	block(model, Vector3.new(4, 4, 4), Vector3.new(-2.5, 3, 0), color)

	-- Grue : mat vertical + fleche horizontale + cable
	block(model, Vector3.new(0.7, 8, 0.7), Vector3.new(2.5, 5, 0), DARK, Enum.Material.Metal)
	block(model, Vector3.new(6, 0.6, 0.6), Vector3.new(4.2, 8.6, 0), DARK, Enum.Material.Metal)
	block(model, Vector3.new(0.25, 3, 0.25), Vector3.new(6.5, 6.8, 0), DARK, Enum.Material.Metal)

	local beacon = block(model, Vector3.new(0.8, 0.8, 0.8), Vector3.new(2.5, 9.2, 0), color)
	beacon.Material = Enum.Material.Neon
end

--[[
	Bunker : une masse basse et large, volontairement ecrasee. Sa silhouette
	doit dire "on ne passe pas" a l'oppose de la verticalite des villes.
]]
local function buildDefense(model: Model, color: Color3)
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
local function buildSilo(model: Model, color: Color3)
	block(model, Vector3.new(8, 1.5, 8), Vector3.new(0, 0.75, 0), CONCRETE, Enum.Material.Concrete)
	cylinder(model, Vector3.new(9, 5, 5), Vector3.new(0, 5, 0), CONCRETE)

	-- Ogive depassant du tube
	local warhead = block(model, Vector3.new(1.6, 4, 1.6), Vector3.new(0, 10, 0), Color3.fromRGB(230, 230, 230))
	warhead.Material = Enum.Material.Metal

	local tip = block(model, Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 12.2, 0), Color3.fromRGB(220, 70, 60))
	tip.Material = Enum.Material.Neon

	-- Trappe ouverte, aux couleurs de la faction
	block(model, Vector3.new(3, 0.4, 5.5), Vector3.new(-3.6, 7.4, 0), color, Enum.Material.Metal)
end

--[[
	Batterie SAM : un socle, un radar incline et deux rampes. L'inclinaison est
	ce qui la distingue du silo, strictement vertical.
]]
local function buildSam(model: Model, color: Color3)
	block(model, Vector3.new(7, 1.5, 7), Vector3.new(0, 0.75, 0), CONCRETE, Enum.Material.Concrete)
	block(model, Vector3.new(3, 2.5, 3), Vector3.new(0, 2.75, 0), color)

	-- Rampes inclinees
	local rail1 = block(model, Vector3.new(1, 5.5, 1), Vector3.new(-1.4, 5.4, 0), DARK, Enum.Material.Metal)
	rail1.CFrame = CFrame.new(-1.4, 5.4, 0) * CFrame.Angles(math.rad(-28), 0, 0)
	local rail2 = block(model, Vector3.new(1, 5.5, 1), Vector3.new(1.4, 5.4, 0), DARK, Enum.Material.Metal)
	rail2.CFrame = CFrame.new(1.4, 5.4, 0) * CFrame.Angles(math.rad(-28), 0, 0)

	-- Antenne radar
	local dish = block(model, Vector3.new(3.4, 0.4, 2.4), Vector3.new(0, 7.4, -1.4), Color3.fromRGB(210, 215, 220))
	dish.CFrame = CFrame.new(0, 7.4, -1.4) * CFrame.Angles(math.rad(-40), 0, 0)
	dish.Material = Enum.Material.Metal

	local light = block(model, Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, 8.4, 0), Color3.fromRGB(120, 255, 160))
	light.Material = Enum.Material.Neon
end

local BUILDERS: { [number]: (Model, Color3) -> () } = {
	[B.CAPITAL] = buildCapital,
	[B.CITY] = buildCity,
	[B.PORT] = buildPort,
	[B.DEFENSE] = buildDefense,
	[B.SILO] = buildSilo,
	[B.SAM] = buildSam,
}

-- Hauteur approximative de chaque modele : sert a placer l'etiquette juste
-- au-dessus sans la faire flotter ni la noyer dans la geometrie.
local HEIGHTS: { [number]: number } = {
	[B.CAPITAL] = 23,
	[B.CITY] = 11,
	[B.PORT] = 9.5,
	[B.DEFENSE] = 5.5,
	[B.SILO] = 13,
	[B.SAM] = 9,
}

--=============================================================================
-- API
--=============================================================================

--[[
	Construit le modele d'un batiment, ancre a `position` (le sol de la tuile).
	Le modele est renvoye non parente : l'appelant decide ou il vit.
]]
function BuildingModels.create(kind: number, color: Color3, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = `Building{kind}`

	local builder = BUILDERS[kind]
	if builder then
		builder(model, color)
	else
		block(model, Vector3.new(3, 6, 3), Vector3.new(0, 3, 0), color)
	end

	-- Les modeles sont construits autour de l'origine puis deplaces d'un bloc :
	-- c'est ce qui permet d'ecrire chaque forme en coordonnees locales lisibles.
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CFrame = part.CFrame + position
		end
	end

	return model
end

function BuildingModels.heightOf(kind: number): number
	return HEIGHTS[kind] or 8
end

--[[
	Recolore un modele existant. On ne recolore que ce qui portait deja la
	couleur de faction : les details gris et les accents lumineux doivent rester
	tels quels, sinon un port capture devient un bloc uniforme.
]]
function BuildingModels.recolor(model: Model, previous: Color3, color: Color3)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Color == previous then
			part.Color = color
		end
	end
end

return BuildingModels
