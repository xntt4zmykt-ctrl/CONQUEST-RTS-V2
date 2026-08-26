--!strict
--[[
	Nom et armee de chaque faction, poses sur son territoire.

	C'est l'information que CONQUEST affiche en permanence sur la
	carte, et elle change completement la lecture d'une partie : sans elle, il
	faut cliquer chaque voisin pour savoir lequel est dangereux. Avec, on voit
	d'un coup d'oeil ou est la grosse armee — et la reponse n'est presque jamais
	la plus grosse tache de couleur, ce qui est precisement l'interet.

	Deux choix de mise en oeuvre meritent d'etre expliques :

	  - **La taille du texte suit la taille de l'empire.** Le libelle est mesure
	    en studs et pas en pixels, donc il grandit avec le zoom comme une
	    inscription posee sur le sol, et une grande faction porte un grand nom.
	    Une taille fixe donnerait douze etiquettes identiques empilees sur les
	    petits pays du centre.

	  - **Le centre est recalcule par echantillonnage, pas a chaque conquete.**
	    Suivre le barycentre a l'incrementale obligerait a maintenir des sommes
	    par faction dans le chemin chaud des deltas de territoire, pour un
	    resultat que personne ne regarde a la tuile pres. Un balayage partiel
	    une fois par seconde coute moins cher et ne peut pas desynchroniser.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapGen = require(Shared:WaitForChild("MapGen"))
local Format = require(Shared:WaitForChild("Format"))
local Theme = require(Shared:WaitForChild("Theme"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))

local FactionLabels = {}
FactionLabels.__index = FactionLabels

export type FactionLabels = typeof(setmetatable({} :: any, FactionLabels))

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT

-- Une tuile sur trois dans chaque direction, soit un neuvieme de la carte par
-- passe. Largement assez pour un barycentre : l'erreur se compte en fractions
-- de tuile alors que l'etiquette fait des dizaines de studs de large.
local SAMPLE_STRIDE = 3

-- Cadence du recalcul. Un empire ne se deplace pas assez vite pour qu'on voie
-- la difference, et c'est dix fois moins de travail qu'un calcul par tick.
local REFRESH_SECONDS = 1

-- Une faction reduite a quelques tuiles n'a pas la place d'afficher son nom :
-- l'etiquette deborderait largement de son territoire.
local MIN_TILES = 12

local MAX_DISTANCE = 4000

-- N96 : surveyTerritories recycle (recette visual V49, hash table.clear).
-- Distinct de N95 (gainBuf arrays) et de N80 (contactBuf serveur).
-- Non reentrant — refresh synchrone unique. table.clear AVANT le scan
-- (leftover slot A = etiquette fantome apres removePlayer). Hash
-- slot→nombre : pas de truncate d'array. Retourner les pools. Overlay /
-- WorldRenderer n'appellent pas surveyTerritories.
local sumXBuf: { [number]: number } = {}
local sumYBuf: { [number]: number } = {}
local countBuf: { [number]: number } = {}

--=============================================================================
-- Construction
--=============================================================================

function FactionLabels.new(parent: Instance, terrain: buffer): FactionLabels
	local self = setmetatable({}, FactionLabels) :: any

	self.terrain = terrain
	self.labels = {}
	self.nextRefresh = 0

	local root = Instance.new("Folder")
	root.Name = "FactionLabels"
	root.Parent = parent
	self.root = root

	return self
end

--[[
	Cree (ou retrouve) l'etiquette d'une faction.

	L'ancre est une Part invisible : une BillboardGui a besoin d'un Adornee, et
	deplacer une Part coute moins cher que de detruire et recreer l'interface a
	chaque fois que la faction change de centre de gravite.
]]
local function ensureLabel(self: FactionLabels, slot: number)
	local existing = self.labels[slot]
	if existing then
		return existing
	end

	local anchor = Instance.new("Part")
	anchor.Name = `FactionAnchor{slot}`
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = self.root

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Parent = anchor

	local name = Instance.new("TextLabel")
	name.Name = "FactionName"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0, 0)
	name.Size = UDim2.fromScale(1, 0.62)
	name.FontFace = Theme.font.display
	name.TextScaled = true
	name.TextStrokeTransparency = 0.45
	name.TextStrokeColor3 = Color3.new(0, 0, 0)
	name.Parent = billboard

	local troops = Instance.new("TextLabel")
	troops.Name = "Troops"
	troops.BackgroundTransparency = 1
	troops.Position = UDim2.fromScale(0, 0.62)
	troops.Size = UDim2.fromScale(1, 0.38)
	troops.FontFace = Theme.font.bold
	troops.TextScaled = true
	troops.TextStrokeTransparency = 0.55
	troops.TextStrokeColor3 = Color3.new(0, 0, 0)
	troops.Parent = billboard

	local entry = { anchor = anchor, billboard = billboard, name = name, troops = troops }
	self.labels[slot] = entry
	return entry
end

--=============================================================================
-- Mise a jour
--=============================================================================

--[[
	Barycentre et taille de chaque faction, par echantillonnage de la carte.

	On renvoie aussi le compte echantillonne plutot que le vrai nombre de
	tuiles : c'est lui qui doit dimensionner l'etiquette, puisqu'il est mesure
	sur la meme grille que le centre qu'il accompagne.
]]
local function surveyTerritories(owner: buffer)
	table.clear(sumXBuf)
	table.clear(sumYBuf)
	table.clear(countBuf)

	for y = 0, H - 1, SAMPLE_STRIDE do
		local rowBase = y * W
		for x = 0, W - 1, SAMPLE_STRIDE do
			local slot = buffer.readu8(owner, rowBase + x)
			if slot ~= Config.NEUTRAL_SLOT then
				sumXBuf[slot] = (sumXBuf[slot] or 0) + x
				sumYBuf[slot] = (sumYBuf[slot] or 0) + y
				countBuf[slot] = (countBuf[slot] or 0) + 1
			end
		end
	end

	return sumXBuf, sumYBuf, countBuf
end

--[[
	Repositionne et reecrit toutes les etiquettes.

	`stats` et `roster` sont ceux que le serveur replique deja pour le HUD : on
	ne demande aucune donnee supplementaire au reseau pour afficher tout ceci.
]]
function FactionLabels.refresh(self: FactionLabels, owner: buffer, stats: any, roster: any)
	local sumX, sumY, counts = surveyTerritories(owner)

	for slot, entry in self.labels do
		if not counts[slot] then
			entry.anchor:Destroy()
			self.labels[slot] = nil
		end
	end

	for slot, count in counts do
		local info = roster and roster[slot]
		if not info or count * SAMPLE_STRIDE * SAMPLE_STRIDE < MIN_TILES then
			local stale = self.labels[slot]
			if stale then
				stale.anchor:Destroy()
				self.labels[slot] = nil
			end
			continue
		end

		local entry = ensureLabel(self, slot)

		local cx = sumX[slot] / count
		local cy = sumY[slot] / count
		local index = MapGen.toIndex(math.floor(cx), math.floor(cy))
		local base = WorldSpace.indexToWorld(index)
		local ground = WorldSpace.surfaceHeight(self.terrain, index)
		entry.anchor.CFrame = CFrame.new(base.X, ground + 6 * Config.WORLD_SCALE, base.Z)

		--[[
			La largeur suit la racine du territoire, pas le territoire lui-meme.

			Un empire cent fois plus grand ne doit pas porter un nom cent fois
			plus large — il couvrirait la moitie de la carte. La racine carree
			donne un rapport de dix, ce qui se lit encore comme une hierarchie
			sans ecraser le reste.
		]]
		-- Le libelle est mesure en studs : il doit grandir avec le monde, sinon
		-- un nom de pays devient un point sur une carte trente fois plus large.
		local k = Config.WORLD_SCALE
		local span = math.clamp(math.sqrt(count) * 3.4, 14, 70) * k
		entry.billboard.Size = UDim2.fromScale(span, span * 0.42)

		local color = Theme.factionColor(slot)
		entry.name.Text = info.name or `Faction {slot}`
		entry.name.TextColor3 = color

		local playerStats = stats and stats[slot]
		local troops = if playerStats then playerStats.troops else 0
		entry.troops.Text = Format.compact(troops)
		entry.troops.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45)
	end
end

--[[
	Cadence les rafraichissements. Appele a chaque image, il ne travaille qu'une
	fois par seconde.
]]
function FactionLabels.step(self: FactionLabels, owner: buffer, stats: any, roster: any)
	local now = os.clock()
	if now < self.nextRefresh then
		return
	end
	self.nextRefresh = now + REFRESH_SECONDS
	self:refresh(owner, stats, roster)
end

function FactionLabels.setVisible(self: FactionLabels, visible: boolean)
	for _, entry in self.labels do
		entry.billboard.Enabled = visible
	end
end

function FactionLabels.clear(self: FactionLabels)
	for slot, entry in self.labels do
		entry.anchor:Destroy()
		self.labels[slot] = nil
	end
end

return FactionLabels
