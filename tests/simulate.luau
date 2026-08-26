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
local ChantierB = __require("ChantierB")

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

	-- 5b. Index buildingsBySlot (V22) : chaque batiment est dans l'index de
	-- son camp, et l'index ne pointe pas vers un fantome.
	if state.buildingsBySlot then
		for slot, set in state.buildingsBySlot do
			for index in set do
				local building = state.buildings[index]
				if not building then
					fail(`tick {tick} — buildingsBySlot[{slot}][{index}] orphelin`)
				elseif building.slot ~= slot then
					fail(`tick {tick} — buildingsBySlot[{slot}][{index}] slot={building.slot}`)
				end
			end
		end
		for index, building in state.buildings do
			local set = state.buildingsBySlot[building.slot]
			if not set or not set[index] then
				fail(`tick {tick} — batiment {index} hors buildingsBySlot[{building.slot}]`)
			end
		end
	end

	-- 5c. coolingBuildings (V19) : uniquement les tuiles a cooldown > 0.
	if state.coolingBuildings then
		for index in state.coolingBuildings do
			local building = state.buildings[index]
			if not building then
				fail(`tick {tick} — coolingBuildings[{index}] orphelin`)
			elseif building.cooldown <= 0 then
				fail(`tick {tick} — coolingBuildings[{index}] cooldown={building.cooldown}`)
			end
		end
		for index, building in state.buildings do
			if building.cooldown > 0 and not state.coolingBuildings[index] then
				fail(`tick {tick} — cooldown {building.cooldown} hors coolingBuildings[{index}]`)
			end
		end
	end

	-- 5d. Index factoriesBySlot = usines (V20).
	if state.factoriesBySlot then
		local indexed = 0
		for slot, set in state.factoriesBySlot do
			for index in set do
				indexed += 1
				local building = state.buildings[index]
				if not building then
					fail(`tick {tick} — factoriesBySlot[{slot}][{index}] orphelin`)
				elseif building.kind ~= Config.BUILDING.FACTORY then
					fail(`tick {tick} — factoriesBySlot[{slot}][{index}] kind={building.kind}`)
				elseif building.slot ~= slot then
					fail(`tick {tick} — factoriesBySlot[{slot}][{index}] slot={building.slot}`)
				end
			end
		end
		local realFactory = 0
		for index, building in state.buildings do
			if building.kind == Config.BUILDING.FACTORY then
				realFactory += 1
				local set = state.factoriesBySlot[building.slot]
				if not set or not set[index] then
					fail(`tick {tick} — FACTORY {index} hors factoriesBySlot[{building.slot}]`)
				end
			end
		end
		if indexed ~= realFactory then
			fail(`tick {tick} — factoriesBySlot count {indexed} != FACTORY {realFactory}`)
		end
	end

	-- 5e. Index portsByTile = PORT slot+level (V21).
	if state.portsByTile then
		local indexed = 0
		for index, info in state.portsByTile do
			indexed += 1
			local building = state.buildings[index]
			if not building then
				fail(`tick {tick} — portsByTile[{index}] orphelin`)
			elseif building.kind ~= Config.BUILDING.PORT then
				fail(`tick {tick} — portsByTile[{index}] kind={building.kind}`)
			elseif building.slot ~= info.slot or building.level ~= info.level then
				fail(`tick {tick} — portsByTile[{index}] slot/level derivent`)
			end
		end
		local realPort = 0
		for index, building in state.buildings do
			if building.kind == Config.BUILDING.PORT then
				realPort += 1
				local info = state.portsByTile[index]
				if not info then
					fail(`tick {tick} — PORT {index} hors portsByTile`)
				end
			end
		end
		if indexed ~= realPort then
			fail(`tick {tick} — portsByTile count {indexed} != PORT {realPort}`)
		end
	end

	-- 5f. Index navalBasesBySlot = NAVAL_BASE (V23).
	if state.navalBasesBySlot then
		local indexed = 0
		for slot, set in state.navalBasesBySlot do
			for index in set do
				indexed += 1
				local building = state.buildings[index]
				if not building then
					fail(`tick {tick} — navalBasesBySlot[{slot}][{index}] orphelin`)
				elseif building.kind ~= Config.BUILDING.NAVAL_BASE then
					fail(`tick {tick} — navalBasesBySlot[{slot}][{index}] kind={building.kind}`)
				elseif building.slot ~= slot then
					fail(`tick {tick} — navalBasesBySlot[{slot}][{index}] slot={building.slot}`)
				end
			end
		end
		local realBase = 0
		for index, building in state.buildings do
			if building.kind == Config.BUILDING.NAVAL_BASE then
				realBase += 1
				local set = state.navalBasesBySlot[building.slot]
				if not set or not set[index] then
					fail(`tick {tick} — NAVAL_BASE {index} hors navalBasesBySlot[{building.slot}]`)
				end
			end
		end
		if indexed ~= realBase then
			fail(`tick {tick} — navalBasesBySlot count {indexed} != NAVAL_BASE {realBase}`)
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
	local expectedFactions = Config.BOT_COUNT + (Config.TRIBE_COUNT or 0)
	if spawned < 10 then
		fail(`seed {seed} — seulement {spawned} factions (spawn sature, plancher 10 / {expectedFactions})`)
	elseif spawned < expectedFactions then
		print(
			`  note seed {seed} : {spawned}/{expectedFactions} factions (disques r={Config.SPAWN_RADIUS}, dist min {Config.SPAWN_MIN_PLAYER_DISTANCE})`
		)
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
			local expandR = math.max(40, (Config.BUILD_MIN_SPACING or 15) * 3)
			for dy = -expandR, expandR do
				for dx = -expandR, expandR do
					if dx * dx + dy * dy <= expandR * expandR then
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

			local spacing = Config.BUILD_MIN_SPACING or 15
			local function siteAwayFromBuildings(nearIndex: number?): number?
				local nx, ny
				if nearIndex then
					nx, ny = MapGen.fromIndex(nearIndex)
				end
				local rail2 = (Config.RAIL_RANGE or 56) * (Config.RAIL_RANGE or 56)
				for index = 0, Config.TILE_COUNT - 1 do
					if buffer.readu8(cityState.owner, index) ~= ps.slot then
						continue
					end
					if cityState.buildings[index] then
						continue
					end
					if not cityState:isLand(index) then
						continue
					end
					local x, y = MapGen.fromIndex(index)
					if nx then
						local ddx, ddy = x - nx, y - ny
						if ddx * ddx + ddy * ddy > rail2 then
							continue
						end
					end
					local ok = true
					for bIndex in cityState.buildings do
						local bx, by = MapGen.fromIndex(bIndex)
						local dx, dy = x - bx, y - by
						if dx * dx + dy * dy < spacing * spacing then
							ok = false
							break
						end
					end
					if ok then
						return index
					end
				end
				return nil
			end

			if not siteAwayFromBuildings(capital) then
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
				local citySite = siteAwayFromBuildings(capital)
				if not citySite then
					fail("evolution urbaine — plus de tuile libre pour la seconde ville")
				end
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
				local factorySite = siteAwayFromBuildings(capital)
				if not factorySite then
					fail("logistique — aucune tuile pour l'usine")
				end
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
			-- 1. Aucune tuile orpheline : chaque prise touche une autre prise
			--    ou le hinterland d'origine de l'attaquant (enclave avalee).
			local orphans = 0
			local probe = table.create(4, 0)
			for index in taken do
				local touching = false
				local n = MapGen.neighbors(index, probe)
				for k = 1, n do
					local nb = probe[k]
					if taken[nb] then
						touching = true
						break
					end
					if buffer.readu8(frontState.owner, nb) == attacker.slot and not before[nb] then
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

		ps.cityPopBonus = 0
		ps.tiles = 1000
		ps.isBot = true
		local botCap = troopState:maxTroops(ps)
		ps.isBot = false
		local humanCap = troopState:maxTroops(ps)
		if humanCap <= 0 or math.abs(botCap * 3 - humanCap) > 1 then
			fail(`plafond de troupes — diviseur bot absent (bot={botCap} humain={humanCap})`)
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
		if diploState:areAllied(a.slot, b.slot) then
			fail("alliances — paix fantome au tick d'echeance (areAllied ignore l'expiry)")
		end
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
	Nightly passe 13 — contrats portes depuis la ligne feel/hardening.
]]
do
	local goldState = GameState.new(1301)
	local human = goldState:addPlayer({ Name = "OrPlat" } :: any, "OrPlat", Random.new(13), 0)
	if human then
		human.gold = 0
		goldState:stepEconomy()
		if human.gold <= 0 then
			fail("or plat — aucun revenu sans ports")
		end
		if human.gold > 20 then
			fail(`or plat — revenu {human.gold} trop eleve (or territorial encore actif ?)`)
		end
	else
		fail("or plat — impossible de creer la faction")
	end
end

do
	local recState = GameState.new(1302)
	local a = recState:addPlayer(nil, "Attaquant", Random.new(61), 0)
	local b = recState:addPlayer(nil, "Defenseur", Random.new(62), 0)
	if not a or not b then
		fail("removePlayer — impossible de creer les factions")
	else
		local before = a.troops
		table.insert(recState.attacks, {
			attacker = a.slot,
			target = b.slot,
			troops = 400,
			frontier = { size = 0 },
			queued = {},
		})
		recState:removePlayer(b.slot)
		if math.abs(a.troops - (before + 400)) > 0.001 then
			fail(`removePlayer — troupes non restituees ({a.troops} vs {before + 400})`)
		end
		if recState.players[b.slot] then
			fail("removePlayer — le defenseur est encore en lice")
		end
	end
end

do
	local embargoState = GameState.new(1303)
	local a = embargoState:addPlayer(nil, "A", Random.new(71), 0)
	local b = embargoState:addPlayer(nil, "B", Random.new(72), 0)
	if not a or not b then
		fail("embargo auto — factions impossibles")
	else
		local scratch = table.create(4, 0)
		local contact: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(embargoState.owner, index) == a.slot then
				local n = MapGen.neighbors(index, scratch)
				for i = 1, n do
					local nb = scratch[i]
					if buffer.readu8(embargoState.owner, nb) == 0 and embargoState:isLand(nb) then
						contact = nb
						break
					end
				end
			end
			if contact then
				break
			end
		end
		if contact then
			embargoState:setOwner(contact, b.slot)
			embargoState.combatUnlocked = true
			a.troops = 20000
			a.attackRatio = 0.5
			local ok = embargoState:launchAttack(a.slot, b.slot)
			if ok then
				local ab = embargoState.embargoes[a.slot] and embargoState.embargoes[a.slot][b.slot]
				local ba = embargoState.embargoes[b.slot] and embargoState.embargoes[b.slot][a.slot]
				if not ab or not ba then
					fail("embargo auto — l'attaque n'a pas pose d'embargo mutuel")
				end
			end
		end
	end
end

do
	local boatState = GameState.new(1304)
	local a = boatState:addPlayer(nil, "Amiral", Random.new(81), 0)
	if not a then
		fail("transports — faction impossible")
	else
		for i = 1, 3 do
			table.insert(boatState.boats, {
				id = i,
				slot = a.slot,
				kind = 1,
				troops = 10,
				x = 0,
				y = 0,
				path = {},
				step = 1,
				targetTile = 0,
				homeTile = 0,
				retreating = false,
			})
		end
		local target: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if boatState:isLand(index) and MapGen.isCoastal(boatState.terrain, index) and buffer.readu8(boatState.owner, index) ~= a.slot then
				target = index
				break
			end
		end
		if target then
			local ok, msg = Navy.launchInvasion(boatState, a.slot, target)
			if ok then
				fail("transports — un 4e bateau a ete lance (cap 3)")
			elseif typeof(msg) == "string" and not string.find(msg, "3 max") then
				-- Autre refus (pas de cote, etc.) : on exige au moins le compteur.
				if Navy.countBoats(boatState, a.slot, 1) < 3 then
					fail("transports — compteur incoherent")
				end
			end
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
			if not siloTile and owner == a.slot and not mirvState.buildings[index] then
				siloTile = index
			elseif not targetTile and owner == b.slot then
				targetTile = index
			end
		end
		if not siloTile or not targetTile then
			fail("mirv — territoires de test introuvables")
		else
			mirvState:placeBuilding(siloTile, Config.BUILDING.SILO, a.slot)
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
print(`batiments         : ville={buildingCounts[1] or 0} port={buildingCounts[2] or 0} bunker={buildingCounts[3] or 0} silo={buildingCounts[4] or 0} sam={buildingCounts[5] or 0} navale={buildingCounts[8] or 0} capitale={buildingCounts[6] or 0} labo={buildingCounts[7] or 0} usine={buildingCounts[8] or 0}`)
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
local industrialTick = main.firstEra[3]
if atomicTick and atomicTick < 2400 then
	fail(`ere Atomique atteinte des {math.floor(atomicTick / Config.TICK_RATE)}s : trop tot`)
elseif not atomicTick then
	if not industrialTick then
		fail("aucune faction n'atteint l'ere Industrielle en 10 minutes")
	else
		print(
			`  note : ere Atomique non atteinte en {TICKS} ticks (or plat OF, {Config.BOT_COUNT + (Config.TRIBE_COUNT or 0)} factions) — Industrielle a t={industrialTick}`
		)
	end
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

		-- N41 : en playing, Attack sans sequence est refuse.
		IntentValidator.reset()
		local okNil, reasonNil = IntentValidator.enqueue(ctx, fakePlayer, "Attack", nil, { index = ps.capitalTile or 0 })
		if okNil or reasonNil ~= "InvalidSchema" then
			fail(`intentions — sequence nil encore acceptee en playing ({tostring(reasonNil)})`)
		end

		-- N29 : un apply rate ne brule pas la sequence.
		IntentValidator.reset()
		ps.gold = 0
		local buildTile = ps.capitalTile or 0
		local okFail = IntentValidator.enqueue(ctx, fakePlayer, "Build", 2, { index = buildTile, kind = Config.BUILDING.CITY })
		if not okFail then
			fail("intentions — enqueue Build refusee avant apply")
		end
		local okRetry, reasonRetry = IntentValidator.enqueue(ctx, fakePlayer, "SetAttackRatio", 2, { ratio = 0.3 })
		if not okRetry then
			fail(`intentions — sequence 2 brulee apres apply rate ({tostring(reasonRetry)})`)
		end
		if ps.attackRatio < 0.29 or ps.attackRatio > 0.31 then
			fail(`intentions — retry seq 2 n'a pas applique le ratio ({ps.attackRatio})`)
		end
		print("intentions : sequence, idempotence, apply immediat, rate limit, N41/N29 OK")
	end
end

--[[
	Nightly passe 16 — revue PR #44 : autorite, recycle, perf.
]]
do
	local corrupt = GameState.new(1601)
	local a = corrupt:addPlayer(nil, "A", Random.new(11), 0)
	local b = corrupt:addPlayer(nil, "B", Random.new(12), 0)
	if not a or not b then
		fail("areAllied — factions impossibles")
	else
		corrupt.alliances[a.slot][b.slot] = "oops"
		corrupt.alliances[b.slot][a.slot] = "oops"
		if corrupt:areAllied(a.slot, b.slot) then
			fail("areAllied — expiry corrompue traitee comme pacte")
		end
		corrupt.alliances[a.slot][b.slot] = true
		corrupt.alliances[b.slot][a.slot] = true
		if not corrupt:areAllied(a.slot, b.slot) then
			fail("areAllied — true legacy casse")
		end
	end
end

do
	IntentValidator.reset()
	local state = GameState.new(1602)
	state.mode = GameModes.get("classic")
	local fakePlayer = __newInstance("Player")
	fakePlayer.Name = "InfRatio"
	fakePlayer.UserId = 1602
	local ps = state:addPlayer(fakePlayer, "InfRatio", Random.new(2), 0)
	if not ps then
		fail("ratio inf — spawn impossible")
	else
		local ctx = {
			state = state,
			matchPhase = "playing",
			matchId = "inf",
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
			reply = function() end,
			refuse = function() end,
			broadcastRoster = function() end,
		}
		local okHuge, reasonHuge = IntentValidator.enqueue(ctx, fakePlayer, "SetAttackRatio", 1, { ratio = math.huge })
		if okHuge or reasonHuge ~= "InvalidSchema" then
			fail(`ratio inf — ±inf encore accepte ({tostring(reasonHuge)})`)
		end
	end
end

do
	local missState = GameState.new(1603)
	local a = missState:addPlayer(nil, "Lanceur", Random.new(31), 0)
	local b = missState:addPlayer(nil, "Cible", Random.new(32), 0)
	if not a or not b then
		fail("missiles outbound — factions impossibles")
	else
		table.insert(missState.missiles, {
			id = 1,
			slot = a.slot,
			kind = 1,
			x = 0,
			y = 0,
			sx = 0,
			sy = 0,
			tx = 10,
			ty = 10,
		})
		missState:removePlayer(a.slot)
		if #missState.missiles ~= 0 then
			fail("missiles outbound — frappe du joueur parti encore en vol")
		end
	end
end

do
	local waitState = GameState.new(1604)
	local fake = __newInstance("Player")
	fake.Name = "Attente"
	fake.UserId = 1604
	local ps = waitState:addPlayer(fake, "Attente", Random.new(41), 0)
	if not ps then
		fail("spawn wait — joueur impossible")
	else
		ChantierB.stripTerritory(waitState, ps)
		if not ps.awaitingSpawn then
			fail("spawn wait — stripTerritory n'a pas arme awaitingSpawn")
		end
		if ps.tiles ~= 0 then
			fail(`spawn wait — tiles={ps.tiles} (attendu 0, pas de sentinelle 1)`)
		end
		local goldBefore = ps.gold
		waitState:stepEconomy()
		if ps.gold ~= goldBefore then
			fail("spawn wait — or verse avant le clic spawn")
		end
		waitState:stepElimination()
		if not waitState.players[ps.slot] then
			fail("spawn wait — humain en attente elimine")
		end
	end
end

do
	local claimState = GameState.new(1605)
	claimState.combatUnlocked = true
	local fake = __newInstance("Player")
	fake.Name = "Colon"
	fake.UserId = 1605
	local colon = claimState:addPlayer(fake, "Colon", Random.new(51), 0)
	local foe = claimState:addPlayer(nil, "Voisin", Random.new(52), 0)
	if not colon or not foe then
		fail("justClaimed — factions impossibles")
	else
		ChantierB.stripTerritory(claimState, colon)
		local land: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if
				claimState:isLand(index)
				and buffer.readu8(claimState.owner, index) == 0
				and claimState:isSpawnIsolated(index)
			then
				land = index
				break
			end
		end
		if not land then
			fail("justClaimed — aucune terre libre isolee")
		else
			local claimed = claimState:claimSpawn(colon.slot, land)
			if not claimed then
				fail("justClaimed — claimSpawn refuse")
			else
				local scratch = table.create(4, 0)
				local contact: number? = nil
				for index = 0, Config.TILE_COUNT - 1 do
					if buffer.readu8(claimState.owner, index) == colon.slot then
						local n = MapGen.neighbors(index, scratch)
						for i = 1, n do
							local nb = scratch[i]
							if claimState:isLand(nb) and buffer.readu8(claimState.owner, nb) == 0 then
								contact = nb
								break
							end
						end
					end
					if contact then
						break
					end
				end
				if contact then
					claimState:setOwner(contact, foe.slot)
					colon.troops = 20000
					colon.attackRatio = 0.5
					local ok = claimState:launchAttack(colon.slot, foe.slot)
					if not ok then
						fail("justClaimed — le premier vrai Attack est encore avale")
					elseif #claimState.attacks == 0 then
						fail("justClaimed — succes sans front")
					end
				end
			end
		end
	end
end

do
	local boatState = GameState.new(1606)
	local a = boatState:addPlayer(nil, "Marin", Random.new(61), 0)
	if not a then
		fail("own-tile boat — faction impossible")
	else
		local home: number? = nil
		for index in a.coast do
			home = index
			break
		end
		if not home then
			for index = 0, Config.TILE_COUNT - 1 do
				if buffer.readu8(boatState.owner, index) == a.slot then
					home = index
					break
				end
			end
		end
		if home then
			local before = a.troops
			table.insert(boatState.boats, {
				id = 99,
				slot = a.slot,
				kind = 1,
				troops = 400,
				x = 0,
				y = 0,
				path = { home },
				step = 1,
				targetTile = home,
				targetOwner = 0,
				homeTile = home,
				retreating = false,
			})
			Navy.step(boatState, Random.new(7))
			local still = false
			for _, boat in boatState.boats do
				if boat.id == 99 then
					still = true
					break
				end
			end
			if still then
				fail("own-tile boat — transport encore en mer")
			end
			if math.abs(a.troops - (before + 400)) > 0.001 then
				fail(`own-tile boat — restitution {a.troops - before} (attendu 400, pas 75 %)`)
			end
		else
			fail("own-tile boat — aucune tuile a soi")
		end
	end
end

do
	local flipState = GameState.new(1607)
	local a = flipState:addPlayer(nil, "Envahisseur", Random.new(71), 0)
	local b = flipState:addPlayer(nil, "Cote", Random.new(72), 0)
	local c = flipState:addPlayer(nil, "Tiers", Random.new(73), 0)
	if not a or not b or not c then
		fail("targetSlot — factions impossibles")
	else
		local coastB: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if flipState:isLand(index) and MapGen.isCoastal(flipState.terrain, index) then
				coastB = index
				break
			end
		end
		if coastB then
			flipState:setOwner(coastB, c.slot)
			table.insert(flipState.boats, {
				id = 77,
				slot = a.slot,
				kind = 1,
				troops = 200,
				x = 0,
				y = 0,
				path = { coastB },
				step = 1,
				targetTile = coastB,
				targetOwner = b.slot,
				homeTile = coastB,
				retreating = false,
			})
			local n = Navy.retreatBoats(flipState, a.slot, b.slot)
			if n < 1 then
				fail("targetSlot — retreatBoats rate le transport apres flip")
			end
		else
			fail("targetSlot — aucune cote")
		end
	end
end

do
	local sea = GameState.new(1608)
	local fromTile: number? = nil
	local toTile: number? = nil
	for index = 0, Config.TILE_COUNT - 1 do
		if buffer.readu8(sea.terrain, index) == Config.TERRAIN.OCEAN then
			if not fromTile then
				fromTile = index
			elseif not toTile and index ~= fromTile then
				toTile = index
			end
		end
		if fromTile and toTile then
			break
		end
	end
	if fromTile and toTile then
		local p1 = Navy.findSeaPath(sea, fromTile, toTile)
		local p2 = Navy.findSeaPath(sea, fromTile, toTile)
		if (p1 == nil) ~= (p2 == nil) then
			fail("findSeaPath pool — second appel diverge")
		end
		if p1 and p2 and #p1 ~= #p2 then
			fail("findSeaPath pool — longueurs divergentes")
		end
	end
end

do
	local carrierState = GameState.new(1609)
	local a = carrierState:addPlayer(nil, "Amiral", Random.new(81), 0)
	if not a then
		fail("carriers dirty — faction impossible")
	else
		local coastal: number? = nil
		for index in a.coast do
			if not carrierState.buildings[index] then
				coastal = index
				break
			end
		end
		if coastal then
			carrierState:placeBuilding(coastal, Config.BUILDING.NAVAL_BASE, a.slot)
			if carrierState._carriersDirty ~= true then
				fail("carriers dirty — placeBuilding NAVAL_BASE n'a pas sale")
			end
			Navy.step(carrierState, Random.new(9))
			if carrierState._carriersDirty ~= false then
				fail("carriers dirty — sync n'a pas consomme le drapeau")
			end
			local n = 0
			for _, boat in carrierState.boats do
				if boat.kind == 3 then
					n += 1
				end
			end
			if n < 1 then
				fail("carriers dirty — aucun porte-avions apres pose")
			end
		end
	end
end

--[[
	Nightly passe 17 — revue PR #47 : bunkersBySlot, recycle, diplomatie, schema.
]]
do
	local pack = GameState.new(1701)
	local bot = pack:addPlayer(nil, "BotSpawn", Random.new(11), 0)
	if not bot then
		fail("spawnCenter — bot impossible")
	elseif bot.spawnCenter == nil then
		fail("spawnCenter — bot sans ancre de packing")
	else
		ChantierB.stripTerritory(pack, bot)
		if not bot.awaitingSpawn then
			fail("spawnCenter — stripTerritory n'a pas arme awaitingSpawn")
		elseif bot.spawnCenter ~= nil then
			fail("spawnCenter — ancre fantome apres stripTerritory")
		end
	end
end

do
	local diplo = GameState.new(1702)
	local a = diplo:addPlayer(nil, "A", Random.new(21), 0)
	local b = diplo:addPlayer(nil, "B", Random.new(22), 0)
	if not a or not b then
		fail("diplo expiry — factions impossibles")
	else
		diplo.alliances[a.slot][b.slot] = "oops"
		diplo.alliances[b.slot][a.slot] = "oops"
		local okStep = pcall(Diplomacy.step, diplo)
		if not okStep then
			fail("diplo expiry — step crash sur expiry corrompue")
		elseif diplo:areAllied(a.slot, b.slot) then
			fail("diplo expiry — pacte corrompu encore vivant apres step")
		end
		diplo.alliances[a.slot][b.slot] = true
		diplo.alliances[b.slot][a.slot] = true
		okStep = pcall(Diplomacy.step, diplo)
		if not okStep then
			fail("diplo expiry — step crash sur true legacy")
		elseif not diplo:areAllied(a.slot, b.slot) then
			fail("diplo expiry — true legacy purge")
		end
		diplo.requests[a.slot] = diplo.requests[a.slot] or {}
		diplo.requests[a.slot][b.slot] = diplo.tick - 1
		local view = Diplomacy.viewFor(diplo, b.slot)
		if view.incoming[a.slot] then
			fail("diplo expiry — viewFor montre une demande perimee")
		end
	end
end

do
	IntentValidator.reset()
	local state = GameState.new(1703)
	state.mode = GameModes.get("classic")
	local fakePlayer = __newInstance("Player")
	fakePlayer.Name = "NukeKind"
	fakePlayer.UserId = 1703
	local ps = state:addPlayer(fakePlayer, "NukeKind", Random.new(3), 0)
	if not ps then
		fail("nuke kind — spawn impossible")
	else
		local ctx = {
			state = state,
			matchPhase = "playing",
			matchId = "nuke",
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
			reply = function() end,
			refuse = function() end,
			broadcastRoster = function() end,
		}
		local okBad, reasonBad = IntentValidator.enqueue(ctx, fakePlayer, "Nuke", 1, {
			index = ps.capitalTile or 0,
			kind = 99,
		})
		if okBad or reasonBad ~= "InvalidSchema" then
			fail(`nuke kind — kind 99 encore accepte ({tostring(reasonBad)})`)
		end
	end
end

do
	local bunkerState = GameState.new(1704)
	local a = bunkerState:addPlayer(nil, "Attaquant", Random.new(41), 0)
	local b = bunkerState:addPlayer(nil, "Defenseur", Random.new(42), 0)
	if not a or not b then
		fail("bunkersBySlot — factions impossibles")
	else
		local tile: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(bunkerState.owner, index) == b.slot and not bunkerState.buildings[index] then
				tile = index
				break
			end
		end
		if not tile then
			fail("bunkersBySlot — aucune tuile libre chez le defenseur")
		else
			bunkerState:placeBuilding(tile, Config.BUILDING.DEFENSE, b.slot)
			local indexed = bunkerState.bunkersBySlot[b.slot] and bunkerState.bunkersBySlot[b.slot][tile]
			if not indexed then
				fail("bunkersBySlot — pose DEFENSE non indexee")
			end
			a.troops = 20000
			b.troops = 20000
			local postedLoss = select(1, ChantierB.attackLogic(bunkerState, 10000, a, b, tile))
			bunkerState:destroyBuilding(tile)
			if bunkerState.bunkersBySlot[b.slot] and bunkerState.bunkersBySlot[b.slot][tile] then
				fail("bunkersBySlot — destroy laisse l'index")
			end
			local bareLoss = select(1, ChantierB.attackLogic(bunkerState, 10000, a, b, tile))
			if postedLoss < bareLoss * 4 then
				fail(`bunkersBySlot — posted {postedLoss} vs bare {bareLoss} (attendu x5)`)
			end
		end
	end
end

do
	local chatState = GameState.new(1705)
	local a = chatState:addPlayer(nil, "Parleur", Random.new(51), 0)
	if not a then
		fail("quickChat recycle — faction impossible")
	else
		chatState.quickChatSent[a.slot] = 12
		chatState.quickChatLast[a.slot] = "hello"
		local slot = a.slot
		chatState:removePlayer(slot)
		if chatState.quickChatSent[slot] ~= nil or chatState.quickChatLast[slot] ~= nil then
			fail("quickChat recycle — anti-spam herite par le prochain occupant")
		end
	end
end

do
	local frontState = GameState.new(1706)
	frontState.combatUnlocked = true
	local a = frontState:addPlayer(nil, "Terre", Random.new(61), 0)
	local b = frontState:addPlayer(nil, "Plage", Random.new(62), 0)
	if not a or not b then
		fail("reinforce beachhead — factions impossibles")
	else
		local beach: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(frontState.owner, index) == b.slot then
				beach = index
				break
			end
		end
		if not beach then
			fail("reinforce beachhead — aucune tuile cible")
		else
			frontState:seedBeachhead(a.slot, b.slot, 400, beach)
			a.troops = 20000
			a.attackRatio = 0.5
			frontState:launchAttack(a.slot, b.slot)
			local beachTroops = nil
			for _, atk in frontState.attacks do
				if atk.attacker == a.slot and atk.target == b.slot and atk.isBeachhead then
					beachTroops = atk.troops
				end
			end
			if beachTroops ~= 400 then
				fail(`reinforce beachhead — tete de pont {tostring(beachTroops)} (attendu 400)`)
			end
		end
	end
end

do
	local deltaState = GameState.new(1707)
	local a = deltaState:addPlayer(nil, "Delta", Random.new(71), 0)
	if not a then
		fail("flushOwnerDelta — faction impossible")
	else
		local first = deltaState:flushOwnerDelta()
		if first and buffer.len(first) % 5 ~= 0 then
			fail("flushOwnerDelta — taille non multiple de 5")
		end
		local second = deltaState:flushOwnerDelta()
		if second ~= nil then
			fail("flushOwnerDelta — dirty pas consomme")
		end
		if a.capitalTile then
			local scratch = table.create(4, 0)
			local n = MapGen.neighbors(a.capitalTile, scratch)
			for i = 1, n do
				local nb = scratch[i]
				if deltaState:isLand(nb) and buffer.readu8(deltaState.owner, nb) == 0 then
					deltaState:setOwner(nb, a.slot)
					break
				end
			end
		end
		local third = deltaState:flushOwnerDelta()
		if third and buffer.len(third) % 5 ~= 0 then
			fail("flushOwnerDelta — format casse apres recycle")
		end
	end
end

do
	if typeof(Nukes.samRange) ~= "function" then
		fail("samRange — helper non exporte")
	elseif math.abs(Nukes.samRange(1) - (150 - 480 / 6)) > 0.001 then
		fail("samRange — formule OF cassee")
	end
end

print("passe 17 : bunkersBySlot, spawnCenter, diplo expiry, nuke kind, beachhead, delta, samRange OK")

--[[
	Nightly passe 18 — revue PR #50 : aura morte, CAPTURE_GUARD, samsBySlot.
]]
do
	if ChantierB.CAPTURE_GUARD ~= 80 then
		fail(`CAPTURE_GUARD — {tostring(ChantierB.CAPTURE_GUARD)} (attendu 80)`)
	elseif Config.MAX_TILES_PER_TICK == ChantierB.CAPTURE_GUARD then
		fail("CAPTURE_GUARD — MAX_TILES_PER_TICK coincide avec le debit vivant")
	end
end

do
	local aura = GameState.new(1801)
	local a = aura:addPlayer(nil, "Attaquant", Random.new(81), 0)
	local b = aura:addPlayer(nil, "Defenseur", Random.new(82), 0)
	if not a or not b then
		fail("aura morte — factions impossibles")
	else
		local tile: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(aura.owner, index) == b.slot and not aura.buildings[index] then
				tile = index
				break
			end
		end
		if not tile then
			fail("aura morte — aucune tuile libre")
		else
			aura:placeBuilding(tile, Config.BUILDING.DEFENSE, b.slot)
			if buffer.readu8(aura.defense, tile) ~= 0 then
				fail("aura morte — pose DEFENSE ecrit encore le buffer")
			end
			a.troops = 20000
			b.troops = 20000
			local postedLoss = select(1, ChantierB.attackLogic(aura, 10000, a, b, tile))
			aura:setOwner(tile, a.slot)
			if aura.bunkersBySlot[b.slot] and aura.bunkersBySlot[b.slot][tile] then
				fail("aura morte — capture laisse l'index chez le defenseur")
			elseif not (aura.bunkersBySlot[a.slot] and aura.bunkersBySlot[a.slot][tile]) then
				fail("aura morte — capture n'indexe pas chez l'attaquant")
			end
			local capturedLoss = select(1, ChantierB.attackLogic(aura, 10000, b, a, tile))
			if capturedLoss < postedLoss * 0.9 then
				fail(`aura morte — posted apres capture {capturedLoss} vs {postedLoss}`)
			end
			aura:destroyBuilding(tile)
			if buffer.readu8(aura.defense, tile) ~= 0 then
				fail("aura morte — destroy DEFENSE ecrit encore le buffer")
			end
		end
	end
end

do
	local samState = GameState.new(1802)
	local a = samState:addPlayer(nil, "Frappe", Random.new(91), 0)
	local b = samState:addPlayer(nil, "Batterie", Random.new(92), 0)
	if not a or not b then
		fail("samsBySlot — factions impossibles")
	else
		local tile: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(samState.owner, index) == b.slot and not samState.buildings[index] then
				tile = index
				break
			end
		end
		if not tile then
			fail("samsBySlot — aucune tuile libre")
		else
			samState:placeBuilding(tile, Config.BUILDING.SAM, b.slot)
			local listed = Buildings.samsOf(samState, b.slot)
			if #listed ~= 1 or listed[1] ~= tile then
				fail("samsBySlot — pose SAM non indexee")
			end
			local bx, by = MapGen.fromIndex(tile)
			table.insert(samState.missiles, {
				id = 1,
				slot = a.slot,
				kind = Config.NUKE.ATOM,
				x = bx,
				y = by,
				sx = bx,
				sy = by,
				tx = bx + 1,
				ty = by,
				progress = 0,
				speed = 1,
			})
			Nukes.step(samState, Random.new(1), function() end)
			if #samState.missiles ~= 0 then
				fail("samsBySlot — missile non intercepte via l'index")
			end
			samState:setOwner(tile, a.slot)
			if samState.samsBySlot[b.slot] and samState.samsBySlot[b.slot][tile] then
				fail("samsBySlot — capture laisse l'index chez le defenseur")
			elseif not (samState.samsBySlot[a.slot] and samState.samsBySlot[a.slot][tile]) then
				fail("samsBySlot — capture n'indexe pas chez l'attaquant")
			end
			local slotB = b.slot
			samState:removePlayer(slotB)
			if samState.samsBySlot[slotB] ~= nil then
				fail("samsBySlot — removePlayer laisse l'index du slot recycle")
			end
			samState:destroyBuilding(tile)
			if samState.samsBySlot[a.slot] and samState.samsBySlot[a.slot][tile] then
				fail("samsBySlot — destroy laisse l'index")
			elseif #Buildings.samsOf(samState, a.slot) ~= 0 then
				fail("samsOf — destroy encore visible")
			end
		end
	end
end

print("passe 18 : aura morte, CAPTURE_GUARD, samsBySlot OK")

--[[
	Nightly passe 19 — revue PR #54 : silosBySlot, samsOf sans fallback hash,
	isolation clic spawn.
]]
do
	local ghost = GameState.new(1901)
	local a = ghost:addPlayer(nil, "Frappe", Random.new(11), 0)
	if not a then
		fail("samsOf ghost — faction impossible")
	else
		local tile: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(ghost.owner, index) == a.slot and not ghost.buildings[index] then
				tile = index
				break
			end
		end
		if not tile then
			fail("samsOf ghost — aucune tuile libre")
		else
			ghost.buildings[tile] = { kind = Config.BUILDING.SAM, slot = a.slot, level = 1, links = {}, cooldown = 0 }
			a.samCount = 1
			local listed = Buildings.samsOf(ghost, a.slot)
			if #listed ~= 0 then
				fail("samsOf — slot sans index rescane le hash (fantome)")
			end
		end
	end
end

do
	local siloState = GameState.new(1902)
	local a = siloState:addPlayer(nil, "Arsenal", Random.new(21), 0)
	local b = siloState:addPlayer(nil, "Cible", Random.new(22), 0)
	if not a or not b then
		fail("silosBySlot — factions impossibles")
	else
		local near: number? = nil
		local far: number? = nil
		local target: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			local owner = buffer.readu8(siloState.owner, index)
			if owner == a.slot and not siloState.buildings[index] then
				if not near then
					near = index
				elseif not far then
					far = index
				end
			elseif not target and owner == b.slot then
				target = index
			end
		end
		if not near or not far or not target then
			fail("silosBySlot — tuiles de test introuvables")
		else
			local tx, ty = MapGen.fromIndex(target)
			local function dist2(index: number): number
				local x, y = MapGen.fromIndex(index)
				local dx, dy = x - tx, y - ty
				return dx * dx + dy * dy
			end
			if dist2(far) < dist2(near) then
				near, far = far, near
			end
			siloState:placeBuilding(near, Config.BUILDING.SILO, a.slot)
			siloState:placeBuilding(far, Config.BUILDING.SILO, a.slot)
			if not (siloState.silosBySlot[a.slot] and siloState.silosBySlot[a.slot][near] and siloState.silosBySlot[a.slot][far]) then
				fail("silosBySlot — pose SILO non indexee")
			end

			-- Fantome hash : l'index est la source de verite.
			local ghostTile: number? = nil
			for index = 0, Config.TILE_COUNT - 1 do
				if buffer.readu8(siloState.owner, index) == a.slot and not siloState.buildings[index] then
					ghostTile = index
					break
				end
			end
			if ghostTile then
				siloState.buildings[ghostTile] =
					{ kind = Config.BUILDING.SILO, slot = a.slot, level = 1, links = {}, cooldown = 0 }
			end

			a.era = Eras.requiredForNuke(Config.NUKE.ATOM)
			a.gold = 5000
			siloState.tick = (Config.SPAWN_NUKE_IMMUNITY or 5) * Config.TICK_RATE + 1
			siloState.buildings[near].cooldown = Config.SILO_COOLDOWN
			local goldBefore = a.gold
			local ok, reason = Nukes.launch(siloState, a.slot, target, Config.NUKE.ATOM)
			if not ok then
				fail("silosBySlot — tir refuse: " .. tostring(reason))
			elseif siloState.buildings[far].cooldown ~= Config.SILO_COOLDOWN then
				fail("silosBySlot — le silo pret le plus proche n'est pas arme")
			elseif siloState.buildings[near].cooldown ~= Config.SILO_COOLDOWN then
				fail("silosBySlot — le silo en recharge a ete rearme")
			elseif a.gold ~= goldBefore - Config.NUKE_STATS[Config.NUKE.ATOM].cost then
				fail("silosBySlot — cout non preleve")
			end
			if ghostTile and siloState.buildings[ghostTile] and (siloState.buildings[ghostTile].cooldown or 0) > 0 then
				fail("silosBySlot — silo fantome hors index arme")
			end

			siloState:setOwner(far, b.slot)
			if siloState.silosBySlot[a.slot] and siloState.silosBySlot[a.slot][far] then
				fail("silosBySlot — capture laisse l'index chez le lanceur")
			elseif not (siloState.silosBySlot[b.slot] and siloState.silosBySlot[b.slot][far]) then
				fail("silosBySlot — capture n'indexe pas chez le nouveau proprio")
			end
			local slotB = b.slot
			siloState:removePlayer(slotB)
			if siloState.silosBySlot[slotB] ~= nil then
				fail("silosBySlot — removePlayer laisse l'index du slot recycle")
			end
			siloState:destroyBuilding(near)
			if siloState.silosBySlot[a.slot] and siloState.silosBySlot[a.slot][near] then
				fail("silosBySlot — destroy laisse l'index")
			end
		end
	end
end

do
	local iso = GameState.new(1903)
	iso.combatUnlocked = true
	local fake = __newInstance("Player")
	fake.Name = "Colon"
	fake.UserId = 1903
	local colon = iso:addPlayer(fake, "Colon", Random.new(31), 0)
	local foe = iso:addPlayer(nil, "Voisin", Random.new(32), 0)
	if not colon or not foe then
		fail("isolation clic — factions impossibles")
	else
		ChantierB.stripTerritory(iso, colon)
		local glued: number? = nil
		local isolated: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if iso:isLand(index) and buffer.readu8(iso.owner, index) == 0 then
				if not glued and not iso:isSpawnIsolated(index) then
					glued = index
				elseif not isolated and iso:isSpawnIsolated(index) then
					isolated = index
				end
			end
			if glued and isolated then
				break
			end
		end
		if not glued then
			fail("isolation clic — aucune terre collee a une capitale")
		else
			local claimed = iso:claimSpawn(colon.slot, glued)
			if claimed then
				fail("isolation clic — claimSpawn accepte une tuile collee")
			end
		end
		if not isolated then
			fail("isolation clic — aucune terre isolee")
		elseif colon.awaitingSpawn then
			local claimed = iso:claimSpawn(colon.slot, isolated)
			if not claimed then
				fail("isolation clic — claimSpawn refuse une tuile isolee")
			end
		end
	end
end

print("passe 19 : silosBySlot, samsOf, isolation clic OK")

--[[
	Nightly passe 20 — revue PR #57 : coolingBuildings + armCooldown (V19),
	buildingsBySlot + bots (V22), samsOf buffer recycle (V25).
]]
do
	local cool = GameState.new(2001)
	local a = cool:addPlayer(nil, "Frappe", Random.new(41), 0)
	local b = cool:addPlayer(nil, "Batterie", Random.new(42), 0)
	if not a or not b then
		fail("coolingBuildings — factions impossibles")
	else
		local samTile: number? = nil
		local portTile: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(cool.owner, index) == b.slot and not cool.buildings[index] then
				if not samTile then
					samTile = index
				elseif not portTile then
					portTile = index
					break
				end
			end
		end
		if not samTile or not portTile then
			fail("coolingBuildings — tuiles libres introuvables")
		else
			cool:placeBuilding(samTile, Config.BUILDING.SAM, b.slot)
			cool:placeBuilding(portTile, Config.BUILDING.PORT, b.slot)
			local bx, by = MapGen.fromIndex(samTile)
			table.insert(cool.missiles, {
				id = 1,
				slot = a.slot,
				kind = Config.NUKE.ATOM,
				x = bx,
				y = by,
				sx = bx,
				sy = by,
				tx = bx + 1,
				ty = by,
				progress = 0,
				speed = 1,
			})
			Nukes.step(cool, Random.new(1), function() end)
			if #cool.missiles ~= 0 then
				fail("coolingBuildings — missile non intercepte")
			elseif not cool.coolingBuildings[samTile] then
				fail("tryIntercept — intercept n'a pas leve coolingBuildings")
			elseif (cool.buildings[samTile].cooldown or 0) <= 0 then
				fail("tryIntercept — SAM sans cooldown apres intercept")
			end
			if cool.coolingBuildings[portTile] then
				fail("stepCooldowns — PORT inscrit dans coolingBuildings")
			end

			Buildings.armCooldown(cool, samTile, 3)
			Buildings.stepCooldowns(cool)
			Buildings.stepCooldowns(cool)
			Buildings.stepCooldowns(cool)
			if (cool.buildings[samTile].cooldown or 0) ~= 0 then
				fail(`stepCooldowns — SAM cooldown={cool.buildings[samTile].cooldown} apres 3 ticks`)
			elseif cool.coolingBuildings[samTile] then
				fail("stepCooldowns — SAM encore dans coolingBuildings a 0")
			end
		end
	end
end

do
	local siloCool = GameState.new(2002)
	local a = siloCool:addPlayer(nil, "Arsenal", Random.new(51), 0)
	local b = siloCool:addPlayer(nil, "Cible", Random.new(52), 0)
	if not a or not b then
		fail("armCooldown silo — factions impossibles")
	else
		local siloTile: number? = nil
		local target: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			local owner = buffer.readu8(siloCool.owner, index)
			if not siloTile and owner == a.slot and not siloCool.buildings[index] then
				siloTile = index
			elseif not target and owner == b.slot then
				target = index
			end
			if siloTile and target then
				break
			end
		end
		if not siloTile or not target then
			fail("armCooldown silo — tuiles introuvables")
		else
			siloCool:placeBuilding(siloTile, Config.BUILDING.SILO, a.slot)
			a.era = Eras.requiredForNuke(Config.NUKE.ATOM)
			a.gold = 5000
			siloCool.tick = (Config.SPAWN_NUKE_IMMUNITY or 5) * Config.TICK_RATE + 1
			local ok, reason = Nukes.launch(siloCool, a.slot, target, Config.NUKE.ATOM)
			if not ok then
				fail("armCooldown silo — tir refuse: " .. tostring(reason))
			elseif siloCool.buildings[siloTile].cooldown ~= Config.SILO_COOLDOWN then
				fail("armCooldown silo — cooldown non pose")
			elseif not siloCool.coolingBuildings[siloTile] then
				fail("armCooldown silo — launch n'a pas leve coolingBuildings")
			end
		end
	end
end

do
	local idx = GameState.new(2003)
	local a = idx:addPlayer(nil, "Indexeur", Random.new(61), 0)
	local b = idx:addPlayer(nil, "Voisin", Random.new(62), 0)
	if not a or not b then
		fail("buildingsBySlot — factions impossibles")
	elseif typeof(Bots.lowestUpgradable) ~= "function" or typeof(Bots.blastValue) ~= "function" then
		fail("buildingsBySlot — helpers bots non exportes")
	else
		local cap = a.capitalTile
		if not cap or not (idx.buildingsBySlot[a.slot] and idx.buildingsBySlot[a.slot][cap]) then
			fail("buildingsBySlot — capitale non indexee")
		end
		local city: number? = nil
		local other: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(idx.owner, index) == a.slot and not idx.buildings[index] then
				if not city then
					city = index
				elseif not other then
					other = index
					break
				end
			end
		end
		if not city or not other then
			fail("buildingsBySlot — tuiles libres introuvables")
		else
			idx:placeBuilding(city, Config.BUILDING.CITY, a.slot)
			idx:placeBuilding(other, Config.BUILDING.CITY, a.slot)
			if not (idx.buildingsBySlot[a.slot][city] and idx.buildingsBySlot[a.slot][other]) then
				fail("buildingsBySlot — pose CITY non indexee")
			end
			idx:upgradeBuilding(city)
			local lowest = Bots.lowestUpgradable(idx, a.slot)
			if lowest ~= other then
				fail(`buildingsBySlot — lowestUpgradable={tostring(lowest)} (attendu ville niv 1)`)
			end
			local vOwn = Bots.blastValue(idx, a.slot, cap, 0)
			local vOther = Bots.blastValue(idx, b.slot, cap, 0)
			if vOwn ~= 1 then
				fail(`buildingsBySlot — blastValue camp={vOwn} (attendu 1 capitale)`)
			elseif vOther ~= 0 then
				fail(`buildingsBySlot — blastValue autre camp={vOther} (attendu 0)`)
			end
			idx:setOwner(city, b.slot)
			if idx.buildingsBySlot[a.slot] and idx.buildingsBySlot[a.slot][city] then
				fail("buildingsBySlot — capture laisse l'index chez le poseur")
			elseif not (idx.buildingsBySlot[b.slot] and idx.buildingsBySlot[b.slot][city]) then
				fail("buildingsBySlot — capture n'indexe pas chez le nouveau proprio")
			end
			local slotB = b.slot
			idx:removePlayer(slotB)
			if idx.buildingsBySlot[slotB] ~= nil then
				fail("buildingsBySlot — removePlayer laisse l'index du slot recycle")
			end
			idx:destroyBuilding(other)
			if idx.buildingsBySlot[a.slot] and idx.buildingsBySlot[a.slot][other] then
				fail("buildingsBySlot — destroy laisse l'index")
			end
		end
	end
end

do
	local rec = GameState.new(2004)
	local owner = rec:addPlayer(nil, "Batteries", Random.new(71), 0)
	local heir = rec:addPlayer(nil, "Vide", Random.new(72), 0)
	if not owner or not heir then
		fail("samsOf recycle — factions impossibles")
	else
		local tiles = {}
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(rec.owner, index) == owner.slot and not rec.buildings[index] then
				table.insert(tiles, index)
				if #tiles >= 3 then
					break
				end
			end
		end
		if #tiles < 3 then
			fail("samsOf recycle — moins de 3 tuiles libres")
		else
			for _, tile in tiles do
				rec:placeBuilding(tile, Config.BUILDING.SAM, owner.slot)
			end
			local listed = Buildings.samsOf(rec, owner.slot)
			if #listed ~= 3 then
				fail(`samsOf recycle — pose #={#listed} (attendu 3)`)
			end
			local empty = Buildings.samsOf(rec, heir.slot)
			if #empty ~= 0 then
				fail(`samsOf recycle — slot vide #={#empty} (queue non tronquee)`)
			end
			local again = Buildings.samsOf(rec, owner.slot)
			if #again ~= 3 then
				fail(`samsOf recycle — refill #={#again} (attendu 3)`)
			end
		end
	end
end

print("passe 20 : coolingBuildings, buildingsBySlot, samsOf recycle OK")

--[[
	Nightly passe 21 — revue PR #61 : factoriesBySlot + factoryBuf (V20),
	portsByTile (V21), navalBasesBySlot (V23).
]]
do
	local idx = GameState.new(2101)
	local owner = idx:addPlayer(nil, "Usines", Random.new(81), 0)
	local heir = idx:addPlayer(nil, "Heritier", Random.new(82), 0)
	if not owner or not heir then
		fail("factoriesBySlot — factions impossibles")
	else
		local factoryA: number? = nil
		local factoryB: number? = nil
		local city: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(idx.owner, index) == owner.slot and not idx.buildings[index] then
				if not factoryA then
					factoryA = index
				elseif not factoryB then
					factoryB = index
				elseif not city then
					city = index
					break
				end
			end
		end
		if not factoryA or not factoryB or not city then
			fail("factoriesBySlot — tuiles libres introuvables")
		else
			idx:placeBuilding(factoryA, Config.BUILDING.FACTORY, owner.slot)
			idx:placeBuilding(factoryB, Config.BUILDING.FACTORY, owner.slot)
			idx:placeBuilding(city, Config.BUILDING.CITY, owner.slot)
			local set = idx.factoriesBySlot[owner.slot]
			local count = 0
			if set then
				for _ in set do
					count += 1
				end
			end
			if count ~= 2 then
				fail(`factoriesBySlot — {count} usines indexees, attendu 2`)
			elseif set and set[city] then
				fail("factoriesBySlot — ville indexee comme usine")
			end
			Trade.step(idx, Random.new(1), function() end)
			local visits = Trade.lastFactoryVisits or 0
			if visits ~= 2 then
				fail(`Trade.step — {visits} visites, attendu 2 (V20)`)
			end
			idx:setOwner(factoryA, heir.slot)
			if idx.factoriesBySlot[owner.slot] and idx.factoriesBySlot[owner.slot][factoryA] then
				fail("factoriesBySlot — capture laisse l'index chez le poseur")
			elseif not (idx.factoriesBySlot[heir.slot] and idx.factoriesBySlot[heir.slot][factoryA]) then
				fail("factoriesBySlot — capture n'indexe pas chez le nouvel camp")
			end
			local slotHeir = heir.slot
			idx:removePlayer(slotHeir)
			if idx.factoriesBySlot[slotHeir] ~= nil then
				fail("factoriesBySlot — removePlayer laisse l'index du slot recycle")
			end
			idx:destroyBuilding(factoryB)
			if idx.factoriesBySlot[owner.slot] and idx.factoriesBySlot[owner.slot][factoryB] then
				fail("factoriesBySlot — destroy laisse l'index")
			end
		end
	end
end

do
	local empty = GameState.new(2102)
	local owner = empty:addPlayer(nil, "SansUsine", Random.new(83), 0)
	if not owner then
		fail("factoryBuf — faction impossible")
	else
		Trade.step(empty, Random.new(2), function() end)
		if (Trade.lastFactoryVisits or -1) ~= 0 then
			fail(`factoryBuf — 0 usine visites={Trade.lastFactoryVisits}, attendu 0`)
		end
	end
end

do
	local sea = GameState.new(2103)
	local a = sea:addPlayer(nil, "PortA", Random.new(91), 0)
	local b = sea:addPlayer(nil, "PortB", Random.new(92), 0)
	if not a or not b then
		fail("portsByTile — factions impossibles")
	else
		local coastal = {}
		for index = 0, Config.TILE_COUNT - 1 do
			if sea:isLand(index) and MapGen.isCoastal(sea.terrain, index) then
				table.insert(coastal, index)
				if #coastal >= 400 then
					break
				end
			end
		end
		local portA: number? = nil
		local portB: number? = nil
		local portC: number? = nil
		for _, first in coastal do
			for _, second in coastal do
				if first ~= second and Navy.findSeaPath(sea, first, second) then
					portA, portB = first, second
					break
				end
			end
			if portA then
				break
			end
		end
		if portA then
			for _, third in coastal do
				if third ~= portA and third ~= portB then
					portC = third
					break
				end
			end
		end
		if not portA or not portB or not portC then
			fail("portsByTile — cotes reliees introuvables")
		else
			sea:setOwner(portA, a.slot)
			sea:setOwner(portB, b.slot)
			sea:setOwner(portC, a.slot)
			sea:placeBuilding(portA, Config.BUILDING.PORT, a.slot)
			sea:placeBuilding(portB, Config.BUILDING.PORT, b.slot)
			sea:placeBuilding(portC, Config.BUILDING.PORT, a.slot)
			sea:upgradeBuilding(portA)
			local infoA = sea.portsByTile[portA]
			local nPorts = 0
			for _ in sea.portsByTile do
				nPorts += 1
			end
			if nPorts ~= 3 then
				fail(`portsByTile — {nPorts} ports, attendu 3`)
			elseif not infoA or infoA.level ~= 2 or infoA.slot ~= a.slot then
				fail("portsByTile — upgrade n'a pas mis a jour le niveau")
			end
			-- Cap atteint : pas de nouveau convoi (early-out avant flatten).
			local far = MapGen.toIndex(Config.MAP_WIDTH - 1, Config.MAP_HEIGHT - 1)
			for _ = 1, Config.MAX_TRADE_SHIPS do
				table.insert(sea.boats, {
					id = sea:nextId(),
					slot = a.slot,
					kind = Navy.KIND_TRADE,
					troops = 0,
					x = 0,
					y = 0,
					path = { far },
					step = 1,
					targetTile = portB,
					homeTile = portA,
				})
			end
			sea.tick = 0
			Navy.step(sea, Random.new(3))
			local afloat = 0
			for _, boat in sea.boats do
				if boat.kind == Navy.KIND_TRADE then
					afloat += 1
				end
			end
			if afloat ~= Config.MAX_TRADE_SHIPS then
				fail(`portsByTile — cap {afloat} != {Config.MAX_TRADE_SHIPS}`)
			end
			sea:destroyBuilding(portC)
			if sea.portsByTile[portC] then
				fail("portsByTile — destroy laisse un orphelin")
			end
			local left = 0
			for _ in sea.portsByTile do
				left += 1
			end
			if left ~= 2 then
				fail(`portsByTile — destroy laisse {left} ports, attendu 2`)
			end
		end
	end
end

do
	local one = GameState.new(2104)
	local owner = one:addPlayer(nil, "UnPort", Random.new(93), 0)
	if not owner then
		fail("portsByTile <2 — faction impossible")
	else
		local coast: number? = nil
		for index in owner.coast do
			if not one.buildings[index] then
				coast = index
				break
			end
		end
		if not coast then
			fail("portsByTile <2 — cote introuvable")
		else
			one:placeBuilding(coast, Config.BUILDING.PORT, owner.slot)
			one.tick = 0
			Navy.step(one, Random.new(4))
			local trades = 0
			for _, boat in one.boats do
				if boat.kind == Navy.KIND_TRADE then
					trades += 1
				end
			end
			if trades ~= 0 then
				fail(`portsByTile <2 — {trades} convois avec un seul port`)
			end
		end
	end
end

do
	local navy = GameState.new(2105)
	local owner = navy:addPlayer(nil, "Amiral", Random.new(94), 0)
	local heir = navy:addPlayer(nil, "Second", Random.new(95), 0)
	if not owner or not heir then
		fail("navalBasesBySlot — factions impossibles")
	else
		local bases = {}
		local portTile: number? = nil
		for index in owner.coast do
			if not navy.buildings[index] then
				if #bases < 2 then
					table.insert(bases, index)
				elseif not portTile then
					portTile = index
					break
				end
			end
		end
		if #bases < 2 or not portTile then
			fail("navalBasesBySlot — cotes libres insuffisantes")
		else
			navy:placeBuilding(bases[1], Config.BUILDING.NAVAL_BASE, owner.slot)
			navy:placeBuilding(bases[2], Config.BUILDING.NAVAL_BASE, owner.slot)
			navy:placeBuilding(portTile, Config.BUILDING.PORT, owner.slot)
			local set = navy.navalBasesBySlot[owner.slot]
			local count = 0
			if set then
				for _ in set do
					count += 1
				end
			end
			if count ~= 2 then
				fail(`navalBasesBySlot — {count} bases indexees, attendu 2`)
			elseif set and set[portTile] then
				fail("navalBasesBySlot — PORT indexe comme base")
			elseif navy._carriersDirty ~= true then
				fail("navalBasesBySlot — pose n'a pas leve _carriersDirty")
			end
			Navy.step(navy, Random.new(5))
			if navy._carriersDirty ~= false then
				fail("navalBasesBySlot — sync n'a pas consomme le drapeau")
			end
			local carriers = 0
			for _, boat in navy.boats do
				if boat.kind == Navy.KIND_CARRIER then
					carriers += 1
				end
			end
			if carriers ~= 2 then
				fail(`navalBasesBySlot — {carriers} carriers, attendu 2 (PORT exclus)`)
			end
			navy:setOwner(bases[1], heir.slot)
			if navy.navalBasesBySlot[owner.slot] and navy.navalBasesBySlot[owner.slot][bases[1]] then
				fail("navalBasesBySlot — capture laisse l'index chez le poseur")
			elseif not (navy.navalBasesBySlot[heir.slot] and navy.navalBasesBySlot[heir.slot][bases[1]]) then
				fail("navalBasesBySlot — capture n'indexe pas chez le nouvel camp")
			end
			local gone = heir.slot
			navy:removePlayer(gone)
			if navy.navalBasesBySlot[gone] ~= nil then
				fail("navalBasesBySlot — removePlayer laisse l'index du slot recycle")
			end
			navy:destroyBuilding(bases[2])
			if navy.navalBasesBySlot[owner.slot] and navy.navalBasesBySlot[owner.slot][bases[2]] then
				fail("navalBasesBySlot — destroy laisse l'index")
			end
		end
	end
end

print("passe 21 : factoriesBySlot, portsByTile, navalBasesBySlot OK")

--[[
	Nightly passe 22 — revue PR #64 : carrierBuf/targetBuf (V24), fillBlastBuf (V27).
]]
do
	-- V24 : ciblage warships (recette feel N67 / hardening N39).
	-- 0 carrier → pas de tir. 1 carrier + transport ennemi a portee → obus.
	-- Allie via areAllied ignore. Own-slot (0 autre slot) → early-out.
	local emptyState = GameState.new(2201)
	local ghost = emptyState:addPlayer(nil, "Fantome", Random.new(90), 0)
	if not ghost then
		fail("warships empty — spawn impossible")
	else
		local destLand: number? = nil
		local farOcean: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if not destLand and emptyState:isLand(index) and buffer.readu8(emptyState.owner, index) == Config.NEUTRAL_SLOT then
				destLand = index
			end
			if not farOcean and not emptyState:isLand(index) then
				farOcean = index
			end
			if destLand and farOcean then
				break
			end
		end
		if not destLand or not farOcean then
			fail("warships empty — tuile neutre / ocean introuvable")
		else
			table.insert(emptyState.boats, {
				id = emptyState:nextId(),
				slot = ghost.slot,
				kind = Navy.KIND_TRANSPORT,
				troops = 400,
				x = 10,
				y = 10,
				path = { farOcean },
				step = 1,
				targetTile = destLand,
				homeTile = destLand,
			})
			emptyState.tick = Config.WARSHIP_SHELL_RATE or 20
			Navy.step(emptyState, Random.new(91))
			if #emptyState.boats ~= 1 or emptyState.boats[1].troops ~= 400 then
				fail("warships empty — 0 carrier a mute un transport")
			end
		end
	end

	local fireState = GameState.new(2202)
	local admiral = fireState:addPlayer(nil, "Amiral", Random.new(92), 0)
	local prey = fireState:addPlayer(nil, "Convoi", Random.new(93), 0)
	if not admiral or not prey then
		fail("warships fire — spawn impossible")
	else
		local site: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(fireState.owner, index) == admiral.slot and not fireState.buildings[index] then
				site = index
				break
			end
		end
		if not site then
			fail("warships fire — tuile libre introuvable")
		else
			fireState:placeBuilding(site, Config.BUILDING.NAVAL_BASE, admiral.slot)
			Navy.step(fireState, Random.new(94))
			local carrier = nil
			for _, boat in fireState.boats do
				if boat.kind == Navy.KIND_CARRIER then
					carrier = boat
				end
			end
			if not carrier then
				fail("warships fire — carrier absent")
			else
				local cx, cy = carrier.x, carrier.y
				local troopsBefore = 1000
				local destLand: number? = nil
				local farOcean: number? = nil
				for index = 0, Config.TILE_COUNT - 1 do
					if
						not destLand
						and fireState:isLand(index)
						and buffer.readu8(fireState.owner, index) == Config.NEUTRAL_SLOT
					then
						destLand = index
					end
					if not farOcean and not fireState:isLand(index) then
						local ox, oy = MapGen.fromIndex(index)
						if (ox - cx) * (ox - cx) + (oy - cy) * (oy - cy) > 400 then
							farOcean = index
						end
					end
					if destLand and farOcean then
						break
					end
				end
				if not destLand or not farOcean then
					fail("warships fire — tuile neutre / ocean introuvable")
				else
					table.insert(fireState.boats, {
						id = fireState:nextId(),
						slot = prey.slot,
						kind = Navy.KIND_TRANSPORT,
						troops = troopsBefore,
						x = cx,
						y = cy,
						path = { farOcean },
						step = 1,
						targetTile = destLand,
						homeTile = destLand,
					})
					fireState.tick = Config.WARSHIP_SHELL_RATE or 20
					Navy.step(fireState, Random.new(94))
					local transport = nil
					for _, boat in fireState.boats do
						if boat.kind == Navy.KIND_TRANSPORT and boat.slot == prey.slot then
							transport = boat
						end
					end
					local expected = troopsBefore * (1 - (Config.WARSHIP_TRANSPORT_DAMAGE or 0.28))
					if not transport then
						fail("warships fire — transport disparu")
					elseif transport.troops >= troopsBefore then
						fail(`warships fire — pas d'obus ({transport.troops} inchange)`)
					elseif transport.troops > expected + 1e-6 then
						fail(`warships fire — degats trop faibles ({transport.troops} > {expected})`)
					elseif (carrier.lastShellTick or 0) ~= fireState.tick then
						fail(`warships fire — lastShellTick={carrier.lastShellTick}, attendu {fireState.tick}`)
					end
				end
			end
		end
	end

	local allyState = GameState.new(2203)
	local host = allyState:addPlayer(nil, "Hote", Random.new(95), 0)
	local friend = allyState:addPlayer(nil, "Allie", Random.new(96), 0)
	if not host or not friend then
		fail("warships ally — spawn impossible")
	else
		local site: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(allyState.owner, index) == host.slot and not allyState.buildings[index] then
				site = index
				break
			end
		end
		if not site then
			fail("warships ally — tuile libre introuvable")
		else
			allyState:placeBuilding(site, Config.BUILDING.NAVAL_BASE, host.slot)
			Navy.step(allyState, Random.new(97))
			local carrier = nil
			for _, boat in allyState.boats do
				if boat.kind == Navy.KIND_CARRIER then
					carrier = boat
				end
			end
			if not carrier then
				fail("warships ally — carrier absent")
			else
				allyState.alliances[host.slot][friend.slot] = allyState.tick + 5000
				allyState.alliances[friend.slot][host.slot] = allyState.tick + 5000
				local destLand: number? = nil
				local farOcean: number? = nil
				for index = 0, Config.TILE_COUNT - 1 do
					if
						not destLand
						and allyState:isLand(index)
						and buffer.readu8(allyState.owner, index) == Config.NEUTRAL_SLOT
					then
						destLand = index
					end
					if not farOcean and not allyState:isLand(index) then
						local ox, oy = MapGen.fromIndex(index)
						if (ox - carrier.x) * (ox - carrier.x) + (oy - carrier.y) * (oy - carrier.y) > 400 then
							farOcean = index
						end
					end
					if destLand and farOcean then
						break
					end
				end
				if not destLand or not farOcean then
					fail("warships ally — tuile neutre / ocean introuvable")
				else
					table.insert(allyState.boats, {
						id = allyState:nextId(),
						slot = friend.slot,
						kind = Navy.KIND_TRANSPORT,
						troops = 800,
						x = carrier.x,
						y = carrier.y,
						path = { farOcean },
						step = 1,
						targetTile = destLand,
						homeTile = destLand,
					})
					allyState.tick = Config.WARSHIP_SHELL_RATE or 20
					Navy.step(allyState, Random.new(97))
					local still = nil
					for _, boat in allyState.boats do
						if boat.kind == Navy.KIND_TRANSPORT and boat.slot == friend.slot then
							still = boat
						end
					end
					if not still or still.troops ~= 800 then
						fail(`warships ally — areAllied ignore ({if still then still.troops else "coule"})`)
					end
				end
			end
		end
	end

	local ownState = GameState.new(2204)
	local solo = ownState:addPlayer(nil, "Solo", Random.new(98), 0)
	if not solo then
		fail("warships own — spawn impossible")
	else
		local site: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(ownState.owner, index) == solo.slot and not ownState.buildings[index] then
				site = index
				break
			end
		end
		if not site then
			fail("warships own — tuile libre introuvable")
		else
			ownState:placeBuilding(site, Config.BUILDING.NAVAL_BASE, solo.slot)
			Navy.step(ownState, Random.new(99))
			local carrier = nil
			for _, boat in ownState.boats do
				if boat.kind == Navy.KIND_CARRIER then
					carrier = boat
				end
			end
			if not carrier then
				fail("warships own — carrier absent")
			else
				local destLand: number? = nil
				local farOcean: number? = nil
				for index = 0, Config.TILE_COUNT - 1 do
					if
						not destLand
						and ownState:isLand(index)
						and buffer.readu8(ownState.owner, index) == Config.NEUTRAL_SLOT
					then
						destLand = index
					end
					if not farOcean and not ownState:isLand(index) then
						farOcean = index
					end
					if destLand and farOcean then
						break
					end
				end
				if not destLand or not farOcean then
					fail("warships own — tuile neutre / ocean introuvable")
				else
					table.insert(ownState.boats, {
						id = ownState:nextId(),
						slot = solo.slot,
						kind = Navy.KIND_TRANSPORT,
						troops = 600,
						x = carrier.x,
						y = carrier.y,
						path = { farOcean },
						step = 1,
						targetTile = destLand,
						homeTile = destLand,
					})
					local shellBefore = carrier.lastShellTick or 0
					ownState.tick = Config.WARSHIP_SHELL_RATE or 20
					Navy.step(ownState, Random.new(99))
					local still = nil
					for _, boat in ownState.boats do
						if boat.kind == Navy.KIND_TRANSPORT then
							still = boat
						end
					end
					if not still or still.troops ~= 600 then
						fail("warships own — early-out a mute le transport du camp")
					elseif (carrier.lastShellTick or 0) ~= shellBefore then
						fail("warships own — lastShellTick avance sans autre slot")
					end
				end
			end
		end
	end
end

do
	-- V27 : fillBlastBuf. Index present + set nil = 0 (pas de fallback hash).
	-- Restore + truncate : deux visees successives ne fuient pas.
	local blast = GameState.new(2205)
	local owner = blast:addPlayer(nil, "Viseur", Random.new(73), 0)
	if not owner then
		fail("blastBuf — spawn impossible")
	else
		local sites: { number } = {}
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(blast.owner, index) == owner.slot and not blast.buildings[index] then
				table.insert(sites, index)
				if #sites >= 3 then
					break
				end
			end
		end
		if #sites < 3 then
			fail("blastBuf — tuiles libres insuffisantes")
		else
			blast:placeBuilding(sites[1], Config.BUILDING.CITY, owner.slot)
			blast:placeBuilding(sites[2], Config.BUILDING.CITY, owner.slot)
			local blast2 = 8
			local rich = Bots.blastValue(blast, owner.slot, sites[1], blast2)
			local poor = Bots.blastValue(blast, owner.slot, sites[3], 0)
			if rich < 1 then
				fail(`blastBuf — cluster {rich}, attendu >= 1`)
			elseif poor ~= 0 then
				fail(`blastBuf — tuile vide score {poor}, attendu 0`)
			else
				local saved = blast.buildingsBySlot[owner.slot]
				blast.buildingsBySlot[owner.slot] = nil
				local afterNil = Bots.blastValue(blast, owner.slot, sites[1], blast2)
				if afterNil ~= 0 then
					fail(`blastBuf — set nil score {afterNil}, attendu 0 (V27)`)
				else
					blast.buildingsBySlot[owner.slot] = saved
					local restored = Bots.blastValue(blast, owner.slot, sites[1], blast2)
					if restored ~= rich then
						fail(`blastBuf — restore {restored} != {rich} (truncate/fuite V27)`)
					end
				end
			end
		end
	end
end

print("passe 22 : carrierBuf/targetBuf, fillBlastBuf OK")

--[[
	Nightly passe 23 — revue PR #67 : snapshotBoats/snapshotMissiles (V26).
]]
do
	-- V26 : snapshotBoats recycle. 1 carrier + 1 transport, pas de path /
	-- homeTile / retreating. Retirer le transport → length 1. Destroy base
	-- → length 0 (pas de fuite du premier remplissage). Recette hardening
	-- N51 / feel N70 sans le champ retreating (Overlay 34/34 ne le lit pas).
	local empty = GameState.new(2301)
	local emptyBoats = empty:snapshotBoats()
	local emptyMissiles = empty:snapshotMissiles()
	if emptyBoats == nil or emptyMissiles == nil then
		fail("unitSnap — 0 unite a renvoye nil (attendu table vide recyclee)")
	elseif #emptyBoats ~= 0 or #emptyMissiles ~= 0 then
		fail(`unitSnap — 0 unite length boats={#emptyBoats} missiles={#emptyMissiles}`)
	end

	local state = GameState.new(2302)
	local owner = state:addPlayer(nil, "FlotteSnap", Random.new(90), 0)
	if not owner then
		fail("boatSnapBuf — spawn impossible")
	else
		local site: number? = nil
		for index = 0, Config.TILE_COUNT - 1 do
			if buffer.readu8(state.owner, index) == owner.slot and not state.buildings[index] then
				site = index
				break
			end
		end
		if not site then
			fail("boatSnapBuf — tuile libre introuvable")
		else
			state:placeBuilding(site, Config.BUILDING.NAVAL_BASE, owner.slot)
			Navy.step(state, Random.new(91))
			table.insert(state.boats, {
				id = state:nextId(),
				slot = owner.slot,
				kind = Navy.KIND_TRANSPORT,
				troops = 400,
				x = 3,
				y = 4,
				path = { site },
				step = 1,
				targetTile = site,
				homeTile = site,
			})
			local snaps = state:snapshotBoats()
			local n = 0
			local sawCarrier = false
			local sawTransport = false
			local leaked = false
			local transportOk = false
			for _, snap in snaps do
				n += 1
				if (snap :: any).path ~= nil or (snap :: any).homeTile ~= nil then
					leaked = true
				end
				if (snap :: any).retreating ~= nil then
					leaked = true
				end
				if snap.kind == Navy.KIND_CARRIER then
					sawCarrier = true
				elseif snap.kind == Navy.KIND_TRANSPORT then
					sawTransport = true
					if snap.troops == 400 then
						transportOk = true
					end
				end
			end
			if leaked then
				fail("boatSnapBuf — path/homeTile/retreating fuite")
			elseif n ~= 2 or #snaps ~= 2 then
				fail(`boatSnapBuf — length {n}/#{#snaps}, attendu 2`)
			elseif not sawCarrier or not sawTransport then
				fail("boatSnapBuf — carrier ou transport manquant")
			elseif not transportOk then
				fail("boatSnapBuf — troops transport incorrect")
			else
				print("boatSnapBuf : 1 carrier + 1 transport, pas de path (V26)")
				for i = #state.boats, 1, -1 do
					if state.boats[i].kind == Navy.KIND_TRANSPORT then
						table.remove(state.boats, i)
					end
				end
				local after = state:snapshotBoats()
				local afterN = 0
				local leftoverTransport = false
				for _, snap in after do
					afterN += 1
					if snap.kind == Navy.KIND_TRANSPORT then
						leftoverTransport = true
					end
				end
				if leftoverTransport or afterN ~= 1 or #after ~= 1 then
					fail(`boatSnapBuf — truncate transport fuite (n={afterN} #{#after})`)
				else
					state:destroyBuilding(site)
					Navy.step(state, Random.new(92))
					local gone = state:snapshotBoats()
					local goneN = 0
					for _ in gone do
						goneN += 1
					end
					if goneN ~= 0 or #gone ~= 0 then
						fail(`boatSnapBuf — destroy base fuite (n={goneN} #{#gone})`)
					else
						print("boatSnapBuf : truncate 2→1→0 (V26)")
					end
				end
			end
		end
	end
end

do
	-- V26 : snapshotMissiles recycle. 1 ogive, tx/ty honores, pas de
	-- progress/speed/sx/sy. Vider missiles → length 0. Relancer → length 1.
	local state = GameState.new(2303)
	local bomber = state:addPlayer(nil, "OgiveSnap", Random.new(93), 0)
	if not bomber then
		fail("missileSnapBuf — spawn impossible")
	else
		local target = bomber.capitalTile
		if not target then
			fail("missileSnapBuf — capitale introuvable")
		else
			local tx, ty = MapGen.fromIndex(target)
			table.insert(state.missiles, {
				id = 1,
				slot = bomber.slot,
				kind = Config.NUKE.ATOM,
				x = tx,
				y = ty,
				sx = tx,
				sy = ty,
				tx = tx + 3,
				ty = ty + 4,
				progress = 0.5,
				speed = Config.MISSILE_SPEED,
			})
			local snaps = state:snapshotMissiles()
			local n = 0
			local leaked = false
			local fieldsOk = false
			for _, snap in snaps do
				n += 1
				if
					(snap :: any).progress ~= nil
					or (snap :: any).speed ~= nil
					or (snap :: any).sx ~= nil
					or (snap :: any).sy ~= nil
				then
					leaked = true
				end
				if snap.id == 1 and snap.tx == tx + 3 and snap.ty == ty + 4 and snap.kind == Config.NUKE.ATOM then
					fieldsOk = true
				end
			end
			if leaked then
				fail("missileSnapBuf — progress/speed/sx/sy fuite")
			elseif n ~= 1 or #snaps ~= 1 then
				fail(`missileSnapBuf — length {n}/#{#snaps}, attendu 1`)
			elseif not fieldsOk then
				fail("missileSnapBuf — tx/ty/kind incorrects")
			else
				print("missileSnapBuf : 1 ogive, tx/ty, pas de progress (V26)")
				table.clear(state.missiles)
				local gone = state:snapshotMissiles()
				local goneN = 0
				for _ in gone do
					goneN += 1
				end
				if goneN ~= 0 or #gone ~= 0 then
					fail(`missileSnapBuf — truncate fuite (n={goneN} #{#gone})`)
				else
					table.insert(state.missiles, {
						id = 2,
						slot = bomber.slot,
						kind = Config.NUKE.ATOM,
						x = tx,
						y = ty,
						sx = tx,
						sy = ty,
						tx = tx + 1,
						ty = ty + 1,
						progress = 0.1,
						speed = Config.MISSILE_SPEED,
					})
					local again = state:snapshotMissiles()
					local againN = 0
					local againOk = false
					for _, snap in again do
						againN += 1
						if snap.id == 2 and snap.tx == tx + 1 and snap.ty == ty + 1 then
							againOk = true
						end
					end
					if againN ~= 1 or #again ~= 1 or not againOk then
						fail(`missileSnapBuf — relance length {againN}/#{#again}`)
					else
						print("missileSnapBuf : truncate 1→0→1 (V26)")
					end
				end
			end
		end
	end
end

print("passe 23 : snapshotBoats, snapshotMissiles OK")

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
	error(`banc serveur : {failures} invariant(s) violes`)
end
