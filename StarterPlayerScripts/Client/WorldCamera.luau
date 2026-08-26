--!strict
--[[
	Camera strategique.

	Deux modes, parce que le jeu demande deux choses opposees :

	  **Survol** (par defaut) — une camera libre au-dessus de la carte, qui
	  orbite autour d'un point au sol. C'est le mode de jeu : on commande un
	  empire, pas un personnage.

	  **Avatar** — la camera Roblox classique attachee au personnage, pour se
	  promener sur son propre territoire.

	Le point de mire reste accroche a la carte, a la maniere du jeu de
	reference : la moitie de l'ecran peut depasser le bord — assez pour
	centrer un coin de carte, pas assez pour se perdre dans le vide.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldSpace = require(Shared:WaitForChild("WorldSpace"))

local WorldCamera = {}
WorldCamera.__index = WorldCamera

export type WorldCamera = typeof(setmetatable({} :: any, WorldCamera))

-- Distances a l'echelle du monde : a 40 studs d'un monde trois fois plus grand,
-- la camera serait dans le sol, et a 900 elle n'en verrait qu'un tiers.
local MIN_DISTANCE = 40 * Config.WORLD_SCALE
local MAX_DISTANCE = 900 * Config.WORLD_SCALE
local MIN_PITCH = math.rad(18)
local MAX_PITCH = math.rad(82)

local PAN_SPEED = 1.6 -- studs par stud de distance et par seconde
local EDGE_MARGIN = 12 -- px : bande de bord qui declenche le defilement

--[[
	Seuil de bascule du panoramique tactile, en px.

	Un doigt pose sur l'ecran tremble toujours un peu : sans seuil, chaque tap
	(pour attaquer ou construire) deplacerait la camera de quelques pixels et le
	joueur se battrait contre sa propre cible. Sous le seuil, le geste est un
	tap ; au-dela, il devient un panoramique et on rattrape tout le deplacement
	depuis l'origine pour que le monde ne saute pas.
]]
local TOUCH_PAN_THRESHOLD = 10

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
	self.orbiting = false
	self.panning = false
	self.shake = 0
	self.fovKick = 0
	self.clock = 0

	-- Gestes tactiles. `touches` retient chaque doigt actif (cle : l'InputObject,
	-- stable pendant toute la duree du contact) ; `touchCount` est expose pour
	-- que le controleur de saisie sache qu'un geste a deux doigts est en cours
	-- et ne declenche pas l'appui long du menu radial.
	self.touches = {}
	self.touchCount = 0
	self.pinch = nil

	self.camera.CameraType = Enum.CameraType.Scriptable
	self.camera.FieldOfView = 60

	self:bindActions()
	self:bindTouch()

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
		local oldDistance = self.targetDistance
		local newDistance = math.clamp(oldDistance * (1 - input.Position.Z * 0.12), MIN_DISTANCE, MAX_DISTANCE)
		if newDistance ~= oldDistance then
			--[[
				Zoom vers le curseur, la signature CONQUEST : le
				point sous la souris reste sous la souris. Sans ca, zoomer sur
				une cible exige de reframer a chaque coup de molette — la mire
				ne bougeant jamais, c'est toujours le centre de l'ecran qui
				grossit.
			]]
			local mouse = UserInputService:GetMouseLocation()
			local ray = self.camera:ScreenPointToRay(mouse.X, mouse.Y)
			if ray.Direction.Y < -1e-3 then
				local ground = ray.Origin + ray.Direction * (-ray.Origin.Y / ray.Direction.Y)
				local blend = 1 - newDistance / oldDistance
				self.targetFocus = self:clampFocus(
					self.targetFocus + (Vector3.new(ground.X, 0, ground.Z) - self.targetFocus) * blend
				)
			end
			self.targetDistance = newDistance
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseWheel)

	--[[
		Orbite au clic droit maintenu.

		Les bornes d'inclinaison existaient depuis le debut sans aucun controle
		pour les atteindre : la camera restait figee a 58 degres. Pouvoir se
		rapprocher de l'horizon change completement la lecture du relief, qui
		n'a d'interet que vu de biais.
	]]
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or self.mode ~= "overview" then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.orbiting = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
			-- Glisser au clic du milieu : le monde suit la souris, comme un
			-- panoramique tactile. C'est le geste de deplacement libre du jeu
			-- de reference, que ni le clavier ni le bord d'ecran ne rendent
			-- aussi directement.
			self.panning = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.orbiting = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
			self.panning = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if self.mode ~= "overview" then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if self.orbiting then
			self.targetYaw += input.Delta.X * 0.006
			self.targetPitch = math.clamp(self.targetPitch - input.Delta.Y * 0.005, MIN_PITCH, MAX_PITCH)
		elseif self.panning then
			self:panByScreenDelta(Vector2.new(input.Delta.X, input.Delta.Y))
		end
	end)
end

function WorldCamera.setMode(self: WorldCamera, mode: string)
	self.mode = mode

	if mode == "overview" then
		self.camera.CameraType = Enum.CameraType.Scriptable
		self.camera.FieldOfView = 60
		self.orbiting = false
		self.panning = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	else
		-- On rend la camera a Roblox : le controle du personnage, la collision
		-- et le zoom epaule sont deja resolus, inutile de les reimplementer.
		-- CameraSubject doit etre repose explicitement : apres plusieurs minutes
		-- en Scriptable, Roblox peut conserver un sujet nul et laisser la camera
		-- au ras de la geometrie au lieu de suivre l'avatar.
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			self.camera.CameraSubject = humanoid
		end
		self.camera.CameraType = Enum.CameraType.Custom
		self.camera.FieldOfView = 70

		-- Un geste strategique en cours ne survit pas a la bascule : en vue
		-- avatar, l'ecran tactile appartient aux controles Roblox du personnage.
		self.touches = {}
		self.touchCount = 0
		self.pinch = nil
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

-- Impulsion courte utilisee par les ordres et explosions. Elle ne deplace pas
-- le point vise : le joueur garde le controle et ne perd jamais son front.
function WorldCamera.punch(self: WorldCamera, intensity: number)
	if self.mode ~= "overview" then
		return
	end
	self.shake = math.max(self.shake, math.clamp(intensity, 0, 1.5))
	self.fovKick = math.max(self.fovKick, intensity * 2.2)
end

--[[
	Le point de mire ne s'egare jamais completement : comme chez le jeu de
	reference, la moitie de l'ecran peut depasser le bord de la carte — assez
	pour centrer un coin de carte et y travailler, pas assez pour se perdre
	dans le vide. La marge depend donc du zoom : elle vaut la moitie de
	l'etendue au sol visible a la distance courante.
]]
local function clampToMap(position: Vector3, marginX: number, marginZ: number): Vector3
	local halfW = Config.WORLD_WIDTH / 2 + marginX
	local halfD = Config.WORLD_DEPTH / 2 + marginZ
	return Vector3.new(
		math.clamp(position.X, -halfW, halfW),
		0,
		math.clamp(position.Z, -halfD, halfD)
	)
end

-- Etendue au sol visible a la distance courante (largeur, hauteur).
function WorldCamera.visibleGround(self: WorldCamera): (number, number)
	local height = 2 * self.targetDistance * math.tan(math.rad(self.camera.FieldOfView) / 2)
	local viewport = self.camera.ViewportSize
	return height * (viewport.X / math.max(viewport.Y, 1)), height
end

function WorldCamera.clampFocus(self: WorldCamera, position: Vector3): Vector3
	local groundW, groundH = self:visibleGround()
	return clampToMap(position, groundW / 2, groundH / 2)
end

--=============================================================================
-- Gestes tactiles
--=============================================================================
--[[
	Sur mobile il n'y a ni clavier ni molette : tout le pilotage de la vue tient
	en trois gestes.

	  un doigt glisse    panoramique — le monde suit le doigt
	  pincement          zoom — ecarter rapproche, pincer eloigne
	  torsion a deux doigts  rotation de la carte

	Le tap reste un ordre (attaque, construction...) : il est gere par le
	controleur de saisie, pas ici. La frontiere entre les deux est le seuil
	TOUCH_PAN_THRESHOLD, plus strict que le seuil de clic cote saisie : un doigt
	qui depasse le seuil de clic annule l'ordre la-bas, et ne bouge la camera
	ici qu'une fois le panoramique franchement amorce.
]]

local function touchPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

-- Convertit un glissement ecran en deplacement du point de mire. Le monde suit
-- le doigt : glisser a droite deplace la mire a gauche.
function WorldCamera.panByScreenDelta(self: WorldCamera, delta: Vector2)
	local viewport = self.camera.ViewportSize
	-- Hauteur visible au niveau du sol, a la distance courante : c'est ce qui
	-- rend le glissement "accroche" au doigt quel que soit le zoom.
	local visibleHeight = 2 * self.targetDistance * math.tan(math.rad(self.camera.FieldOfView) / 2)
	local studsPerPixel = visibleHeight / math.max(viewport.Y, 1)
	local dx = delta.X * studsPerPixel
	local dy = delta.Y * studsPerPixel
	-- Meme repere que stepInput : "l'ecran" suit l'orientation courante.
	local sin, cos = math.sin(self.targetYaw), math.cos(self.targetYaw)
	local worldX = -cos * dx + sin * dy
	local worldZ = -sin * dx - cos * dy
	self.targetFocus = self:clampFocus(self.targetFocus + Vector3.new(worldX, 0, worldZ))
end

-- Les deux premiers doigts actifs, pour le pincement.
function WorldCamera.twoTouches(self: WorldCamera): (any, any)
	local first, second = nil, nil
	for _, touch in self.touches do
		if not first then
			first = touch
		else
			second = touch
			break
		end
	end
	return first, second
end

function WorldCamera.beginPinch(self: WorldCamera)
	local a, b = self:twoTouches()
	if not a or not b then
		return
	end
	self.pinch = {
		distance = (a.last - b.last).Magnitude,
		angle = math.atan2(b.last.Y - a.last.Y, b.last.X - a.last.X),
		mid = (a.last + b.last) / 2,
	}
end

function WorldCamera.stepPinch(self: WorldCamera)
	local a, b = self:twoTouches()
	if not a or not b then
		return
	end
	local distance = (a.last - b.last).Magnitude
	local angle = math.atan2(b.last.Y - a.last.Y, b.last.X - a.last.X)
	local mid = (a.last + b.last) / 2

	local pinch = self.pinch
	if not pinch then
		self:beginPinch()
		return
	end

	-- Zoom : le rapport des ecartements, pas leur difference — un pincement
	-- reste proportionnel a l'effort, de pres comme de loin.
	if distance > 1 and pinch.distance > 1 then
		self.targetDistance = math.clamp(
			self.targetDistance * pinch.distance / distance,
			MIN_DISTANCE,
			MAX_DISTANCE
		)
	end

	-- Torsion : le monde suit la rotation des doigts (sens inverse, puisque
	-- c'est la camera qui orbite autour de la mire).
	self.targetYaw -= angle - pinch.angle

	-- Le point milieu qui derive translate la carte comme un glissement simple.
	self:panByScreenDelta(mid - pinch.mid)

	self.pinch = { distance = distance, angle = angle, mid = mid }
end

function WorldCamera.bindTouch(self: WorldCamera)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or self.mode ~= "overview" then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local pos = touchPosition(input)
		self.touches[input] = { origin = pos, last = pos, panning = false }
		self.touchCount += 1
		if self.touchCount == 2 then
			self:beginPinch()
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local touch = self.touches[input]
		if not touch then
			return
		end
		local pos = touchPosition(input)
		local delta = pos - touch.last
		touch.last = pos

		if self.touchCount >= 2 then
			self:stepPinch()
			return
		end

		if not touch.panning then
			if (pos - touch.origin).Magnitude < TOUCH_PAN_THRESHOLD then
				return
			end
			touch.panning = true
			-- Rattrapage depuis l'origine : le franchissement du seuil ne doit
			-- pas avaler les premiers pixels du glissement.
			delta = pos - touch.origin
		end
		self:panByScreenDelta(delta)
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if self.touches[input] then
			self.touches[input] = nil
			self.touchCount -= 1
			if self.touchCount < 2 then
				self.pinch = nil
			end
		end
	end)
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

	-- Inclinaison au clavier, en complement du clic droit.
	if UserInputService:IsKeyDown(Enum.KeyCode.R) then
		self.targetPitch = math.clamp(self.targetPitch + dt * 1.1, MIN_PITCH, MAX_PITCH)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.T) then
		self.targetPitch = math.clamp(self.targetPitch - dt * 1.1, MIN_PITCH, MAX_PITCH)
	end

	if move.Magnitude > 0 then
		move = move.Unit
		-- Le deplacement suit l'orientation courante : "haut" doit signifier
		-- "vers le haut de l'ecran", pas "vers le nord de la carte".
		local sin, cos = math.sin(self.targetYaw), math.cos(self.targetYaw)
		local worldX = move.X * cos - move.Y * sin
		local worldZ = move.X * sin + move.Y * cos
		local speed = PAN_SPEED * self.targetDistance * dt
		self.targetFocus = self:clampFocus(self.targetFocus + Vector3.new(worldX, 0, worldZ) * speed)
	end
end

function WorldCamera.step(self: WorldCamera, dt: number)
	self:stepInput(dt)
	self.clock += dt

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
	self.shake = math.max(0, self.shake - dt * 2.8)
	self.fovKick += (0 - self.fovKick) * (1 - math.exp(-7 * dt))

	local rotation = CFrame.fromEulerAnglesYXZ(-self.pitch, self.yaw, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(0, 0, self.distance))
	local shake = Vector3.new(
		math.sin(self.clock * 31) * self.shake * 0.65,
		math.cos(self.clock * 37) * self.shake * 0.42,
		math.sin(self.clock * 23) * self.shake * 0.5
	)
	-- N118 : pose = translation * rotation deja calculee. Plus de lookAt
	-- deux Vector3 60 Hz. L'oeil tremble encore (shake sur la translation) ;
	-- le biais lookAt(..., focus + shake * 0.18) est abandonne (visee
	-- cosmétique, yaw/pitch portés par `rotation`). Vector3.new offset/shake
	-- restent (leftover N119 / N120). Overlay unites / camion inchanges
	-- (N117 / N116 / N115). Recette visual V66, portee pas mergee.
	local ex = self.focus.X + offset.X + shake.X
	local ey = self.focus.Y + offset.Y + shake.Y
	local ez = self.focus.Z + offset.Z + shake.Z
	self.camera.CFrame = CFrame.new(ex, ey, ez) * rotation
	local zoomRatio = math.clamp((self.distance - MIN_DISTANCE) / (MAX_DISTANCE - MIN_DISTANCE), 0, 1)
	local targetFov = 56 + zoomRatio * 7 + self.fovKick
	self.camera.FieldOfView += (targetFov - self.camera.FieldOfView) * (1 - math.exp(-8 * dt))
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
	-- `screenPos` vient de UserInputService:GetMouseLocation/InputObject.Position :
	-- ce sont des coordonnees ecran qui incluent la safe-area du CoreGui.
	-- ViewportPointToRay emploie un autre repere et decalait donc le ciblage,
	-- surtout avec IgnoreGuiInset et la barre Roblox visible.
	local ray = self.camera:ScreenPointToRay(screenPos.X, screenPos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local included = { worldRoot }
	local terrain = Workspace:FindFirstChild("Terrain")
	if terrain then
		table.insert(included, terrain)
	end
	params.FilterDescendantsInstances = included

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
