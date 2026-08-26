--[[
	Banc d'essai headless.

	Fait tourner la simulation serveur complete hors de Studio, avec uniquement
	des bots, puis verifie a intervalles reguliers un jeu d'invariants.

	Les invariants sont choisis pour attraper la categorie de bug la plus
	dangereuse ici : la comptabilite incrementale. `tiles`, `border`,
	`portCount` et compagnie sont maintenus a la main a chaque capture ; s'ils
	derivent de la realite du buffer `owner`, tout l'equilibrage se fausse
	silencieusement sans jamais lever d'erreur.
]]

local Config = __require("Config")
local MapGen = __require("MapGen")
local Eras = __require("Eras")
local GameState = __require("GameState")
local Buildings = __require("Buildings")
local Navy = __require("Navy")
local Trade = __require("Trade")
local Nukes = __require("Nukes")
local Diplomacy = __require("Diplomacy")
local SystemsBootstrap = __require("SystemsBootstrap")
SystemsBootstrap.install()
local Bots = __require("Bots")
local GreedyMesh = __require("GreedyMesh")
local WorldBuilder = __require("WorldBuilder")
local GameModes = __require("GameModes")
local BuildingDefs = __require("BuildingDefs")
local Placement = __require("Placement")
local RailPath = __require("RailPath")
local Format = __require("Format")
local Leaderstats = __require("Leaderstats")
local QuickChat = __require("QuickChat")
local IntentValidator = __require("IntentValidator")
local TickMetrics = __require("TickMetrics")
local Research = __require("Research")

local TICKS = tonumber(_G.TICKS) or 6000
local CHECK_EVERY = 500

local failures = 0

local function fail(message)
	failures += 1
	print(`  \27[31mECHEC\27[0m  {message}`)
end

--=============================================================================
-- Invariants
--=============================================================================

local function checkInvariants(state, tick)
	-- 1. Le compteur de tuiles de chaque joueur doit correspondre au buffer.
	local realTiles = {}
	for index = 0, Config.TILE_COUNT - 1 do
		local slot = buffer.readu8(state.owner, index)
		if slot ~= 0 then
			realTiles[slot] = (realTiles[slot] or 0) + 1
		end
	end

	for slot, ps in state.players do
		local real = realTiles[slot] or 0
		if real ~= ps.tiles then
			fail(`tick {tick} — slot {slot} : tiles={ps.tiles} mais {real} dans le buffer`)
		end
	end

	for slot, count in realTiles do
		if not state.players[slot] then
			fail(`tick {tick} — slot {slot} n'existe plus mais possede {count} tuiles`)
		end
	end

	-- 2. Les ensembles frontieres doivent etre exacts : une frontiere fantome
	-- ferait partir des offensives depuis un territoire qu'on ne detient plus.
	local scratch = table.create(4, 0)
	for slot, ps in state.players do
		for index in ps.border do
			if buffer.readu8(state.owner, index) ~= slot then
				fail(`tick {tick} — slot {slot} : tuile frontiere {index} ne lui appartient pas`)
				break
			end
			local n = MapGen.neighbors(index, scratch)
			local touchesForeign = false
			for i = 1, n do
				local nb = scratch[i]
				if buffer.readu8(state.owner, nb) ~= slot and state:isLand(nb) then
					touchesForeign = true
					break
				end
			end
			if not touchesForeign then
				fail(`tick {tick} — slot {slot} : tuile {index} marquee frontiere sans voisin etranger`)
				break
			end
		end
	end

	-- 3. L'ensemble cotier doit correspondre exactement aux tuiles possedees
	-- touchant l'ocean. C'est lui qui conditionne les ports et les
	-- debarquements : s'il derive, la marine devient injouable en silence.
	for slot, ps in state.players do
		for index in ps.coast do
			if buffer.readu8(state.owner, index) ~= slot then
				fail(`tick {tick} — slot {slot} : tuile cotiere {index} ne lui appartient pas`)
				break
			end
			if not MapGen.isCoastal(state.terrain, index) then
				fail(`tick {tick} — slot {slot} : tuile {index} marquee cotiere sans acces a l'ocean`)
				break
			end
		end
	end

	-- 4. Aucune valeur negative ou non finie.
	for slot, ps in state.players do
		if ps.troops < 0 or ps.troops ~= ps.troops then
			fail(`tick {tick} — slot {slot} : troupes invalides ({ps.troops})`)
		end
		if ps.gold < 0 or ps.gold ~= ps.gold then
			fail(`tick {tick} — slot {slot} : or invalide ({ps.gold})`)
		end
	end

	-- 5. Comptage des batiments coherent avec la table reelle.
	local realPorts, realSilos, realCapitals = {}, {}, {}
	local realPortLevels = {}
	local realBuildingCounts = {}
	local realCityPop, realCityGold = {}, {}
	for index, building in state.buildings do
		realBuildingCounts[building.slot] = realBuildingCounts[building.slot] or {}
		local slotCounts = realBuildingCounts[building.slot]
		slotCounts[building.kind] = (slotCounts[building.kind] or 0) + 1
		if building.kind == Config.BUILDING.CITY then
			local city = Config.CITY_LEVELS[building.level or 1]
			realCityPop[building.slot] = (realCityPop[building.slot] or 0) + city.popCapBonus
			realCityGold[building.slot] = (realCityGold[building.slot] or 0) + city.goldBonus
		elseif building.kind == Config.BUILDING.PORT then
			realPorts[building.slot] = (realPorts[building.slot] or 0) + 1
			realPortLevels[building.slot] = (realPortLevels[building.slot] or 0) + (building.level or 1)
		elseif building.kind == Config.BUILDING.SILO then
			realSilos[building.slot] = (realSilos[building.slot] or 0) + 1
		elseif building.kind == Config.BUILDING.CAPITAL then
			realCapitals[building.slot] = (realCapitals[building.slot] or 0) + 1
			local def = BuildingDefs.get(Config.BUILDING.CAPITAL)
			realCityPop[building.slot] = (realCityPop[building.slot] or 0) + (if def then def.popCapBonus else 0)
		elseif building.kind == Config.BUILDING.FACTORY then
			-- Une usine est une gare : chaque liaison doit pointer sur une autre
			-- gare du meme camp (ville, capitale, port ou usine) et rester dans
			-- la portee du reseau.
			local fx, fy = MapGen.fromIndex(index)
			for _, other in building.links do
				local station = state.buildings[other]
				local isStation = station ~= nil
					and (
						station.kind == Config.BUILDING.CITY
						or station.kind == Config.BUILDING.CAPITAL
						or station.kind == Config.BUILDING.PORT
						or station.kind == Config.BUILDING.FACTORY
					)
				if not isStation or station.slot ~= building.slot then
					fail(`tick {tick} — usine {index} reliee a un batiment qui n'est pas une gare du meme camp`)
					break
				end
				local cx, cy = MapGen.fromIndex(other)
				local distance = math.sqrt((cx - fx) ^ 2 + (cy - fy) ^ 2)
				if distance > Config.RAIL_RANGE then
					fail(`tick {tick} — liaison ferroviaire {index}->{other} hors portee ({distance})`)
					break
				end
				if other == index then
					fail(`tick {tick} — usine {index} reliee a elle-meme`)
					break
				end
			end
		end
	end
	for slot, ps in state.players do
		local actualCounts = realBuildingCounts[slot] or {}
		for _, def in BuildingDefs.LIST do
			if (actualCounts[def.id] or 0) ~= (ps.buildingCounts[def.id] or 0) then
				fail(
					`tick {tick} — slot {slot} : buildingCounts[{def.id}]={ps.buildingCounts[def.id] or 0} mais {actualCounts[def.id] or 0} reels`
				)
			end
		end
		if (realPorts[slot] or 0) ~= ps.portCount then
			fail(`tick {tick} — slot {slot} : portCount={ps.portCount} mais {realPorts[slot] or 0} reels`)
		end
		if (realPortLevels[slot] or 0) ~= ps.portLevels then
			fail(`tick {tick} — slot {slot} : portLevels={ps.portLevels} mais {realPortLevels[slot] or 0} reels`)
		end
		if (realSilos[slot] or 0) ~= ps.siloCount then
			fail(`tick {tick} — slot {slot} : siloCount={ps.siloCount} mais {realSilos[slot] or 0} reels`)
		end
		if (realCapitals[slot] or 0) ~= ps.capitalCount then
			fail(`tick {tick} — slot {slot} : capitalCount={ps.capitalCount} mais {realCapitals[slot] or 0} reels`)
		end
		if (realCityPop[slot] or 0) ~= ps.cityPopBonus then
			fail(`tick {tick} — slot {slot} : cityPopBonus={ps.cityPopBonus} mais {realCityPop[slot] or 0} reel`)
		end
		if math.abs((realCityGold[slot] or 0) - ps.cityGoldBonus) > 0.0001 then
			fail(`tick {tick} — slot {slot} : cityGoldBonus={ps.cityGoldBonus} mais {realCityGold[slot] or 0} reel`)
		end
	end

	-- 6. Espacement minimal, tous types confondus. C'est la regle qui empeche un
	-- empire de concentrer tout son developpement sur un mouchoir de poche, et
	-- elle passe par le resolveur de placement : si elle casse, c'est que le
	-- chemin serveur a cesse de l'appliquer.
	do
		local spacing2 = Config.BUILD_MIN_SPACING * Config.BUILD_MIN_SPACING
		local placed: { number } = {}
		for index in state.buildings do
			table.insert(placed, index)
		end
		table.sort(placed)
		for i = 1, #placed do
			for j = i + 1, #placed do
				local ax, ay = MapGen.fromIndex(placed[i])
				local bx, by = MapGen.fromIndex(placed[j])
				local dx, dy = ax - bx, ay - by
				if dx * dx + dy * dy < spacing2 then
					fail(`tick {tick} — batiments {placed[i]} et {placed[j]} trop proches`)
				end
			end
		end
	end

	-- 7. Les alliances doivent etre symetriques, sinon un camp peut frapper
	-- alors que l'autre est bloque.
	for a, set in state.alliances do
		for b in set do
			local other = state.alliances[b]
			if not other or not other[a] then
				fail(`tick {tick} — alliance asymetrique entre {a} et {b}`)
			end
		end
	end
end

--=============================================================================
-- Execution
--=============================================================================

--[[
	Joue une partie complete et renvoie son resume. La seed pilote a la fois le
	relief et toutes les decisions des bots, donc chaque seed est une partie
	structurellement differente — c'est le seul moyen d'attraper les cartes
	pathologiques (archipels sans continent, spawns satures).
]]
local function runMatch(seed, ticks)
	local state = GameState.new(seed)
	state.mode = GameModes.get("classic")
	local rng = Random.new(seed)

	local landRatio = state.landCount / Config.TILE_COUNT
	if landRatio < 0.2 or landRatio > 0.65 then
		fail(`seed {seed} — ratio de terre aberrant : {string.format("%.2f", landRatio)}`)
	end

	Bots.spawnAll(state, rng)
	-- Headless : pas de phase de spawn humain — liberer les bots tout de suite.
	SystemsBootstrap.flushPendingBots(state)

	local spawned = 0
	for _ in state.players do
		spawned += 1
	end
	if spawned < Config.BOT_COUNT then
		fail(`seed {seed} — {spawned} factions creees sur {Config.BOT_COUNT} (spawn sature ?)`)
	end

	local explosions = 0
	local function onExplosion()
		explosions += 1
	end

	-- Instant ou la premiere faction franchit chaque palier : c'est la mesure
	-- du rythme de partie. L'ancien systeme ouvrait le nucleaire avant la
	-- premiere minute, ce qui rendait toute la progression decorative.
	local firstEra = {}

	local startClock = os.clock()
	TickMetrics.reset()

	for tick = 1, ticks do
		local t0 = os.clock()
		Bots.step(state, rng)
		Navy.step(state, rng)
		Nukes.step(state, rng, onExplosion)
		Trade.step(state, rng, function() end)
		Diplomacy.step(state)
		state:step()

		-- Le serveur vide ces files a chaque tick ; sans ca elles croissent
		-- indefiniment et le test mesurerait une fuite qui n'existe pas en jeu.
		local delta = state:flushOwnerDelta()
		state:flushBuildingDelta()
		table.clear(state.events)
		table.clear(state.sounds)
		local changed = if delta then buffer.len(delta) // 5 else 0
		TickMetrics.record(tick, changed, delta, (os.clock() - t0) * 1000)

		for _, ps in state.players do
			if not firstEra[ps.era] then
				firstEra[ps.era] = tick
			end
		end

		if tick % CHECK_EVERY == 0 then
			checkInvariants(state, tick)
		end
	end

	checkInvariants(state, ticks)

	return {
		state = state,
		seed = seed,
		spawned = spawned,
		explosions = explosions,
		elapsed = os.clock() - startClock,
		landRatio = landRatio,
		firstEra = firstEra,
	}
end

--[[
	Unicite des identifiants de batiment.

	Deux batiments ont deja partage l'identifiant 8 pendant plusieurs commits :
	l'usine et la base navale etaient alors strictement indistinguables — meme
	definition, memes compteurs, meme comportement de flotte. Rien ne l'avait
	signale, parce que tout le code lit les identifiants sans jamais verifier
	qu'ils sont distincts.
]]
do
	local seen = {}
	for name, id in Config.BUILDING do
		if seen[id] then
			fail(`identifiant de batiment {id} partage par {seen[id]} et {name}`)
		end
		seen[id] = name
	end

	local defs = {}
	for _, def in BuildingDefs.LIST do
		if defs[def.id] then
			fail(`deux definitions de batiment portent l'identifiant {def.id}`)
		end
		defs[def.id] = true
	end
end

print("=== CONQUEST RTS — simulation headless ===")

-- Accessibilite : un humain commence avec assez de ressources pour agir tout
-- de suite, tandis que l'IA conserve son economie standard et un engagement
-- plus prudent. Cela attrape les regressions qui recreeraient le faux depart
-- ou les renforts bot a 45 % observes dans l'ancien equilibrage.
do
	local friendlyState = GameState.new(20260818)
	local human = friendlyState:addPlayer({ Name = "Commandant" } :: any, "Commandant", Random.new(11), 0)
	if not human then
		fail("accessibilite — impossible de creer le joueur humain")
	else
		if human.gold ~= Config.HUMAN_START_GOLD or human.troops ~= Config.HUMAN_START_TROOPS then
			fail("accessibilite — bonus de depart humain absent")
		end
		local firstCity = Buildings.priceFor(friendlyState, human.slot, Config.BUILDING.CITY)
		if human.gold < firstCity then
			fail("accessibilite — le joueur ne peut toujours pas construire une premiere ville")
		end
	end

	Bots.spawnAll(friendlyState, Random.new(12), 2)
	for _, ps in friendlyState.players do
		if ps.isBot and (ps.attackRatio < Config.BOT_ATTACK_RATIO_MIN or ps.attackRatio > Config.BOT_ATTACK_RATIO_MAX) then
			fail(`accessibilite — engagement bot hors limites ({ps.attackRatio})`)
		end
	end
end

-- Parcours joueur explicite : accrochage du placement, evolution d'une ville,
-- puis raccordement d'une usine au reseau. Les bots exercent aussi ces chemins,
-- mais ce test garantit qu'ils restent couverts meme si leur strategie change.
do
	local cityState = GameState.new(20260817)
	local ps = cityState:addPlayer(nil, "Urbaniste", Random.new(20260817), 0)
	if not ps then
		fail("evolution urbaine — impossible de creer la faction de test")
	else
		ps.gold = 100000
		ps.era = 3

		-- Le territoire de depart n'est qu'un disque de rayon SPAWN_RADIUS : trop
		-- petit pour y poser plusieurs batiments espaces. On elargit a la main
		-- plutot que de tester le placement dans un cas degenere.
		local capital = ps.capitalTile
		if not capital then
			fail("evolution urbaine — la faction de test n'a pas de capitale")
		else
			local ccx, ccy = MapGen.fromIndex(capital)
			for dy = -14, 14 do
				for dx = -14, 14 do
					if dx * dx + dy * dy <= 196 then
						local nx, ny = ccx + dx, ccy + dy
						if MapGen.inBounds(nx, ny) then
							local index = MapGen.toIndex(nx, ny)
							if cityState:isLand(index) then
								cityState:setOwner(index, ps.slot)
							end
						end
					end
				end
			end

			local function freeSiteAt(dx: number, dy: number): number?
				local nx, ny = ccx + dx, ccy + dy
				if not MapGen.inBounds(nx, ny) then
					return nil
				end
				local index = MapGen.toIndex(nx, ny)
				if buffer.readu8(cityState.owner, index) ~= ps.slot then
					return nil
				end
				return index
			end

			local citySite = freeSiteAt(6, 0)
			local factorySite = freeSiteAt(-6, 0)
			if not citySite or not factorySite then
				fail("evolution urbaine — aucune tuile constructible")
			else
				--[[
					Accrochage : on vise deliberement la capitale elle-meme, ce qui
					etait un refus pur et simple avant. Le moteur doit maintenant
					reporter la ville sur une tuile libre du voisinage.
				]]
				local snapped = Buildings.build(cityState, ps.slot, capital, Config.BUILDING.CITY)
				local snappedCity: number? = nil
				for index, building in cityState.buildings do
					if building.kind == Config.BUILDING.CITY then
						snappedCity = index
					end
				end
				if not snapped or not snappedCity or snappedCity == capital then
					fail("placement — un clic sur une tuile occupee n'a pas ete reporte a cote")
				end

				--[[
					Un second clic au meme endroit ne pose pas une deuxieme ville : il
					fait monter celle qui vient d'apparaitre. C'est la regle "un seul
					bouton par type" — le joueur n'a aucun mode a choisir.
				]]
				local before = ps.buildingCounts[Config.BUILDING.CITY] or 0
				local upgraded = Buildings.build(cityState, ps.slot, snappedCity :: number, Config.BUILDING.CITY)
				local after = ps.buildingCounts[Config.BUILDING.CITY] or 0
				local grown = cityState.buildings[snappedCity :: number]
				if not upgraded or after ~= before or not grown or grown.level ~= 2 then
					fail("placement — un clic sur une ville existante n'a pas declenche son amelioration")
				end

				-- Parcours complet des paliers sur une ville posee a l'ecart.
				local built = Buildings.build(cityState, ps.slot, citySite, Config.BUILDING.CITY)
				local level2 = Buildings.upgradeAt(cityState, ps.slot, citySite)
				local level3 = Buildings.upgradeAt(cityState, ps.slot, citySite)
				local blocked = Buildings.upgradeAt(cityState, ps.slot, citySite)
				if not built or not level2 or not level3 or blocked then
					fail("evolution urbaine — parcours ville -> metropole -> megapole invalide")
				end
				local city = cityState.buildings[citySite]
				if not city or city.level ~= Config.CITY_MAX_LEVEL then
					fail("evolution urbaine — niveau final incorrect")
				end

				--[[
					Reseau ferroviaire. Une usine relie *toutes* les gares a portee —
					ici la capitale et les deux villes — et le revenu suit le nombre de
					liaisons de la grappe, pas le nombre d'usines.
				]]
				local factoryBuilt = Buildings.build(cityState, ps.slot, factorySite, Config.BUILDING.FACTORY)
				local factory = cityState.buildings[factorySite]
				local routes, logisticsIncome = cityState:logisticsFor(ps.slot)
				if not factoryBuilt or not factory then
					fail("logistique — l'usine n'a pas pu etre construite")
				elseif #factory.links < 3 then
					fail(`logistique — l'usine ne relie que {#factory.links} gare(s), 3 attendues`)
				elseif routes ~= 3 or logisticsIncome <= 0 then
					fail(`logistique — grappe de {routes} liaison(s) pour {logisticsIncome} or/tick`)
				end

				--[[
					Le port est une gare comme les autres : l'ajouter agrandit la
					grappe existante au lieu de creer un reseau parallele. C'est la
					difference entre un graphe et une etoile.
				]]
				local coastal: number? = nil
				for index in cityState.dirty do
					if buffer.readu8(cityState.owner, index) == ps.slot and MapGen.isCoastal(cityState.terrain, index) then
						coastal = index
						break
					end
				end
				if coastal then
					local portBuilt = Buildings.build(cityState, ps.slot, coastal, Config.BUILDING.PORT)
					local grownRoutes = select(1, cityState:logisticsFor(ps.slot))
					if portBuilt and grownRoutes <= routes then
						fail("logistique — un port raccorde n'agrandit pas la grappe")
					end
				end

				checkInvariants(cityState, 0)
			end
		end
	end
end

--[[
	Inflation des couts : doublement borne, et compteur partage port/usine.

	La courbe precedente etait lineaire et sans plafond — trop molle sur les
	premiers batiments, sans fin sur les derniers. Ce test verrouille les deux
	proprietes qui la remplacent.
]]
do
	local counts: { [number]: number } = {}
	local base = 0
	for _, def in BuildingDefs.LIST do
		if def.id == Config.BUILDING.CITY then
			base = def.cost
		end
	end

	local expected = { 1, 2, 4, 8, 8, 8 }
	for n, multiple in expected do
		counts[Config.BUILDING.CITY] = n - 1
		local price = Placement.priceFor(counts, Config.BUILDING.CITY, 1)
		if price ~= math.floor(base * multiple) then
			fail(`couts — {n}e ville a {price}, attendu {math.floor(base * multiple)}`)
		end
	end

	-- Le port rencherit l'usine et reciproquement : un seul budget pour les deux
	-- axes economiques.
	local shared: { [number]: number } = { [Config.BUILDING.PORT] = 2 }
	if
		Placement.priceFor(shared, Config.BUILDING.FACTORY, 1)
		~= Placement.priceFor({ [Config.BUILDING.FACTORY] = 2 }, Config.BUILDING.FACTORY, 1)
	then
		fail("couts — le port et l'usine ne partagent pas leur compteur d'inflation")
	end
end

--[[
	Frein a l'emballement.

	Les trois proprietes qui remplacent l'ancienne penalite de ravitaillement.
	Elles sont testees sur des valeurs et pas seulement sur des signes, parce que
	c'est exactement ce genre de courbe qu'on casse sans s'en apercevoir en
	ajustant une constante.
]]
do
	local debuffState = GameState.new(4242)
	local small = debuffState:addPlayer(nil, "Petit", Random.new(1), 0)
	local huge = debuffState:addPlayer(nil, "Geant", Random.new(2), 0)
	if not small or not huge then
		fail("frein — impossible de creer les factions de test")
	else
		small.tiles = 200
		huge.tiles = math.floor(debuffState.landCount * 0.5)

		local smallDefense = debuffState:sizeDefenseFactor(small)
		local hugeDefense = debuffState:sizeDefenseFactor(huge)
		if smallDefense <= hugeDefense then
			fail("frein — un empire immense ne defend pas moins bien qu'un petit")
		end
		if smallDefense > 1.0001 or hugeDefense < Config.LARGE_DEFENDER_FLOOR - 0.0001 then
			fail(`frein — facteur de defense hors bornes ({smallDefense} / {hugeDefense})`)
		end

		local smallSpeed, smallCost = debuffState:sizeAttackFactors(small)
		local hugeSpeed, hugeCost = debuffState:sizeAttackFactors(huge)
		if smallSpeed ~= 1 or smallCost ~= 1 then
			fail("frein — un petit empire est penalise alors qu'il ne devrait pas l'etre")
		end
		if hugeSpeed >= 1 or hugeSpeed < Config.LARGE_ATTACKER_SPEED_FLOOR - 0.0001 then
			fail(`frein — vitesse du geant hors bornes ({hugeSpeed})`)
		end
		-- La compensation est la piece qui rend la regle jouable : sans elle, le
		-- leader est simplement puni et le jeu devient une course a rester second.
		if hugeCost >= 1 then
			fail("frein — le gros attaquant ne beneficie d'aucune compensation en cout")
		end
	end
end

--[[
	Commerce maritime.

	L'or arrive a l'arrivee du convoi, pas au tick. Trois proprietes portent la
	mecanique et aucune ne se voit dans une partie normale si elle casse : on
	constate juste, dix minutes plus tard, que personne n'a d'or.
]]
do
	local seaState = GameState.new(31415)
	local a = seaState:addPlayer(nil, "Thalassa", Random.new(11), 0)
	local b = seaState:addPlayer(nil, "Ostrave", Random.new(12), 0)
	if not a or not b then
		fail("commerce — impossible de creer les factions de test")
	else
		--[[
			On choisit les deux ports sur la carte puis on donne la case a la
			faction, plutot que de compter sur son territoire de depart.

			Les premieres versions de ce test lisaient `ps.coast` : le resultat
			dependait alors de l'endroit ou la graine avait fait apparaitre les
			factions, et le test echouait sur une carte parfaitement saine des
			qu'une faction naissait dans les terres.
		]]
		local coastal: { number } = {}
		for index = 0, Config.TILE_COUNT - 1 do
			if seaState:isLand(index) and MapGen.isCoastal(seaState.terrain, index) then
				table.insert(coastal, index)
				if #coastal >= 400 then
					break
				end
			end
		end

		local portA: number? = nil
		local portB: number? = nil
		for _, first in coastal do
			for _, second in coastal do
				if first ~= second and Navy.findSeaPath(seaState, first, second) then
					portA, portB = first, second
					break
				end
			end
			if portA then
				break
			end
		end

		if not portA or not portB then
			fail("commerce — aucune paire de cotes reliees par la mer sur la carte de test")
		else
			seaState:setOwner(portA, a.slot)
			seaState:setOwner(portB, b.slot)
			seaState:placeBuilding(portA, Config.BUILDING.PORT, a.slot)
			seaState:placeBuilding(portB, Config.BUILDING.PORT, b.slot)

			local path = Navy.findSeaPath(seaState, portA :: number, portB :: number)
			if not path then
				fail("commerce — aucune route maritime entre les deux ports de test")
			else
				local goldA, goldB = a.gold, b.gold

				--[[
					Un convoi arrive : les DEUX ports touchent.

					C'est ce qui fait d'un voisin cotier une ressource et pas
					seulement une menace, et c'est ce qui donne un cout a la
					piraterie — un convoi coule prive deux factions a la fois.
				]]
				table.insert(seaState.boats, {
					id = seaState:nextId(),
					slot = a.slot,
					kind = Navy.KIND_TRADE,
					troops = 0,
					x = 0,
					y = 0,
					path = path,
					step = #path + 1,
					targetTile = portB,
					homeTile = portA,
				})
				Navy.step(seaState, Random.new(1))

				if a.gold <= goldA then
					fail("commerce — le port expediteur ne touche rien a l'arrivee")
				end
				if b.gold <= goldB then
					fail("commerce — le port destinataire ne touche rien a l'arrivee")
				end
				if math.abs((a.gold - goldA) - (b.gold - goldB)) > 0.001 then
					fail("commerce — les deux ports ne touchent pas la meme somme")
				end

				-- Une route plus longue paie davantage : le commerce lointain
				-- doit valoir le risque de traverser des eaux hostiles.
				local shortGain = a.gold - goldA
				goldA, goldB = a.gold, b.gold
				local longPath = table.clone(path)
				for _ = 1, 50 do
					table.insert(longPath, path[#path])
				end
				table.insert(seaState.boats, {
					id = seaState:nextId(),
					slot = a.slot,
					kind = Navy.KIND_TRADE,
					troops = 0,
					x = 0,
					y = 0,
					path = longPath,
					step = #longPath + 1,
					targetTile = portB,
					homeTile = portA,
				})
				Navy.step(seaState, Random.new(1))
				if (a.gold - goldA) <= shortGain then
					fail("commerce — une route longue ne rapporte pas plus qu'une courte")
				end

				--[[
					L'embargo ferme la ligne.

					Il est reverifie a l'ARRIVEE et pas au depart : entre les deux,
					le port a pu etre detruit, capture, ou l'embargo tomber. Payer
					sur la foi des conditions de depart recompenserait une route qui
					n'existe plus.
				]]
				Diplomacy.setEmbargo(seaState, b.slot, a.slot, true)
				goldA, goldB = a.gold, b.gold
				table.insert(seaState.boats, {
					id = seaState:nextId(),
					slot = a.slot,
					kind = Navy.KIND_TRADE,
					troops = 0,
					x = 0,
					y = 0,
					path = path,
					step = #path + 1,
					targetTile = portB,
					homeTile = portA,
				})
				Navy.step(seaState, Random.new(1))
				if a.gold ~= goldA or b.gold ~= goldB then
					fail("commerce — un convoi paie malgre l'embargo")
				end
			end
		end
	end
end

--[[
	Commerce terrestre.

	Une usine n'a qu'un colis en route a la fois, un rechargement suit chaque
	livraison, et l'or n'arrive qu'avec le colis — jamais au depart, jamais si
	la gare est tombee entre-temps. Trois proprietes invisibles en jeu normal :
	on constate juste, dix minutes plus tard, que l'economie tourne deux fois
	ou pas du tout.
]]
do
	local landState = GameState.new(2718)
	local a = landState:addPlayer(nil, "Ferrovia", Random.new(21), 0)
	if not a then
		fail("commerce terrestre — impossible de creer la faction de test")
	else
		-- Deux cases terrestres proches : une usine, une ville a sa portee. La
		-- distance depasse TRUCK_SPEED pour que le trajet dure plus d'un tick —
		-- sinon la livraison est immediate et les etapes se telescopent.
		local factoryTile: number? = nil
		local cityTile: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if landState:isLand(index) then
				local fx, fy = MapGen.fromIndex(index)
				for d = Config.TRUCK_SPEED + 2, Config.TRUCK_SPEED + 10 do
					local cx, cy = fx + d, fy
					if MapGen.inBounds(cx, cy) then
						local candidate = MapGen.toIndex(cx, cy)
						if landState:isLand(candidate) then
							factoryTile, cityTile = index, candidate
							break
						end
					end
				end
			end
			if factoryTile then
				break
			end
		end

		if not factoryTile or not cityTile then
			fail("commerce terrestre — aucune paire de cases terrestres proches sur la carte de test")
		else
			landState:setOwner(factoryTile, a.slot)
			landState:setOwner(cityTile, a.slot)
			landState:placeBuilding(factoryTile, Config.BUILDING.FACTORY, a.slot)
			landState:placeBuilding(cityTile, Config.BUILDING.CITY, a.slot)

			local events: { { any } } = {}
			local function onEvent(action, x, y, slot, value)
				table.insert(events, { action, x, y, slot, value })
			end

			-- Une expedition part des que l'usine est prete : un colis, un seul.
			landState.tick += 1
			Trade.step(landState, Random.new(7), onEvent)
			local delivery = landState.tradeDeliveries[factoryTile]
			if not delivery then
				fail("commerce terrestre — l'usine n'expedie pas vers sa gare voisine")
			else
				if events[#events][1] ~= "dispatch" then
					fail("commerce terrestre — l'expedition n'est pas annoncee au client")
				end

				-- Tant que le colis roule, aucun second depart.
				landState.tick += 1
				Trade.step(landState, Random.new(8), onEvent)
				if #events ~= 1 then
					fail("commerce terrestre — une usine a deux colis en route a la fois")
				end

				-- L'or n'arrive qu'avec le colis, pas avant.
				local goldBefore = a.gold
				landState.tick = delivery.arrivalTick
				Trade.step(landState, Random.new(9), onEvent)
				if a.gold <= goldBefore then
					fail("commerce terrestre — la livraison ne paie pas")
				end
				if events[#events][1] ~= "arrival" then
					fail("commerce terrestre — la livraison n'est pas annoncee au client")
				end

				-- Rechargement : pas de nouvelle expedition avant la fin du retour.
				landState.tick += 1
				Trade.step(landState, Random.new(10), onEvent)
				if landState.tradeDeliveries[factoryTile] ~= nil then
					fail("commerce terrestre — l'usine repart sans rechargement")
				end
				landState.tick += Config.TRUCK_COOLDOWN
				Trade.step(landState, Random.new(11), onEvent)
				if landState.tradeDeliveries[factoryTile] == nil then
					fail("commerce terrestre — l'usine ne repart pas apres le rechargement")
				end

				-- Une gare tombee entre le depart et l'arrivee ne paie rien.
				local pending = landState.tradeDeliveries[factoryTile]
				if pending then
					landState.buildings[cityTile] = nil
					local goldMid = a.gold
					landState.tick = pending.arrivalTick
					Trade.step(landState, Random.new(12), onEvent)
					if a.gold ~= goldMid then
						fail("commerce terrestre — un colis paie une gare qui n'existe plus")
					end
				end
			end
		end
	end
end

--[[
	Mise en forme des nombres.

	Ces chaines partent dans la liste des joueurs, sur les etiquettes de la carte
	et dans le bandeau du HUD. Une regression ne planterait rien : elle
	afficherait juste 1290000 la ou on attend 1.29M, et personne ne le
	remarquerait avant de voir la colonne deborder en jeu.
]]
do
	local cases = {
		{ value = 0, expected = "0" },
		{ value = 543, expected = "543" },
		{ value = 5500, expected = "5.50K" },
		{ value = 39800, expected = "39.8K" },
		{ value = 87500, expected = "87.5K" },
		{ value = 683000, expected = "683K" },
		{ value = 1290000, expected = "1.29M" },
		{ value = 5020000, expected = "5.02M" },
	}
	for _, case in cases do
		local got = Format.compact(case.value)
		if got ~= case.expected then
			fail(`format — {case.value} donne "{got}" au lieu de "{case.expected}"`)
		end
	end

	-- Le negatif garde son signe plutot que de produire une chaine absurde.
	if Format.compact(-1500) ~= "-1.50K" then
		fail(`format — un nombre negatif donne "{Format.compact(-1500)}"`)
	end

	--[[
		La part de territoire garde une decimale.

		En debut de partie tout le monde est sous 1 % : un entier afficherait
		douze factions a "0 %", soit exactement l'information que la colonne
		existe pour donner.
	]]
	if Format.percent(80, 15568) ~= "0.5%" then
		fail(`format — une part sous 1 %% donne "{Format.percent(80, 15568)}"`)
	end
	if Format.percent(5, 0) ~= "0.0%" then
		fail("format — une carte sans terre fait diviser par zero")
	end
end

--[[
	Classement Roblox natif.

	Cette logique vivait dans init.server.luau, exclu du bundle, donc verifiee
	par relecture seulement. C'est un angle mort dangereux precisement parce
	qu'une regression n'y plante rien : elle affiche des valeurs fausses ou
	vides dans la liste que les joueurs ouvrent par reflexe, et rien dans les
	journaux ne le signale.
]]
do
	-- Rien dans les modules ne fabrique de Player : le bouchon expose son
	-- constructeur d'instances pour qu'on puisse en poser un ici.
	local function fakePlayer(name)
		local player = __newInstance("Player")
		player.Name = name
		return player
	end

	local function columnValues(player)
		local folder = player:FindFirstChild("leaderstats")
		if not folder then
			return nil
		end
		local keys, values = {}, {}
		for _, child in folder:GetChildren() do
			table.insert(keys, child:GetAttribute("Key"))
			table.insert(values, child.Value)
		end
		return keys, values, folder
	end

	--[[
		Ordre des colonnes.

		La liste des joueurs affiche les colonnes dans leur ordre de creation et
		n'offre aucun autre levier de rangement : le territoire doit rester en
		tete, puisque c'est lui qui decide la victoire.
	]]
	local player = fakePlayer("Commandant")
	local folder = Leaderstats.ensure(player)
	if folder.Name ~= "leaderstats" then
		fail(`classement — le dossier s'appelle "{folder.Name}" et non "leaderstats"`)
	end
	if folder.Parent ~= player then
		fail("classement — le dossier n'est pas parente au joueur")
	end

	local keys, values = columnValues(player)
	local expectedOrder = { "share", "gold", "troops" }
	if not keys or #keys ~= #expectedOrder then
		fail(`classement — {if keys then #keys else 0} colonne(s) creees, {#expectedOrder} attendues`)
	else
		for i, expected in expectedOrder do
			if keys[i] ~= expected then
				fail(`classement — colonne {i} = "{tostring(keys[i])}" au lieu de "{expected}"`)
			end
		end
		-- Un tiret et non "0" : tant qu'aucun tick n'a publie, "pas encore
		-- mesure" et "reduit a rien" ne doivent pas se confondre.
		for i, value in values do
			if value ~= "-" then
				fail(`classement — colonne {i} vaut "{tostring(value)}" avant la premiere publication`)
			end
		end
	end

	--[[
		Idempotence.

		La publication passe par ensure a chaque tick de seconde. Si ensure
		recreait les colonnes, la liste se remplirait de doublons en quelques
		secondes de jeu — et rien ne leverait d'erreur.
	]]
	local again = Leaderstats.ensure(player)
	if again ~= folder then
		fail("classement — un second appel recree le dossier au lieu de reutiliser l'existant")
	end
	local keysAfter = columnValues(player)
	if keysAfter and #keysAfter ~= #expectedOrder then
		fail(`classement — {#keysAfter} colonnes apres deux appels, {#expectedOrder} attendues`)
	end

	--[[
		Report de l'etat du joueur.

		Les valeurs attendues passent par Format et non par une chaine ecrite a
		la main : c'est le formatage partage qui fait foi, et le recopier ici
		reintroduirait la divergence que Format existe pour empecher.
	]]
	local sample = { tiles = 1200, gold = 87500, troops = 1290000 }
	Leaderstats.apply(player, sample :: any, 15568)

	local _, applied = columnValues(player)
	local expectedValues = {
		Format.percent(sample.tiles, 15568),
		Format.compact(sample.gold),
		Format.compact(sample.troops),
	}
	if applied then
		for i, expected in expectedValues do
			if applied[i] ~= expected then
				fail(`classement — colonne {i} affiche "{tostring(applied[i])}" au lieu de "{expected}"`)
			end
		end
	end

	--[[
		La colonne se retrouve par son attribut `Key`, jamais par son nom.

		Les en-tetes sont des emoji. Un code qui les comparerait en dur casserait
		en silence a la premiere icone changee : on renomme donc les colonnes
		avant de republier, et la mise a jour doit continuer a tomber juste.
	]]
	local renamed = fakePlayer("Iconoclaste")
	local renamedFolder = Leaderstats.ensure(renamed)
	for i, child in renamedFolder:GetChildren() do
		child.Name = `colonne{i}`
	end

	local other = { tiles = 80, gold = 543, troops = 5500 }
	Leaderstats.apply(renamed, other :: any, 15568)

	local _, renamedValues = columnValues(renamed)
	local expectedRenamed = {
		Format.percent(other.tiles, 15568),
		Format.compact(other.gold),
		Format.compact(other.troops),
	}
	if renamedValues then
		for i, expected in expectedRenamed do
			if renamedValues[i] ~= expected then
				fail(
					`classement — colonne renommee {i} affiche "{tostring(renamedValues[i])}" `
						.. `au lieu de "{expected}" : la mise a jour dependait du nom`
				)
			end
		end
	end

	--[[
		Publication complete, depuis un vrai GameState.

		Elle exerce le chemin reel qu'emprunte le serveur, y compris la part de
		territoire calculee sur `state.landCount` — la seule valeur des trois qui
		ne sorte pas directement du joueur.
	]]
	local pubState = GameState.new(20260820)
	local pubPlayer = fakePlayer("Publie")
	local ps = pubState:addPlayer(pubPlayer :: any, "Publie", Random.new(3), 0)
	if not ps then
		fail("classement — impossible de creer la faction de publication")
	else
		ps.gold = 4321
		ps.troops = 98765

		Leaderstats.publish(pubState, { [pubPlayer] = ps.slot })

		local pubKeys, pubValues = columnValues(pubPlayer)
		if not pubKeys then
			fail("classement — publish n'a pas equipe un joueur qui n'avait pas encore de liste")
		else
			local wanted = {
				share = Format.percent(ps.tiles, pubState.landCount),
				gold = Format.compact(ps.gold),
				troops = Format.compact(ps.troops),
			}
			for i, key in pubKeys do
				if pubValues[i] ~= wanted[key] then
					fail(`classement — publish : "{key}" = "{tostring(pubValues[i])}" au lieu de "{wanted[key]}"`)
				end
			end
		end

		--[[
			Une faction eliminee voit ses colonnes EFFACEES, pas gelees.

			C'est le cas d'un joueur dont la faction est morte alors qu'il est
			toujours connecte : le serveur garde son entree dans slotByPlayer
			jusqu'a la relance du match.

			Le comportement precedent se contentait de l'ignorer, et ses colonnes
			restaient donc figees sur leur derniere valeur — un territoire qu'il
			ne possede plus, une armee qui n'existe plus. La colonne affichait
			exactement le contraire de ce pour quoi elle existe, avec des chiffres
			parfaitement plausibles : rien a l'ecran ne pouvait le trahir.
		]]
		local ok = pcall(function()
			Leaderstats.publish(pubState, { [pubPlayer] = 99 })
		end)
		if not ok then
			fail("classement — publish plante sur un joueur sans faction")
		end

		local _, ghostValues = columnValues(pubPlayer)
		if not ghostValues then
			fail("classement — un joueur elimine mais connecte perd ses colonnes au lieu de les voir vidées")
		else
			for i, value in ghostValues do
				if value ~= "\u{2014}" then
					fail(
						`classement — colonne {i} d'un elimine vaut encore "{tostring(value)}" : `
							.. `les valeurs sont gelees au lieu d'etre effacees`
					)
				end
			end
		end

		-- Et un joueur jamais equipe ne fait pas planter l'effacement.
		local stranger = fakePlayer("Inconnu")
		if not pcall(function()
			Leaderstats.publish(pubState, { [stranger] = 99 })
		end) then
			fail("classement — publish plante sur un joueur sans liste prealable")
		end
	end
end

--[[
	Rancune : une faction retient qui l'a frappee.

	C'est une regle de COMPORTEMENT, donc invisible pour tous les autres
	invariants : si elle disparait, les comptes de tuiles, l'or et les fronts
	restent parfaitement corrects. Seul le sens de la partie s'evapore — les
	guerres n'ont plus de cause, et le joueur ne fait plus le lien entre son
	agression et la riposte.
]]
do
	local grudgeState = GameState.new(4711)
	local raider = grudgeState:addPlayer(nil, "Agresseur", Random.new(21), 0)
	local victim = grudgeState:addPlayer(nil, "Victime", Random.new(22), 0)
	if not raider or not victim then
		fail("rancune — impossible de creer les factions de test")
	else
		if grudgeState:holdsGrudge(victim.slot, raider.slot) then
			fail("rancune — une faction en veut a quelqu'un qui ne lui a rien fait")
		end

		victim.grudges[raider.slot] = grudgeState.tick + Config.GRUDGE_DURATION
		if not grudgeState:holdsGrudge(victim.slot, raider.slot) then
			fail("rancune — une agression n'est pas retenue")
		end

		-- Elle n'est pas reciproque : l'agresseur n'a rien subi.
		if grudgeState:holdsGrudge(raider.slot, victim.slot) then
			fail("rancune — l'agresseur en veut a sa propre victime")
		end

		-- Elle expire, et la lecture purge au passage : sans cette purge la
		-- table grossit d'une entree par agresseur et ne se vide jamais.
		grudgeState.tick += Config.GRUDGE_DURATION
		if grudgeState:holdsGrudge(victim.slot, raider.slot) then
			fail("rancune — une rancune expiree tient toujours")
		end
		if victim.grudges[raider.slot] ~= nil then
			fail("rancune — l'entree expiree reste dans la table")
		end

		--[[
			Une faction eliminee ne laisse pas de rancune derriere elle.

			Sinon un bot garderait une dette envers un slot recycle par une
			nouvelle faction, et attaquerait un inconnu sans raison.
		]]
		victim.grudges[raider.slot] = grudgeState.tick + Config.GRUDGE_DURATION
		grudgeState:removePlayer(raider.slot)
		if victim.grudges[raider.slot] ~= nil then
			fail("rancune — la rancune survit a la faction qui l'avait provoquee")
		end
	end
end

--[[
	Forme du front de conquete.

	Une offensive doit avancer comme une VAGUE : les cases prises forment une
	tache d'un seul tenant, accrochee au territoire de l'assaillant. Avant, la
	file etait un ensemble depile avec `next()`, dont l'ordre est arbitraire —
	le moteur grignotait donc des cases sans rapport les unes avec les autres et
	laissait des tuiles orphelines au milieu du territoire ennemi.

	Rien dans les autres invariants ne le voyait : le compte de tuiles, le cout
	en troupes et les ensembles frontieres etaient tous parfaitement corrects.
	Seule la forme etait absurde, et la forme est ce que le joueur regarde.
]]
do
	local frontState = GameState.new(20260901)
	local attacker = frontState:addPlayer(nil, "Assaillant", Random.new(1), 0)
	local defender = frontState:addPlayer(nil, "Defenseur", Random.new(2), 0)
	if not attacker or not defender then
		fail("front — impossible de creer les factions de test")
	else
		local cx, cy = MapGen.fromIndex(attacker.capitalTile :: number)

		-- Un large bandeau au defenseur, colle au territoire de l'assaillant.
		local given = 0
		for dy = -18, 18 do
			for dx = 4, 26 do
				local nx, ny = cx + dx, cy + dy
				if MapGen.inBounds(nx, ny) then
					local index = MapGen.toIndex(nx, ny)
					if frontState:isLand(index) then
						frontState:setOwner(index, defender.slot)
						given += 1
					end
				end
			end
		end
		for dy = -18, 18 do
			for dx = -6, 3 do
				local nx, ny = cx + dx, cy + dy
				if MapGen.inBounds(nx, ny) then
					local index = MapGen.toIndex(nx, ny)
					if frontState:isLand(index) then
						frontState:setOwner(index, attacker.slot)
					end
				end
			end
		end

		--[[
			Le rapport de force est calibre pour une conquete PARTIELLE.

			C'est la seule situation ou la forme se mesure : une offensive qui
			avale tout le territoire donne 100 % de cohesion quelle que soit sa
			logique, et une offensive qui prend deux cases n'a pas de forme du
			tout. Les deux cas passaient avec l'ancien code.
		]]
		attacker.troops = 90000
		defender.troops = 60000

		local before: { [number]: true } = {}
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(frontState.owner, index) == defender.slot then
				before[index] = true
			end
		end

		frontState:launchAttack(attacker.slot, defender.slot)
		for _ = 1, 20 do
			frontState:stepAttacks()
		end

		local taken: { [number]: true } = {}
		local count = 0
		for index in before do
			if buffer.readu8(frontState.owner, index) == attacker.slot then
				taken[index] = true
				count += 1
			end
		end

		if count < 20 or count > given - 20 then
			fail(`front — conquete de {count}/{given} tuiles : le cas de test ne mesure plus une forme`)
		else
			-- 1. Aucune tuile orpheline : chaque prise touche une autre prise.
			local orphans = 0
			local probe = table.create(4, 0)
			for index in taken do
				local touching = false
				local n = MapGen.neighbors(index, probe)
				for k = 1, n do
					if taken[probe[k]] then
						touching = true
						break
					end
				end
				if not touching then
					orphans += 1
				end
			end
			if orphans > 0 then
				fail(`front — {orphans} tuile(s) prise(s) isolee(s) : l'avancee saute au lieu de progresser`)
			end

			--[[
				2. La tache reste compacte.

				Mesure : rayon moyen autour du barycentre des prises. Une avancee
				en vague sur ~68 tuiles tient sous 7 ; l'ancien tirage arbitraire
				etalait les memes prises sur un rayon de 9 a 10 pour deux fois
				moins de cases.
			]]
			local sumX, sumY = 0, 0
			for index in taken do
				local x, y = MapGen.fromIndex(index)
				sumX += x
				sumY += y
			end
			local mx, my = sumX / count, sumY / count
			local spread = 0
			for index in taken do
				local x, y = MapGen.fromIndex(index)
				spread += math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
			end
			local radius = spread / count

			-- Rayon d'un disque de meme aire : la reference geometrique du plus
			-- compact possible. On tolere 1,8 fois cette valeur.
			local ideal = math.sqrt(count / math.pi)
			if radius > ideal * 1.8 then
				fail(
					`front — rayon moyen {string.format("%.1f", radius)} pour {count} tuiles `
						.. `(compact = {string.format("%.1f", ideal)}) : l'avancee s'eparpille`
				)
			end
		end
	end
end

--[[
	Trace des voies : alignement sur la grille et economie de virages.

	Ce sont exactement les proprietes qu'un rendu ne trahit jamais tout seul. Une
	diagonale ou un escalier a douze paliers s'affichent sans la moindre erreur —
	ils sont juste laids, et on ne s'en apercoit qu'en lancant le jeu.
]]
do
	local railTerrain = MapGen.generate(4242)

	-- On cherche deux cases de terre eloignees, pour un cas realiste.
	local land: { number } = {}
	for index = 0, Config.TILE_COUNT - 1, 37 do
		if buffer.readu8(railTerrain, index) ~= Config.TERRAIN.OCEAN then
			table.insert(land, index)
		end
	end

	if #land < 2 then
		fail("voies — pas assez de terre sur la carte de test")
	else
		local checked = 0
		for i = 1, math.min(#land, 60) do
			local from = land[i]
			local to = land[math.min(#land, i + 7)]
			if from == to then
				continue
			end

			local path = RailPath.find(railTerrain, from, to)
			if not path then
				fail(`voies — aucun trace entre {from} et {to}`)
				break
			end
			checked += 1

			-- 1. Chaque pas est un deplacement d'une seule case en croix.
			for k = 1, #path - 1 do
				local ax, ay = MapGen.fromIndex(path[k])
				local bx, by = MapGen.fromIndex(path[k + 1])
				local step = math.abs(bx - ax) + math.abs(by - ay)
				if step ~= 1 then
					fail(`voies — pas de {step} cases entre deux points : le trace saute ou part en diagonale`)
					break
				end
			end

			-- 2. Les extremites sont bien celles demandees.
			if path[1] ~= from or path[#path] ~= to then
				fail("voies — le trace ne relie pas les deux cases demandees")
				break
			end

			--[[
				3. Des tronçons longs.

				C'est la penalite de changement de direction qui est mesuree ici, et
				c'est elle qui distingue le resultat d'un A* ordinaire : sans elle,
				tous les escaliers coutent pareil et l'algorithme en choisit un au
				hasard.

				On mesure la longueur MOYENNE des tronçons plutot que leur nombre.
				Compter les tronçons punissait un contournement de cote
				parfaitement legitime — quatre segments sur vingt-trois cases est
				un bon trace — alors que la moyenne separe nettement les deux cas :
				un escalier a des tronçons d'une case, un trace propre en a de dix.
			]]
			local runs = RailPath.runs(path)
			local manhattan = #path - 1
			if manhattan >= 8 then
				local average = manhattan / #runs
				if average < 3 then
					fail(
						`voies — troncons de {string.format("%.1f", average)} cases en moyenne `
							.. `({#runs} pour {manhattan}) : le trace fait un escalier`
					)
					break
				end
			end
		end

		if checked == 0 then
			fail("voies — aucun trace n'a pu etre verifie")
		end
	end
end

--[[
	Empilement des usines.

	Deux effets qui portent le meme compteur mais ne doivent surtout pas se
	comporter pareil : etaler subit un rendement decroissant, empiler est
	strictement lineaire. Les confondre — ce qu'on faisait — rendait
	l'amelioration systematiquement perdante face a une construction neuve.
]]
do
	local millState = GameState.new(90210)
	local ps = millState:addPlayer(nil, "Fonderie", Random.new(77), 0)
	if not ps then
		fail("usines — impossible de creer la faction de test")
	else
		local capital = ps.capitalTile
		if not capital then
			fail("usines — la faction de test n'a pas de capitale")
		else
			local cx, cy = MapGen.fromIndex(capital)
			for dy = -14, 14 do
				for dx = -14, 14 do
					if dx * dx + dy * dy <= 196 then
						local nx, ny = cx + dx, cy + dy
						if MapGen.inBounds(nx, ny) then
							local index = MapGen.toIndex(nx, ny)
							if millState:isLand(index) then
								millState:setOwner(index, ps.slot)
							end
						end
					end
				end
			end

			--[[
				On cherche deux emplacements suffisamment ecartes, au lieu de les
				supposer a des decalages fixes.

				La version precedente visait (-7, 0) et (7, 0) en dur : selon la
				graine, l'une des deux tombait a l'eau et le test echouait sur un
				moteur parfaitement sain. Un test dont le montage depend du hasard
				de la carte ne mesure pas ce qu'il pretend mesurer.
			]]
			local candidates: { number } = {}
			for radius = 5, 13 do
				for angle = 0, 7 do
					local a2 = angle * math.pi / 4
					local nx = cx + math.floor(math.cos(a2) * radius)
					local ny = cy + math.floor(math.sin(a2) * radius)
					if MapGen.inBounds(nx, ny) then
						local index = MapGen.toIndex(nx, ny)
						if
							millState:isLand(index)
							and buffer.readu8(millState.owner, index) == ps.slot
							and not millState.buildings[index]
						then
							table.insert(candidates, index)
						end
					end
				end
			end

			-- Les deux usines doivent etre assez loin l'une de l'autre pour ne
			-- pas declencher l'accrochage en amelioration, et assez proches pour
			-- rester dans la meme grappe ferroviaire.
			local millSite: number? = nil
			local secondSite: number? = nil
			for _, first in candidates do
				local fx, fy = MapGen.fromIndex(first)
				for _, second in candidates do
					local sx, sy = MapGen.fromIndex(second)
					local dx, dy = fx - sx, fy - sy
					local gap = dx * dx + dy * dy
					local spacing = Config.BUILD_MIN_SPACING * Config.BUILD_MIN_SPACING
					if gap > spacing and gap <= Config.RAIL_RANGE * Config.RAIL_RANGE then
						millSite, secondSite = first, second
						break
					end
				end
				if millSite then
					break
				end
			end

			if not millSite or not secondSite then
				fail("usines — pas de place pour poser les usines de test")
			else
				millState:placeBuilding(millSite, Config.BUILDING.FACTORY, ps.slot)
				local _, single = millState:logisticsFor(ps.slot)
				if single <= 0 then
					fail("usines — une usine reliee a la capitale ne produit rien")
				end

				-- Empiler : niveau 2 produit exactement le double.
				millState:upgradeBuilding(millSite)
				local _, stacked = millState:logisticsFor(ps.slot)
				if math.abs(stacked - single * 2) > 0.001 then
					fail(`usines — empiler donne {stacked / single}x au lieu de 2x`)
				end

				-- Etaler : la seconde usine rapporte, mais nettement moins que
				-- la premiere. C'est ce qui pousse a fonder un second reseau.
				millState:upgradeBuilding(millSite) -- retour au niveau 3
				local _, before = millState:logisticsFor(ps.slot)
				millState:placeBuilding(secondSite, Config.BUILDING.FACTORY, ps.slot)
				local _, spread = millState:logisticsFor(ps.slot)
				if spread <= before then
					fail("usines — une seconde usine ne rapporte rien du tout")
				end
			end
		end
	end
end

--[[
	Plafond de troupes sous-lineaire.

	C'est la correction qui a le plus change l'equilibrage, et c'est aussi celle
	qu'une simple relecture ne rattrape pas : un plafond lineaire se remarque
	seulement dix minutes plus tard, sous la forme d'un leader a 99 % des terres.
]]
do
	local troopState = GameState.new(777)
	-- Joueur humain (pas bot) : le bonus urbain doit rester integral.
	local human = __newInstance("Player")
	human.Name = "Mesure"
	human.UserId = 7771
	local ps = troopState:addPlayer(human, "Mesure", Random.new(777), 0)
	if not ps then
		fail("plafond de troupes — impossible de creer la faction de test")
	else
		ps.cityPopBonus = 0

		ps.tiles = 1000
		local atThousand = troopState:maxTroops(ps)
		ps.tiles = 15000
		local atFifteenThousand = troopState:maxTroops(ps)

		local landRatio = 15
		local troopRatio = atFifteenThousand / atThousand
		if troopRatio >= landRatio then
			fail(`plafond de troupes — {troopRatio}x d'armee pour {landRatio}x de territoire : la courbe est lineaire`)
		end
		if troopRatio > 6 then
			fail(`plafond de troupes — {troopRatio}x reste trop proche du lineaire`)
		end

		-- Les villes, elles, gardent un rendement plein : c'est ce qui en fait le
		-- vrai levier militaire face a l'expansion brute.
		ps.tiles = 1000
		ps.cityPopBonus = 10000
		if math.abs(troopState:maxTroops(ps) - atThousand - 10000) > 0.001 then
			fail("plafond de troupes — le bonus urbain n'est plus integralement compte")
		end
	end
end

--[[
	Expiration des alliances.

	Les pactes permanents figeaient la fin de partie : les survivants finissaient
	tous allies deux a deux, plus une seule cible legale sur la carte, zero
	offensive et zero frappe. Le jeu ne plantait pas, il s'arretait — et rien ne
	le signalait.
]]
do
	local diploState = GameState.new(5150)
	local a = diploState:addPlayer(nil, "Alpha", Random.new(41), 0)
	local b = diploState:addPlayer(nil, "Beta", Random.new(42), 0)
	if not a or not b then
		fail("alliances — impossible de creer les factions de test")
	else
		Diplomacy.request(diploState, a.slot, b.slot)
		local signed = Diplomacy.accept(diploState, a.slot, b.slot)
		if not signed or not diploState:areAllied(a.slot, b.slot) then
			fail("alliances — le pacte n'a pas ete signe")
		end

		-- Toujours en vigueur juste avant l'echeance.
		diploState.tick = Config.ALLIANCE_DURATION - 1
		Diplomacy.step(diploState)
		if not diploState:areAllied(a.slot, b.slot) then
			fail("alliances — le pacte expire avant son terme")
		end

		-- Et tombe de lui-meme ensuite, sans marquer personne : ce n'est pas une
		-- trahison.
		local betrayalsBefore = a.betrayals
		diploState.tick = Config.ALLIANCE_DURATION
		Diplomacy.step(diploState)
		if diploState:areAllied(a.slot, b.slot) then
			fail("alliances — le pacte ne tombe jamais a echeance")
		end
		if a.betrayals ~= betrayalsBefore then
			fail("alliances — une expiration est comptee comme une trahison")
		end

		-- Carence : sans elle, deux camps resignent au tick suivant et la carte
		-- se retrouve a nouveau entierement alliee.
		local tooSoon = Diplomacy.request(diploState, a.slot, b.slot)
		if tooSoon then
			fail("alliances — un pacte est resigne immediatement apres son expiration")
		end
		diploState.tick += Config.ALLIANCE_COOLDOWN
		if not Diplomacy.request(diploState, a.slot, b.slot) then
			fail("alliances — impossible de resigner apres la carence")
		end
	end
end

--[[
	Retraite d'attaque.

	Le rappel n'est honore qu'apres RETREAT_DELAY ticks : sans delai, chaque
	offensive devient un essai sans risque. Le test verifie les trois temps de
	la mecanique — l'ordre est pris, le front survit pendant le delai, les
	survivants rentrent ensuite.
]]
do
	local retreatState = GameState.new(777)
	local a = retreatState:addPlayer(nil, "Attaquant", Random.new(51), 0)
	local b = retreatState:addPlayer(nil, "Assiege", Random.new(52), 0)
	if not a or not b then
		fail("retraite — impossible de creer les factions de test")
	else
		-- On colle l'assiege contre l'attaquant : une tuile frontaliere de a,
		-- puis un large carre de terres pour b afin qu'une seule etape de
		-- combat ne le fasse pas s'effondrer.
		local scratch = table.create(4, 0)
		local anchor: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(retreatState.owner, index) == a.slot then
				local n = MapGen.neighbors(index, scratch)
				for i = 1, n do
					local nb = scratch[i]
					if buffer.readu8(retreatState.owner, nb) == 0 and retreatState:isLand(nb) then
						anchor = nb
						break
					end
				end
			end
			if anchor then
				break
			end
		end
		if not anchor then
			fail("retraite — aucune tuile neutre au contact de l'attaquant")
		else
			local ax, ay = MapGen.fromIndex(anchor)
			local given = 0
			for dy = 0, 24 do
				for dx = 0, 24 do
					local nx, ny = ax + dx, ay + dy
					if given < 500 and MapGen.inBounds(nx, ny) then
						local index = MapGen.toIndex(nx, ny)
						if retreatState:isLand(index) and buffer.readu8(retreatState.owner, index) == 0 then
							retreatState:setOwner(index, b.slot)
							given += 1
						end
					end
				end
			end

			retreatState.combatUnlocked = true
			a.attackRatio = 0.5
			a.troops = 20000

			local launched = retreatState:launchAttack(a.slot, b.slot)
			if not launched or #retreatState.attacks ~= 1 then
				fail("retraite — l'offensive de test n'a pas pu etre lancee")
			else
				if not retreatState:retreatAttack(a.slot, b.slot) then
					fail("retraite — l'ordre de rappel est refuse")
				end
				if retreatState:retreatAttack(a.slot, b.slot) then
					fail("retraite — un second rappel est accepte sur le meme front")
				end
				if retreatState:retreatAttack(b.slot, a.slot) then
					fail("retraite — un rappel sans front est accepte")
				end

				local atk = retreatState.attacks[1]
				local retreatAt = atk.retreatAt
				if not retreatAt then
					fail("retraite — l'echeance du rappel n'est pas enregistree")
				else
					-- Avant l'echeance, le front continue de se battre.
					retreatState.tick = retreatAt - 1
					retreatState:stepAttacks()
					if #retreatState.attacks ~= 1 then
						fail("retraite — le front se degage avant la fin du delai")
					end

					-- A l'echeance, les survivants rentrent au pays (moins la perte de retraite).
					atk = retreatState.attacks[1]
					local survivors = atk and atk.troops or 0
					local retreatLoss = Config.RETREAT_LOSS or 0
					local expectedReturn = math.max(0, survivors) * (1 - retreatLoss)
					local before = a.troops
					retreatState.tick = retreatAt
					retreatState:stepAttacks()
					if #retreatState.attacks ~= 0 then
						fail("retraite — le front n'est pas dissous a echeance")
					end
					if math.abs((a.troops - before) - expectedReturn) > 0.001 then
						fail("retraite — les survivants ne sont pas restitues a l'attaquant")
					end
				end
			end
		end
	end
end

--[[
	Prolongation d'alliance.

	La prolongation est mutuelle : l'intention du premier camp ne change rien
	tant que le second n'a pas marque la sienne. Sans ca, un camp enfermerait
	l'autre dans un pacte dont il ne veut plus.
]]
do
	local extState = GameState.new(5151)
	local a = extState:addPlayer(nil, "Prolonge", Random.new(53), 0)
	local b = extState:addPlayer(nil, "Confirme", Random.new(54), 0)
	local c = extState:addPlayer(nil, "Etranger", Random.new(55), 0)
	if not a or not b or not c then
		fail("prolongation — impossible de creer les factions de test")
	else
		Diplomacy.request(extState, a.slot, b.slot)
		Diplomacy.accept(extState, a.slot, b.slot)

		if Diplomacy.extend(extState, a.slot, c.slot) then
			fail("prolongation — un pacte inexistant peut etre prolonge")
		end

		extState.tick = 100
		if not Diplomacy.extend(extState, a.slot, b.slot) then
			fail("prolongation — l'intention du premier camp est refusee")
		end
		if extState.alliances[a.slot][b.slot] ~= Config.ALLIANCE_DURATION then
			fail("prolongation — l'intention seule repousse deja l'echeance")
		end

		if not Diplomacy.extend(extState, b.slot, a.slot) then
			fail("prolongation — la confirmation du second camp est refusee")
		end
		if extState.alliances[a.slot][b.slot] ~= 100 + Config.ALLIANCE_DURATION then
			fail("prolongation — le pacte confirme ne repart pas pour une duree complete")
		end
		if extState.allianceExtensions[a.slot][b.slot] or extState.allianceExtensions[b.slot][a.slot] then
			fail("prolongation — les intentions ne sont pas purgees apres confirmation")
		end

		-- Une intention en suspens meurt avec le pacte.
		Diplomacy.extend(extState, a.slot, b.slot)
		Diplomacy.breakAlliance(extState, a.slot, b.slot)
		if extState.allianceExtensions[a.slot][b.slot] or extState.allianceExtensions[b.slot][a.slot] then
			fail("prolongation — une intention survit a la rupture du pacte")
		end
	end
end

--[[
	Dons entre allies.

	C'est ce qui donne un corps a l'alliance : sans dons, un pacte n'est qu'un
	traite de non-agression. Les planchers evitent le spam de micro-dons, et le
	receveur ne depasse jamais son plafond de troupes.
]]
do
	local giftState = GameState.new(5152)
	local a = giftState:addPlayer(nil, "Donateur", Random.new(56), 0)
	local b = giftState:addPlayer(nil, "Receveur", Random.new(57), 0)
	local c = giftState:addPlayer(nil, "Tiers", Random.new(58), 0)
	if not a or not b or not c then
		fail("dons — impossible de creer les factions de test")
	else
		Diplomacy.request(giftState, a.slot, b.slot)
		Diplomacy.accept(giftState, a.slot, b.slot)

		a.gold = 1000
		b.gold = 0
		if Diplomacy.donateGold(giftState, a.slot, c.slot, 500) then
			fail("dons — un non-allie peut recevoir de l'or")
		end
		if Diplomacy.donateGold(giftState, a.slot, b.slot, Config.MIN_DONATION - 1) then
			fail("dons — un micro-don sous le plancher est accepte")
		end
		if not Diplomacy.donateGold(giftState, a.slot, b.slot, 400) then
			fail("dons — un don d'or valide est refuse")
		end
		if a.gold ~= 600 or b.gold ~= 400 then
			fail(`dons — comptabilite de l'or fausse ({a.gold} / {b.gold})`)
		end
		if Diplomacy.donateGold(giftState, a.slot, b.slot, 10000) then
			fail("dons — un don superieur au tresor est accepte")
		end

		a.troops = 5000
		b.troops = 0
		if Diplomacy.donateTroops(giftState, a.slot, b.slot, Config.MIN_DONATION_TROOPS - 1) then
			fail("dons — un micro-don de troupes est accepte")
		end
		if not Diplomacy.donateTroops(giftState, a.slot, b.slot, 500) then
			fail("dons — un don de troupes valide est refuse")
		end
		if a.troops ~= 4500 then
			fail(`dons — le donateur conserve {a.troops} troupes au lieu de 4500`)
		end
		local cap = giftState:maxTroops(b)
		if b.troops > cap then
			fail("dons — le receveur depasse son plafond de troupes")
		end
	end
end

--[[
	Le MIRV.

	L'arme ultime ne fait pas un cratere mais une pluie : a mi-parcours, le
	porteur se scinde en ogives independantes qui retombent sur le territoire
	de la victime. Le test verifie la scission elle-meme — c'est elle qui
	distingue le MIRV d'une bombe plus grosse.
]]
do
	local mirvState = GameState.new(8888)
	local a = mirvState:addPlayer(nil, "Stratege", Random.new(61), 0)
	local b = mirvState:addPlayer(nil, "Cible", Random.new(62), 0)
	if not a or not b then
		fail("mirv — impossible de creer les factions de test")
	else
		local siloTile: number? = nil
		local targetTile: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			local owner = buffer.readu8(mirvState.owner, index)
			if not siloTile and owner == a.slot then
				siloTile = index
			elseif not targetTile and owner == b.slot then
				targetTile = index
			end
		end
		if not siloTile or not targetTile then
			fail("mirv — territoires de test introuvables")
		else
			mirvState.buildings[siloTile] =
				{ kind = Config.BUILDING.SILO, slot = a.slot, level = 1, links = {}, cooldown = 0 }
			a.siloCount = 1
			a.era = Eras.requiredForNuke(Config.NUKE.MIRV)
			a.gold = 5000
			b.troops = 10000
			-- Hors de l'immunite de deploiement OF (5 s).
			mirvState.tick = (Config.SPAWN_NUKE_IMMUNITY or 5) * Config.TICK_RATE + 1

			local ok, reason = Nukes.launch(mirvState, a.slot, targetTile, Config.NUKE.MIRV)
			if not ok then
				fail("mirv — le tir est refuse: " .. tostring(reason))
			elseif a.gold ~= 5000 - Config.NUKE_STATS[Config.NUKE.MIRV].cost then
				fail("mirv — le cout du tir n'est pas preleve")
			else
				local rng = Random.new(7)
				local tilesBefore, troopsBefore = b.tiles, b.troops
				local splitSeen = 0
				local steps = 0
				while #mirvState.missiles > 0 and steps < 800 do
					Nukes.step(mirvState, rng, function() end)
					steps += 1
					local warheads = 0
					for _, missile in mirvState.missiles do
						if missile.warhead then
							warheads += 1
						end
					end
					splitSeen = math.max(splitSeen, warheads)
				end

				if splitSeen < 2 then
					fail(`mirv — le porteur ne s'est jamais scinde (ogives vues : {splitSeen})`)
				end
				if #mirvState.missiles ~= 0 then
					fail("mirv — des ogives ne retombent jamais")
				end
				if b.tiles >= tilesBefore and b.troops >= troopsBefore then
					fail("mirv — la pluie d'ogives ne laisse aucun degat")
				end
			end
		end
	end
end

--[[
	Messages rapides et marquage de cible.

	La coordination d'alliance repose sur deux proprietes invisibles en jeu
	normal : le texte substitue bien le nom de la cible, et la marque n'est
	livree qu'a ceux qui doivent la voir — soi-meme et ses allies, jamais a la
	victime.
]]
do
	-- Chaque message qui exige une cible doit contenir le trou "{target}",
	-- sinon il serait envoye avec un placeholder brut.
	for _, entry in QuickChat.MESSAGES do
		local hasHole = string.find(entry.text, "{target}", 1, true) ~= nil
		if entry.needsTarget and not hasHole then
			fail(`quick chat — {entry.id} exige une cible sans trou dans son texte`)
		end
		if not entry.needsTarget and hasHole then
			fail(`quick chat — {entry.id} a un trou mais n'exige pas de cible`)
		end
	end

	local entry = QuickChat.get("attack_target")
	if not entry or not entry.mark then
		fail("quick chat — l'appel a l'attaque ne designe plus sa cible")
	else
		local text = QuickChat.format(entry, "Vodark")
		if text ~= "Attaquez Vodark !" then
			fail(`quick chat — substitution inattendue : {text}`)
		end
	end

	local markState = GameState.new(6161)
	local a = markState:addPlayer(nil, "Marqueur", Random.new(71), 0)
	local b = markState:addPlayer(nil, "Allie", Random.new(72), 0)
	local c = markState:addPlayer(nil, "Victime", Random.new(73), 0)
	if not a or not b or not c then
		fail("marquage — impossible de creer les factions de test")
	else
		Diplomacy.request(markState, a.slot, b.slot)
		Diplomacy.accept(markState, a.slot, b.slot)

		if Diplomacy.setTargetMark(markState, a.slot, a.slot) then
			fail("marquage — on peut se designer soi-meme comme cible")
		end
		if not Diplomacy.setTargetMark(markState, a.slot, c.slot) then
			fail("marquage — la designation est refusee")
		end

		local mine = Diplomacy.viewFor(markState, a.slot)
		local allyView = Diplomacy.viewFor(markState, b.slot)
		local victimView = Diplomacy.viewFor(markState, c.slot)
		if mine.marks[a.slot] ~= c.slot then
			fail("marquage — l'auteur ne voit pas sa propre marque")
		end
		if allyView.marks[a.slot] ~= c.slot then
			fail("marquage — l'allie ne voit pas la marque")
		end
		if victimView.marks[a.slot] ~= nil then
			fail("marquage — la victime voit la marque qui la vise")
		end

		-- Une seconde designation sur la meme cible retire la marque.
		Diplomacy.setTargetMark(markState, a.slot, c.slot)
		if markState.targetMarks[a.slot] ~= nil then
			fail("marquage — la marque ne se retire pas au second geste")
		end

		-- Une marque dont la cible disparait est oubliee.
		Diplomacy.setTargetMark(markState, a.slot, c.slot)
		markState.players[c.slot] = nil
		Diplomacy.step(markState)
		if markState.targetMarks[a.slot] ~= nil then
			fail("marquage — une marque survit a la disparition de sa cible")
		end
	end
end

--[[
	Effondrement d'une faction agonisante.

	Sans cette regle la carte se termine avec des factions a trois tuiles qui ne
	peuvent plus rien faire mais ne meurent jamais.
]]
do
	local collapseState = GameState.new(20260819)
	local victim = collapseState:addPlayer(nil, "Agonisant", Random.new(31), 0)
	local heir = collapseState:addPlayer(nil, "Heritier", Random.new(32), 0)
	if not victim or not heir then
		fail("effondrement — impossible de creer les factions de test")
	else
		-- On colle l'heritier contre la victime pour garantir un contact.
		local center = victim.capitalTile
		if not center then
			fail("effondrement — la victime n'a pas de capitale")
		else
			local cx, cy = MapGen.fromIndex(center)
			local touched = 0
			for dy = -6, 6 do
				local nx, ny = cx + 5, cy + dy
				if MapGen.inBounds(nx, ny) then
					local index = MapGen.toIndex(nx, ny)
					if collapseState:isLand(index) then
						collapseState:setOwner(index, heir.slot)
						touched += 1
					end
				end
			end

			local before = victim.tiles
			victim.gold = 4000
			heir.gold = 500
			collapseState:collapseFaction(victim.slot, heir.slot)
			if victim.tiles >= before or victim.tiles > 0 then
				fail(`effondrement — la victime conserve {victim.tiles} tuiles sur {before}`)
			end
			if touched > 0 and heir.tiles <= touched then
				fail("effondrement — l'assaillant n'a rien recupere du territoire partage")
			end

			--[[
				Le butin de mise a mort.

				Achever une faction est l'effort le plus long du jeu ; sans butin,
				sa seule recompense etait une ligne dans le fil de notifications.
				Rien ne planterait si ce transfert disparaissait — le jeu
				continuerait, simplement plus plat.
			]]
			if heir.gold <= 500 then
				fail("effondrement — achever une faction ne rapporte rien au vainqueur")
			end
			if victim.gold >= 4000 then
				fail("effondrement — la victime garde son tresor apres avoir ete achevee")
			end

			-- Un bot est depouille entierement ; un humain de moitie seulement,
			-- pour que sa defaite ne soit pas une aubaine pour son bourreau.
			local looted = heir.gold - 500
			local expected = math.floor(4000 * Config.CONQUEST_PLUNDER_BOT)
			if looted ~= expected then
				fail(`effondrement — butin de {looted} au lieu de {expected}`)
			end

			--[[
				Le butin doit etre localise, sinon le "+X or" flotte au milieu de
				nulle part. La file est ce que le serveur envoie aux clients.
			]]
			local loot = collapseState.plunders[#collapseState.plunders]
			if not loot then
				fail("effondrement — aucun butin n'est signale aux clients")
			elseif loot.slot ~= heir.slot or loot.gold ~= expected then
				fail(`effondrement — butin signale a {loot.slot} pour {loot.gold}`)
			elseif loot.tile < 0 or loot.tile >= Config.TILE_COUNT then
				fail("effondrement — le butin est signale sur une tuile inexistante")
			end
		end
	end
end

-- Seeds secondaires : on ne veut pas un rapport detaille, juste la certitude
-- qu'aucune carte ne fait planter la simulation ni deriver la comptabilite.
local EXTRA_SEEDS = { 7, 99991, 31337, 1234567 }
for _, seed in EXTRA_SEEDS do
	local run = runMatch(seed, 3000)
	local survivors = 0
	for _ in run.state.players do
		survivors += 1
	end
	print(
		`seed {seed} : terre {string.format("%.0f", run.landRatio * 100)}%  `
			.. `factions {run.spawned}->{survivors}  frappes {run.explosions}  `
			.. `{string.format("%.2f", run.elapsed)}s`
	)
end

print("")

local main = runMatch(424242, TICKS)
local state = main.state
local explosions = main.explosions
local elapsed = main.elapsed

print(`carte : {Config.MAP_WIDTH}x{Config.MAP_HEIGHT}, {state.landCount} tuiles de terre`)
print(`factions : {main.spawned}`)

--=============================================================================
-- Rapport
--=============================================================================

local totalTiles, totalGold, totalTroops = 0, 0, 0
local buildingCounts = {}
local allianceCount = 0
local betrayalCount = 0

for _, ps in state.players do
	totalTiles += ps.tiles
	totalGold += ps.gold
	totalTroops += ps.troops
	betrayalCount += ps.betrayals
end

for _, building in state.buildings do
	buildingCounts[building.kind] = (buildingCounts[building.kind] or 0) + 1
end

for _, set in state.alliances do
	for _ in set do
		allianceCount += 1
	end
end
allianceCount //= 2

local ranked = {}
for slot, ps in state.players do
	table.insert(ranked, { slot = slot, name = ps.name, tiles = ps.tiles, troops = math.floor(ps.troops) })
end
table.sort(ranked, function(a, b)
	return a.tiles > b.tiles
end)

print("")
print(`--- apres {TICKS} ticks ({string.format("%.1f", TICKS / Config.TICK_RATE)} s de jeu simule) ---`)
print(`temps de calcul   : {string.format("%.2f", elapsed)} s`)
print(`colonisation      : {string.format("%.1f", state:colonizedRatio() * 100)} % des terres`)
print(`batiments         : ville={buildingCounts[1] or 0} port={buildingCounts[2] or 0} bunker={buildingCounts[3] or 0} silo={buildingCounts[4] or 0} sam={buildingCounts[5] or 0} navale={buildingCounts[9] or 0} capitale={buildingCounts[6] or 0} labo={buildingCounts[7] or 0} usine={buildingCounts[8] or 0}`)
local carriers = 0
for _, boat in state.boats do
	if boat.kind == 3 then
		carriers += 1
	end
end
print(`navires en mer    : {#state.boats} dont {carriers} porte-avions`)
print(`offensives actives: {#state.attacks}`)
print(`alliances         : {allianceCount}`)
print(`trahisons         : {betrayalCount}`)
print(`explosions        : {explosions}`)
print(`capitales prises  : {state.capitalEvents}`)

local eraCounts = {}
for _, ps in state.players do
	eraCounts[ps.era] = (eraCounts[ps.era] or 0) + 1
end
local eraLine = ""
for era = 1, 5 do
	eraLine ..= `{era}:{eraCounts[era] or 0}  `
end
print(`eres atteintes    : {eraLine}`)

local function eraTime(era)
	local tick = main.firstEra[era]
	if not tick then
		return "jamais"
	end
	local seconds = tick / Config.TICK_RATE
	return `{math.floor(seconds / 60)}m{string.format("%02d", math.floor(seconds % 60))}`
end
print(`premiere ere 2/3/4/5 : {eraTime(2)} / {eraTime(3)} / {eraTime(4)} / {eraTime(5)}`)
print(`or total          : {math.floor(totalGold)}`)

-- Concentration : combien de factions pesent encore reellement en fin de
-- partie. C'est la mesure du "milieu de partie" — une valeur de 1 ou 2 signifie
-- que la partie s'est jouee toute seule.
local contenders = 0
local leaderShare = 0
for _, ps in state.players do
	local share = ps.tiles / math.max(1, state.landCount)
	if share > 0.05 then
		contenders += 1
	end
	if share > leaderShare then
		leaderShare = share
	end
end
print(`part du leader    : {string.format("%.0f", leaderShare * 100)} %`)
print(`factions >5%      : {contenders}`)
print("")
print("classement :")
for i = 1, math.min(6, #ranked) do
	local r = ranked[i]
	print(`  {i}. {r.name}  {r.tiles} tuiles  {r.troops} troupes`)
end

print("")
--=============================================================================
-- Cout du monde 3D
--=============================================================================
-- Le vrai risque du monde en blocs n'est pas la logique mais le nombre de
-- Parts. On le mesure sur l'etat reel de fin de partie plutot que de l'esperer.

local serverBlocks = #WorldBuilder.blocksFor(state.terrain)

local clientParts = 0
local worstChunk = 0
local chunkScratch = {}
for chunk = 0, Config.CHUNKS_X * Config.CHUNKS_Y - 1 do
	local cx = (chunk % Config.CHUNKS_X) * Config.CHUNK_SIZE
	local cy = (chunk // Config.CHUNKS_X) * Config.CHUNK_SIZE
	local x1 = math.min(cx + Config.CHUNK_SIZE - 1, Config.MAP_WIDTH - 1)
	local y1 = math.min(cy + Config.CHUNK_SIZE - 1, Config.MAP_HEIGHT - 1)

	-- Meme cle que WorldRenderer.chunkKeyAt : proprietaire et relief.
	local rects = GreedyMesh.rectangles(function(x, y)
		local index = MapGen.toIndex(x, y)
		local terrain = buffer.readu8(state.terrain, index)
		if terrain == Config.TERRAIN.OCEAN then
			return nil
		end
		return buffer.readu8(state.owner, index) * 16 + terrain
	end, cx, cy, x1, y1, chunkScratch)

	clientParts += #rects
	if #rects > worstChunk then
		worstChunk = #rects
	end
end

local landTiles = state.landCount
print("")
print("--- cout du monde 3D ---")
print(`collision serveur : {serverBlocks} blocs (statique, repliquee une fois)`)
print(`visuel client     : {clientParts} parts pour {landTiles} tuiles de terre`)
print(`  compression     : {string.format("%.1f", landTiles / math.max(1, clientParts))}x`)
print(`  pire chunk      : {worstChunk} parts`)

-- Rythme : le nucleaire doit etre un climax de fin de partie. Trop tot il
-- ecrase la phase d'expansion, jamais il rend toute la branche technologique
-- decorative.
local atomicTick = main.firstEra[4]
if not atomicTick then
	fail("aucune faction n'atteint l'ere Atomique en 10 minutes")
elseif atomicTick < 2400 then
	fail(`ere Atomique atteinte des {math.floor(atomicTick / Config.TICK_RATE)}s : trop tot`)
end

-- Seuils au-dela desquels le rendu devient un probleme sur mobile.
--[[
	Seuil du visuel client.

	Mesure : environ 7 000 Parts en fin de partie. Ce qui les fragmente n'est
	plus l'altitude — la carte est plate — mais le decoupage politique croise au
	type de terrain : une carte disputee entre six factions fusionne bien moins
	bien qu'une carte partagee entre deux. Le seuil laisse de la marge pour une
	partie plus morcelee que la moyenne, tout en attrapant un changement de
	generation qui ferait exploser la fragmentation.
]]
if clientParts > 9000 then
	fail(`{clientParts} parts cote client : trop pour tenir sur mobile`)
end

--[[
	Seuil de la collision serveur.

	La carte etant plate, la cle de fusion est constante sur toute la terre
	ferme : on tombe a quelques centaines de dalles. Le seuil est resserre en
	consequence — a 6 000 il ne cassait plus rien, alors qu'une regression qui
	remettrait de la hauteur dans la cle se verrait immediatement ici.
]]
if serverBlocks > 1500 then
	fail(`{serverBlocks} blocs de collision : replication initiale trop lourde`)
end

--=============================================================================
-- P0 — hash carte, intentions, capacite, metrics
--=============================================================================

print("")
print("--- P0 contrats ---")

do
	local a = MapGen.generate(4242)
	local b = MapGen.generate(4242)
	local ha, hb = MapGen.terrainHash(a), MapGen.terrainHash(b)
	if ha ~= hb then
		fail(`hash carte non deterministe : {ha} vs {hb}`)
	end
	local meta = MapGen.mapMeta(4242, a)
	if meta.mapId ~= Config.MAP_ID or meta.terrainHash ~= ha then
		fail("mapMeta incoherent")
	end
	local counts = MapGen.countByBiome(a)
	local sum = 0
	for _, n in counts do
		sum += n
	end
	if sum ~= Config.TILE_COUNT then
		fail(`compte biomes {sum} != TILE_COUNT`)
	end
	print(`hash carte seed 4242 : {ha}`)
end

do
	if Config.MAX_HUMAN_PLAYERS > Config.MAX_TOTAL_FACTIONS then
		fail("MAX_HUMAN_PLAYERS > MAX_TOTAL_FACTIONS")
	end
	if Config.PUBLIC_MATCH_CAPACITY > Config.MAX_TOTAL_FACTIONS then
		fail("PUBLIC_MATCH_CAPACITY > MAX_TOTAL_FACTIONS")
	end
	if Config.RENDER_MODE ~= "Blocks" then
		fail(`RENDER_MODE de production doit etre Blocks, pas {Config.RENDER_MODE}`)
	end
	print(
		`capacite : humans={Config.MAX_HUMAN_PLAYERS} bots={Config.MAX_BOTS} public={Config.PUBLIC_MATCH_CAPACITY} slots={Config.MAX_TOTAL_FACTIONS}`
	)
end

do
	IntentValidator.reset()
	local state = GameState.new(99)
	state.mode = GameModes.get("classic")
	local fakePlayer = __newInstance("Player")
	fakePlayer.Name = "Tester"
	fakePlayer.UserId = 42
	local ps = state:addPlayer(fakePlayer, "Testland", Random.new(1), 0)
	if not ps then
		fail("intentions — spawn joueur impossible")
	else
		local replies = {}
		local refuses = {}
		local ctx = {
			state = state,
			matchPhase = "playing",
			matchId = "test",
			slotOf = function(p)
				return if p == fakePlayer then ps.slot else nil
			end,
			doctrineLockAt = os.clock() + 999,
			now = os.clock,
			buildings = Buildings,
			navy = Navy,
			nukes = Nukes,
			diplomacy = Diplomacy,
			research = Research,
			reply = function(_p, ok, msg)
				table.insert(replies, { ok = ok, msg = msg })
			end,
			refuse = function(_p, reason, detail)
				table.insert(refuses, { reason = reason, detail = detail })
			end,
			broadcastRoster = function() end,
		}

		local ok1 = IntentValidator.enqueue(ctx, fakePlayer, "SetAttackRatio", 1, { ratio = 0.4 })
		local okDup, reasonDup = IntentValidator.enqueue(ctx, fakePlayer, "SetAttackRatio", 1, { ratio = 0.5 })
		if not ok1 then
			fail("intentions — premiere sequence refusee")
		end
		if okDup or reasonDup ~= "DuplicateSequence" then
			fail(`intentions — doublon non detecte ({tostring(reasonDup)})`)
		end
		-- Feel OF : application immediate a l'enqueue, pas au flush.
		if ps.attackRatio < 0.39 or ps.attackRatio > 0.41 then
			fail(`intentions — ratio non applique immediatement ({ps.attackRatio})`)
		end
		if IntentValidator.flush(ctx) ~= 0 then
			fail("intentions — la file aurait du rester vide apres apply immediat")
		end

		-- Rate limit
		IntentValidator.reset()
		local limited = false
		for i = 1, (Config.INTENT_RATE_LIMIT_PER_SEC or 20) + 5 do
			local ok, reason = IntentValidator.enqueue(ctx, fakePlayer, "SetAttackRatio", i, { ratio = 0.2 })
			if not ok and reason == "RateLimited" then
				limited = true
				break
			end
		end
		if not limited then
			fail("intentions — rate limit non declenche")
		end
		print("intentions : sequence, idempotence, apply immediat, rate limit OK")

		-- Doctrine inconnue : plus de repli silencieux vers Industrielle.
		IntentValidator.reset()
		local okBadDoc, reasonBadDoc =
			IntentValidator.enqueue(ctx, fakePlayer, "ChooseDoctrine", 1, { doctrineId = 999 })
		if okBadDoc or reasonBadDoc ~= "InvalidSchema" then
			fail(`intentions — doctrine 999 acceptee ({tostring(reasonBadDoc)})`)
		end

		-- Action diplomatique hors catalogue.
		local okBadDip, reasonBadDip = IntentValidator.enqueue(
			ctx,
			fakePlayer,
			"Diplomacy",
			2,
			{ action = "hackGold", targetSlot = 1 }
		)
		if okBadDip or reasonBadDip ~= "UnknownAction" then
			fail(`intentions — diplomatie pirate acceptee ({tostring(reasonBadDip)})`)
		end

		-- Nuke kind hors NUKE_STATS.
		local okBadNuke, reasonBadNuke =
			IntentValidator.enqueue(ctx, fakePlayer, "Nuke", 3, { index = 0, kind = 99 })
		if okBadNuke or reasonBadNuke ~= "InvalidSchema" then
			fail(`intentions — nuke kind 99 accepte ({tostring(reasonBadNuke)})`)
		end

		-- Phase ended : plus aucun ordre, y compris doctrine / ratio.
		ctx.matchPhase = "ended"
		local okEnded, reasonEnded =
			IntentValidator.enqueue(ctx, fakePlayer, "SetAttackRatio", 4, { ratio = 0.5 })
		if okEnded or reasonEnded ~= "NotPlaying" then
			fail(`intentions — ordre accepte en phase ended ({tostring(reasonEnded)})`)
		end
		ctx.matchPhase = "playing"
		print("intentions : schema doctrine/nuke/diplomatie, ended OK")

		-- Feel OF : apply immediat → la file reste vide ; MAX_PENDING_INTENTS est
		-- dormant. On verifie juste que le rate limit ne laisse rien en file.
		if IntentValidator.pendingCount() ~= 0 then
			fail(`intentions — file non vide apres apply immediat ({IntentValidator.pendingCount()})`)
		end

		-- QuickChat : le cooldown serveur doit faire echouer l'intent, pas un succes fantome.
		IntentValidator.reset()
		table.clear(replies)
		state.tick = 10
		local okChat = IntentValidator.enqueue(ctx, fakePlayer, "QuickChat", 1, { messageId = "social_luck" })
		if not okChat then
			fail("intentions — QuickChat refuse a l'enqueue")
		end
		local firstChat = replies[#replies]
		if not firstChat or not firstChat.ok then
			fail("intentions — premier QuickChat non applique")
		end
		table.clear(replies)
		local okChat2 = IntentValidator.enqueue(ctx, fakePlayer, "QuickChat", 2, { messageId = "social_luck" })
		if not okChat2 then
			fail("intentions — second QuickChat refuse a l'enqueue (schema OK, apply doit refuser)")
		end
		local secondChat = replies[#replies]
		if not secondChat or secondChat.ok then
			fail("intentions — QuickChat en cooldown rapporte un succes")
		end
		print("intentions : QuickChat cooldown honore")

		-- needsTarget sans sequence = client 2-args (id, N) : N n'est pas une cible.
		IntentValidator.reset()
		table.clear(replies)
		state.quickChatSent[ps.slot] = nil
		state.quickChatLast[ps.slot] = nil
		state.tick = 80
		local chatTarget = state:addPlayer(nil, "CibleChat", Random.new(2), 0)
		if not chatTarget then
			fail("intentions — cible QuickChat introuvable")
		else
			local okHijack, reasonHijack = IntentValidator.enqueue(
				ctx,
				fakePlayer,
				"QuickChat",
				nil,
				{ messageId = "attack_target", targetSlot = chatTarget.slot }
			)
			if okHijack or reasonHijack ~= "InvalidSchema" then
				fail(`intentions — QuickChat 2-args accepte ({tostring(reasonHijack)})`)
			end
			if state.targetMarks[ps.slot] == chatTarget.slot then
				fail("intentions — QuickChat 2-args a marque la cible")
			end
			local okMark = IntentValidator.enqueue(
				ctx,
				fakePlayer,
				"QuickChat",
				10,
				{ messageId = "attack_target", targetSlot = chatTarget.slot }
			)
			if not okMark then
				fail("intentions — QuickChat 3-args refuse a l'enqueue")
			end
			if state.targetMarks[ps.slot] ~= chatTarget.slot then
				fail("intentions — QuickChat 3-args n'a pas marque")
			end
			print("intentions : QuickChat 2-args refuse, 3-args marque")
		end
	end
end

do
	-- Alliance : areAllied exige les deux directions.
	local state = GameState.new(101)
	local a = state:addPlayer(nil, "A", Random.new(1), 0)
	local b = state:addPlayer(nil, "B", Random.new(2), 0)
	if not a or not b then
		fail("alliances — spawn impossible")
	else
		state.alliances[a.slot][b.slot] = true
		if state:areAllied(a.slot, b.slot) then
			fail("areAllied vrai sur un pacte a une direction")
		end
		state.alliances[b.slot][a.slot] = true
		if not state:areAllied(a.slot, b.slot) then
			fail("areAllied faux sur un pacte symetrique")
		end
		state.alliances[b.slot][a.slot] = nil
		local oneWay = Diplomacy.viewFor(state, a.slot)
		if oneWay.allies[b.slot] then
			fail("viewFor — alliance unidirectionnelle exposee au HUD")
		end
	end
end

do
	-- removePlayer doit laisser les frontieres voisines coherentes.
	local state = GameState.new(202)
	local a = state:addPlayer(nil, "Stay", Random.new(1), 0)
	local b = state:addPlayer(nil, "Leave", Random.new(2), 0)
	if not a or not b then
		fail("removePlayer — spawn impossible")
	else
		local contact = nil
		local scratch = table.create(4, 0)
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(state.owner, index) == a.slot and state:isLand(index) then
				local n = MapGen.neighbors(index, scratch)
				for i = 1, n do
					local nb = scratch[i]
					if state:isLand(nb) and buffer.readu8(state.owner, nb) == 0 then
						state:setOwner(nb, b.slot)
						contact = index
						break
					end
				end
			end
			if contact then
				break
			end
		end
		if not contact then
			fail("removePlayer — impossible de creer un contact")
		elseif not a.border[contact] then
			fail("removePlayer — contact non marque frontiere avant depart")
		else
			state:removePlayer(b.slot)
			if buffer.readu8(state.owner, contact) ~= a.slot then
				fail("removePlayer — tuile du survivant perdue")
			end
			if not a.border[contact] then
				fail("removePlayer — frontiere du survivant non rafraichie (contact vs neutre)")
			end
		end
	end
end

do
	local ChantierB = __require("ChantierB")
	local state = GameState.new(303)
	local bot = state:addPlayer(nil, "Stripped", Random.new(3), 0)
	if not bot then
		fail("stripTerritory — spawn impossible")
	else
		ChantierB.stripTerritory(state, bot)
		if bot.tiles ~= 0 then
			fail(`stripTerritory — tiles={bot.tiles} attendu 0`)
		end
		local owned = 0
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(state.owner, index) == bot.slot then
				owned += 1
			end
		end
		if owned ~= 0 then
			fail(`stripTerritory — {owned} tuiles encore possedees`)
		end
	end
end

do
	-- justClaimed ne doit plus avaler une vraie offensive.
	local state = GameState.new(404)
	state.combatUnlocked = true
	local a = state:addPlayer(nil, "Claimant", Random.new(4), 0)
	if not a then
		fail("justClaimed — spawn impossible")
	else
		a.justClaimed = true
		a.troops = 500
		a.attackRatio = 1
		local target = Config.NEUTRAL_SLOT
		local ok, message = state:launchAttack(a.slot, target)
		if ok and message == nil and #state.attacks == 0 then
			fail("justClaimed — launchAttack a renvoye un succes silencieux")
		end
	end
end

do
	-- Nukes : meme garde combatUnlocked que terre / mer.
	local state = GameState.new(505)
	state.combatUnlocked = false
	local a = state:addPlayer(nil, "Bomber", Random.new(5), 0)
	local b = state:addPlayer(nil, "Target", Random.new(6), 0)
	if not a or not b then
		fail("nukes prep — spawn impossible")
	else
		a.era = 5
		a.gold = 99999
		a.spawnTick = -10000 -- hors SPAWN_NUKE_IMMUNITY pour isoler combatUnlocked
		local siloTile = nil
		local scratch = table.create(4, 0)
		if a.capitalTile then
			local n = MapGen.neighbors(a.capitalTile, scratch)
			for i = 1, n do
				local nb = scratch[i]
				if buffer.readu8(state.owner, nb) == a.slot then
					siloTile = nb
					break
				end
			end
		end
		if not siloTile then
			fail("nukes prep — pas de tuile pour le silo")
		else
			state:placeBuilding(siloTile, Config.BUILDING.SILO, a.slot)
			local ok, message = Nukes.launch(state, a.slot, b.capitalTile, Config.NUKE.ATOM)
			if ok then
				fail("nukes prep — frappe acceptee pendant la preparation")
			elseif not message or not string.find(message, "preparation", 1, true) then
				fail(`nukes prep — mauvais refus ({tostring(message)})`)
			end
			state.combatUnlocked = true
			local ok2, message2 = Nukes.launch(state, a.slot, b.capitalTile, Config.NUKE.ATOM)
			if not ok2 then
				fail(`nukes prep — frappe refusee une fois le combat ouvert ({tostring(message2)})`)
			end
		end
	end
end

do
	if math.abs((Config.BOAT_TROOP_RATIO or 0) - 0.2) > 1e-9 then
		fail(`BOAT_TROOP_RATIO={Config.BOAT_TROOP_RATIO} attendu 0.2 (charge 1/5)`)
	end
end

do
	-- Cadran : un humain pas encore spawn (tiles=0) ne doit pas saigner.
	local Doomsday = __require("Doomsday")
	local state = GameState.new(707)
	state.mode = GameModes.get("blitz")
	local leader = state:addPlayer(nil, "Leader", Random.new(7), 0)
	local afk = state:addPlayer(nil, "Afk", Random.new(8), 0)
	if not leader or not afk then
		fail("doomsday spawn — spawn impossible")
	else
		local ChantierB = __require("ChantierB")
		ChantierB.stripTerritory(state, afk)
		afk.awaitingSpawn = true
		afk.troops = 12000
		local before = afk.troops
		state.tick = math.floor((state.mode.duration * 0.55) / Config.TICK_DT)
		if not Doomsday.waveState(state.mode.duration, state.tick * Config.TICK_DT).armed then
			fail("doomsday spawn — vague non armee dans le scenario de test")
		elseif GameState.stepDoomsday then
			GameState.stepDoomsday(state)
			if afk.troops ~= before then
				fail(`doomsday spawn — troupes AFK {before} -> {afk.troops}`)
			end
		else
			fail("doomsday spawn — stepDoomsday absent")
		end
	end
end

do
	-- Beachhead : la tuile debarquee est deja a l'attaquant. L'enfiler dans
	-- la frontier faisait skip + remboursement le meme tick (invasions mortes).
	local state = GameState.new(9191)
	state.combatUnlocked = true
	local invader = state:addPlayer(nil, "Debarque", Random.new(91), 0)
	local defender = state:addPlayer(nil, "Cote", Random.new(92), 0)
	if not invader or not defender then
		fail("beachhead — spawn impossible")
	else
		local scratch = table.create(4, 0)
		local landing: number? = nil
		local inland: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if state:isLand(index) then
				local n = MapGen.neighbors(index, scratch)
				for i = 1, n do
					local nb = scratch[i]
					if state:isLand(nb) and nb ~= index then
						landing, inland = index, nb
						break
					end
				end
			end
			if landing then
				break
			end
		end
		if not landing or not inland then
			fail("beachhead — paire terrestre introuvable")
		else
			state:setOwner(landing, invader.slot)
			state:setOwner(inland, defender.slot)
			local committed = 800
			local troopsBefore = invader.troops
			state:seedBeachhead(invader.slot, defender.slot, committed, landing)
			if #state.attacks ~= 1 then
				fail(`beachhead — {#state.attacks} fronts apres seed (attendu 1)`)
			else
				local atk = state.attacks[1]
				if atk.queued[landing] then
					fail("beachhead — la tuile debarquee est encore dans la frontier")
				end
				if not atk.queued[inland] then
					fail("beachhead — le voisin cible n'est pas enfile")
				end
				if atk.frontier.size < 1 then
					fail("beachhead — frontier vide")
				end
				state:step()
				if invader.troops >= troopsBefore + committed then
					fail("beachhead — troupes remboursees sans expansion")
				end
				local inlandOwner = buffer.readu8(state.owner, inland)
				local still = false
				for _, front in state.attacks do
					if front.attacker == invader.slot then
						still = true
						break
					end
				end
				if inlandOwner ~= invader.slot and not still then
					fail("beachhead — ni capture ni front survivant")
				end
				print("beachhead : frontier voisins, pas de remboursement")
			end
		end
	end
end

do
	-- Renforcer un front vise ne doit pas creer un second Attack.
	local state = GameState.new(4242)
	state.combatUnlocked = true
	local a = state:addPlayer(nil, "Aimer", Random.new(11), 0)
	if not a then
		fail("aim reinforce — spawn impossible")
	else
		a.troops = 8000
		a.attackRatio = 1
		local scratch = table.create(4, 0)
		local aimTile: number? = nil
		local targetSlot: number? = nil
		for index in a.border do
			local n = MapGen.neighbors(index, scratch)
			for i = 1, n do
				local nb = scratch[i]
				if state:isLand(nb) then
					local owner = buffer.readu8(state.owner, nb)
					if owner ~= a.slot then
						aimTile = nb
						targetSlot = owner
						break
					end
				end
			end
			if aimTile then
				break
			end
		end
		if not aimTile or targetSlot == nil then
			fail("aim reinforce — pas de contact")
		else
			a.aimTile = aimTile
			local ok1 = state:launchAttack(a.slot, targetSlot)
			if not ok1 then
				fail("aim reinforce — premiere offensive refusee")
			else
				local n1 = #state.attacks
				if n1 < 1 then
					fail("aim reinforce — aucun front")
				else
					a.troops = 8000
					a.aimTile = aimTile
					state:launchAttack(a.slot, targetSlot)
					if #state.attacks ~= n1 then
						fail(`aim reinforce — fronts dupliques ({n1} -> {#state.attacks})`)
					end
					print("aim reinforce : un seul front apres deux lancers")
				end
			end
		end
	end
end

do
	-- Colis : le niveau snapshot au depart, pas le niveau a l'arrivee.
	local landState = GameState.new(2720)
	local a = landState:addPlayer(nil, "Snapshot", Random.new(22), 0)
	if not a then
		fail("colis snapshot — spawn impossible")
	else
		local factoryTile: number? = nil
		local cityTile: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if landState:isLand(index) then
				local fx, fy = MapGen.fromIndex(index)
				local cx, cy = fx + Config.TRUCK_SPEED + 3, fy
				if MapGen.inBounds(cx, cy) then
					local candidate = MapGen.toIndex(cx, cy)
					if landState:isLand(candidate) then
						factoryTile, cityTile = index, candidate
						break
					end
				end
			end
		end
		if not factoryTile or not cityTile then
			fail("colis snapshot — paire terrestre introuvable")
		else
			landState:setOwner(factoryTile, a.slot)
			landState:setOwner(cityTile, a.slot)
			landState:placeBuilding(factoryTile, Config.BUILDING.FACTORY, a.slot)
			landState:placeBuilding(cityTile, Config.BUILDING.CITY, a.slot)
			landState.tick += 1
			Trade.step(landState, Random.new(7), function() end)
			local delivery = landState.tradeDeliveries[factoryTile]
			if not delivery then
				fail("colis snapshot — pas d'expedition")
			else
				local snapLevel = delivery.level
				landState.buildings[factoryTile].level = snapLevel + 2
				local goldBefore = a.gold
				landState.tick = delivery.arrivalTick
				Trade.step(landState, Random.new(9), function() end)
				local gained = a.gold - goldBefore
				local stopBonus = 1 + math.min(0.8, (delivery.links - 1) * (Config.TRAIN_STOP_BONUS or 0.12))
				local expected = (Config.TRUCK_GOLD_BASE + delivery.distance * Config.TRUCK_GOLD_PER_TILE)
					* snapLevel
					* math.max(1, delivery.links)
					* stopBonus
				if math.abs(gained - expected) > 0.01 then
					fail(`colis snapshot — gain {gained} attendu {expected} (niveau depart)`)
				end
				print("colis snapshot : niveau au depart honore")
			end
		end
	end
end

do
	-- Proposition expiree : refus meme si Diplomacy.step n'a pas encore nettoye.
	local state = GameState.new(5153)
	local a = state:addPlayer(nil, "Offrant", Random.new(71), 0)
	local b = state:addPlayer(nil, "Cible", Random.new(72), 0)
	if not a or not b then
		fail("accept expire — spawn impossible")
	else
		Diplomacy.request(state, a.slot, b.slot)
		state.tick += Config.ALLIANCE_REQUEST_TIMEOUT + 1
		if Diplomacy.accept(state, a.slot, b.slot) then
			fail("accept expire — proposition perimee encore honoree")
		end
		if state:areAllied(a.slot, b.slot) then
			fail("accept expire — pacte cree hors delai")
		end
		print("accept expire : proposition perimee refusee")
	end
end

do
	-- Terre + tete de pont contre le meme slot : un clic retraite marque les deux.
	local state = GameState.new(7070)
	state.combatUnlocked = true
	local a = state:addPlayer(nil, "TerreMer", Random.new(17), 0)
	local b = state:addPlayer(nil, "DoubleFront", Random.new(18), 0)
	if not a or not b then
		fail("retraite couple — spawn impossible")
	else
		local scratch = table.create(4, 0)
		local contact: number? = nil
		local inland: number? = nil
		for index in a.border do
			local n = MapGen.neighbors(index, scratch)
			for i = 1, n do
				local nb = scratch[i]
				if state:isLand(nb) and buffer.readu8(state.owner, nb) ~= a.slot then
					contact = index
					inland = nb
					break
				end
			end
			if contact then
				break
			end
		end
		if not contact or not inland then
			fail("retraite couple — pas de contact")
		else
			state:setOwner(inland, b.slot)
			a.troops = 12000
			a.attackRatio = 0.4
			local launched = state:launchAttack(a.slot, b.slot)
			state:seedBeachhead(a.slot, b.slot, 800, contact)
			if not launched or #state.attacks < 2 then
				fail(`retraite couple — {#state.attacks} fronts (attendu 2)`)
			else
				local ok = state:retreatAttack(a.slot, b.slot)
				if not ok then
					fail("retraite couple — ordre refuse")
				end
				local marked = 0
				for _, atk in state.attacks do
					if atk.attacker == a.slot and atk.target == b.slot and atk.retreatAt then
						marked += 1
					end
				end
				if marked < 2 then
					fail(`retraite couple — {marked} fronts marques (attendu 2)`)
				end
				if state:retreatAttack(a.slot, b.slot) then
					fail("retraite couple — second clic accepte")
				end
				print("retraite couple : terre + tete de pont marques")
			end
		end
	end
end

do
	-- removePlayer du defenseur restitue les troupes engagees a l'attaquant.
	local state = GameState.new(6060)
	state.combatUnlocked = true
	local a = state:addPlayer(nil, "Restitue", Random.new(21), 0)
	local b = state:addPlayer(nil, "Deconnecte", Random.new(22), 0)
	if not a or not b then
		fail("refund disconnect — spawn impossible")
	else
		local scratch = table.create(4, 0)
		local found = false
		for index in a.border do
			local n = MapGen.neighbors(index, scratch)
			for i = 1, n do
				local nb = scratch[i]
				if state:isLand(nb) and buffer.readu8(state.owner, nb) ~= a.slot then
					state:setOwner(nb, b.slot)
					found = true
					break
				end
			end
			if found then
				break
			end
		end
		if not found then
			fail("refund disconnect — pas de contact")
		else
			a.troops = 9000
			a.attackRatio = 1
			local launched = state:launchAttack(a.slot, b.slot)
			local committed = 0
			for _, atk in state.attacks do
				if atk.attacker == a.slot and atk.target == b.slot then
					committed += atk.troops
				end
			end
			if not launched or committed <= 0 then
				fail("refund disconnect — offensive absente")
			else
				local reserve = a.troops
				state:removePlayer(b.slot)
				if #state.attacks ~= 0 then
					fail(`refund disconnect — {#state.attacks} fronts survivants`)
				end
				if math.abs(a.troops - (reserve + committed)) > 0.001 then
					fail(
						`refund disconnect — troupes {a.troops} attendu {reserve + committed}`
					)
				end
				print("refund disconnect : troupes restituees a l'attaquant")
			end
		end
	end
end

do
	if math.abs((Config.RETREAT_LOSS or 0) - 0.25) > 1e-9 then
		fail(`RETREAT_LOSS={Config.RETREAT_LOSS} attendu 0.25`)
	end
	if math.abs((Config.BOAT_RETREAT_LOSS or 0) - 0.25) > 1e-9 then
		fail(`BOAT_RETREAT_LOSS={Config.BOAT_RETREAT_LOSS} attendu 0.25`)
	end
end

do
	local ChantierB = __require("ChantierB")
	local perTick = ChantierB.attackTilesPerTick(10000, nil, 1)
	print(
		`combat vivant : MAX_TILES_PER_TICK={Config.MAX_TILES_PER_TICK} (inutilise) attackTilesPerTick(10k,nil,1)={perTick} guard=80`
	)
end

do
	local report = TickMetrics.formatReport()
	print(`metrics run principal : {report}`)
	local snap = TickMetrics.snapshot()
	if snap.totals.ticks < 100 then
		fail("metrics — pas assez d'echantillons sur le run principal")
	end
	-- Ne change PAS MAX_TILES_PER_TICK ici : on journalise seulement.
	print(
		`MAX_TILES_PER_TICK reste {Config.MAX_TILES_PER_TICK} (p95 changed={snap.p95.changedTiles}, p95 deltaB={snap.p95.deltaBytes})`
	)
end

print("")
if failures == 0 then
	print("\27[32mTous les invariants tiennent.\27[0m")
else
	print(`\27[31m{failures} invariant(s) violes.\27[0m`)
end
