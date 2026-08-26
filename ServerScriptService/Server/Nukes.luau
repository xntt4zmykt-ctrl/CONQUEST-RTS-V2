--!strict
--[[
	Phase nucleaire.

	Regle de design : le nucleaire ne doit jamais etre une strategie
	d'ouverture. Il se debloque tard (voir NUKE_UNLOCK_LAND_RATIO), coute cher,
	et surtout il est interceptable — une batterie SAM bien placee rend une
	frappe incertaine, donc la menace vaut souvent plus que le tir.

	L'effet est volontairement brutal sur la population et les batiments, mais
	ne rase pas le territoire entierement : une frappe affaiblit, elle ne
	remplace pas la conquete.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Eras = require(ReplicatedStorage.Shared.Eras)
local GameState = require(script.Parent.GameState)
local Buildings = require(script.Parent.Buildings)

type GameState = GameState.GameState

local Nukes = {}

local NEUTRAL = Config.NEUTRAL_SLOT

--=============================================================================
-- Tir
--=============================================================================

function Nukes.launch(state: GameState, slot: number, targetTile: number, kind: number): (boolean, string?)
	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
	end

	-- OF : immunite nucleaire ~5 s apres le spawn.
	local immunity = Config.SPAWN_NUKE_IMMUNITY or 5
	local spawnedAt = ps.spawnTick or 0
	if state.tick < spawnedAt + immunity * Config.TICK_RATE then
		local left = math.ceil((spawnedAt + immunity * Config.TICK_RATE - state.tick) / Config.TICK_RATE)
		return false, `Immunite de deploiement : encore {left}s.`
	end

	local stats = Config.NUKE_STATS[kind]
	if not stats then
		return false, "Type de missile inconnu."
	end

	local requiredEra = Eras.requiredForNuke(kind)
	if ps.era < requiredEra then
		return false, `{stats.name} : necessite l'ere {Eras.get(requiredEra).name}.`
	end

	if targetTile < 0 or targetTile >= Config.TILE_COUNT then
		return false, "Position hors carte."
	end

	if ps.siloCount <= 0 then
		return false, "Il te faut un silo."
	end

	if ps.gold < stats.cost then
		return false, `Il te faut {stats.cost} d'or ({math.floor(ps.gold)} disponible).`
	end

	local targetOwner = buffer.readu8(state.owner, targetTile)
	if targetOwner ~= NEUTRAL and state:areAllied(slot, targetOwner) then
		return false, "Tu es allie a cette faction."
	end

	--[[
		Le tir part du silo pret le plus proche de la cible.

		Le joueur ne selectionne jamais un silo : il designe une cible, le moteur
		choisit le lanceur. Un silo qui recharge est simplement ignore, ce qui
		fait de la couverture geographique des silos une decision reelle.
	]]
	local tx, ty = MapGen.fromIndex(targetTile)
	local bestSilo: number? = nil
	local bestDist = math.huge
	local anySilo = false
	for index, building in state.buildings do
		if building.slot == slot and building.kind == Config.BUILDING.SILO then
			anySilo = true
			if building.cooldown <= 0 then
				local x, y = MapGen.fromIndex(index)
				local dx, dy = x - tx, y - ty
				local dist = dx * dx + dy * dy
				if dist < bestDist then
					bestDist = dist
					bestSilo = index
				end
			end
		end
	end

	if not bestSilo then
		if anySilo then
			return false, "Tous tes silos rechargent."
		end
		return false, "Il te faut un silo."
	end

	local silo = state.buildings[bestSilo]
	if silo then
		silo.cooldown = Config.SILO_COOLDOWN
	end

	ps.gold -= stats.cost

	local sx, sy = MapGen.fromIndex(bestSilo)
	table.insert(state.missiles, {
		id = state:nextId(),
		slot = slot,
		kind = kind,
		x = sx,
		y = sy,
		sx = sx,
		sy = sy,
		tx = tx,
		ty = ty,
		progress = 0,
		speed = Config.MISSILE_SPEED,
	})

	-- Une frappe nucleaire est un evenement public : tout le monde voit le
	-- depart, c'est ce qui declenche la panique diplomatique.
	state:notify(`\u{2622} {ps.name} a lance {stats.name} !`, "alert")
	state:sound("nukeLaunch")

	return true, "Missile en vol."
end

--=============================================================================
-- Interception
--=============================================================================

--[[
	Interception SAM — port OF SAMLauncherExecution.

	Un seul SAM engage chaque missile (: exclusivite de cible).
	Choix = plus proche batterie prete dans SAM_RANGE (defaultSamRange 70).
	Cooldown apres tir ; succes selon SAM_INTERCEPT_CHANCE.
]]
local function tryIntercept(state: GameState, missile: GameState.Missile, rng: Random): boolean
	if missile.engaged then
		return false
	end

	local range = Config.SAM_RANGE or 70
	local range2 = range * range
	local best = nil
	local bestDist = math.huge

	for index, building in state.buildings do
		if building.kind ~= Config.BUILDING.SAM then
			continue
		end
		if building.slot == missile.slot then
			continue
		end
		if state:areAllied(building.slot, missile.slot) then
			continue
		end
		if building.cooldown > 0 then
			continue
		end

		local x, y = MapGen.fromIndex(index)
		local dx, dy = x - missile.x, y - missile.y
		local d2 = dx * dx + dy * dy
		if d2 > range2 then
			continue
		end
		if d2 < bestDist then
			best = building
			bestDist = d2
		end
	end

	if not best then
		return false
	end

	missile.engaged = true
	best.cooldown = Config.SAM_COOLDOWN or 90

	local chance = if Config.SAM_INTERCEPT_CHANCE ~= nil then Config.SAM_INTERCEPT_CHANCE else 1
	if rng:NextNumber() < chance then
		local owner = state.players[best.slot]
		state:notify(
			`\u{1F6E1} {if owner then owner.name else "Une batterie"} a intercepte un missile !`,
			"good"
		)
		state:sound("samIntercept")
		return true
	end

	return false
end

--=============================================================================
-- Scission du MIRV
--=============================================================================

--[[
	A mi-parcours, le MIRV libere ses ogives, regle CONQUEST : chaque ogive
	devient un missile a part entiere, avec sa propre cible choisie SUR le
	territoire de la victime, et chacune peut etre interceptee separement —
	c'est ce qui rend une batterie SAM precieuse meme contre l'arme ultime.

	Les cibles sont re-validees a l'instant de la scission : si la victime a
	perdu du terrain pendant le vol, les ogives ne frappent pas des tuiles
	qu'elle ne possede plus.
]]
local function splitMirv(state: GameState, missile: GameState.Missile, rng: Random)
	local stats = Config.NUKE_STATS[Config.NUKE.MIRV]
	local bx, by = math.floor(missile.tx), math.floor(missile.ty)
	local victim = if MapGen.inBounds(bx, by)
		then buffer.readu8(state.owner, MapGen.toIndex(bx, by))
		else NEUTRAL

	local targets: { Vector2 } = {}
	local spread = stats.spread
	local minGap = 4

	for _ = 1, stats.warheads * 30 do
		if #targets >= stats.warheads then
			break
		end
		local nx = bx + rng:NextInteger(-spread, spread)
		local ny = by + rng:NextInteger(-spread, spread)
		if not MapGen.inBounds(nx, ny) then
			continue
		end
		local index = MapGen.toIndex(nx, ny)
		if not state:isLand(index) then
			continue
		end
		if victim ~= NEUTRAL and buffer.readu8(state.owner, index) ~= victim then
			continue
		end
		local tooClose = false
		for _, t in targets do
			if math.abs(t.X - nx) + math.abs(t.Y - ny) < minGap then
				tooClose = true
				break
			end
		end
		if tooClose then
			continue
		end
		table.insert(targets, Vector2.new(nx, ny))
	end

	-- La victime a disparu ou n'a plus de terre dans la zone : les ogives
	-- retombent sur le point vise, comme un tir non guide.
	if #targets == 0 then
		table.insert(targets, Vector2.new(bx, by))
	end

	for _, t in targets do
		table.insert(state.missiles, {
			id = state:nextId(),
			slot = missile.slot,
			kind = Config.NUKE.MIRV,
			warhead = true,
			x = missile.x,
			y = missile.y,
			sx = missile.x,
			sy = missile.y,
			tx = t.X,
			ty = t.Y,
			progress = 0,
			-- Les ogives retombent plus vite que le porteur ne montait : la
			-- fenetre d'interception est courte, c'est le prix de la saturation.
			speed = Config.MISSILE_SPEED * 1.8,
			radius = stats.warheadRadius,
			troopKill = stats.warheadTroopKill,
		})
	end

	local owner = state.players[missile.slot]
	state:notify(
		`\u{2622} Le MIRV {if owner then `de {owner.name} ` else ""}se scinde en {#targets} ogives !`,
		"alert"
	)
end

--=============================================================================
-- Detonation
--=============================================================================

function Nukes.detonate(state: GameState, missile: GameState.Missile)
	local stats = Config.NUKE_STATS[missile.kind]
	if not stats then
		return
	end

	-- Une ogive porte sa propre puissance ; un missile complet celle de sa
	-- fiche. Voir splitMirv.
	local radius = missile.radius or stats.radius
	local troopKill = missile.troopKill or stats.troopKill
	local cx, cy = math.floor(missile.tx), math.floor(missile.ty)

	-- Pertes humaines : proportionnelles a la part du territoire touche, pour
	-- qu'une frappe sur un petit empire soit devastatrice et qu'une frappe sur
	-- un geant ne soit qu'une morsure.
	local hitTiles: { [number]: number } = {}

	for dy = -radius, radius do
		for dx = -radius, radius do
			local dist2 = dx * dx + dy * dy
			if dist2 > radius * radius then
				continue
			end

			local nx, ny = cx + dx, cy + dy
			if not MapGen.inBounds(nx, ny) then
				continue
			end

			local index = MapGen.toIndex(nx, ny)
			local owner = buffer.readu8(state.owner, index)
			if owner ~= NEUTRAL then
				hitTiles[owner] = (hitTiles[owner] or 0) + 1
			end

			if state.buildings[index] then
				state:destroyBuilding(index)
			end

			-- Le coeur du cratere est rase et redevient neutre ; la peripherie
			-- est seulement depeuplee.
			if dist2 <= (radius * 0.55) * (radius * 0.55) then
				if state:isLand(index) and owner ~= NEUTRAL then
					state:setOwner(index, NEUTRAL)
				end
			end
		end
	end

	for slot, tilesHit in hitTiles do
		local victim = state.players[slot]
		if victim then
			local share = tilesHit / math.max(1, victim.tiles + tilesHit)
			local loss = victim.troops * troopKill * math.min(1, share * 3)
			victim.troops = math.max(0, victim.troops - loss)
			state:notify(`\u{2622} Ton territoire a ete frappe — {math.floor(loss)} pertes.`, "bad", slot)
		end
	end
end

--=============================================================================
-- Tick
--=============================================================================

function Nukes.step(state: GameState, rng: Random, onExplosion: (number, number, number) -> ())
	Buildings.stepCooldowns(state)

	for i = #state.missiles, 1, -1 do
		local missile = state.missiles[i]

		local dx = missile.tx - missile.sx
		local dy = missile.ty - missile.sy
		local total = math.sqrt(dx * dx + dy * dy)

		if total < 0.001 then
			missile.progress = 1
		else
			missile.progress += missile.speed / total
		end

		missile.x = missile.sx + dx * math.min(1, missile.progress)
		missile.y = missile.sy + dy * math.min(1, missile.progress)

		if tryIntercept(state, missile, rng) then
			table.remove(state.missiles, i)
			continue
		end

		-- Le porteur MIRV n'explose jamais entier : a mi-parcours il libere
		-- ses ogives et disparait. Intercepter le porteur avant la scission
		-- reste la seule parade totale.
		if missile.kind == Config.NUKE.MIRV and not missile.warhead and missile.progress >= Config.MIRV_SEPARATION then
			splitMirv(state, missile, rng)
			table.remove(state.missiles, i)
			continue
		end

		if missile.progress >= 1 then
			local stats = Config.NUKE_STATS[missile.kind]
			Nukes.detonate(state, missile)
			onExplosion(missile.tx, missile.ty, missile.radius or (if stats then stats.radius else 8))
			table.remove(state.missiles, i)
		end
	end
end

return Nukes
