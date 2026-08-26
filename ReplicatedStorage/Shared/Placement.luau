--!strict
--[[
	Resolution d'un emplacement de construction.

	Le principe, repris d'CONQUEST : **un clic est une intention, pas une
	coordonnee**. Le joueur designe une direction, le moteur trouve la meilleure
	tuile valide autour et construit la. On ne refuse jamais un clic pour une
	raison de position.

	Ce qui a change et pourquoi : l'ancienne validation renvoyait `(false,
	raison)` sur huit conditions differentes — hors territoire, deja occupe, trop
	proche, pas cotier... Le joueur passait son temps a se battre contre son
	curseur, cliquait, lisait une erreur, recliquait deux tuiles plus loin. Il ne
	reste plus que trois refus possibles, et aucun n'est positionnel :

	  - le batiment n'est pas debloque (ere) ;
	  - il n'y a pas assez d'or ;
	  - il n'existe litteralement aucune tuile valide a portee.

	Ce module est **partage** entre client et serveur. C'est indispensable : la
	validation locale et la validation autoritaire etaient deux implementations
	distinctes de la meme regle, et elles divergeaient — le fantome vert refuse
	par le serveur etait un bug structurel, pas un accident. Ici les deux camps
	executent le meme code sur les memes donnees, via une interface d'acces
	minimale (`Context`).
]]

local Config = require(script.Parent.Config)
local MapGen = require(script.Parent.MapGen)
local BuildingDefs = require(script.Parent.BuildingDefs)
local Eras = require(script.Parent.Eras)

local Placement = {}

local B = Config.BUILDING

-- V47 : validTiles recycle (recette ctxBuf / V40). Distinct de ctxBuf
-- (record ownerAt/buildingAt) et de stationBuf (V39). Non reentrant —
-- resolve synchrone unique. Early-out kind/index/owner → emptyTileBuf
-- (JAMAIS d'insert). Retourner candBuf est licite uniquement parce que
-- resolve lit tiles[1] tout de suite. Truncate leftover AVANT BFS
-- (queue) et AVANT le sort candidats. placeScratch distinct de
-- GameState.scratch. Overlay / Preview n'appellent pas validTiles.
local blockBuf: { number } = table.create(32)
local candBuf: { number } = table.create(32)
local queueBuf: { number } = table.create(64)
local visitBuf: { [number]: true } = {}
local emptyTileBuf: { number } = table.create(0)
local placeScratch = table.create(4, 0)

--[[
	Tout ce dont la resolution a besoin de la partie.

	Le serveur branche ses buffers, le client ses calques de rendu. Aucun des
	deux n'a besoin de connaitre l'autre.
]]
export type Context = {
	slot: number,
	era: number,
	gold: number,
	terrain: buffer,
	ownerAt: (index: number) -> number,
	-- Renvoie (kind, slot, level) du batiment pose sur la tuile, ou nil.
	buildingAt: (index: number) -> (number?, number?, number?),
}

export type Resolution = {
	-- "build" : poser un nouveau batiment. "upgrade" : faire monter d'un niveau
	-- celui qui est deja la.
	action: string,
	tile: number,
	price: number,
	level: number?,
}

--=============================================================================
-- Couts
--=============================================================================

--[[
	Nombre de batiments deja possedes qui comptent dans l'inflation d'un type.

	Le port et l'usine partagent leur compteur (voir Config.BUILD_COST_GROUPS) :
	les deux axes economiques puisent dans le meme budget.
]]
function Placement.costUnits(counts: { [number]: number }, kind: number): number
	local group = Config.BUILD_COST_GROUPS[kind]
	if not group then
		return counts[kind] or 0
	end
	local total = 0
	for _, other in group do
		total += counts[other] or 0
	end
	return total
end

--[[
	Prix courant d'un batiment.

	Doublement borne : 1x, 2x, 4x puis 8x pour toujours. Les trois premiers sont
	bon marche, ensuite ameliorer devient plus rentable que multiplier.
	`extra` sert a interroger le prix du n-ieme suivant sans le construire.
]]
function Placement.priceFor(counts: { [number]: number }, kind: number, buildCostModifier: number, extra: number?): number
	local def = BuildingDefs.get(kind)
	if not def then
		return math.huge
	end

	local units = Placement.costUnits(counts, kind) + (extra or 0)
	-- 2^units plafonne : au-dela du plafond, l'exposant n'est plus evalue, ce
	-- qui evite un depassement silencieux sur une partie tres longue.
	local multiplier = if units >= 32 then Config.BUILD_COST_CAP_MULT else math.min(Config.BUILD_COST_CAP_MULT, 2 ^ units)

	return math.floor(def.cost * multiplier * buildCostModifier)
end

--[[
	Prix d'une amelioration.

	Volontairement egal au prix du batiment suivant du meme type : ameliorer et
	construire coutent pareil, donc le joueur arbitre sur le seul critere qui
	compte — a-t-il besoin de couvrir une zone de plus, ou d'intensifier ce
	qu'il tient deja ? La ville garde ses paliers nommes et leurs prix propres.
]]
function Placement.upgradePriceFor(
	counts: { [number]: number },
	kind: number,
	level: number,
	buildCostModifier: number
): number
	if kind == B.CITY then
		local tier = Config.CITY_LEVELS[level]
		if not tier or not tier.upgradeCost then
			return math.huge
		end
		return math.floor(tier.upgradeCost * buildCostModifier)
	end
	return Placement.priceFor(counts, kind, buildCostModifier)
end

function Placement.upgradeRequiredEra(kind: number, level: number): number
	if kind == B.CITY then
		local tier = Config.CITY_LEVELS[level + 1]
		return if tier then tier.requiredEra else math.huge
	end
	-- Les autres paliers ne sont pas verrouilles par une ere : leur cout suffit.
	return 1
end

--=============================================================================
-- Recherche
--=============================================================================

local function radiusFor(def: BuildingDefs.BuildingDef): number
	return if def.coastalOnly then Config.BUILD_SNAP_RADIUS_COASTAL else Config.BUILD_SNAP_RADIUS
end

--[[
	Toutes les tuiles ou ce batiment peut atterrir, triees par distance au clic.

	Parcours en largeur **connexe** a travers le territoire du joueur : une
	enclave separee par des terres ennemies n'est jamais atteignable, meme
	proche a vol d'oiseau. C'est ce qui fait que le placement respecte la
	topologie du front au lieu de teleporter un batiment par-dessus l'ennemi.
]]
function Placement.validTiles(ctx: Context, index: number, kind: number): { number }
	local def = BuildingDefs.get(kind)
	if not def or not def.buildable then
		return emptyTileBuf
	end
	if index < 0 or index >= Config.TILE_COUNT then
		return emptyTileBuf
	end
	-- Seul filtre dur restant : on part de son propre territoire. Cliquer chez
	-- le voisin n'est pas une erreur de precision, c'est une autre intention.
	if ctx.ownerAt(index) ~= ctx.slot then
		return emptyTileBuf
	end

	local radius = radiusFor(def)
	local radius2 = radius * radius
	local ox, oy = MapGen.fromIndex(index)

	-- Batiments susceptibles de bloquer une tuile candidate. On les collecte une
	-- fois : la liste est courte, alors que rescanner le disque d'espacement
	-- pour chaque candidate serait quadratique.
	local spacing = Config.BUILD_MIN_SPACING
	local spacing2 = spacing * spacing
	local nB = 0
	do
		local reach = radius + spacing
		for dy = -reach, reach do
			for dx = -reach, reach do
				local nx, ny = ox + dx, oy + dy
				if MapGen.inBounds(nx, ny) then
					local i = MapGen.toIndex(nx, ny)
					if ctx.buildingAt(i) ~= nil then
						nB += 1
						blockBuf[nB] = i
					end
				end
			end
		end
	end
	for i = #blockBuf, nB + 1, -1 do
		blockBuf[i] = nil
	end

	local nC = 0
	table.clear(visitBuf)
	visitBuf[index] = true
	local nQ = 1
	queueBuf[1] = index
	for i = #queueBuf, nQ + 1, -1 do
		queueBuf[i] = nil
	end
	local head = 1

	while head <= nQ do
		local current = queueBuf[head]
		head += 1

		local cx, cy = MapGen.fromIndex(current)
		local dx, dy = cx - ox, cy - oy
		local dist2 = dx * dx + dy * dy

		local usable = dist2 <= radius2
		if not usable then
			-- rien a faire : la tuile n'a ete visitee que pour propager
		elseif buffer.readu8(ctx.terrain, current) == Config.TERRAIN.OCEAN then
			usable = false
		elseif ctx.buildingAt(current) ~= nil then
			usable = false
		elseif def.coastalOnly and not MapGen.isCoastal(ctx.terrain, current) then
			usable = false
		else
			for i = 1, nB do
				local other = blockBuf[i]
				local bx, by = MapGen.fromIndex(other)
				local ex, ey = bx - cx, by - cy
				if ex * ex + ey * ey < spacing2 then
					usable = false
					break
				end
			end
		end

		if usable then
			nC += 1
			candBuf[nC] = current
		end

		-- On continue a propager meme depuis une tuile inutilisable : c'est
		-- souvent en traversant un batiment existant qu'on atteint l'espace
		-- libre juste derriere.
		if dist2 < radius2 then
			local n = MapGen.neighbors(current, placeScratch)
			for i = 1, n do
				local nb = placeScratch[i]
				if not visitBuf[nb] and ctx.ownerAt(nb) == ctx.slot then
					visitBuf[nb] = true
					nQ += 1
					queueBuf[nQ] = nb
				end
			end
		end
	end

	for i = #candBuf, nC + 1, -1 do
		candBuf[i] = nil
	end

	table.sort(candBuf, function(a, b)
		local ax, ay = MapGen.fromIndex(a)
		local bx, by = MapGen.fromIndex(b)
		local da = (ax - ox) ^ 2 + (ay - oy) ^ 2
		local db = (bx - ox) ^ 2 + (by - oy) ^ 2
		if da == db then
			-- Depart deterministe : sans cle secondaire, deux tuiles a egale
			-- distance pouvaient s'echanger entre client et serveur et faire
			-- atterrir le batiment ailleurs que sur le fantome.
			return a < b
		end
		return da < db
	end)

	return candBuf
end

--[[
	Batiment ameliorable du meme type deja pose a portee d'accrochage.

	C'est ce qui donne un seul bouton par type : dans le rayon minimal on
	ameliore, en dehors on construit. Le joueur n'a jamais a choisir un mode.
]]
function Placement.upgradeTarget(ctx: Context, index: number, kind: number): number?
	if not BuildingDefs.isUpgradable(kind) then
		return nil
	end
	if index < 0 or index >= Config.TILE_COUNT then
		return nil
	end

	local radius = Config.BUILD_MIN_SPACING
	local ox, oy = MapGen.fromIndex(index)
	local best: number? = nil
	local bestDist = math.huge

	for dy = -radius, radius do
		for dx = -radius, radius do
			local dist2 = dx * dx + dy * dy
			if dist2 <= radius * radius and dist2 < bestDist then
				local nx, ny = ox + dx, oy + dy
				if MapGen.inBounds(nx, ny) then
					local i = MapGen.toIndex(nx, ny)
					local otherKind, otherSlot, otherLevel = ctx.buildingAt(i)
					if
						otherKind == kind
						and otherSlot == ctx.slot
						and (otherLevel or 1) < BuildingDefs.maxLevel(kind)
					then
						best = i
						bestDist = dist2
					end
				end
			end
		end
	end

	return best
end

--=============================================================================
-- Point d'entree
--=============================================================================

--[[
	Que se passe-t-il si le joueur clique ici avec ce batiment arme ?

	Renvoie soit une resolution exploitable, soit `nil` et une raison lisible.
	Les deux camps appellent exactement cette fonction : le client pour placer
	son fantome, le serveur pour executer. Ils ne peuvent plus diverger.
]]
function Placement.resolve(
	ctx: Context,
	index: number,
	kind: number,
	counts: { [number]: number },
	buildCostModifier: number
): (Resolution?, string?)
	local def = BuildingDefs.get(kind)
	if not def then
		return nil, "Batiment inconnu."
	end
	-- La capitale est posee par le moteur au spawn : elle ne doit jamais etre
	-- accessible depuis un ordre client, meme forge a la main.
	if not def.buildable then
		return nil, "Ce batiment ne se construit pas."
	end
	if index < 0 or index >= Config.TILE_COUNT then
		return nil, "Position hors carte."
	end

	-- Amelioration d'abord : si un exemplaire du meme type est deja la, c'est
	-- lui qu'on vise, et il echappe a toutes les regles de placement.
	local target = Placement.upgradeTarget(ctx, index, kind)
	if target then
		local _, _, level = ctx.buildingAt(target)
		level = level or 1
		local price = Placement.upgradePriceFor(counts, kind, level, buildCostModifier)
		if price == math.huge then
			return nil, `{def.name} a atteint son niveau maximum.`
		end
		local requiredEra = Placement.upgradeRequiredEra(kind, level)
		if ctx.era < requiredEra then
			return nil, `Necessite l'ere {Eras.get(requiredEra).name}.`
		end
		if ctx.gold < price then
			return nil, `Il te faut {price} d'or ({math.floor(ctx.gold)} disponible).`
		end
		return { action = "upgrade", tile = target, price = price, level = level + 1 }, nil
	end

	local requiredEra = Eras.requiredFor(kind)
	if ctx.era < requiredEra then
		return nil, `Necessite l'ere {Eras.get(requiredEra).name}.`
	end

	local price = Placement.priceFor(counts, kind, buildCostModifier)
	if ctx.gold < price then
		return nil, `Il te faut {price} d'or ({math.floor(ctx.gold)} disponible).`
	end

	if ctx.ownerAt(index) ~= ctx.slot then
		return nil, "Tu ne controles pas ce territoire."
	end

	local tiles = Placement.validTiles(ctx, index, kind)
	if #tiles == 0 then
		-- Le seul refus de position qui subsiste, et il est informatif : il n'y a
		-- pas "un peu plus loin", il n'y a nulle part.
		if def.coastalOnly then
			return nil, "Aucune cote libre a portee."
		end
		return nil, "Pas de place a portee : tes batiments sont trop serres ici."
	end

	return { action = "build", tile = tiles[1], price = price, level = 1 }, nil
end

return Placement
