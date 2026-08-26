--!strict
-- Cree (serveur) ou attend (client) les RemoteEvents, pour qu'aucun des deux
-- cotes n'ait a connaitre l'arborescence exacte.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- Serveur -> client
	"MapInit", -- (seed, slot, roster, capital?, profile?, mapMeta?)
	"StateDelta", -- (ownerDelta: buffer?, stats)
	"RosterUpdate", -- (roster)
	"BuildingDelta", -- ({BuildingSnapshot})
	"UnitSnapshot", -- ({BoatSnapshot}, {MissileSnapshot})
	"OwnerSnapshot", -- (owner: buffer, tick, structureHash) : resync complet
	"DiplomacyUpdate", -- (Diplomacy)
	"MatchUpdate", -- (MatchInfo)
	"ProfileUpdate", -- (Profile) : niveau, XP et bilan persistant
	"Notify", -- (text, kind)
	"IntentReject", -- (reason: string, detail: string?) : refus enumere
	"Explosion", -- (x, y, radius)
	"Sfx", -- (soundName)
	"Plunder", -- (tuile, slot du vainqueur, or) : le "+X or" de la mise a mort
	"TradeEvent", -- ("dispatch", usine, gare, slot, trajetTicks) | ("arrival", gare, slot, or)

	-- Client -> serveur
	-- Tous les ordres acceptent un clientSequence optionnel en DERNIER argument
	-- pour idempotence. Sans sequence : accepte mais non idempotent (compat).
	"AttackOrder", -- (targetTileIndex, clientSequence?)
	"RetreatOrder", -- (targetTileIndex, clientSequence?)
	"SetAttackRatio", -- (ratio, clientSequence?)
	"ChooseDoctrine", -- (doctrineId, clientSequence?)
	"BuildOrder", -- (tileIndex, buildingKind, clientSequence?)
	"UpgradeBuildingOrder", -- (tileIndex, clientSequence?)
	"BoatOrder", -- (targetTileIndex, clientSequence?)
	"NukeOrder", -- (targetTileIndex, nukeKind, clientSequence?)
	"DiplomacyOrder", -- (action: string, targetSlot: number, clientSequence?)
	"QuickChat", -- (messageId: string, targetSlot: number?, clientSequence?)
	"ResearchOrder", -- (clientSequence?)
	"JoinRequest", -- (nationId: number, modeId: string) : deploiement depuis le menu
	"RequestSnapshot", -- () : resync rate-limite si chunkVersion impossible
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
