--!strict
-- Cree (serveur) ou attend (client) les RemoteEvents, pour qu'aucun des deux
-- cotes n'ait a connaitre l'arborescence exacte.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- Serveur -> client
	"MapInit", -- (seed, slot, roster)
	"StateDelta", -- (ownerDelta: buffer?, stats)
	"RosterUpdate", -- (roster)
	"BuildingDelta", -- ({BuildingSnapshot})
	"UnitSnapshot", -- ({BoatSnapshot}, {MissileSnapshot})
	"DiplomacyUpdate", -- (Diplomacy)
	"MatchUpdate", -- (MatchInfo)
	"ProfileUpdate", -- (Profile) : niveau, XP et bilan persistant
	"Notify", -- (text, kind)
	"Explosion", -- (x, y, radius)
	"Sfx", -- (soundName)
	"TradeEvent", -- ("dispatch", usine, gare, slot, trajetTicks) | ("arrival", gare, slot, or)

	-- Client -> serveur
	"AttackOrder", -- (targetTileIndex), le serveur derive la faction
	"RetreatOrder", -- (targetTileIndex), rappelle l'offensive contre ce proprietaire
	"SetAttackRatio", -- (ratio)
	"ChooseDoctrine", -- (doctrineId)
	"BuildOrder", -- (tileIndex, buildingKind)
	"UpgradeBuildingOrder", -- (tileIndex), actuellement reserve aux villes
	"BoatOrder", -- (targetTileIndex)
	"NukeOrder", -- (targetTileIndex, nukeKind)
	"DiplomacyOrder", -- (action: string, targetSlot: number)
	"QuickChat", -- (messageId: string, targetSlot: number?) : message rapide predefini
	"ResearchOrder", -- () : avancer d'une ere
	"JoinRequest", -- (nationId: number, modeId: string) : deploiement depuis le menu
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
