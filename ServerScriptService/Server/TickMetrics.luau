--!strict
--[[
	Instrumentation de debit simulation / replication.

	Mesure avant toute modification de MAX_TILES_PER_TICK : changedTiles,
	dirtyChunks estimes, octets de delta, duree de tick. Les percentiles sont
	calculables a partir de l'historique borne.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TickMetrics = {}

export type Sample = {
	tick: number,
	changedTiles: number,
	dirtyChunks: number,
	deltaBytes: number,
	tickMs: number,
}

local HISTORY_CAP = 600 -- 60 s a 10 Hz
local history: { Sample } = table.create(HISTORY_CAP)
local historyCount = 0
local historyWrite = 0
local seenBuf: { [number]: boolean } = {}
-- N79 : copies numeriques pour percentile. table.sort mute — le prochain
-- snapshot reecrit 1..historyCount (pas d'early-out « deja plein »).
local changedBuf: { number } = table.create(HISTORY_CAP, 0)
local bytesBuf: { number } = table.create(HISTORY_CAP, 0)
local msBuf: { number } = table.create(HISTORY_CAP, 0)
local chunksBuf: { number } = table.create(HISTORY_CAP, 0)
local totals = {
	ticks = 0,
	changedTiles = 0,
	dirtyChunks = 0,
	deltaBytes = 0,
	tickMs = 0,
	maxChanged = 0,
	maxDeltaBytes = 0,
	maxTickMs = 0,
}
-- N81 : 1 record + 2 nested module-level. formatReport lit tout de suite ;
-- un 2e snapshot reecrit les champs (pas d'early-out).
local p95Buf = {
	changedTiles = 0,
	deltaBytes = 0,
	tickMs = 0,
	dirtyChunks = 0,
}
local p99Buf = {
	changedTiles = 0,
	deltaBytes = 0,
	tickMs = 0,
	dirtyChunks = 0,
}
local snapBuf = {
	samples = 0,
	totals = totals,
	p95 = p95Buf,
	p99 = p99Buf,
}

local function chunkOf(index: number): number
	local w = Config.MAP_WIDTH
	local cs = Config.CHUNK_SIZE
	local x = index % w
	local y = index // w
	local cx = x // cs
	local cy = y // cs
	return cy * Config.CHUNKS_X + cx
end

--[[
	Estime les chunks sales a partir d'un delta owner ([u32][u8] repete).
]]
function TickMetrics.dirtyChunksFromDelta(delta: buffer?): number
	if not delta then
		-- N78 : early-out nil conserve — pas de table.clear inutile.
		return 0
	end
	-- N78 : hash module, table.clear avant fill. Un leftover gonflerait
	-- dirtyChunks (instrumentation, pas d'autorite GameState).
	table.clear(seenBuf)
	local count = buffer.len(delta) // 5
	local n = 0
	for i = 0, count - 1 do
		local index = buffer.readu32(delta, i * 5)
		local chunk = chunkOf(index)
		if not seenBuf[chunk] then
			seenBuf[chunk] = true
			n += 1
		end
	end
	return n
end

local function acquireSample(): Sample
	if historyCount < HISTORY_CAP then
		historyCount += 1
		historyWrite = historyCount
	else
		historyWrite = historyWrite % HISTORY_CAP + 1
	end
	local sample = history[historyWrite]
	if not sample then
		sample = {
			tick = 0,
			changedTiles = 0,
			dirtyChunks = 0,
			deltaBytes = 0,
			tickMs = 0,
		}
		history[historyWrite] = sample
	end
	TickMetrics.historyCount = historyCount
	return sample
end

function TickMetrics.record(tick: number, changedTiles: number, delta: buffer?, tickMs: number)
	local deltaBytes = if delta then buffer.len(delta) else 0
	local dirtyChunks = TickMetrics.dirtyChunksFromDelta(delta)
	-- N78 : ring 1..HISTORY_CAP, pas table.insert + table.remove(1) O(n).
	-- Reecrit les champs du record recycle. Totaux inchanges.
	local sample = acquireSample()
	sample.tick = tick
	sample.changedTiles = changedTiles
	sample.dirtyChunks = dirtyChunks
	sample.deltaBytes = deltaBytes
	sample.tickMs = tickMs

	totals.ticks += 1
	totals.changedTiles += changedTiles
	totals.dirtyChunks += dirtyChunks
	totals.deltaBytes += deltaBytes
	totals.tickMs += tickMs
	totals.maxChanged = math.max(totals.maxChanged, changedTiles)
	totals.maxDeltaBytes = math.max(totals.maxDeltaBytes, deltaBytes)
	totals.maxTickMs = math.max(totals.maxTickMs, tickMs)
end

local function percentile(values: { number }, p: number): number
	if #values == 0 then
		return 0
	end
	table.sort(values)
	local rank = math.clamp(math.ceil(#values * p), 1, #values)
	return values[rank]
end

local function truncateMetric(buf: { number }, n: number)
	for i = n + 1, #buf do
		buf[i] = nil
	end
end

function TickMetrics.snapshot()
	-- N79 : 4 arrays module. N80 contrat B : iterer 1..historyCount, pas
	-- #history (les Sample restent apres reset). Truncate leftover avant
	-- percentile — un [601] fantome fausserait p95. N81 : snapBuf +
	-- p95Buf / p99Buf, pas une table neuve.
	local n = historyCount
	for i = 1, n do
		local sample = history[i]
		changedBuf[i] = sample.changedTiles
		bytesBuf[i] = sample.deltaBytes
		msBuf[i] = sample.tickMs
		chunksBuf[i] = sample.dirtyChunks
	end
	truncateMetric(changedBuf, n)
	truncateMetric(bytesBuf, n)
	truncateMetric(msBuf, n)
	truncateMetric(chunksBuf, n)

	snapBuf.samples = n
	p95Buf.changedTiles = percentile(changedBuf, 0.95)
	p95Buf.deltaBytes = percentile(bytesBuf, 0.95)
	p95Buf.tickMs = percentile(msBuf, 0.95)
	p95Buf.dirtyChunks = percentile(chunksBuf, 0.95)
	p99Buf.changedTiles = percentile(changedBuf, 0.99)
	p99Buf.deltaBytes = percentile(bytesBuf, 0.99)
	p99Buf.tickMs = percentile(msBuf, 0.99)
	p99Buf.dirtyChunks = percentile(chunksBuf, 0.99)
	return snapBuf
end

function TickMetrics.reset()
	-- N80 contrat B : ne pas table.clear(history) — le pool Sample reste.
	-- historyCount = 0 pour que snapshot / formatReport ignorent les
	-- leftovers d'un match mort (sinon p95 du match precedent).
	historyCount = 0
	historyWrite = 0
	TickMetrics.historyCount = 0
	totals.ticks = 0
	totals.changedTiles = 0
	totals.dirtyChunks = 0
	totals.deltaBytes = 0
	totals.tickMs = 0
	totals.maxChanged = 0
	totals.maxDeltaBytes = 0
	totals.maxTickMs = 0
end

function TickMetrics.formatReport(): string
	local snap = TickMetrics.snapshot()
	local t = snap.totals
	local avgChanged = if t.ticks > 0 then t.changedTiles / t.ticks else 0
	local avgBytes = if t.ticks > 0 then t.deltaBytes / t.ticks else 0
	local avgMs = if t.ticks > 0 then t.tickMs / t.ticks else 0
	return string.format(
		"ticks=%d avgChanged=%.1f p95Changed=%.0f maxChanged=%d avgDeltaB=%.0f p95DeltaB=%.0f avgTickMs=%.2f p95TickMs=%.2f p95DirtyChunks=%.0f",
		t.ticks,
		avgChanged,
		snap.p95.changedTiles,
		t.maxChanged,
		avgBytes,
		snap.p95.deltaBytes,
		avgMs,
		snap.p95.tickMs,
		snap.p95.dirtyChunks
	)
end

-- Banc N78 : rawequal seenBuf / Sample recycle. Pas replique.
-- Banc N79 : rawequal des 4 arrays. Banc N80 : historyCount / Sample pool.
-- Banc N81 : rawequal snapBuf / p95Buf / p99Buf.
TickMetrics.HISTORY_CAP = HISTORY_CAP
TickMetrics.history = history
TickMetrics.historyCount = historyCount
TickMetrics.seenBuf = seenBuf
TickMetrics.changedBuf = changedBuf
TickMetrics.bytesBuf = bytesBuf
TickMetrics.msBuf = msBuf
TickMetrics.chunksBuf = chunksBuf
TickMetrics.snapBuf = snapBuf
TickMetrics.p95Buf = p95Buf
TickMetrics.p99Buf = p99Buf

return TickMetrics
