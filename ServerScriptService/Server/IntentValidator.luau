--!strict
--[[
	Validation centrale des intentions joueur.

	Tous les RemoteEvents client->serveur passent ici avant toute mutation :
	schema, phase, ownership, sequence/idempotence, rate limit. Les intentions
	acceptees sont mises en file et appliquees au debut du tick suivant dans un
	ordre stable (userId, sequence, type).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BuildingDefs = require(ReplicatedStorage.Shared.BuildingDefs)
local Doctrines = require(ReplicatedStorage.Shared.Doctrines)
local QuickChat = require(ReplicatedStorage.Shared.QuickChat)

local IntentValidator = {}

export type RefuseReason =
	"NotPlaying"
	| "Eliminated"
	| "InvalidSchema"
	| "InvalidTarget"
	| "InsufficientGold"
	| "RateLimited"
	| "DuplicateSequence"
	| "StaleSequence"
	| "UnknownAction"

export type Intent = {
	player: Player,
	userId: number,
	slot: number,
	sequence: number,
	actionType: string,
	payload: { [string]: any },
}

export type Context = {
	state: any,
	matchPhase: string,
	matchId: string,
	slotOf: (Player) -> number?,
	doctrineLockAt: number,
	now: () -> number,
	buildings: any,
	navy: any,
	nukes: any,
	diplomacy: any,
	research: any,
	reply: (Player, boolean, string?) -> (),
	refuse: (Player, RefuseReason, string?) -> (),
	broadcastRoster: (() -> ())?,
}

local queue: { Intent } = {}
local lastSequence: { [number]: number } = {} -- userId -> last accepted seq
local windowStart: { [number]: number } = {}
local windowCount: { [number]: number } = {}
local refuseCounts: { [string]: number } = {}

local ACTION_ORDER = {
	SetAttackRatio = 1,
	ChooseDoctrine = 2,
	Retreat = 3,
	Attack = 4,
	Build = 5,
	Upgrade = 6,
	Boat = 7,
	Nuke = 8,
	Research = 9,
	Diplomacy = 10,
	QuickChat = 11,
}

local DIPLOMACY_ACTIONS = {
	request = true,
	accept = true,
	decline = true,
	["break"] = true,
	extend = true,
	donateGold = true,
	donateTroops = true,
	embargo = true,
	unembargo = true,
	markTarget = true,
}

local function bumpRefuse(reason: string)
	refuseCounts[reason] = (refuseCounts[reason] or 0) + 1
end

function IntentValidator.refuseStats(): { [string]: number }
	return refuseCounts
end

function IntentValidator.reset()
	table.clear(queue)
	table.clear(lastSequence)
	table.clear(windowStart)
	table.clear(windowCount)
	table.clear(refuseCounts)
end

function IntentValidator.clearPlayer(userId: number)
	lastSequence[userId] = nil
	windowStart[userId] = nil
	windowCount[userId] = nil
	for i = #queue, 1, -1 do
		if queue[i].userId == userId then
			table.remove(queue, i)
		end
	end
end

local function isInteger(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value == math.floor(value)
		and math.abs(value) ~= math.huge
end

local function checkRate(userId: number, now: number): boolean
	local limit = Config.INTENT_RATE_LIMIT_PER_SEC or 20
	local start = windowStart[userId]
	if not start or now - start >= 1 then
		windowStart[userId] = now
		windowCount[userId] = 1
		return true
	end
	local count = (windowCount[userId] or 0) + 1
	windowCount[userId] = count
	return count <= limit
end

local function checkSequence(userId: number, sequence: number?): (boolean, RefuseReason?)
	if sequence == nil then
		-- Compat : intention sans numero — acceptee mais non idempotente.
		return true, nil
	end
	if not isInteger(sequence) or sequence < 1 then
		return false, "InvalidSchema"
	end
	local last = lastSequence[userId] or 0
	if sequence == last then
		return false, "DuplicateSequence"
	end
	if sequence < last then
		return false, "StaleSequence"
	end
	return true, nil
end

--[[
	Enfile une intention apres validation de base. Renvoie ok, raison.
]]
function IntentValidator.enqueue(
	ctx: Context,
	player: Player,
	actionType: string,
	sequence: number?,
	payload: { [string]: any }
): (boolean, RefuseReason?)
	local now = ctx.now()
	local userId = player.UserId

	if not ACTION_ORDER[actionType] then
		bumpRefuse("UnknownAction")
		return false, "UnknownAction"
	end

	-- Partie terminee : plus aucun ordre. Doctrine / ratio restent valides
	-- en lobby (waiting), pas une fois le match clos.
	if ctx.matchPhase == "ended" then
		bumpRefuse("NotPlaying")
		return false, "NotPlaying"
	end
	if ctx.matchPhase ~= "playing" and actionType ~= "ChooseDoctrine" and actionType ~= "SetAttackRatio" then
		bumpRefuse("NotPlaying")
		return false, "NotPlaying"
	end

	-- Join n'est pas une intention de tick ; les ordres de jeu exigent un slot.
	local slot = ctx.slotOf(player)
	if not slot then
		bumpRefuse("NotPlaying")
		return false, "NotPlaying"
	end

	local ps = ctx.state.players[slot]
	if not ps then
		bumpRefuse("Eliminated")
		return false, "Eliminated"
	end

	if not checkRate(userId, now) then
		bumpRefuse("RateLimited")
		return false, "RateLimited"
	end

	local maxPending = Config.MAX_PENDING_INTENTS or 32
	local pending = 0
	for _, intent in queue do
		if intent.userId == userId then
			pending += 1
		end
	end
	if pending >= maxPending then
		bumpRefuse("RateLimited")
		return false, "RateLimited"
	end

	local seqOk, seqReason = checkSequence(userId, sequence)
	if not seqOk then
		bumpRefuse(seqReason :: string)
		return false, seqReason
	end

	-- Schema leger par type (bornes dures). Le cout exact reste calcule a l'apply.
	if actionType == "Attack" or actionType == "Retreat" or actionType == "Boat" then
		local index = payload.index
		if not isInteger(index) or index < 0 or index >= Config.TILE_COUNT then
			bumpRefuse("InvalidTarget")
			return false, "InvalidTarget"
		end
	elseif actionType == "Build" then
		local index, kind = payload.index, payload.kind
		if not isInteger(index) or index < 0 or index >= Config.TILE_COUNT then
			bumpRefuse("InvalidTarget")
			return false, "InvalidTarget"
		end
		if not isInteger(kind) or not BuildingDefs.get(kind) then
			bumpRefuse("InvalidSchema")
			return false, "InvalidSchema"
		end
	elseif actionType == "Upgrade" then
		local index = payload.index
		if not isInteger(index) or index < 0 or index >= Config.TILE_COUNT then
			bumpRefuse("InvalidTarget")
			return false, "InvalidTarget"
		end
	elseif actionType == "Nuke" then
		local index, kind = payload.index, payload.kind
		if not isInteger(index) or index < 0 or index >= Config.TILE_COUNT then
			bumpRefuse("InvalidTarget")
			return false, "InvalidTarget"
		end
		if not isInteger(kind) or Config.NUKE_STATS[kind] == nil then
			bumpRefuse("InvalidSchema")
			return false, "InvalidSchema"
		end
	elseif actionType == "SetAttackRatio" then
		if typeof(payload.ratio) ~= "number" or payload.ratio ~= payload.ratio then
			bumpRefuse("InvalidSchema")
			return false, "InvalidSchema"
		end
		-- Meme bornes que l'apply : un ratio extreme n'occupe pas la file.
		payload.ratio = math.clamp(payload.ratio, 0.05, 1)
	elseif actionType == "ChooseDoctrine" then
		if not Doctrines.isValid(payload.doctrineId) then
			bumpRefuse("InvalidSchema")
			return false, "InvalidSchema"
		end
	elseif actionType == "Diplomacy" then
		if typeof(payload.action) ~= "string" or not isInteger(payload.targetSlot) then
			bumpRefuse("InvalidSchema")
			return false, "InvalidSchema"
		end
		if not DIPLOMACY_ACTIONS[payload.action] then
			bumpRefuse("UnknownAction")
			return false, "UnknownAction"
		end
		if payload.targetSlot < 1 or payload.targetSlot > Config.MAX_TOTAL_FACTIONS then
			bumpRefuse("InvalidTarget")
			return false, "InvalidTarget"
		end
		if payload.targetSlot == slot then
			bumpRefuse("InvalidTarget")
			return false, "InvalidTarget"
		end
	elseif actionType == "QuickChat" then
		local entry = if typeof(payload.messageId) == "string" then QuickChat.get(payload.messageId) else nil
		if not entry then
			bumpRefuse("InvalidSchema")
			return false, "InvalidSchema"
		end
		-- Un needsTarget sans 3e arg lisait un sequence (ex. 99) comme slot.
		if entry.needsTarget then
			local targetSlot = payload.targetSlot
			if not isInteger(targetSlot) or targetSlot < 1 or targetSlot > Config.MAX_TOTAL_FACTIONS then
				bumpRefuse("InvalidTarget")
				return false, "InvalidTarget"
			end
		end
	end

	if sequence ~= nil then
		lastSequence[userId] = sequence
	end

	table.insert(queue, {
		player = player,
		userId = userId,
		slot = slot,
		sequence = sequence or 0,
		actionType = actionType,
		payload = payload,
	})
	return true, nil
end

local function applyOne(ctx: Context, intent: Intent)
	local state = ctx.state
	local slot = intent.slot
	local player = intent.player
	local payload = intent.payload
	local ok = false
	local message: string? = nil

	if intent.actionType == "Attack" then
		local index = payload.index
		local ps = state.players[slot]
		if ps then
			ps.aimTile = index
			if ps.awaitingSpawn then
				local claimed = state:claimSpawn(slot, index)
				if claimed then
					ok, message = true, "Territoire revendique."
				else
					ok, message = false, "Spawn invalide."
				end
			else
				if not state:isLand(index) then
					ok, message = false, "Impossible d'attaquer l'ocean. Choisis une terre."
				else
					local targetSlot = buffer.readu8(state.owner, index)
					ok, message = state:launchAttack(slot, targetSlot)
				end
			end
		end
	elseif intent.actionType == "Retreat" then
		local index = payload.index
		local targetSlot = buffer.readu8(state.owner, index)
		ok, message = state:retreatAttack(slot, targetSlot)
	elseif intent.actionType == "SetAttackRatio" then
		local ps = state.players[slot]
		if ps then
			ps.attackRatio = math.clamp(payload.ratio, 0.05, 1)
			ok = true
		end
	elseif intent.actionType == "ChooseDoctrine" then
		if ctx.now() > ctx.doctrineLockAt then
			ok, message = false, "Ta doctrine est deja engagee."
		else
			local ps = state.players[slot]
			if ps then
				ps.doctrine = Doctrines.get(payload.doctrineId).id
				if ctx.broadcastRoster then
					ctx.broadcastRoster()
				end
				ok, message = true, `Doctrine {Doctrines.get(payload.doctrineId).name} adoptee.`
			end
		end
	elseif intent.actionType == "Build" then
		ok, message = ctx.buildings.build(state, slot, payload.index, payload.kind)
	elseif intent.actionType == "Upgrade" then
		ok, message = ctx.buildings.upgradeAt(state, slot, payload.index)
	elseif intent.actionType == "Boat" then
		ok, message = ctx.navy.launchInvasion(state, slot, payload.index)
	elseif intent.actionType == "Nuke" then
		ok, message = ctx.nukes.launch(state, slot, payload.index, payload.kind)
	elseif intent.actionType == "Research" then
		ok, message = ctx.research.advance(state, slot)
	elseif intent.actionType == "Diplomacy" then
		local action = payload.action
		local targetSlot = payload.targetSlot
		if action == "request" then
			ok, message = ctx.diplomacy.request(state, slot, targetSlot)
		elseif action == "accept" then
			ok, message = ctx.diplomacy.accept(state, targetSlot, slot)
		elseif action == "decline" then
			ok, message = ctx.diplomacy.decline(state, targetSlot, slot)
		elseif action == "break" then
			ok, message = ctx.diplomacy.breakAlliance(state, slot, targetSlot)
		elseif action == "extend" then
			ok, message = ctx.diplomacy.extend(state, slot, targetSlot)
		elseif action == "donateGold" then
			local ps = state.players[slot]
			local amount = ps and math.floor(ps.gold * Config.DONATION_SHARE) or 0
			ok, message = ctx.diplomacy.donateGold(state, slot, targetSlot, amount)
		elseif action == "donateTroops" then
			local ps = state.players[slot]
			local amount = ps and math.floor(ps.troops * Config.DONATION_SHARE) or 0
			ok, message = ctx.diplomacy.donateTroops(state, slot, targetSlot, amount)
		elseif action == "embargo" then
			ok, message = ctx.diplomacy.setEmbargo(state, slot, targetSlot, true)
		elseif action == "unembargo" then
			ok, message = ctx.diplomacy.setEmbargo(state, slot, targetSlot, false)
		elseif action == "markTarget" then
			ok, message = ctx.diplomacy.setTargetMark(state, slot, targetSlot)
		else
			bumpRefuse("UnknownAction")
			ctx.refuse(player, "UnknownAction", nil)
			return
		end
	elseif intent.actionType == "QuickChat" then
		local entry = QuickChat.get(payload.messageId)
		if entry and entry.needsTarget then
			local targetSlot = payload.targetSlot
			if not isInteger(targetSlot) or targetSlot == slot then
				ok, message = false, "Ce message demande une cible."
			elseif not state.players[targetSlot] then
				ok, message = false, "Cette faction n'existe plus."
			else
				ok = ctx.diplomacy.sendQuickChat(state, slot, payload.messageId, targetSlot)
				if not ok then
					message = "Message trop frequent."
				end
			end
		else
			ok = ctx.diplomacy.sendQuickChat(
				state,
				slot,
				payload.messageId,
				if isInteger(payload.targetSlot) then payload.targetSlot else nil
			)
			if not ok then
				message = "Message trop frequent."
			end
		end
	end

	if message or ok then
		ctx.reply(player, ok, message)
	end
	if not ok and message then
		-- Refus metier (or, cible) : compteur generique InvalidTarget / InsufficientGold
		if string.find(message, "or", 1, true) then
			bumpRefuse("InsufficientGold")
		else
			bumpRefuse("InvalidTarget")
		end
	end
end

--[[
	Applique la file dans l'ordre stable : userId, sequence, type.
	A appeler en tete de tick, avant bots et systemes.
]]
function IntentValidator.flush(ctx: Context): number
	if #queue == 0 then
		return 0
	end

	local batch = queue
	queue = {}

	table.sort(batch, function(a, b)
		if a.userId ~= b.userId then
			return a.userId < b.userId
		end
		if a.sequence ~= b.sequence then
			return a.sequence < b.sequence
		end
		return (ACTION_ORDER[a.actionType] or 99) < (ACTION_ORDER[b.actionType] or 99)
	end)

	local applied = 0
	for _, intent in batch do
		-- Revalider presence : elimination entre enqueue et flush.
		if not ctx.state.players[intent.slot] then
			bumpRefuse("Eliminated")
			ctx.refuse(intent.player, "Eliminated", "Faction eliminee.")
			continue
		end
		if ctx.matchPhase == "ended"
			or (
				ctx.matchPhase ~= "playing"
				and intent.actionType ~= "ChooseDoctrine"
				and intent.actionType ~= "SetAttackRatio"
			)
		then
			bumpRefuse("NotPlaying")
			ctx.refuse(intent.player, "NotPlaying", nil)
			continue
		end
		applyOne(ctx, intent)
		applied += 1
	end
	return applied
end

function IntentValidator.pendingCount(): number
	return #queue
end

return IntentValidator
