--!strict
-- Cree (serveur) ou attend (client) les RemoteEvents, pour qu'aucun des deux
-- cotes n'ait a connaitre l'arborescence exacte.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- Serveur -> client
	"MapInit", -- (seed: number, slot: number, roster: {[number]: {name, color}})
	"StateDelta", -- (ownerDelta: buffer, stats: {[number]: {troops, tiles}})
	"RosterUpdate", -- (roster)
	-- Client -> serveur
	"AttackOrder", -- (targetSlot: number)
	"SetAttackRatio", -- (ratio: number)
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
