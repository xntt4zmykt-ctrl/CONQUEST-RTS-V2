--!strict
--[[
	File de priorite minimale, sur tableaux plats.

	Deux tableaux paralleles plutot qu'un tableau de tables : allouer un objet
	par element ferait travailler le ramasse-miettes bien plus que l'algorithme
	qui s'en sert. Sur un front de conquete, ou l'on empile et depile plusieurs
	milliers de tuiles par seconde, c'est la difference entre un tick invisible
	et une saccade.

	Ce module existe parce que deux systemes en avaient besoin — le trace des
	voies et la progression des offensives — et que la premiere version en avait
	deux copies. Un tas binaire mal recopie se remarque tard et mal : il ne
	plante pas, il rend simplement l'ordre legerement faux.
]]

local Heap = {}

export type Heap = {
	values: { number },
	costs: { number },
	size: number,
}

function Heap.new(): Heap
	return { values = {}, costs = {}, size = 0 }
end

function Heap.clear(heap: Heap)
	table.clear(heap.values)
	table.clear(heap.costs)
	heap.size = 0
end

function Heap.push(heap: Heap, value: number, cost: number)
	local i = heap.size + 1
	heap.size = i
	heap.values[i] = value
	heap.costs[i] = cost

	-- Remontee : tant que le parent est plus cher, on echange.
	while i > 1 do
		local parent = i // 2
		if heap.costs[parent] <= heap.costs[i] then
			break
		end
		heap.values[parent], heap.values[i] = heap.values[i], heap.values[parent]
		heap.costs[parent], heap.costs[i] = heap.costs[i], heap.costs[parent]
		i = parent
	end
end

function Heap.pop(heap: Heap): number?
	if heap.size == 0 then
		return nil
	end
	local top = heap.values[1]

	heap.values[1] = heap.values[heap.size]
	heap.costs[1] = heap.costs[heap.size]
	heap.size -= 1

	-- Descente : on echange avec le moins cher des deux enfants.
	local i = 1
	while true do
		local left, right = i * 2, i * 2 + 1
		local smallest = i
		if left <= heap.size and heap.costs[left] < heap.costs[smallest] then
			smallest = left
		end
		if right <= heap.size and heap.costs[right] < heap.costs[smallest] then
			smallest = right
		end
		if smallest == i then
			break
		end
		heap.values[smallest], heap.values[i] = heap.values[i], heap.values[smallest]
		heap.costs[smallest], heap.costs[i] = heap.costs[i], heap.costs[smallest]
		i = smallest
	end

	return top
end

function Heap.isEmpty(heap: Heap): boolean
	return heap.size == 0
end

return Heap
