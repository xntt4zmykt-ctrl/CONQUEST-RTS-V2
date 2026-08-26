--!strict
--[[
	Phase nucleaire.

	Regle de design : le nucleaire ne doit jamais etre une strategie
	d'ouverture. Il se debloque par ere (silo + ere Atomique), coute cher,
	et est bloque tant que combatUnlocked est faux — comme l'attaque terrestre
	et le debarquement. Il est interceptable : une batterie SAM bien placee
	rend une frappe incertaine, donc la menace vaut souvent plus que le tir.

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

-- N76 : snapshots crater recycles (pas un spatial hash). Maps, pas
-- arrays — table.clear avant fill, pas de truncate. Distinct de
-- samBuf / blastX (Bots) / destroyBuf. Non reentrant : Nukes.step
-- detonne en serie, le clear au boom suivant est voulu. Un leftover
-- hitTiles taxerait un camp non touche (autorite troupes).
local tilesBeforeBuf: { [number]: number } = {}
local hitTilesBuf: { [number]: number } = {}

-- N77 : visee MIRV recyclee (nombres, pas Vector2). Truncate leftover
-- AVANT fill — un leftover viserait les ogives du porteur precedent
-- (autorite). Distinct de tilesBeforeBuf / hitTilesBuf (N76) / samBuf
-- / blastX. Non reentrant : Nukes.step scinde en serie.
local mirvTxBuf: { number } = table.create(8)
local mirvTyBuf: { number } = table.create(8)
-- N97 : missile live recycle (leftover N52/N96). Contrat A free-list,
-- recette boatFree N96. launch / splitMirv pop, table.remove push.
-- Overwrite id/slot/kind/x/y/sx/sy/tx/ty/progress/speed. engaged /
-- warhead / radius / troopKill nil sauf ogive (warhead=true + radius
-- + troopKill). Pool module survit a GameState.new. Ne pas require
-- depuis GameState (cycle). GameState.removePlayer inchange. Overlay
-- lit snapshot N52, pas le live. table.clear du record interdit.
-- Un leftover engaged = SAM skip ; leftover warhead = pas de scission.
local missileFree: { GameState.Missile } = table.create(8)
Nukes.missileFree = missileFree

local function acquireMissile(
	id: number,
	slot: number,
	kind: number,
	x: number,
	y: number,
	sx: number,
	sy: number,
	tx: number,
	ty: number,
	progress: number,
	speed: number,
	warhead: boolean?,
	radius: number?,
	troopKill: number?
): GameState.Missile
	local rec = table.remove(missileFree)
	if rec == nil then
		rec = {
			id = id,
			slot = slot,
			kind = kind,
			x = x,
			y = y,
			sx = sx,
			sy = sy,
			tx = tx,
			ty = ty,
			progress = progress,
			speed = speed,
			warhead = warhead,
			radius = radius,
			troopKill = troopKill,
		}
	else
		rec.id = id
		rec.slot = slot
		rec.kind = kind
		rec.x = x
		rec.y = y
		rec.sx = sx
		rec.sy = sy
		rec.tx = tx
		rec.ty = ty
		rec.progress = progress
		rec.speed = speed
		rec.engaged = nil
		if warhead then
			rec.warhead = true
			rec.radius = radius
			rec.troopKill = troopKill
		else
			rec.warhead = nil
			rec.radius = nil
			rec.troopKill = nil
		end
	end
	return rec
end

local function despawnMissile(state: GameState, i: number)
	local missile = state.missiles[i]
	table.remove(state.missiles, i)
	table.insert(missileFree, missile)
end

--=============================================================================
-- Tir
--=============================================================================

function Nukes.launch(state: GameState, slot: number, targetTile: number, kind: number): (boolean, string?)
	local ps = state.players[slot]
	if not ps then
		return false, "Faction inconnue."
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
	if targetOwner ~= NEUTRAL and not state.combatUnlocked then
		return false, "Les frontieres sont protegees pendant la preparation."
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

	local function consider(index: number, building: any)
		if not building or building.kind ~= Config.BUILDING.SILO then
			return
		end
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

	-- N44 : index silosBySlot, pas le hash buildings (recette feel N60).
	-- Si l'index existe, un slot sans silo (set nil) ne rescane PAS le hash.
	if state.silosBySlot then
		local silos = state.silosBySlot[slot]
		if silos then
			for index in silos do
				consider(index, state.buildings[index])
			end
		end
	else
		for index, building in state.buildings do
			if building.slot == slot then
				consider(index, building)
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
		Buildings.armCooldown(state, bestSilo, Config.SILO_COOLDOWN)
	end

	ps.gold -= stats.cost

	local sx, sy = MapGen.fromIndex(bestSilo)
	table.insert(
		state.missiles,
		acquireMissile(
			state:nextId(),
			slot,
			kind,
			sx,
			sy,
			sx,
			sy,
			tx,
			ty,
			0,
			Config.MISSILE_SPEED,
			nil,
			nil,
			nil
		)
	)

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
	local bestIndex: number? = nil
	local bestDist = math.huge
	local samsBySlot = state.samsBySlot

	-- N42 : index samsBySlot, pas le hash buildings (recette feel N57).
	if samsBySlot then
		for slot, set in samsBySlot do
			if slot == missile.slot then
				continue
			end
			if state:areAllied(slot, missile.slot) then
				continue
			end
			for tile in set do
				local building = state.buildings[tile]
				if not building or building.kind ~= Config.BUILDING.SAM then
					continue
				end
				if building.cooldown > 0 then
					continue
				end

				local x, y = MapGen.fromIndex(tile)
				local dx, dy = x - missile.x, y - missile.y
				local d2 = dx * dx + dy * dy
				if d2 > range2 then
					continue
				end
				if d2 < bestDist then
					best = building
					bestIndex = tile
					bestDist = d2
				end
			end
		end
	else
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
				bestIndex = index
				bestDist = d2
			end
		end
	end

	if not best or not bestIndex then
		return false
	end

	missile.engaged = true
	Buildings.armCooldown(state, bestIndex, Config.SAM_COOLDOWN or 90)

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
-- Snapshot des champs du porteur AVANT despawn : acquireMissile peut
-- recycler le meme record comme premiere ogive (rawequal voulu).
local function splitMirv(
	state: GameState,
	slot: number,
	mx: number,
	my: number,
	tx: number,
	ty: number,
	rng: Random
)
	local stats = Config.NUKE_STATS[Config.NUKE.MIRV]
	local bx, by = math.floor(tx), math.floor(ty)
	local victim = if MapGen.inBounds(bx, by)
		then buffer.readu8(state.owner, MapGen.toIndex(bx, by))
		else NEUTRAL

	-- N77 : table.clear avant fill. Pas de Vector2 — copie tx/ty dans
	-- l'ogive. Loi spread / minGap=4 / fallback point vise inchangee.
	table.clear(mirvTxBuf)
	table.clear(mirvTyBuf)
	local spread = stats.spread
	local minGap = 4

	for _ = 1, stats.warheads * 30 do
		if #mirvTxBuf >= stats.warheads then
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
		for i = 1, #mirvTxBuf do
			if math.abs(mirvTxBuf[i] - nx) + math.abs(mirvTyBuf[i] - ny) < minGap then
				tooClose = true
				break
			end
		end
		if tooClose then
			continue
		end
		table.insert(mirvTxBuf, nx)
		table.insert(mirvTyBuf, ny)
	end

	-- La victime a disparu ou n'a plus de terre dans la zone : les ogives
	-- retombent sur le point vise, comme un tir non guide.
	if #mirvTxBuf == 0 then
		table.insert(mirvTxBuf, bx)
		table.insert(mirvTyBuf, by)
	end

	for i = 1, #mirvTxBuf do
		-- Ogives uniques entre elles (pas d'alias live). La premiere
		-- recycle le porteur despawn (rawequal).
		table.insert(
			state.missiles,
			acquireMissile(
				state:nextId(),
				slot,
				Config.NUKE.MIRV,
				mx,
				my,
				mx,
				my,
				mirvTxBuf[i],
				mirvTyBuf[i],
				0,
				Config.MISSILE_SPEED * 1.8,
				true,
				stats.warheadRadius,
				stats.warheadTroopKill
			)
		)
	end

	local owner = state.players[slot]
	state:notify(
		`\u{2622} Le MIRV {if owner then `de {owner.name} ` else ""}se scinde en {#mirvTxBuf} ogives !`,
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
	-- un geant ne soit qu'une morsure. Snapshot AVANT le crater : setOwner
	-- reduit victim.tiles dans la boucle, ce qui faussait le denominateur.
	-- N76 : hashes module, table.clear avant fill. Formule share inchangee.
	table.clear(tilesBeforeBuf)
	for ownerSlot, ownerPs in state.players do
		tilesBeforeBuf[ownerSlot] = ownerPs.tiles
	end
	table.clear(hitTilesBuf)

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
				hitTilesBuf[owner] = (hitTilesBuf[owner] or 0) + 1
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

	for slot, tilesHit in hitTilesBuf do
		local victim = state.players[slot]
		if victim then
			local share = tilesHit / math.max(1, tilesBeforeBuf[slot] or victim.tiles)
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
			despawnMissile(state, i)
			continue
		end

		-- Le porteur MIRV n'explose jamais entier : a mi-parcours il libere
		-- ses ogives et disparait. Intercepter le porteur avant la scission
		-- reste la seule parade totale. Despawn AVANT split pour que la
		-- premiere ogive recycle le porteur (snapshot des champs ci-dessus).
		if missile.kind == Config.NUKE.MIRV and not missile.warhead and missile.progress >= Config.MIRV_SEPARATION then
			local slot, mx, my = missile.slot, missile.x, missile.y
			local tx, ty = missile.tx, missile.ty
			despawnMissile(state, i)
			splitMirv(state, slot, mx, my, tx, ty, rng)
			continue
		end

		if missile.progress >= 1 then
			local stats = Config.NUKE_STATS[missile.kind]
			Nukes.detonate(state, missile)
			onExplosion(missile.tx, missile.ty, missile.radius or (if stats then stats.radius else 8))
			despawnMissile(state, i)
		end
	end
end

-- Banc N76 : leftover ocean / rawequal. Pas replique.
Nukes.tilesBeforeBuf = tilesBeforeBuf
Nukes.hitTilesBuf = hitTilesBuf
-- Banc N77 : leftover ocean / rawequal. Pas replique.
Nukes.mirvTxBuf = mirvTxBuf
Nukes.mirvTyBuf = mirvTyBuf

return Nukes
