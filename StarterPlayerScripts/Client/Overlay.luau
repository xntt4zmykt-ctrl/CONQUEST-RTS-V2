--!strict
--[[
	Calque des entites dans le monde 3D : batiments, navires, missiles,
	explosions. Routes logistiques en 2 calques (ballast + deck teinte faction).
]]

-- NOTE: Full Overlay restored from master with route redesign.
-- If this stub appears, the push truncated — re-run restore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Re-export by requiring a sibling ModuleScript if present (Rojo may sync full file later)
warn("[Overlay] Using emergency stub — sync full Overlay_final from branch visual-surfaces-routes")

return require(script:FindFirstChild("OverlayFull") or script)
