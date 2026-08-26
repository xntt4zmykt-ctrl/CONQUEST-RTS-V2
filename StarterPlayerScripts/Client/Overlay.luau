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
-- V57 : lift camion en nombre (deja cuit dans route.from / route.to).
-- path[i] reste au niveau chaussee ; on ajoute TRUCK_LIFT sans Vector3.
local TRUCK_LIFT = 0.8

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

	-- V78 + V79 + V80 + V81 : rotation cylindre plat cuite une fois (recette
	-- V75 footprintRot / feel N130 + N131 + N132 + N133). Plus de
	-- CFrame.Angles a chaque spawn (LaunchWake), despawn (LandingSplash)
	-- navire, arrivee camion (DeliveryPulse), ni explosion (Shockwave).
	-- fromEulerAnglesYXZ(0, 0, rad(90)) ≡ Angles(0, 0, 90°) (rx=0, ry=0 →
	-- Z seul). Wake Y + 0.12 / splash Y + 0.14 / shock PLAINS + 0.5
	-- inchanges. Tween Size/Transparency inchange. Skip missiles inchange.
	-- Distinct de V77 (Preview hover). Distinct de V75 (Preview, pas Overlay).
	-- Leftover V82 (Effects conquestPulse).
	self.wakeRot = CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))

	-- V113 : free-list Blast PAR overlay (pas global). Recette feel N165
	-- inline — ne PAS merger 6512. Leftover Parent = nil, pas Destroy.
	-- PointLight enfant FindFirstChildWhichIsA. Distinct de V112
	-- (Ground/Border par chunk, WorldRenderer). Distinct de V81
	-- (Shockwave wakeRot). Pas reentrant.
	self.blastFree = {} :: { Part }

	-- V114 : free-list BlastSmoke PAR overlay (pas blastFree). Recette
	-- feel N164 inline — ne PAS merger f293. Leftover Parent = nil,
	-- pas Destroy. Name BlastSmoke. Boucle i=1..5. Distinct de V113
	-- (Blast). Distinct de V81 (Shockwave wakeRot). Pas reentrant.
	self.smokeFree = {} :: { Part }

	-- V115 : free-list Shockwave PAR overlay (pas blastFree / smokeFree).
	-- Recette feel N163 inline — ne PAS merger df45. Leftover Parent =
	-- nil, pas Destroy. Name Shockwave. Euler N133 deja (wakeRot V81).
	-- Distinct de V113 (Blast). Distinct de V114 (BlastSmoke). Pas
	-- reentrant.
	self.shockFree = {} :: { Part }

	-- V116 : free-list DeliveryPulse PAR overlay (pas blastFree /
	-- smokeFree / shockFree). Recette feel N162 inline — ne PAS
	-- merger 076b. Leftover Parent = nil, pas Destroy. Name
	-- DeliveryPulse. Euler N132 deja (wakeRot V80). Distinct de
	-- V113 (Blast). Distinct de V114 (BlastSmoke). Distinct de
	-- V115 (Shockwave). Distinct de V117 (LandingSplash). Distinct
	-- de V118 (LaunchWake). Distinct de V119 (goldPopup goldFree).
	-- Pas reentrant.
	self.deliveryFree = {} :: { Part }

	-- V117 : free-list LandingSplash PAR overlay (pas blastFree /
	-- smokeFree / shockFree / deliveryFree). Recette feel N161
	-- inline — ne PAS merger 41d3. Leftover Parent = nil, pas
	-- Destroy. Name LandingSplash. Euler N131 deja (wakeRot V79).
	-- Distinct de V113 (Blast). Distinct de V114 (BlastSmoke).
	-- Distinct de V115 (Shockwave). Distinct de V116
	-- (DeliveryPulse). Distinct de V118 (LaunchWake). Distinct
	-- de V119 (goldPopup goldFree). Pas reentrant.
	self.splashFree = {} :: { Part }

	-- V118 : free-list LaunchWake PAR overlay (pas blastFree /
	-- smokeFree / shockFree / deliveryFree / splashFree / goldFree).
	-- Recette feel N160 inline — ne PAS merger d29b. Leftover
	-- Parent = nil, pas Destroy. Name LaunchWake. Euler N130 deja
	-- (wakeRot V78). Distinct de V113 (Blast). Distinct de V114
	-- (BlastSmoke). Distinct de V115 (Shockwave). Distinct de
	-- V116 (DeliveryPulse). Distinct de V117 (LandingSplash).
	-- Distinct de V119 (goldPopup goldFree). Pas reentrant.
	self.wakeFree = {} :: { Part }

	-- V119 : free-list GoldPopup PAR overlay (pas blastFree /
	-- smokeFree / shockFree / deliveryFree / splashFree / wakeFree).
	-- Recette feel N159 inline — ne PAS merger b63e. Leftover
	-- Parent = nil, pas Destroy. Name GoldPopup / Board. Arbre
	-- Billboard conserve (anchor + Board + TextLabel, pas recreer
	-- les enfants). Distinct de V118 (LaunchWake). Distinct de
	-- V117 (LandingSplash). Distinct de V116 (DeliveryPulse).
	-- Distinct de V115 (Shockwave). Distinct de V113 (Blast).
	-- Distinct de V114 (BlastSmoke). Pas reentrant. Evenement
	-- arrivee colis, pas 60 Hz.
	self.goldFree = {} :: { Part }

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
		local dx, dy, dz = segment.dx, segment.dy, segment.dz
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
			-- V63 : pose = translation * rot cuit. Plus de lookAt(deux Vector3)
			-- 60 Hz. Lerp nombres inchange (V62). Size inchange (API). Lift
			-- cuit inchange (V61). Cable / feuillage / houle / camion /
			-- unites inchanges (V60/V59/V58/V57/V56).
			local t = visible - shown / 2
			local cx = layer.ox + dx * t
			local cy = layer.oy + dy * t
			local cz = layer.oz + dz * t
			part.CFrame = CFrame.new(cx, cy, cz) * segment.rot
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
		local dx, dy, dz = direction.X, direction.Y, direction.Z
		local ox, oy, oz = origin.X, origin.Y, origin.Z
		-- V63 : orientation cuit une fois (grille HV, un axe ≈ 0).
		-- applyRouteProgress compose translation * rot, plus de lookAt 60 Hz.
		local rot = CFrame.lookAt(Vector3.zero, direction)

		-- Largeurs a l'echelle du monde : une chaussee de deux studs se perdrait
		-- sur une tuile qui en fait douze.
		local k = Config.WORLD_SCALE
		local liftAsphalt = 0.08 * k
		local liftStripe = 0.18 * k
		local shoulder = routePart(model, "Shoulder", Vector3.new(2.7 * k, 0.12 * k, length), Color3.fromRGB(39, 43, 48), Enum.Material.Concrete)
		shoulder.CFrame = frame
		local asphalt = routePart(model, "Road", Vector3.new(1.9 * k, 0.16 * k, length), Color3.fromRGB(52, 58, 66), Enum.Material.Asphalt)
		asphalt.CFrame = frame + Vector3.new(0, liftAsphalt, 0)
		local stripe = routePart(model, "CenterMark", Vector3.new(0.1 * k, 0.2 * k, length * 0.58), Color3.fromRGB(237, 207, 123), Enum.Material.Neon)
		stripe.Transparency = 0.28
		stripe.CFrame = frame + Vector3.new(0, liftStripe, 0)

		table.insert(segments, {
			-- Chaque calque garde sa largeur et sa hauteur propres : seule la
			-- longueur est animee, et la bande centrale reste plus courte que
			-- la chaussee qui la porte.
			-- V61 : lift cuit dans origin par calque (une fois).
			-- V62 : ox/oy/oz + dx/dy/dz cuits ici. applyRouteProgress n'additionne
			-- plus origin + direction * t a 60 Hz.
			-- V63 : rot cuit ici. applyRouteProgress n'appelle plus lookAt 60 Hz.
			layers = {
				{ part = shoulder, width = 2.7 * k, thickness = 0.12 * k, origin = origin, ox = ox, oy = oy, oz = oz, ratio = 1 },
				{ part = asphalt, width = 1.9 * k, thickness = 0.16 * k, origin = origin + Vector3.new(0, liftAsphalt, 0), ox = ox, oy = oy + liftAsphalt, oz = oz, ratio = 1 },
				{ part = stripe, width = 0.1 * k, thickness = 0.2 * k, origin = origin + Vector3.new(0, liftStripe, 0), ox = ox, oy = oy + liftStripe, oz = oz, ratio = 0.58 },
			},
			origin = origin,
			direction = direction,
			rot = rot,
			dx = dx,
			dy = dy,
			dz = dz,
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

	-- V64 : orientation camion cuite une fois par segment (grille HV, Y identique
	-- aux deux bouts — le lift 0.8 s'annule). stepInterpolation compose
	-- translation * segRot, plus de lookAt 60 Hz. Magnitude < 0.01 → rot
	-- precedente (ou identite au premier), jamais un lookAt degenere.
	local segRot: { CFrame } = {}
	for i = 1, #path - 1 do
		local d = path[i + 1] - path[i]
		if d.Magnitude < 0.01 then
			segRot[i] = if i > 1 then segRot[i - 1] else CFrame.new(0, 0, 0)
		else
			segRot[i] = CFrame.lookAt(Vector3.zero, d)
		end
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
		segRot = segRot,
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
	-- V119 : recycler GoldPopup. CFrame (tuile + y + 7 * WORLD_SCALE)
	-- + Board Size (ours 120×32 vs rival 80×22) + Text / TextSize /
	-- TextTransparency / TextStrokeTransparency AVANT Tween (un
	-- leftover CFrame = lift +5, Transparency 1 du popup precedent).
	-- Recette feel N159 inline — ne PAS merger b63e. Name GoldPopup /
	-- Board conserves. Arbre Billboard conserve (pas recreer Board
	-- ni TextLabel). Pas de pool partage avec Blast / BlastSmoke /
	-- Shockwave / DeliveryPulse / LandingSplash / LaunchWake. Ne pas
	-- nil les slots du pool (pop O(1) : [n] = nil). Distinct de V118
	-- (wakeFree). Distinct de V117 (splashFree). Distinct de V116
	-- (deliveryFree). Distinct de V115 (shockFree). Distinct de V113
	-- (blastFree). Distinct de V114 (smokeFree). Distinct de Effects
	-- floatingText (feel N158, autre fichier — fermee V120). Distinct
	-- de Effects tileFlash (feel N156, autre fichier — fermee V121). Distinct
	-- de Effects conquestPulse (feel N157, autre fichier — fermee V122). Distinct
	-- de BuildingModels BuildRing (feel N166, autre fichier — fermee V123). Distinct
	-- de HUD notify (feel N167, autre fichier — fermee V124). Delay
	-- 1.5 inchange. Tween lift + fade inchanges. ours = mine ~= false
	-- inchange. Ne pas modifier routePart. Ne pas changer Overlay.clear.
	local goldFree = self.goldFree
	local pn = #goldFree
	local anchor = if pn > 0 then goldFree[pn] else nil
	local board
	local text
	if anchor then
		goldFree[pn] = nil
		board = anchor:FindFirstChild("Board")
		text = if board then board:FindFirstChildWhichIsA("TextLabel") else nil
	else
		anchor = Instance.new("Part")
		anchor.Name = "GoldPopup"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		board = Instance.new("BillboardGui")
		board.Name = "Board"
		board.StudsOffset = Vector3.new(0, 1.5, 0)
		board.AlwaysOnTop = true
		board.Parent = anchor
		text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.FontFace = Theme.font.display
		text.TextColor3 = Theme.color.gold
		text.Parent = board
	end
	anchor.Name = "GoldPopup"
	anchor.CFrame = CFrame.new(base.X, y + 7 * Config.WORLD_SCALE, base.Z)
	anchor.Parent = self.root
	if board then
		board.Name = "Board"
		board.Size = UDim2.fromOffset(if ours then 120 else 80, if ours then 32 else 22)
	end
	if text then
		text.TextSize = if ours then 22 else 15
		text.TextStrokeTransparency = if ours then 0.35 else 0.7
		text.TextTransparency = if ours then 0 else 0.35
		-- "+1.24K or" plutot que "+1240" : meme format que le reste du jeu, et
		-- l'unite dit de quelle ressource il s'agit.
		text.Text = `+{Format.compact(gold)} or`
	end

	local lift = TweenService:Create(anchor, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame + Vector3.new(0, 5 * Config.WORLD_SCALE, 0),
	})
	lift:Play()
	if text then
		TweenService:Create(text, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end
	task.delay(1.5, function()
		anchor.Parent = nil
		goldFree[#goldFree + 1] = anchor
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
			-- V118 : recycler LaunchWake. Size (0.16, 2.5, 2.5) +
			-- Transparency 0.34 + Color 174,231,244 + CFrame AVANT
			-- Tween (un leftover Size = tween 9×9 / Transparency 1
			-- du spawn precedent). Recette feel N160 inline —
			-- ne PAS merger d29b. Name LaunchWake conserve. Euler
			-- N130 deja (wakeRot V78). Pas de pool partage avec
			-- Blast / BlastSmoke / Shockwave / DeliveryPulse /
			-- LandingSplash / GoldPopup. Ne pas nil les slots du pool (pop
			-- O(1) : [n] = nil). Skip missiles conserve. Distinct
			-- de V117 (splashFree). Distinct de V116 (deliveryFree).
			-- Distinct de V115 (shockFree). Distinct de V113
			-- (blastFree). Distinct de V114 (smokeFree). Distinct
			-- de V119 (goldFree). Distinct
			-- de V81 (Shockwave wakeRot). Flame Size (V111)
			-- inchangee. Ne pas modifier routePart.
			local wakeFree = self.wakeFree
			local pn = #wakeFree
			local wake = if pn > 0 then wakeFree[pn] else nil
			if wake then
				wakeFree[pn] = nil
			else
				wake = Instance.new("Part")
				wake.Name = "LaunchWake"
				wake.Shape = Enum.PartType.Cylinder
				wake.Anchored = true
				wake.CanCollide = false
				wake.CanTouch = false
				wake.CanQuery = false
				wake.CastShadow = false
				wake.Material = Enum.Material.Neon
				wake.TopSurface = Enum.SurfaceType.Smooth
				wake.BottomSurface = Enum.SurfaceType.Smooth
			end
			wake.Name = "LaunchWake"
			wake.Color = Color3.fromRGB(174, 231, 244)
			wake.Transparency = 0.34
			wake.Size = Vector3.new(0.16, 2.5, 2.5)
			-- V78 : translation * rot cuit. Plus de CFrame.Angles spawn.
			-- Recette feel N130. Y + 0.12 inchange. Distinct de V79
			-- (despawn, Y + 0.14). Distinct de DeliveryPulse (V80 +
			-- V116 recycle). Distinct de Shockwave (V81). Distinct
			-- de LandingSplash (V79 + V117 recycle). Wake recycle
			-- (V118).
			wake.CFrame = CFrame.new(origin.X, Config.OCEAN_LEVEL + 0.12, origin.Z) * self.wakeRot
			wake.Parent = self.root
			TweenService:Create(wake, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.16, 9, 9),
				Transparency = 1,
			}):Play()
			task.delay(0.8, function()
				wake.Parent = nil
				wakeFree[#wakeFree + 1] = wake
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
				-- V117 : recycler LandingSplash. Size (0.18, 3, 3) +
				-- Transparency 0.18 + Color 202,239,247 + CFrame AVANT
				-- Tween (un leftover Size = tween 15×15 / Transparency 1
				-- du despawn precedent). Recette feel N161 inline —
				-- ne PAS merger 41d3. Name LandingSplash conserve. Euler
				-- N131 deja (wakeRot V79). Pas de pool partage avec
				-- Blast / BlastSmoke / Shockwave / DeliveryPulse. Ne
				-- pas nil les slots du pool (pop O(1) : [n] = nil).
				-- Destroy modele navire conserve. Skip missiles
				-- conserve. Distinct de V116 (deliveryFree). Distinct
				-- de V115 (shockFree). Distinct de V113 (blastFree).
				-- Distinct de V114 (smokeFree). Distinct de V118
				-- (wakeFree). Distinct de V81 (Shockwave wakeRot).
				-- Flame Size (V111) inchangee.
				local splashFree = self.splashFree
				local pn = #splashFree
				local splash = if pn > 0 then splashFree[pn] else nil
				if splash then
					splashFree[pn] = nil
				else
					splash = Instance.new("Part")
					splash.Name = "LandingSplash"
					splash.Shape = Enum.PartType.Cylinder
					splash.Anchored = true
					splash.CanCollide = false
					splash.CanTouch = false
					splash.CanQuery = false
					splash.CastShadow = false
					splash.Material = Enum.Material.Neon
					splash.TopSurface = Enum.SurfaceType.Smooth
					splash.BottomSurface = Enum.SurfaceType.Smooth
				end
				splash.Name = "LandingSplash"
				splash.Color = Color3.fromRGB(202, 239, 247)
				splash.Transparency = 0.18
				splash.Size = Vector3.new(0.18, 3, 3)
				-- V79 : translation * rot cuit. Plus de CFrame.Angles despawn.
				-- Recette feel N131. Y + 0.14 inchange. Distinct de V78 (spawn,
				-- Y + 0.12, recycle V118). Distinct de DeliveryPulse (V80 + V116
				-- recycle). Distinct de Shockwave (V81). Splash recycle
				-- (V117).
				splash.CFrame = CFrame.new(last.X, Config.OCEAN_LEVEL + 0.14, last.Z) * self.wakeRot
				splash.Parent = self.root
				TweenService:Create(splash, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.18, 15, 15),
					Transparency = 1,
				}):Play()
				for _, piece in unit.visual.pieces do
					TweenService:Create(piece.part, TweenInfo.new(0.35), { Transparency = 1 }):Play()
				end
				task.delay(0.95, function()
					splash.Parent = nil
					splashFree[#splashFree + 1] = splash
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
			-- V116 : recycler DeliveryPulse. Size (0.22, 2.8, 2.8) +
			-- Transparency 0.28 + Color colorFor(slot) + CFrame AVANT
			-- Tween (un leftover Size = tween 11×11 / Transparency 1
			-- de l'arrivee precedente). Recette feel N162 inline —
			-- ne PAS merger 076b. Name DeliveryPulse conserve. Euler
			-- N132 deja (wakeRot V80). Pas de pool partage avec
			-- Blast / BlastSmoke / Shockwave. Ne pas nil les slots
			-- du pool (pop O(1) : [n] = nil). Camion Parent = nil
			-- conserve. Distinct de V115 (shockFree). Distinct de
			-- V113 (blastFree). Distinct de V114 (smokeFree). Distinct
			-- de V81 (Shockwave wakeRot). Distinct de V117
			-- (splashFree). Distinct de V118 (wakeFree). Flame Size
			-- (V111) inchangee.
			local deliveryFree = self.deliveryFree
			local pn = #deliveryFree
			local pulse = if pn > 0 then deliveryFree[pn] else nil
			if pulse then
				deliveryFree[pn] = nil
			else
				pulse = Instance.new("Part")
				pulse.Name = "DeliveryPulse"
				pulse.Shape = Enum.PartType.Cylinder
				pulse.Anchored = true
				pulse.CanCollide = false
				pulse.CanTouch = false
				pulse.CanQuery = false
				pulse.CastShadow = false
				pulse.Material = Enum.Material.Neon
				pulse.TopSurface = Enum.SurfaceType.Smooth
				pulse.BottomSurface = Enum.SurfaceType.Smooth
			end
			pulse.Name = "DeliveryPulse"
			pulse.Color = colorFor(route.slot)
			pulse.Transparency = 0.28
			pulse.Size = Vector3.new(0.22, 2.8, 2.8)
			-- V80 : translation * rot cuit. Plus de CFrame.Angles arrivee.
			-- Recette feel N132 — ne pas merger 5aa9. Distinct de V78
			-- (spawn, Y + 0.12) / V79 (despawn, Y + 0.14). Distinct de
			-- Shockwave (V81). Pulse recycle (V116). route.to deja un
			-- Vector3.
			pulse.CFrame = CFrame.new(route.to) * self.wakeRot
			pulse.Parent = self.root
			TweenService:Create(pulse, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.22, 11, 11),
				Transparency = 1,
			}):Play()
			task.delay(0.85, function()
				pulse.Parent = nil
				deliveryFree[#deliveryFree + 1] = pulse
			end)
			continue
		end
		-- V57 : lerp X/Y/Z en nombres. Plus de Vector3.new(0, 0.8, 0) × 2,
		-- ni (b - a), ni (a + dir * t), ni CFrame.new() identite par piece.
		-- V64 : pose = translation * rot cuit. Plus de lookAt(deux Vector3)
		-- 60 Hz. V72 : roues fromEulerAnglesYXZ, plus de CFrame.Angles.
		-- Unites : V65 yaw + V71 roulis. Chantier segment.rot inchange
		-- (V63). Radar / flag / boom inchanges (V70).
		local path = route.path
		local nSeg = #path - 1
		local scaled = delivery.progress * nSeg
		local floorScaled = math.floor(scaled)
		local segmentIndex = math.min(nSeg, floorScaled + 1)
		local segmentProgress = scaled - floorScaled
		local a = path[segmentIndex]
		local b = path[segmentIndex + 1]
		local ax, ay, az = a.X, a.Y + TRUCK_LIFT, a.Z
		local bx, by, bz = b.X, b.Y + TRUCK_LIFT, b.Z
		local dx, dy, dz = bx - ax, by - ay, bz - az
		local px = ax + dx * segmentProgress
		local py = ay + dy * segmentProgress
		local pz = az + dz * segmentProgress
		local frame = CFrame.new(px, py, pz) * route.segRot[segmentIndex]
		-- V72 : spin π×20 × progress, compose sur frame*offset. Plus de
		-- CFrame.Angles 60 Hz. fromEulerAnglesYXZ(spin, 0, 0) ≡
		-- Angles(spin, 0, 0) (ry=0, rz=0 → X seul). Garde Wheel inchangee.
		-- Pieces non-Wheel : frame * offset inchange. Roulis navire
		-- inchange (V71). Radar / flag / boom inchanges (V70).
		local spin = delivery.progress * math.pi * 20
		for _, piece in route.truck do
			if piece.part.Name == "Wheel" then
				piece.part.CFrame = frame * piece.offset * CFrame.fromEulerAnglesYXZ(spin, 0, 0)
			else
				piece.part.CFrame = frame * piece.offset
			end
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
		-- CFrame.new(position) par unite.
		-- V65 : pose = translation * yaw. Plus de lookAt(deux Vector3) 60 Hz.
		-- Immobile = lookX=0, lookZ=-1 → atan2(0, 1) = 0 → identite
		-- (meme pose que CFrame.new(x,y,z)). Extra missile inchange (V52).
		-- Camion segRot inchange (V64). Chantier segment.rot inchange (V63).
		-- V71 : roulis navire fromEulerAnglesYXZ, plus de CFrame.Angles.
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
		local frame = CFrame.new(worldX, py, worldZ) * CFrame.fromEulerAnglesYXZ(0, math.atan2(lookX, -lookZ), 0)
		if mag > 0.01 and not unit.isMissile then
			-- V71 : compose translation*yaw * euler. Plus de CFrame.Angles
			-- 60 Hz. fromEulerAnglesYXZ(rx, 0, rz) ≡ Angles(rx, 0, rz)
			-- (ry=0 → X puis Z). Amplitude 0.018 / 0.035 et frequences
			-- 1.7 / 2.1 inchangees. Garde mag / missile inchangee.
			-- Radar / flag / boom inchanges (V70). Yaw inchange (V65).
			-- Roues camion inchangees (V72). Immobile : zero compose.
			local rx = math.sin(now * 1.7 + unit.phase) * 0.018
			local rz = math.sin(now * 2.1 + unit.phase) * 0.035
			frame = frame * CFrame.fromEulerAnglesYXZ(rx, 0, rz)
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

	-- V113 : recycler Blast. Size (4,4,4) + Transparency 0.15 + Color +
	-- CFrame AVANT Tween (un leftover Size = rayon de la frappe
	-- precedente). Recette feel N165 inline — ne PAS merger 6512.
	-- Name Blast conserve. Pas de pool partage avec Shockwave / fumee.
	-- Ne pas nil les slots du pool (pop O(1) : [n] = nil). Distinct de
	-- V112 (Ground/Border, WorldRenderer). Distinct de V81 (Shockwave
	-- wakeRot). Distinct de V115 (shockFree). Distinct de V116
	-- (DeliveryPulse deliveryFree). Distinct de V117
	-- (LandingSplash splashFree). Distinct de V118 (LaunchWake
	-- wakeFree). Flame Size (V111) inchangee.
	local free = self.blastFree
	local n = #free
	local sphere = if n > 0 then free[n] else nil
	if sphere then
		free[n] = nil
	else
		sphere = Instance.new("Part")
		sphere.Name = "Blast"
		sphere.Shape = Enum.PartType.Ball
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.CanTouch = false
		sphere.CanQuery = false
		sphere.CastShadow = false
		sphere.Material = Enum.Material.Neon
	end
	sphere.Name = "Blast"
	sphere.Color = Color3.fromRGB(255, 190, 110)
	sphere.Transparency = 0.15
	sphere.Size = Vector3.new(4, 4, 4)
	sphere.CFrame = CFrame.new(ground.X, 14, ground.Z)
	sphere.Parent = self.root

	-- Onde horizontale : elle communique la portee bien mieux qu'une simple
	-- sphere et reste visible quand la camera regarde presque a la verticale.
	-- V115 : recycler Shockwave. Size (0.32, 5, 5) + Transparency 0.12 +
	-- Color 255,229,181 + CFrame AVANT Tween (un leftover Size = rayon
	-- de la frappe precedente). Recette feel N163 inline — ne PAS
	-- merger df45. Name Shockwave conserve. Euler N133 deja (wakeRot
	-- V81). Pas de pool partage avec Blast / BlastSmoke. Ne pas nil
	-- les slots du pool (pop O(1) : [n] = nil). Distinct de V113
	-- (Blast blastFree). Distinct de V114 (BlastSmoke smokeFree).
	-- Distinct de V81 (wakeRot). Distinct de V116 (DeliveryPulse
	-- deliveryFree). Distinct de V117 (LandingSplash splashFree).
	-- Distinct de V118 (LaunchWake wakeFree). Flame Size (V111)
	-- inchangee.
	local shockFree = self.shockFree
	local kn = #shockFree
	local shockwave = if kn > 0 then shockFree[kn] else nil
	if shockwave then
		shockFree[kn] = nil
	else
		shockwave = Instance.new("Part")
		shockwave.Name = "Shockwave"
		shockwave.Shape = Enum.PartType.Cylinder
		shockwave.Anchored = true
		shockwave.CanCollide = false
		shockwave.CanTouch = false
		shockwave.CanQuery = false
		shockwave.CastShadow = false
		shockwave.Material = Enum.Material.Neon
		shockwave.TopSurface = Enum.SurfaceType.Smooth
		shockwave.BottomSurface = Enum.SurfaceType.Smooth
	end
	shockwave.Name = "Shockwave"
	shockwave.Color = Color3.fromRGB(255, 229, 181)
	shockwave.Transparency = 0.12
	shockwave.Size = Vector3.new(0.32, 5, 5)
	-- V81 : translation * rot cuit. Plus de CFrame.Angles explosion.
	-- Recette feel N133 — ne pas merger bfcc. Distinct de V78 (spawn,
	-- Y + 0.12) / V79 (despawn, Y + 0.14) / V80 (arrivee camion).
	-- Distinct de Effects conquestPulse (V82). Y = PLAINS + 0.5.
	-- Sphere Blast recyclee (V113). Fumee recyclee (V114). Shockwave
	-- recyclee (V115).
	shockwave.CFrame = CFrame.new(ground.X, Config.TERRAIN_HEIGHT[Config.TERRAIN.PLAINS] + 0.5, ground.Z) * self.wakeRot
	shockwave.Parent = self.root
	TweenService:Create(shockwave, TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.32, worldRadius * 2.5, worldRadius * 2.5),
		Transparency = 1,
	}):Play()

	-- Colonne de fumee en volumes superposes. Elle est courte et stylisee pour
	-- rester lisible de loin sans texture de particules externe.
	-- V114 : recycler BlastSmoke. Size (5+i) + Transparency 0.22+i*0.07
	-- + Color + CFrame AVANT Tween (un leftover Size = tween * 2.1 de
	-- la frappe precedente). Recette feel N164 inline — ne PAS merger
	-- f293. Name BlastSmoke conserve. Pas de pool partage avec Blast /
	-- Shockwave. Ne pas nil les slots du pool (pop O(1) : [n] = nil).
	-- Distinct de V113 (Blast blastFree). Distinct de V115 (Shockwave
	-- shockFree). Distinct de V116 (DeliveryPulse deliveryFree).
	-- Distinct de V117 (LandingSplash splashFree). Distinct de
	-- V118 (LaunchWake wakeFree). Distinct de V81 (Shockwave
	-- wakeRot). Flame Size (V111) inchangee.
	local smokeFree = self.smokeFree
	for i = 1, 5 do
		local sn = #smokeFree
		local smoke = if sn > 0 then smokeFree[sn] else nil
		if smoke then
			smokeFree[sn] = nil
		else
			smoke = Instance.new("Part")
			smoke.Name = "BlastSmoke"
			smoke.Shape = Enum.PartType.Ball
			smoke.Anchored = true
			smoke.CanCollide = false
			smoke.CanTouch = false
			smoke.CanQuery = false
			smoke.CastShadow = false
			smoke.Material = Enum.Material.SmoothPlastic
			smoke.TopSurface = Enum.SurfaceType.Smooth
			smoke.BottomSurface = Enum.SurfaceType.Smooth
		end
		smoke.Name = "BlastSmoke"
		smoke.Color = Color3.fromRGB(82 + i * 7, 76 + i * 6, 71 + i * 5)
		smoke.Transparency = 0.22 + i * 0.07
		smoke.Size = Vector3.new(5 + i, 5 + i, 5 + i)
		smoke.CFrame = CFrame.new(ground.X + math.sin(i * 2.1) * 2, 7 + i * 5, ground.Z + math.cos(i * 1.7) * 2)
		smoke.Parent = self.root
		TweenService:Create(smoke, TweenInfo.new(1.7 + i * 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = smoke.CFrame + Vector3.new(0, 18 + i * 3, 0),
			Size = smoke.Size * 2.1,
			Transparency = 1,
		}):Play()
		task.delay(2.5, function()
			smoke.Parent = nil
			smokeFree[#smokeFree + 1] = smoke
		end)
	end

	TweenService:Create(sphere, TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(worldRadius * 2, worldRadius * 2, worldRadius * 2),
		Transparency = 1,
	}):Play()

	-- V113 : PointLight enfant reutilise. FindFirstChildWhichIsA, pas
	-- Instance.new a chaque frappe. Brightness / Range / Color
	-- reecrits (leftover Brightness = 0 apres Tween). Recette feel
	-- N165. BlastSmoke recyclee (V114). Shockwave recyclee (V115).
	local light = sphere:FindFirstChildWhichIsA("PointLight")
	if not light then
		light = Instance.new("PointLight")
		light.Parent = sphere
	end
	light.Brightness = 8
	light.Range = math.min(worldRadius * 2, 60)
	light.Color = Color3.fromRGB(255, 200, 120)
	TweenService:Create(light, TweenInfo.new(1.1), { Brightness = 0 }):Play()

	task.delay(1.3, function()
		sphere.Parent = nil
		free[#free + 1] = sphere
	end)
	task.delay(1, function()
		shockwave.Parent = nil
		shockFree[#shockFree + 1] = shockwave
	end)
end

return Overlay
