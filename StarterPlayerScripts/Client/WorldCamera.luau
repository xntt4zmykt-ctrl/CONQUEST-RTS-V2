--!strict
--[[
	Camera strategique.

	Deux modes, parce que le jeu demande deux choses opposees :

	  **Survol** (par defaut) — une camera libre au-dessus de la carte, qui
	  orbite autour d'un point au sol. C'est le mode de jeu : on commande un
	  empire, pas un personnage.

	  **Avatar** — la camera Roblox classique attachee au personnage, pour se
	  promener sur son propre territoire.

	Le point de mire est contraint aux limites de la carte : sans cette borne,
	deux coups de molette suffisent a se perdre dans le vide et a ne plus
	retrouver le monde.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))

local WorldCamera = {}
WorldCamera.__index = WorldCamera

export type WorldCamera = typeof(setmetatable({} :: any, WorldCamera))

local MIN_DISTANCE = 40
local MAX_DISTANCE = 900
local MIN_PITCH = math.rad(18)
local MAX_PITCH = math.rad(82)

local PAN_SPEED = 1.6 -- studs par stud de distance et par seconde
local EDGE_MARGIN = 12 -- px : bande de bord qui declenche le defilement

function WorldCamera.new(): WorldCamera
	local self = setmetatable({}, WorldCamera) :: any

	self.camera = Workspace.CurrentCamera
	self.focus = Vector3.zero
	self.targetFocus = Vector3.zero
	self.distance = 320
	self.targetDistance = 320
	self.yaw = 0
	self.targetYaw = 0
	self.pitch = math.rad(58)
	self.targetPitch = math.rad(58)
	self.mode = "overview"
	self.edgePan = false

	self.camera.CameraType = Enum.CameraType.Scriptable
	self.camera.FieldOfView = 60

	self:bindActions()

	return self
end

--=============================================================================
-- Entrees
--=============================================================================

function WorldCamera.bindActions(self: WorldCamera)
	-- Le zoom passe par ContextActionService plutot que par un branchement
	-- direct : cela laisse l'interface consommer la molette quand le curseur
	-- survole un panneau.
	ContextActionService:BindAction("ConquestZoom", function(_, state, input)
		if state ~= Enum.UserInputState.Change or self.mode ~= "overview" then
			return Enum.ContextActionResult.Pass
		end
		self.targetDistance = math.clamp(
			self.targetDistance * (1 - input.Position.Z * 0.12),
			MIN_DISTANCE,
			MAX_DISTANCE
		)
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseWheel)
end

function WorldCamera.setMode(self: WorldCamera, mode: string)
	self.mode = mode

	if mode == "overview" then
		self.camera.CameraType = Enum.CameraType.Scriptable
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	else
		-- On rend la camera a Roblox : le controle du personnage, la collision
		-- et le zoom epaule sont deja resolus, inutile de les reimplementer.
		self.camera.CameraType = Enum.CameraType.Custom
	end
end

function WorldCamera.toggleMode(self: WorldCamera)
	self:setMode(if self.mode == "overview" then "avatar" else "overview")
end

--=============================================================================
-- Deplacement
--=============================================================================

-- Recentre la vue sur une tuile.
function WorldCamera.focusTile(self: WorldCamera, index: number, instant: boolean?)
	local position = WorldSpace.indexToWorld(index)
	self.targetFocus = Vector3.new(position.X, 0, position.Z)
	if instant then
		self.focus = self.targetFocus
	end
end

function WorldCamera.setDistance(self: WorldCamera, distance: number, instant: boolean?)
	self.targetDistance = math.clamp(distance, MIN_DISTANCE, MAX_DISTANCE)
	if instant then
		self.distance = self.targetDistance
	end
end

-- Le point de mire ne quitte jamais la carte, avec une marge de tolerance.
local function clampToMap(position: Vector3): Vector3
	local halfW = Config.WORLD_WIDTH / 2 + 60
	local halfD = Config.WORLD_DEPTH / 2 + 60
	return Vector3.new(
		math.clamp(position.X, -halfW, halfW),
		0,
		math.clamp(position.Z, -halfD, halfD)
	)
end

--[[
	Deplacement au clavier et par les bords de l'ecran.

	La vitesse est proportionnelle a la distance : dezoome, on survole vite ;
	zoome sur un front, on ajuste finement. Une vitesse fixe rend l'un des deux
	niveaux de zoom inutilisable.
]]
function WorldCamera.stepInput(self: WorldCamera, dt: number)
	if self.mode ~= "overview" then
		return
	end

	local move = Vector2.zero

	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		move += Vector2.new(0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		move += Vector2.new(0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		move += Vector2.new(-1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		move += Vector2.new(1, 0)
	end

	if self.edgePan then
		local mouse = UserInputService:GetMouseLocation()
		local size = self.camera.ViewportSize
		if mouse.X <= EDGE_MARGIN then
			move += Vector2.new(-1, 0)
		elseif mouse.X >= size.X - EDGE_MARGIN then
			move += Vector2.new(1, 0)
		end
		if mouse.Y <= EDGE_MARGIN then
			move += Vector2.new(0, -1)
		elseif mouse.Y >= size.Y - EDGE_MARGIN then
			move += Vector2.new(0, 1)
		end
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		self.targetYaw -= dt * 1.6
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then
		self.targetYaw += dt * 1.6
	end

	if move.Magnitude > 0 then
		move = move.Unit
		-- Le deplacement suit l'orientation courante : "haut" doit signifier
		-- "vers le haut de l'ecran", pas "vers le nord de la carte".
		local sin, cos = math.sin(self.targetYaw), math.cos(self.targetYaw)
		local worldX = move.X * cos - move.Y * sin
		local worldZ = move.X * sin + move.Y * cos
		local speed = PAN_SPEED * self.targetDistance * dt
		self.targetFocus = clampToMap(self.targetFocus + Vector3.new(worldX, 0, worldZ) * speed)
	end
end

function WorldCamera.step(self: WorldCamera, dt: number)
	self:stepInput(dt)

	if self.mode ~= "overview" then
		return
	end

	-- Lissage exponentiel encadre : reste correct quel que soit le framerate,
	-- contrairement a un simple `dt * k` qui devient instable sous 30 FPS.
	local alpha = 1 - math.exp(-12 * dt)
	self.focus += (self.targetFocus - self.focus) * alpha
	self.distance += (self.targetDistance - self.distance) * alpha
	self.yaw += (self.targetYaw - self.yaw) * alpha
	self.pitch += (self.targetPitch - self.pitch) * alpha

	local rotation = CFrame.fromEulerAnglesYXZ(-self.pitch, self.yaw, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(0, 0, self.distance))
	self.camera.CFrame = CFrame.lookAt(self.focus + offset, self.focus)
end

--=============================================================================
-- Selection
--=============================================================================

--[[
	Tuile sous une position ecran, par lancer de rayon dans le monde.

	On vise le dossier du monde uniquement : sans ce filtre, le rayon accroche
	l'avatar du joueur des qu'il passe devant la camera, et le clic tombe sur sa
	propre tuile au lieu de la cible visee.
]]
function WorldCamera.tileAtScreen(self: WorldCamera, screenPos: Vector2, worldRoot: Instance): number?
	local ray = self.camera:ViewportPointToRay(screenPos.X, screenPos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { worldRoot }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	if not result then
		return nil
	end

	return WorldSpace.worldToIndex(result.Position)
end

function WorldCamera.destroy(self: WorldCamera)
	ContextActionService:UnbindAction("ConquestZoom")
	self.camera.CameraType = Enum.CameraType.Custom
end

return WorldCamera
