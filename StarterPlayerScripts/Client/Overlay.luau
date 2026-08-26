--!strict
--[[
	Calque des entites dans le monde 3D : batiments, navires, missiles,
	explosions.

	Le terrain est de la geometrie fusionnee (voir WorldRenderer) et ne peut
	donc pas porter d'information ponctuelle : un bloc couvre parfois cinquante
	tuiles. Tout ce qui est localise vit donc ici, sous forme de vrais objets
	poses dans le monde.

	Le nombre d'elements reste petit — quelques centaines de batiments, quelques
	dizaines de navires — ce qui rend l'approche par instances viable ici, alors
	qu'elle serait catastrophique pour les 40 000 tuiles du terrain.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BuildingDefs = require(Shared:WaitForChild("BuildingDefs"))
local BuildingModels = require(script.Parent.BuildingModels)
local UnitModels = require(script.Parent.UnitModels)
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))
local RailPath = require(Shared:WaitForChild("RailPath"))
local Format = require(Shared:WaitForChild("Format"))
local Types = require(Shared:WaitForChild("Types"))

local Overlay = {}
Overlay.__index = Overlay

export type Overlay = typeof(setmetatable({} :: any, Overlay))

local colorFor = Theme.factionColor
local DARK = Color3.fromRGB(29, 35, 43)
-- V56 : conversion tuile → monde en nombres (meme formule que WorldSpace.tileToWorld).
-- Le helper allouerait un Vector3 par unite / frame ; il reste le point unique
-- serveur / batiments / splash — on ne le change pas.
local TILE = Config.TILE_SIZE
local HALF_W = Config.WORLD_WIDTH / 2
local HALF_D = Config.WORLD_DEPTH / 2
local TILE_HALF = TILE / 2

--=============================================================================
-- Construction
--=============================================================================

function Overlay.new(parent: Instance, terrain: buffer): Overlay
	local self = setmetatable({}, Overlay) :: any

	self.terrain = terrain
	self.buildings = {}
	self.counts = {}
	-- Notre propre faction, pour distinguer nos livraisons de celles des autres.
	self.mySlot = 0
	self.routes = {}
	self.units = {}
	self.seen = {}
	-- Les batiments deja presents a l'arrivee ne s'animent pas : voir trente
	-- chantiers demarrer en meme temps a la connexion serait absurde. Seuls
	-- ceux poses apres ce delai sont mis en scene.
	self.animateFrom = os.clock() + 3

	local root = Instance.new("Folder")
	root.Name = "Entities"
	root.Parent = parent
	self.root = root

	return self
end

function Overlay.clear(self: Overlay)
	table.clear(self.counts)
	for _, part in self.buildings do
		part:Destroy()
	end
	for _, unit in self.units do
		unit.visual.model:Destroy()
	end
	for _, route in self.routes do
		route.model:Destroy()
	end
	table.clear(self.buildings)
	table.clear(self.units)
	table.clear(self.routes)
	table.clear(self.seen)
end

--=============================================================================
-- Batiments
--=============================================================================

--[[
	Un batiment est un vrai petit modele 3D pose sur le relief, surmonte d'une
	etiquette toujours face camera.

	Le modele donne la presence et la lisibilite de pres ; l'etiquette garantit
	qu'on identifie le batiment meme completement dezoome, ou le modele ne ferait
	plus que quelques pixels.
]]
local function makeBuilding(
	parent: Instance,
	index: number,
	kind: number,
	slot: number,
	level: number,
	terrain: buffer
): Model
	local def = BuildingDefs.get(kind)
	local color = colorFor(slot)

	local base = WorldSpace.indexToWorld(index)
	local ground = WorldSpace.surfaceHeight(terrain, index)
	local model = BuildingModels.create(kind, color, Vector3.new(base.X, ground, base.Z), level)
	model.Name = `Building{index}`

	-- L'etiquette a besoin d'un ancrage : le premier bloc du modele fait
	-- l'affaire et evite d'ajouter une Part uniquement pour la porter.
	local anchor = model:FindFirstChildWhichIsA("BasePart")
	if anchor then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Marker"
		local size = if kind == Config.BUILDING.CAPITAL then 32 else 22
		billboard.Size = UDim2.fromOffset(size, size)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 1400
		-- Positionnee en absolu depuis le sol, pas depuis l'ancre : le premier
		-- bloc n'est pas au meme endroit selon le modele.
		billboard.StudsOffsetWorldSpace =
			Vector3.new(base.X, ground + BuildingModels.heightOf(kind, level) + 3, base.Z) - anchor.Position
		billboard.Parent = anchor

		local label = Instance.new("TextLabel")
		label.Name = "Symbol"
		label.BackgroundColor3 = Theme.color.surface
		label.BackgroundTransparency = 0.08
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Theme.font.bold
		label.TextScaled = true
		--[[
			Le niveau est ecrit a cote du symbole, pour tout batiment a paliers.

			C'est la seule chose qui rend l'empilement lisible : deux usines
			empilees n'occupent qu'une case et ressemblent a une seule usine. Sans
			ce chiffre, rien a l'ecran ne distingue un reseau qui produit le double
			d'un reseau ordinaire. Reserve auparavant aux villes, alors que le port
			et l'usine ont des paliers eux aussi.
		]]
		label.Text = if def
			then `{def.symbol}{if level > 1 and BuildingDefs.isUpgradable(kind) then level else ""}`
			else "?"
		label.TextColor3 = color
		label.Parent = billboard
		Theme.corner(label, Theme.radius.pill)

		local outline = Instance.new("UIStroke")
		outline.Color = color
		outline.Transparency = 0.15
		outline.Thickness = 1
		outline.Parent = label
	end

	model:SetAttribute("Kind", kind)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("Level", level)
	model:SetAttribute("TintR", color.R)
	model:SetAttribute("TintG", color.G)
	model:SetAttribute("TintB", color.B)
	model.Parent = parent
	return model
end

local function routePart(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	Retrace toutes les routes d'une usine.

	Une usine dessert plusieurs villes : on efface donc ses routes existantes
	avant de les redessiner, plutot que de tenir un diff par ville. Le nombre
	de routes reste petit et le recalcul n'a lieu qu'a la pose ou a la capture
	d'un batiment.
]]
function Overlay.syncFactoryRoutes(self: Overlay, factoryIndex: number, links: { number }?, slot: number)
	for key, route in self.routes do
		if route.factory == factoryIndex then
			route.model:Destroy()
			self.routes[key] = nil
		end
	end

	for _, cityIndex in links or {} do
		self:buildFactoryRoute(factoryIndex, cityIndex, slot)
	end
end

--[[
	Applique l'avancement d'un chantier de voie.

	Un tronçon n'est visible que sur la portion deja construite : il grandit
	depuis son origine au lieu de grandir depuis son centre, sinon la route
	pousserait par les deux bouts a la fois.
]]
local function applyRouteProgress(construction: any, progress: number)
	local covered = construction.total * math.clamp(progress, 0, 1)

	for _, segment in construction.segments do
		local visible = math.clamp(covered - segment.startsAt, 0, segment.length)
		for _, layer in segment.layers do
			local part = layer.part
			--[[
				La taille suit TOUJOURS l'avancement, meme a zero.

				Premiere version : a l'arret on se contentait de rendre la Part
				transparente en lui laissant sa longueur finale. Invisible a
				l'ecran, donc sans consequence visuelle — mais l'etat mentait, et
				tout ce qui lit la geometrie (un test, une mesure de budget, un
				futur calcul d'emprise) voyait une route complete la ou il n'y
				avait rien.
			]]
			local shown = math.max(0.01, visible * layer.ratio)
			part.Size = Vector3.new(layer.width, layer.thickness, shown)
			local centre = segment.origin + segment.direction * (visible - shown / 2)
			part.CFrame = CFrame.lookAt(centre, centre + segment.direction) + Vector3.new(0, layer.lift, 0)
			part.Transparency = if visible <= 0.01
				then 1
				elseif layer.ratio < 1 then 0.28
				else 0
		end
	end
end

--[[
	Trace une liaison logistique entre deux gares.

	Le trace suit la grille : quatre directions, aucune diagonale, et le moins de
	virages possible (voir Shared/RailPath). Avant, c'etait une courbe de Bezier
	avec un coude arbitraire — une belle ligne qui partait en travers des cases
	alors que tout le reste du jeu, frontieres comprises, est aligne dessus.

	Le chemin est recalcule ici a partir du terrain plutot que replique : il ne
	depend que de deux indices de case et de la carte, que le client possede
	deja. Une voie ne coute donc pas un octet de reseau.
]]
function Overlay.buildFactoryRoute(self: Overlay, factoryIndex: number, cityIndex: number, slot: number)
	local tiles = RailPath.find(self.terrain, factoryIndex, cityIndex)
	if not tiles or #tiles < 2 then
		return
	end

	local roadY = WorldSpace.surfaceHeight(self.terrain, factoryIndex) + 0.38

	local model = Instance.new("Model")
	model.Name = `LogisticsRoute{factoryIndex}`
	model.Parent = self.root

	local function worldAt(index: number): Vector3
		local base = WorldSpace.indexToWorld(index)
		return Vector3.new(base.X, roadY, base.Z)
	end

	--[[
		Un tronçon droit = un jeu de Parts, pas une Part par case.

		C'est ce qui rend le trace abordable : une liaison de cent cases dessinee
		case par case couterait trois cents Parts. Et c'est justement parce que
		l'algorithme evite les virages qu'il y a si peu de tronçons a produire —
		la penalite de virage paie deux fois, en lisibilite et en budget.
	]]
	local runs = RailPath.runs(tiles)
	local tileSize = Config.TILE_SIZE

	--[[
		Les tronçons sont conserves pour pouvoir etre construits PROGRESSIVEMENT.

		Une voie qui apparait d'un bloc ne dit pas qu'on vient de la batir : elle
		a l'air d'avoir toujours ete la. En la faisant sortir de l'usine et
		ramper vers la gare, le joueur voit son investissement se realiser — et
		il voit surtout OU va sa route, ce qu'un trace fini ne raconte plus.
	]]
	local segments: { any } = {}
	local totalLength = 0

	for _, run in runs do
		local a = worldAt(run.fromIndex)
		local b = worldAt(run.toIndex)
		local span = b - a
		if span.Magnitude < 0.01 then
			continue
		end

		-- On prolonge d'une demi-case a chaque bout : sinon deux tronçons
		-- perpendiculaires laissent un trou carre visible dans le virage.
		local length = span.Magnitude + tileSize
		local frame = CFrame.lookAt(a + span * 0.5, b)
		local direction = span.Unit
		local origin = a - direction * (tileSize / 2)

		-- Largeurs a l'echelle du monde : une chaussee de deux studs se perdrait
		-- sur une tuile qui en fait douze.
		local k = Config.WORLD_SCALE
		local shoulder = routePart(model, "Shoulder", Vector3.new(2.7 * k, 0.12 * k, length), Color3.fromRGB(39, 43, 48), Enum.Material.Concrete)
		shoulder.CFrame = frame
		local asphalt = routePart(model, "Road", Vector3.new(1.9 * k, 0.16 * k, length), Color3.fromRGB(52, 58, 66), Enum.Material.Asphalt)
		asphalt.CFrame = frame + Vector3.new(0, 0.08 * k, 0)
		local stripe = routePart(model, "CenterMark", Vector3.new(0.1 * k, 0.2 * k, length * 0.58), Color3.fromRGB(237, 207, 123), Enum.Material.Neon)
		stripe.Transparency = 0.28
		stripe.CFrame = frame + Vector3.new(0, 0.18 * k, 0)

		table.insert(segments, {
			-- Chaque calque garde sa largeur et sa hauteur propres : seule la
			-- longueur est animee, et la bande centrale reste plus courte que
			-- la chaussee qui la porte.
			layers = {
				{ part = shoulder, width = 2.7 * k, thickness = 0.12 * k, lift = 0, ratio = 1 },
				{ part = asphalt, width = 1.9 * k, thickness = 0.16 * k, lift = 0.08 * k, ratio = 1 },
				{ part = stripe, width = 0.1 * k, thickness = 0.2 * k, lift = 0.18 * k, ratio = 0.58 },
			},
			origin = origin,
			direction = direction,
			length = length,
			startsAt = totalLength,
		})
		totalLength += length
	end

	--[[
		La construction ne se joue que pour une voie posee PENDANT la partie.

		A la connexion, toutes les usines deja presentes creent leur voie d'un
		coup ; les voir toutes ramper en meme temps serait absurde. C'est le meme
		garde-fou que pour les chantiers de batiments.
	]]
	if #segments > 0 and totalLength > 0 and os.clock() >= self.animateFrom then
		-- Vitesse constante plutot que duree fixe : une voie de dix cases se
		-- construit vite, une de cent prend son temps. L'inverse donnerait
		-- l'impression que la longueur ne coute rien.
		local construction = {
			progress = 0,
			duration = math.clamp(totalLength / Config.ROUTE_BUILD_SPEED, 0.35, 3),
			segments = segments,
			total = totalLength,
		}
		applyRouteProgress(construction, 0)
		self.pendingConstruction = construction
	end

	-- Le convoi suit les memes coins que la voie : il tourne a angle droit au
	-- lieu de couper au travers.
	local path: { Vector3 } = { worldAt(tiles[1]) }
	for _, run in runs do
		table.insert(path, worldAt(run.toIndex))
	end

	local from = path[1]
	local to = path[#path]

	--[[
		Le camion EST le colis : il n'existe visuellement que pendant une
		livraison reelle, commandee par le serveur (voir onTradeEvent). Hors
		livraison la route reste vide — un camion qui tournerait en boucle
		ferait croire a un flux continu qui n'existe plus.
	]]
	local truckModel = Instance.new("Model")
	truckModel.Name = "CargoTruck"
	truckModel.Parent = nil
	local truck = {}
	local function truckPart(name: string, size: Vector3, color: Color3, offset: CFrame, material: Enum.Material?): Part
		local part = routePart(truckModel, name, size, color, material or Enum.Material.Metal)
		part.CastShadow = true
		part.CFrame = CFrame.lookAt(from + Vector3.new(0, 0.8, 0), to) * offset
		table.insert(truck, { part = part, offset = offset })
		return part
	end
	truckPart("Chassis", Vector3.new(1.55, 0.28, 2.9), DARK, CFrame.new(0, 0.35, 0))
	truckPart("Container", Vector3.new(1.45, 1.05, 1.75), Color3.fromRGB(255, 196, 72), CFrame.new(0, 0.94, 0.45))
	truckPart("Cab", Vector3.new(1.45, 0.9, 0.9), colorFor(slot), CFrame.new(0, 0.82, -0.95))
	local windshield = truckPart("Windshield", Vector3.new(1.15, 0.36, 0.08), Color3.fromRGB(125, 210, 235), CFrame.new(0, 1.02, -1.42), Enum.Material.Glass)
	windshield.Transparency = 0.18
	for sideLight = -1, 1, 2 do
		local lamp = truckPart("Headlight", Vector3.new(0.28, 0.24, 0.08), Color3.fromRGB(255, 239, 176), CFrame.new(sideLight * 0.48, 0.72, -1.47), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = lamp.Color
		light.Brightness = 0.8
		light.Range = 8
		light.Parent = lamp
	end
	for side = -1, 1, 2 do
		for axle = -1, 1, 2 do
			local wheel = truckPart("Wheel", Vector3.new(0.3, 0.48, 0.48), Color3.fromRGB(18, 21, 25), CFrame.new(side * 0.78, 0.28, axle * 0.88))
			wheel.Shape = Enum.PartType.Cylinder
		end
	end

	-- Cle composite : une usine peut avoir plusieurs routes simultanees.
	self.routes[factoryIndex * 100000 + cityIndex] = {
		factory = factoryIndex,
		model = model,
		truck = truck,
		truckModel = truckModel,
		from = from + Vector3.new(0, 0.8, 0),
		to = to + Vector3.new(0, 0.8, 0),
		path = path,
		slot = slot,
		delivery = nil,
		-- Chantier en cours, s'il y en a un. Voir applyRouteProgress.
		construction = self.pendingConstruction,
	}
	self.pendingConstruction = nil
end

--[[
	Evenement de commerce terrestre, envoye par le serveur.

	  "dispatch" (usine, gare, slot, trajetTicks) — un colis part : le camion
	  apparait au depart de la voie et roule pendant `trajetTicks` ticks.

	  "arrival" (gare, _, slot, or) — le colis est livre : l'or monte au-
	  dessus de la gare. Le retrait du camion est pilote localement par la fin
	  du trajet, pas par cet evenement, pour que le vehicule ne s'efface pas
	  en plein virage si le reseau a du retard.
]]
function Overlay.onTradeEvent(self: Overlay, action: string, a: number, b: number, slot: number, value: number)
	if action == "dispatch" then
		local route = self.routes[a * 100000 + b]
		if not route then
			-- La voie n'est pas encore dessinee chez nous : le colis arrivera
			-- quand meme, seule l'animation manque.
			return
		end
		route.delivery = {
			progress = 0,
			duration = math.max(value / Config.TICK_RATE, 0.1),
		}
		route.truckModel.Parent = route.model
	elseif action == "arrival" then
		self:goldPopup(a, value, slot == self.mySlot)
	end
end

--[[
	"+X or" flottant au-dessus d'une gare, la signature d'une livraison
	reussie — le seul retour du commerce terrestre, exactement comme dans le
	regles CONQUEST.
]]
--[[
	Notre slot, pour savoir quelles livraisons nous concernent.

	Il n'est pas connu a la construction de la couche : le client apprend son
	identite apres avoir rejoint. D'ou ce setter plutot qu'un parametre.
]]
function Overlay.setLocalSlot(self: Overlay, slot: number)
	self.mySlot = slot
end

function Overlay.goldPopup(self: Overlay, tileIndex: number, gold: number, mine: boolean?)
	local base = WorldSpace.indexToWorld(tileIndex)
	local y = WorldSpace.surfaceHeight(self.terrain, tileIndex)

	local anchor = Instance.new("Part")
	anchor.Name = "GoldPopup"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(base.X, y + 7 * Config.WORLD_SCALE, base.Z)
	anchor.Parent = self.root

	--[[
		Notre livraison se lit, celle du voisin se devine.

		Sur une carte a vingt-six usines, sept cents colis arrivent en dix
		minutes. Les afficher tous a la meme taille noyait le seul chiffre qui
		compte pour le joueur — le sien — au milieu du bruit des autres. Les
		livraisons etrangeres restent visibles, parce que voir un rival
		s'enrichir est une information, mais elles ne se disputent plus
		l'attention.
	]]
	local ours = mine ~= false
	local board = Instance.new("BillboardGui")
	board.Name = "Board"
	board.Size = UDim2.fromOffset(if ours then 120 else 80, if ours then 32 else 22)
	board.StudsOffset = Vector3.new(0, 1.5, 0)
	board.AlwaysOnTop = true
	board.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.FontFace = Theme.font.display
	text.TextSize = if ours then 22 else 15
	text.TextColor3 = Theme.color.gold
	text.TextStrokeTransparency = if ours then 0.35 else 0.7
	text.TextTransparency = if ours then 0 else 0.35
	-- "+1.24K or" plutot que "+1240" : meme format que le reste du jeu, et
	-- l'unite dit de quelle ressource il s'agit.
	text.Text = `+{Format.compact(gold)} or`
	text.Parent = board

	local lift = TweenService:Create(anchor, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame + Vector3.new(0, 5 * Config.WORLD_SCALE, 0),
	})
	lift:Play()
	TweenService:Create(text, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.5, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

--[[
	Nombre de batiments par type pour une faction.

	Le resolveur de placement partage en a besoin pour calculer le prix courant :
	sans lui, le fantome ne saurait pas si le joueur a les moyens et afficherait
	vert alors que le serveur refuse. Le decompte est maintenu a l'incrementale
	dans applyBuildingDelta — le recalculer a chaque frame de survol couterait un
	balayage complet des batiments soixante fois par seconde.
]]
local EMPTY_COUNTS: { [number]: number } = {}

function Overlay.buildingCounts(self: Overlay, slot: number): { [number]: number }
	-- Table partagee plutot qu'une allocation par frame : cette fonction est
	-- appelee a chaque image tant que le mode Construire est arme.
	return self.counts[slot] or EMPTY_COUNTS
end

--[[
	Ajoute (ou retire) un batiment du decompte par faction.

	Le compteur suit des unites et non des niveaux : c'est bien le nombre de
	batiments possedes qui pilote l'inflation des couts.
]]
function Overlay.tally(self: Overlay, slot: number?, kind: number?, sign: number)
	if not slot or not kind or kind == 0 then
		return
	end
	local bucket = self.counts[slot]
	if not bucket then
		bucket = {}
		self.counts[slot] = bucket
	end
	bucket[kind] = math.max(0, (bucket[kind] or 0) + sign)
end

function Overlay.applyBuildingDelta(self: Overlay, deltas: { Types.BuildingSnapshot })
	for _, entry in deltas do
		local existing = self.buildings[entry.index]
		local level = entry.level or 1

		-- Le batiment qui occupait la tuile disparait du decompte quoi qu'il
		-- arrive ensuite : destruction, capture ou remplacement.
		if existing then
			self:tally(existing:GetAttribute("Slot") :: number?, existing:GetAttribute("Kind") :: number?, -1)
		end
		if entry.kind ~= 0 then
			self:tally(entry.slot, entry.kind, 1)
		end

		if entry.kind == 0 then
			self:syncFactoryRoutes(entry.index, nil, 0)
			if existing then
				existing:Destroy()
				self.buildings[entry.index] = nil
			end
			continue
		end

		-- Un batiment capture change de couleur, pas de forme : reconstruire tout
		-- le modele a chaque prise serait du gaspillage, et les prises sont
		-- frequentes en fin de partie.
		if
			existing
			and existing:GetAttribute("Kind") == entry.kind
			and existing:GetAttribute("Level") == level
		then
			local previous = Color3.new(
				existing:GetAttribute("TintR") :: number,
				existing:GetAttribute("TintG") :: number,
				existing:GetAttribute("TintB") :: number
			)
			local next = colorFor(entry.slot)
			BuildingModels.recolor(existing, previous, next)
			existing:SetAttribute("TintR", next.R)
			existing:SetAttribute("TintG", next.G)
			existing:SetAttribute("TintB", next.B)
			existing:SetAttribute("Slot", entry.slot)

			local anchor = existing:FindFirstChildWhichIsA("BasePart")
			local marker = anchor and anchor:FindFirstChild("Marker")
			local label = marker and marker:FindFirstChild("Symbol")
			if label and label:IsA("TextLabel") then
				label.TextColor3 = next
			end
			if entry.kind == Config.BUILDING.FACTORY then
				existing:SetAttribute("Routes", if entry.links then #entry.links else 0)
				self:syncFactoryRoutes(entry.index, entry.links, entry.slot)
			end
			continue
		end

		if existing then
			existing:Destroy()
		end

		local model = makeBuilding(self.root, entry.index, entry.kind, entry.slot, level, self.terrain)
		self.buildings[entry.index] = model
		if entry.kind == Config.BUILDING.FACTORY then
			model:SetAttribute("Routes", if entry.links then #entry.links else 0)
			self:syncFactoryRoutes(entry.index, entry.links, entry.slot)
		end

		if os.clock() >= self.animateFrom then
			local base = WorldSpace.indexToWorld(entry.index)
			local ground = WorldSpace.surfaceHeight(self.terrain, entry.index)
			BuildingModels.playConstruction(model, Vector3.new(base.X, ground + 0.4, base.Z))
		end
	end
end

function Overlay.buildingAt(self: Overlay, index: number): (number?, number?, number?, number?)
	local model = self.buildings[index]
	if not model then
		return nil, nil, nil, nil
	end
	return
		model:GetAttribute("Kind") :: number?,
		model:GetAttribute("Slot") :: number?,
		model:GetAttribute("Level") :: number?,
		model:GetAttribute("Routes") :: number?
end

--=============================================================================
-- Unites
--=============================================================================

-- V52 : applyUnits hoist trackUnit + extra missile mute (recette boatSnapBuf inner).
-- Distinct de V26 (payload serveur) et du refactor Vector2.
-- Non reentrant — un seul applyUnits / lot. Navire : extra reste nil.
-- Insert : poser { tx, ty } une fois (copie, jamais l'alias snapshot).
-- Deja suivi : muter tx/ty, jamais remplacer unit.extra.
-- V55 : targetX/Y + currentX/Y nombres (recette extra mute). Vector2 immuable
-- aurait force un Vector2.new a chaque lot (10 Hz) et a chaque lerp (60 Hz).
-- Insert : poser les quatre nombres une fois. Update : muter targetX/Y.
-- Distinct de V52 (extra) / V54 (HUD sort). V56 ferme Vector3/CFrame 60 Hz
-- dans stepInterpolation (unites), pas ici.
-- Pas de RemoteFunction. HUD / UnitModels / serveur non touches.
local function trackUnit(
	self: Overlay,
	id: number,
	slot: number,
	kind: number,
	x: number,
	y: number,
	isMissile: boolean,
	extra: any?
)
	local unit = self.units[id]
	if not unit then
		local visual = if isMissile
			then UnitModels.createMissile(self.root, slot, kind)
			else UnitModels.createBoat(self.root, slot, kind)
		local ownedExtra: any? = nil
		if isMissile and extra then
			ownedExtra = { tx = extra.tx, ty = extra.ty }
		end
		unit = {
			visual = visual,
			currentX = x,
			currentY = y,
			targetX = x,
			targetY = y,
			isMissile = isMissile,
			phase = (id % 31) / 31 * math.pi * 2,
			extra = ownedExtra,
		}
		self.units[id] = unit
		if not isMissile then
			local origin = WorldSpace.tileToWorld(x, y)
			local wake = routePart(self.root, "LaunchWake", Vector3.new(0.16, 2.5, 2.5), Color3.fromRGB(174, 231, 244), Enum.Material.Neon)
			wake.Shape = Enum.PartType.Cylinder
			wake.Transparency = 0.34
			wake.CFrame = CFrame.new(origin.X, Config.OCEAN_LEVEL + 0.12, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
			TweenService:Create(wake, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.16, 9, 9),
				Transparency = 1,
			}):Play()
			task.delay(0.8, function()
				if wake.Parent then
					wake:Destroy()
				end
			end)
		end
	elseif isMissile then
		if extra then
			local owned = unit.extra
			if owned == nil then
				unit.extra = { tx = extra.tx, ty = extra.ty }
			else
				owned.tx = extra.tx
				owned.ty = extra.ty
			end
		end
	else
		unit.extra = nil
	end
	unit.targetX = x
	unit.targetY = y
	self.seen[id] = true
end

--[[
	Les instantanes arrivent a 10 Hz. On stocke la position cible et on
	interpole a chaque frame, sinon les navires avancent par saccades visibles.
]]
function Overlay.applyUnits(self: Overlay, boats: { Types.BoatSnapshot }, missiles: { Types.MissileSnapshot })
	table.clear(self.seen)

	for _, boat in boats do
		trackUnit(self, boat.id, boat.slot, boat.kind, boat.x, boat.y, false)
	end

	for _, missile in missiles do
		-- Le snapshot (missileSnapBuf) porte deja tx/ty : le passer comme
		-- extra n'alloue pas. trackUnit copie / mute, jamais d'alias.
		trackUnit(self, missile.id, missile.slot, missile.kind, missile.x, missile.y, true, missile)
	end

	-- Toute unite absente de l'instantane a disparu cote serveur.
	for id, unit in self.units do
		if not self.seen[id] then
			if not unit.isMissile then
				local last = WorldSpace.tileToWorld(unit.currentX, unit.currentY)
				local splash = routePart(self.root, "LandingSplash", Vector3.new(0.18, 3, 3), Color3.fromRGB(202, 239, 247), Enum.Material.Neon)
				splash.Shape = Enum.PartType.Cylinder
				splash.Transparency = 0.18
				splash.CFrame = CFrame.new(last.X, Config.OCEAN_LEVEL + 0.14, last.Z) * CFrame.Angles(0, 0, math.rad(90))
				TweenService:Create(splash, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.18, 15, 15),
					Transparency = 1,
				}):Play()
				for _, piece in unit.visual.pieces do
					TweenService:Create(piece.part, TweenInfo.new(0.35), { Transparency = 1 }):Play()
				end
				task.delay(0.95, function()
					if splash.Parent then
						splash:Destroy()
					end
					if unit.visual.model.Parent then
						unit.visual.model:Destroy()
					end
				end)
			else
				unit.visual.model:Destroy()
			end
			self.units[id] = nil
		end
	end
end

function Overlay.stepInterpolation(self: Overlay, dt: number)
	local alpha = math.min(1, dt * 9)
	local now = os.clock()

	--[[
		Les camions ne roulent que pendant une livraison reelle, cadencee par le
		serveur. En fin de trajet, le vehicule s'efface et la gare pulse : le
		flux economique reste lisible dans le monde, mais il dit desormais la
		verite — un camion visible est un colis qui arrive, pas une decoration.
	]]
	--[[
		Chantiers de voie : la route sort de l'usine et rampe vers la gare.

		Pilote ici plutot que par des delais chaines : la boucle d'images est
		deja le seul endroit ou le temps avance cote client, et un chantier
		interrompu par une capture disparait avec sa route sans laisser de
		minuterie orpheline derriere lui.
	]]
	for _, route in self.routes do
		local construction = route.construction
		if not construction then
			continue
		end
		construction.progress += dt / construction.duration
		applyRouteProgress(construction, construction.progress)
		if construction.progress >= 1 then
			route.construction = nil
		end
	end

	for _, route in self.routes do
		local delivery = route.delivery
		if not delivery then
			continue
		end
		delivery.progress += dt / delivery.duration
		if delivery.progress >= 1 then
			route.delivery = nil
			route.truckModel.Parent = nil
			local pulse = routePart(self.root, "DeliveryPulse", Vector3.new(0.22, 2.8, 2.8), colorFor(route.slot), Enum.Material.Neon)
			pulse.Shape = Enum.PartType.Cylinder
			pulse.Transparency = 0.28
			pulse.CFrame = CFrame.new(route.to) * CFrame.Angles(0, 0, math.rad(90))
			TweenService:Create(pulse, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.22, 11, 11),
				Transparency = 1,
			}):Play()
			task.delay(0.85, function()
				if pulse.Parent then
					pulse:Destroy()
				end
			end)
			continue
		end
		local scaled = delivery.progress * (#route.path - 1)
		local segmentIndex = math.min(#route.path - 1, math.floor(scaled) + 1)
		local segmentProgress = scaled - math.floor(scaled)
		local a = route.path[segmentIndex] + Vector3.new(0, 0.8, 0)
		local b = route.path[segmentIndex + 1] + Vector3.new(0, 0.8, 0)
		local direction = b - a
		local position = a + direction * segmentProgress
		local frame = CFrame.lookAt(position, position + direction)
		for _, piece in route.truck do
			local spin = if piece.part.Name == "Wheel" then CFrame.Angles(delivery.progress * math.pi * 20, 0, 0) else CFrame.new()
			piece.part.CFrame = frame * piece.offset * spin
		end
	end

	for _, model in self.buildings do
		BuildingModels.animate(model, now, dt)
	end

	for _, unit in self.units do
		-- V55 : lerp numerique. Vector2.current += aurait alloue 60 Hz.
		unit.currentX += (unit.targetX - unit.currentX) * alpha
		unit.currentY += (unit.targetY - unit.currentY) * alpha

		local x, y = unit.currentX, unit.currentY
		-- V56 : X/Z monde en nombres. Plus de tileToWorld / Vector3.Unit /
		-- CFrame.new(position) par unite. Un seul lookAt. Immobile = regard -Z
		-- (meme pose que CFrame.new(x,y,z)). Extra missile inchange (V52).
		local worldX = x * TILE - HALF_W + TILE_HALF
		local worldZ = y * TILE - HALF_D + TILE_HALF

		local height
		if unit.isMissile then
			-- Trajectoire en cloche : un missile qui rase le sol ne se lit pas,
			-- alors que c'est l'evenement le plus spectaculaire de la partie.
			-- L'altitude se deduit de la distance restante, donc elle retombe
			-- naturellement a zero au point d'impact.
			local remaining = 80
			if unit.extra then
				remaining = math.sqrt((unit.extra.tx - x) ^ 2 + (unit.extra.ty - y) ^ 2)
			end
			local approach = math.clamp(remaining / 60, 0, 1)
			height = 25 + math.sin(approach * math.pi * 0.5) * 95
		else
			height = Config.OCEAN_LEVEL + 1
		end

		local bob = if unit.isMissile then 0 else math.sin(now * 2.4 + unit.phase) * 0.24
		local py = height + bob
		local dx = unit.targetX - unit.currentX
		local dy = unit.targetY - unit.currentY
		local mag = math.sqrt(dx * dx + dy * dy)
		local lookX = if mag > 0.01 then dx else 0
		local lookZ = if mag > 0.01 then dy else -1
		local frame = CFrame.lookAt(Vector3.new(worldX, py, worldZ), Vector3.new(worldX + lookX, py, worldZ + lookZ))
		if mag > 0.01 and not unit.isMissile then
			frame *= CFrame.Angles(math.sin(now * 1.7 + unit.phase) * 0.018, 0, math.sin(now * 2.1 + unit.phase) * 0.035)
		end
		UnitModels.place(unit.visual, frame, now + unit.phase, if mag > 0.01 then mag else 0)
	end
end

--=============================================================================
-- Effets
--=============================================================================

--[[
	Onde de choc nucleaire : une sphere qui se dilate jusqu'au rayon reel de la
	frappe, donc le joueur juge la zone d'effet a l'oeil.
]]
function Overlay.explosion(self: Overlay, x: number, y: number, radius: number)
	local ground = WorldSpace.tileToWorld(x, y)
	local worldRadius = radius * Config.TILE_SIZE

	local sphere = Instance.new("Part")
	sphere.Name = "Blast"
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanTouch = false
	sphere.CanQuery = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.Neon
	sphere.Color = Color3.fromRGB(255, 190, 110)
	sphere.Transparency = 0.15
	sphere.Size = Vector3.new(4, 4, 4)
	sphere.CFrame = CFrame.new(ground.X, 14, ground.Z)
	sphere.Parent = self.root

	-- Onde horizontale : elle communique la portee bien mieux qu'une simple
	-- sphere et reste visible quand la camera regarde presque a la verticale.
	local shockwave = routePart(self.root, "Shockwave", Vector3.new(0.32, 5, 5), Color3.fromRGB(255, 229, 181), Enum.Material.Neon)
	shockwave.Shape = Enum.PartType.Cylinder
	shockwave.Transparency = 0.12
	shockwave.CFrame = CFrame.new(ground.X, Config.TERRAIN_HEIGHT[Config.TERRAIN.PLAINS] + 0.5, ground.Z) * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(shockwave, TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.32, worldRadius * 2.5, worldRadius * 2.5),
		Transparency = 1,
	}):Play()

	-- Colonne de fumee en volumes superposes. Elle est courte et stylisee pour
	-- rester lisible de loin sans texture de particules externe.
	for i = 1, 5 do
		local smoke = routePart(self.root, "BlastSmoke", Vector3.new(5 + i, 5 + i, 5 + i), Color3.fromRGB(82 + i * 7, 76 + i * 6, 71 + i * 5), Enum.Material.SmoothPlastic)
		smoke.Shape = Enum.PartType.Ball
		smoke.Transparency = 0.22 + i * 0.07
		smoke.CFrame = CFrame.new(ground.X + math.sin(i * 2.1) * 2, 7 + i * 5, ground.Z + math.cos(i * 1.7) * 2)
		TweenService:Create(smoke, TweenInfo.new(1.7 + i * 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = smoke.CFrame + Vector3.new(0, 18 + i * 3, 0),
			Size = smoke.Size * 2.1,
			Transparency = 1,
		}):Play()
		task.delay(2.5, function()
			if smoke.Parent then
				smoke:Destroy()
			end
		end)
	end

	TweenService:Create(sphere, TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(worldRadius * 2, worldRadius * 2, worldRadius * 2),
		Transparency = 1,
	}):Play()

	local light = Instance.new("PointLight")
	light.Brightness = 8
	light.Range = math.min(worldRadius * 2, 60)
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Parent = sphere
	TweenService:Create(light, TweenInfo.new(1.1), { Brightness = 0 }):Play()

	task.delay(1.3, function()
		sphere:Destroy()
	end)
	task.delay(1, function()
		if shockwave.Parent then
			shockwave:Destroy()
		end
	end)
end

return Overlay
