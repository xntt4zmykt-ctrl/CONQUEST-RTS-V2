--!strict
--[[
	Fusion gloutonne 2D.

	Regroupe les tuiles voisines partageant la meme cle en rectangles les plus
	grands possibles. C'est l'algorithme qui rend le monde 3D viable : sans lui,
	40 960 tuiles feraient 40 960 Parts et Roblox s'ecroulerait.

	Il est ici, partage, parce que deux appelants en dependent avec des cles
	differentes :
	  - le serveur fusionne par relief seul, pour une collision statique
	  - le client fusionne par relief + proprietaire, pour la couleur

	Les avoir en double aurait garanti qu'ils divergent, et une divergence entre
	collision et visuel produit le pire bug possible : un sol ou l'on tombe.

	La fonction ne cree rien — elle renvoie des rectangles. C'est ce qui permet
	de la mesurer hors de Roblox.
]]

local GreedyMesh = {}

export type Rect = {
	x: number,
	y: number,
	width: number,
	depth: number,
	key: number,
}

--[[
	`keyAt(x, y)` renvoie la cle d'une tuile, ou nil si elle ne produit aucun
	bloc (l'ocean, typiquement). Deux tuiles fusionnent si et seulement si leurs
	cles sont egales.

	Le balayage etend d'abord vers la droite, puis vers le bas tant que la ligne
	entiere correspond. `scratch` est une table de travail reutilisable, pour
	eviter une allocation par appel dans les boucles de reconstruction.
]]
function GreedyMesh.rectangles(
	keyAt: (number, number) -> number?,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	scratch: { [number]: boolean }?
): { Rect }
	local consumed = scratch or {}
	table.clear(consumed)

	local stride = x1 - x0 + 1
	local out: { Rect } = {}

	local function localIndex(x: number, y: number): number
		return (y - y0) * stride + (x - x0)
	end

	for y = y0, y1 do
		for x = x0, x1 do
			if consumed[localIndex(x, y)] then
				continue
			end

			local key = keyAt(x, y)
			if not key then
				continue
			end

			-- Extension horizontale.
			local width = 1
			while x + width <= x1 do
				if consumed[localIndex(x + width, y)] or keyAt(x + width, y) ~= key then
					break
				end
				width += 1
			end

			-- Extension verticale : la ligne entiere doit correspondre, sinon on
			-- creerait un rectangle qui deborde sur une autre cle.
			local depth = 1
			while y + depth <= y1 do
				local rowMatches = true
				for dx = 0, width - 1 do
					if consumed[localIndex(x + dx, y + depth)] or keyAt(x + dx, y + depth) ~= key then
						rowMatches = false
						break
					end
				end
				if not rowMatches then
					break
				end
				depth += 1
			end

			for dy = 0, depth - 1 do
				for dx = 0, width - 1 do
					consumed[localIndex(x + dx, y + dy)] = true
				end
			end

			table.insert(out, { x = x, y = y, width = width, depth = depth, key = key })
		end
	end

	return out
end

return GreedyMesh
