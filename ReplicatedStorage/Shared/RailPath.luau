--!strict
--[[
	Trace des voies ferrees, regle CONQUEST.

	Le probleme qu'on corrige : les liaisons logistiques etaient des courbes de
	Bezier tirees d'un point a un autre, avec un coude arbitraire pour ne pas
	"ressembler a une ligne de debug". Le resultat partait dans tous les sens et
	ignorait completement la grille — alors que TOUT le reste du jeu est aligne
	sur la case : les frontieres, les batiments, les blocs de terrain.

	L'algorithme CONQUEST tient en trois choix, et c'est leur
	combinaison qui produit des voies droites :

	  1. **Quatre directions, aucune diagonale.** Une voie ne peut aller que
	     nord, sud, est ou ouest. Elle suit donc forcement les aretes des cases.

	  2. **Un changement de direction coute cher** (TURN_PENALTY). C'est la
	     piece maitresse. Sans elle, un A* a cout uniforme produit un escalier :
	     tous les chemins en escalier ont le meme cout, et l'algorithme en
	     choisit un au hasard. Avec elle, aller tout droit puis tourner une
	     seule fois devient strictement moins cher que dix petits paliers.

	  3. **Une heuristique surponderee** (HEURISTIC_WEIGHT). L'A* cesse d'etre
	     optimal et devient franchement directif : il fonce vers la cible au
	     lieu d'explorer le voisinage. On y perd un cout theorique negligeable
	     et on y gagne un ordre de grandeur en temps de calcul.

	Le tout est deterministe et ne depend que du terrain, donc le client
	recalcule le trace lui-meme a partir des liaisons deja repliquees : une voie
	ne coute pas un octet de reseau.
]]

local Config = require(script.Parent.Config)
local MapGen = require(script.Parent.MapGen)
local Heap = require(script.Parent.Heap)

local RailPath = {}

local W = Config.MAP_WIDTH
local H = Config.MAP_HEIGHT
local OCEAN = Config.TERRAIN.OCEAN

--[[
	Couts. Les valeurs viennent CONQUEST et se tiennent entre elles :
	le detour vaut la peine tant qu'il economise un virage, et un virage vaut
	trois cases de detour.
]]
local STEP_COST = 1
local TURN_PENALTY = 3
-- Traverser l'eau reste possible — c'est un pont — mais assez cher pour qu'un
-- contournement par la terre soit toujours prefere quand il existe.
local WATER_PENALTY = 5
local HEURISTIC_WEIGHT = 2

--[[
	Garde-fou : une recherche qui explose ne doit jamais figer une image.

	Le cas qui declenche ce plafond est reel et pas rare : une liaison qui longe
	une cote sur cent cases paie la penalite d'eau a chaque pas, donc A* part
	explorer tout l'arriere-pays a la recherche d'un contournement terrestre qui
	n'existe pas. Le budget saute avant qu'il ne conclue.

	Au-dela, on ne renonce pas — on retombe sur un trace en L (voir
	fallbackPath). Ne rien tracer laisserait une usine visiblement connectee
	dans les chiffres et reliee a rien a l'ecran, ce qui est bien pire qu'un
	trace grossier.
]]
local MAX_EXPANDED = 24000

--=============================================================================
-- Recherche
--=============================================================================

--[[
	Le pas precedent, sous forme de delta d'indice.

	La carte etant un tableau plat en lignes, un pas vers l'est vaut +1 et un
	pas vers le sud vaut +largeur : comparer deux deltas d'indice compare donc
	directement deux directions, sans jamais decoder x et y. C'est ce qui rend
	le test de virage gratuit dans la boucle chaude.

	Attention au piege : +1 depuis la derniere colonne "avance" vers la premiere
	colonne de la ligne suivante. Les voisins sont donc filtres sur x et y, pas
	sur l'indice.
]]
local function isWaterAt(terrain: buffer, index: number): boolean
	return buffer.readu8(terrain, index) == OCEAN
end

--[[
	Trace de repli : un L, horizontal puis vertical.

	Toujours calculable, toujours aligne sur la grille, exactement deux tronçons
	droits. Ce n'est pas le plus joli mais il a la seule propriete qui compte
	ici : il existe toujours.
]]
local function fallbackPath(from: number, to: number): { number }
	local x1, y1 = MapGen.fromIndex(from)
	local x2, y2 = MapGen.fromIndex(to)

	local path = { from }
	local stepX = if x2 > x1 then 1 else -1
	while x1 ~= x2 do
		x1 += stepX
		table.insert(path, MapGen.toIndex(x1, y1))
	end

	local stepY = if y2 > y1 then 1 else -1
	while y1 ~= y2 do
		y1 += stepY
		table.insert(path, MapGen.toIndex(x1, y1))
	end

	return path
end

--[[
	Trace une voie de `from` a `to`. Renvoie la liste des cases traversees,
	extremites comprises. Ne renvoie nil que sur une entree invalide : une cible
	atteignable produit toujours un trace, au pire celui de repli.
]]
function RailPath.find(terrain: buffer, from: number, to: number): { number }?
	if from == to then
		return { from }
	end
	if from < 0 or from >= Config.TILE_COUNT or to < 0 or to >= Config.TILE_COUNT then
		return nil
	end

	local goalX, goalY = MapGen.fromIndex(to)

	local cameFrom: { [number]: number } = {}
	local bestCost: { [number]: number } = { [from] = 0 }
	-- Delta d'indice par lequel on est arrive sur une case : sert a savoir si
	-- le pas suivant est un virage.
	local arrivedBy: { [number]: number } = {}

	local heap = Heap.new()
	Heap.push(heap, from, 0)

	local expanded = 0

	while not Heap.isEmpty(heap) do
		local current = Heap.pop(heap)
		if not current then
			break
		end
		if current == to then
			break
		end

		expanded += 1
		if expanded > MAX_EXPANDED then
			return fallbackPath(from, to)
		end

		local cx, cy = MapGen.fromIndex(current)
		local currentCost = bestCost[current] or 0
		local incoming = arrivedBy[current]

		for dir = 1, 4 do
			local nx, ny = cx, cy
			if dir == 1 then
				nx += 1
			elseif dir == 2 then
				nx -= 1
			elseif dir == 3 then
				ny += 1
			else
				ny -= 1
			end

			if nx < 0 or nx >= W or ny < 0 or ny >= H then
				continue
			end

			local neighbor = MapGen.toIndex(nx, ny)
			local delta = neighbor - current

			local stepCost = if isWaterAt(terrain, neighbor) then STEP_COST + WATER_PENALTY else STEP_COST
			if incoming and incoming ~= delta then
				stepCost += TURN_PENALTY
			end

			local tentative = currentCost + stepCost
			local known = bestCost[neighbor]
			if known == nil or tentative < known then
				bestCost[neighbor] = tentative
				cameFrom[neighbor] = current
				arrivedBy[neighbor] = delta

				local remaining = math.abs(nx - goalX) + math.abs(ny - goalY)
				Heap.push(heap, neighbor, tentative + HEURISTIC_WEIGHT * remaining)
			end
		end
	end

	if bestCost[to] == nil then
		return fallbackPath(from, to)
	end

	local reversed = { to }
	local node = to
	while node ~= from do
		local previous = cameFrom[node]
		if not previous then
			-- Chaine rompue : plutot qu'un tronçon faux, on repart sur le L.
			return fallbackPath(from, to)
		end
		node = previous
		table.insert(reversed, node)
	end

	local path = table.create(#reversed)
	for i = #reversed, 1, -1 do
		table.insert(path, reversed[i])
	end
	return path
end

--=============================================================================
-- Segments droits
--=============================================================================

export type Run = {
	fromIndex: number,
	toIndex: number,
	-- Longueur en cases, extremites comprises.
	length: number,
	horizontal: boolean,
}

--[[
	Regroupe les cases consecutives de meme direction en tronçons droits.

	C'est l'etape qui rend le rendu abordable : une voie de cent cases dessinee
	case par case couterait cent Parts, alors que la meme voie tracee par
	tronçons en coute une poignee — et c'est precisement parce que
	l'algorithme evite les virages qu'il y a si peu de tronçons a produire.
]]
function RailPath.runs(path: { number }): { Run }
	local out: { Run } = {}
	if #path < 2 then
		return out
	end

	local startIndex = path[1]
	local previous = path[1]
	local currentDelta: number? = nil

	for i = 2, #path do
		local node = path[i]
		local delta = node - previous

		if currentDelta ~= nil and delta ~= currentDelta then
			local x1, y1 = MapGen.fromIndex(startIndex)
			local x2, y2 = MapGen.fromIndex(previous)
			table.insert(out, {
				fromIndex = startIndex,
				toIndex = previous,
				length = math.abs(x2 - x1) + math.abs(y2 - y1) + 1,
				horizontal = y1 == y2,
			})
			startIndex = previous
		end

		currentDelta = delta
		previous = node
	end

	local x1, y1 = MapGen.fromIndex(startIndex)
	local x2, y2 = MapGen.fromIndex(previous)
	table.insert(out, {
		fromIndex = startIndex,
		toIndex = previous,
		length = math.abs(x2 - x1) + math.abs(y2 - y1) + 1,
		horizontal = y1 == y2,
	})

	return out
end

RailPath.TURN_PENALTY = TURN_PENALTY
RailPath.WATER_PENALTY = WATER_PENALTY

return RailPath
