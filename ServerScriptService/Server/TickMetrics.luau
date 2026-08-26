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

local history: { Sample } = {}
local HISTORY_CAP = 600 -- 60 s a 10 Hz
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
		return 0
	end
	local count = buffer.len(delta) // 5
	local seen: { [number]: boolean } = {}
	local n = 0
	for i = 0, count - 1 do
		local index = buffer.readu32(delta, i * 5)
		local chunk = chunkOf(index)
		if not seen[chunk] then
			seen[chunk] = true
			n += 1
		end
	end
	return n
end

function TickMetrics.record(tick: number, changedTiles: number, delta: buffer?, tickMs: number)
	local deltaBytes = if delta then buffer.len(delta) else 0
	local dirtyChunks = TickMetrics.dirtyChunksFromDelta(delta)
	local sample: Sample = {
		tick = tick,
		changedTiles = changedTiles,
		dirtyChunks = dirtyChunks,
		deltaBytes = deltaBytes,
		tickMs = tickMs,
	}

	table.insert(history, sample)
	if #history > HISTORY_CAP then
		table.remove(history, 1)
	end

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

function TickMetrics.snapshot()
	local changed = table.create(#history, 0)
	local bytes = table.create(#history, 0)
	local ms = table.create(#history, 0)
	local chunks = table.create(#history, 0)
	for i, sample in history do
		changed[i] = sample.changedTiles
		bytes[i] = sample.deltaBytes
		ms[i] = sample.tickMs
		chunks[i] = sample.dirtyChunks
	end

	return {
		samples = #history,
		totals = totals,
		p95 = {
			changedTiles = percentile(changed, 0.95),
			deltaBytes = percentile(bytes, 0.95),
			tickMs = percentile(ms, 0.95),
			dirtyChunks = percentile(chunks, 0.95),
		},
		p99 = {
			changedTiles = percentile(changed, 0.99),
			deltaBytes = percentile(bytes, 0.99),
			tickMs = percentile(ms, 0.99),
			dirtyChunks = percentile(chunks, 0.99),
		},
	}
end

function TickMetrics.reset()
	table.clear(history)
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

return TickMetrics
