--!strict
--[=[
	Lightweight arcade car physics. Each car is one rigid body held up by a raycast spring per
	wheel, with tire forces computed in code and applied through a VectorForce and a Torque.
	Wheels are visual only.

	Cars use the A-Chassis model layout: a `DriveSeat` VehicleSeat, a `Wheels` folder holding
	`FL`, `FR`, `RL` and `RR`, and an optional `Body` folder. Input comes from the VehicleSeat's
	ThrottleFloat and SteerFloat, which Roblox's default controls fill for keyboard, gamepad and touch.

	Each car's tune comes from the ModuleScript its `Config` ObjectValue points to, layered over
	DefaultConfig, so a tune only needs the values it changes.
	@class Raycer
]=]
local Raycer = {}
Raycer.__index = Raycer

const CollectionService = game:GetService("CollectionService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const DefaultConfig = require(script.DefaultConfig)

export type Config = typeof(DefaultConfig)

const CAR_TAG = "Raycer"
const WHEEL_NAMES = { "FL", "FR", "RL", "RR" }

export type Raycer = typeof(setmetatable({} :: { car: Model, _connections: { RBXScriptConnection } }, Raycer))

type Wheel = {
	part: BasePart,
	motor: Motor6D,
	rest: Vector3, -- Wheel centre at rest, in seat space
	radius: number,
	isFront: boolean,
	localUp: Vector3, -- Car up and right in the wheel's own space, for Motor6D.Transform
	localAxle: Vector3,
	spin: number,
}

type Vehicle = {
	car: Model,
	seat: VehicleSeat,
	frame: CFrame, -- Level car frame in seat space, built from the wheel layout
	config: Config,
	wheels: { Wheel },
	steer: number,
	flipTime: number,
	engineSound: Sound,
	attachment: Attachment?,
	force: VectorForce?,
	torque: Torque?,
}

--- Builds a level frame in the space of the given points, centred between the wheels.
local function frameFromWheels(points: { [string]: Vector3 }): CFrame
	local right = ((points.FR - points.FL) + (points.RR - points.RL)).Unit
	local forward = ((points.FL + points.FR) - (points.RL + points.RR)).Unit
	local up = right:Cross(forward).Unit
	local center = (points.FL + points.FR + points.RL + points.RR) / 4
	return CFrame.fromMatrix(center, forward:Cross(up).Unit, up)
end

--- Reads the tune from the car's `Config` ObjectValue, filling unset values from the default.
local function loadConfig(car: Model): Config
	const configValue = car:FindFirstChild("Config")
	const module = if configValue and configValue:IsA("ObjectValue") then configValue.Value else nil
	if not module or not module:IsA("ModuleScript") or module == script.DefaultConfig then
		return DefaultConfig
	end

	const success, overrides = pcall(require, module)
	if not success or typeof(overrides) ~= "table" then
		warn(`[Raycer] Config "{module:GetFullName()}" failed to load, using the default: {overrides}`)
		return DefaultConfig
	end

	const config = table.clone(DefaultConfig)
	for key, value in overrides do
		if DefaultConfig[key] == nil then
			warn(`[Raycer] Unknown config key "{key}" in "{module:GetFullName()}"`)
		end
		config[key] = value
	end
	return table.freeze(config)
end

local function getWheelPart(car: Model, name: string): BasePart
	return (car:WaitForChild("Wheels") :: Instance):WaitForChild(name) :: BasePart
end

--[=[
	Wraps a car model. Call `Init` on the server to build it.
	@param car The car model.
	@param config Tune to use instead of the one the car's `Config` ObjectValue points to.
]=]
function Raycer.new(car: Model, config: ModuleScript?): Raycer
	if config then
		local configValue = car:FindFirstChild("Config") or Instance.new("ObjectValue")
		assert(configValue:IsA("ObjectValue"), `"{car:GetFullName()}.Config" must be an ObjectValue`)
		configValue.Name = "Config"
		configValue.Value = config
		configValue.Parent = car
	end
	return setmetatable({ car = car, _connections = {} }, Raycer)
end

--[=[
	Welds the car into one rigid body, adds its collision hull, and hands physics to the driver.
	Server only.
]=]
function Raycer:Init()
	const car = self.car
	const seat = car:WaitForChild("DriveSeat") :: VehicleSeat

	const points: { [string]: Vector3 } = {}
	for _, name in WHEEL_NAMES do
		points[name] = getWheelPart(car, name).Position
	end
	const frame = frameFromWheels(points)
	const radius = getWheelPart(car, "FL").Size.Y / 2

	-- Collision hull from the body's footprint, raised off the ground so only the springs touch it
	local minCorner, maxCorner = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in (car:FindFirstChild("Body") or car):GetDescendants() do
		if not part:IsA("BasePart") then continue end
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local corner = frame:PointToObjectSpace(part.CFrame * (part.Size / 2 * Vector3.new(x, y, z)))
					minCorner, maxCorner = minCorner:Min(corner), maxCorner:Max(corner)
				end
			end
		end
	end
	const hull = Instance.new("Part")
	hull.Name = "#Hull"
	hull.Transparency = 1
	hull.Size = Vector3.new(maxCorner.X - minCorner.X, radius * 1.2, maxCorner.Z - minCorner.Z)
	hull.CFrame = frame * CFrame.new((minCorner.X + maxCorner.X) / 2, 0, (minCorner.Z + maxCorner.Z) / 2)
	hull.CustomPhysicalProperties = PhysicalProperties.new(2, 0, 0.2, 100, 1)
	hull.Parent = car:FindFirstChild("Body") or car

	for _, part in car:GetDescendants() do
		if not part:IsA("BasePart") or part == seat then continue end

		part.Massless = part ~= hull
		if part.Parent and part.Parent.Name == "Wheels" then
			part.CanCollide = false
			local motor = Instance.new("Motor6D")
			motor.Name = "Suspension"
			motor.Part0 = seat
			motor.Part1 = part
			motor.C0 = seat.CFrame:ToObjectSpace(part.CFrame)
			motor.Parent = part
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = seat
			weld.Part1 = part
			weld.Parent = part
		end
	end
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then part.Anchored = false end
	end

	table.insert(
		self._connections,
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = seat.Occupant
			local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
			if seat:CanSetNetworkOwnership() then seat:SetNetworkOwner(player) end
		end)
	)

	car:AddTag(CAR_TAG)
end

--- Disconnects the server-side listeners.
function Raycer:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

local function buildVehicle(car: Model): Vehicle?
	const seat = car:WaitForChild("DriveSeat", 10) :: VehicleSeat?
	if not seat then return nil end

	const wheels: { Wheel } = {}
	const points: { [string]: Vector3 } = {}
	for _, name in WHEEL_NAMES do
		local part = getWheelPart(car, name)
		local motor = part:WaitForChild("Suspension") :: Motor6D
		points[name] = motor.C0.Position
		table.insert(wheels, {
			part = part,
			motor = motor,
			rest = motor.C0.Position,
			radius = part.Size.Y / 2,
			isFront = name:sub(1, 1) == "F",
			localUp = Vector3.zero,
			localAxle = Vector3.zero,
			spin = 0,
		})
	end

	const frame = frameFromWheels(points)
	for _, wheel in wheels do
		wheel.localUp = wheel.motor.C0.Rotation:VectorToObjectSpace(frame.UpVector)
		wheel.localAxle = wheel.motor.C0.Rotation:VectorToObjectSpace(frame.RightVector)
	end

	const config = loadConfig(car)
	const engineSound = Instance.new("Sound")
	engineSound.Name = "Engine"
	engineSound.SoundId = config.ENGINE_SOUND_ID
	engineSound.Volume = config.ENGINE_VOLUME
	engineSound.Looped = true
	engineSound.RollOffMode = Enum.RollOffMode.Inverse
	engineSound.RollOffMinDistance = 10
	engineSound.RollOffMaxDistance = 10000
	engineSound.Parent = seat

	return {
		car = car,
		seat = seat,
		frame = frame,
		config = config,
		wheels = wheels,
		steer = 0,
		flipTime = 0,
		engineSound = engineSound,
	}
end

local function setDriving(vehicle: Vehicle, driving: boolean)
	if driving == (vehicle.attachment ~= nil) then return end

	if vehicle.attachment then
		vehicle.attachment:Destroy()
		vehicle.attachment, vehicle.force, vehicle.torque = nil, nil, nil
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "RaycerForces"
	local force = Instance.new("VectorForce")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = attachment
	local torque = Instance.new("Torque")
	torque.Attachment0 = attachment
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Torque = Vector3.zero
	torque.Parent = attachment
	attachment.Parent = vehicle.seat
	vehicle.attachment, vehicle.force, vehicle.torque = attachment, force, torque
end

--- Target forward acceleration for the throttle input at the current forward speed.
local function getDriveAcceleration(config: Config, throttle: number, speed: number, dt: number): number
	if throttle > 0 then
		if speed < -1 then return config.BRAKE_DECELERATION * throttle end
		return config.ACCELERATION * throttle * math.clamp((config.MAX_SPEED - speed) / (config.MAX_SPEED * 0.15), 0, 1)
	elseif throttle < 0 then
		if speed > 1 then return config.BRAKE_DECELERATION * throttle end
		return config.ACCELERATION
			* throttle
			* math.clamp((config.REVERSE_SPEED + speed) / (config.REVERSE_SPEED * 0.15), 0, 1)
	end
	return -math.sign(speed) * math.min(config.COAST_DECELERATION, math.abs(speed) / dt)
end

local function flipUpright(vehicle: Vehicle)
	const seat = vehicle.seat
	const look = (seat.CFrame * vehicle.frame).LookVector * Vector3.new(1, 0, 1)
	const flatLook = if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis
	const target = CFrame.lookAt(seat.Position, seat.Position + flatLook) + Vector3.yAxis * 3
	vehicle.car:PivotTo((target * vehicle.frame:Inverse()) * seat.CFrame:ToObjectSpace(vehicle.car:GetPivot()))
	seat.AssemblyLinearVelocity = Vector3.zero
	seat.AssemblyAngularVelocity = Vector3.zero
end

local function stepVehicle(vehicle: Vehicle, dt: number, rayParams: RaycastParams, driving: boolean)
	const seat = vehicle.seat
	const config = vehicle.config
	const frame = seat.CFrame * vehicle.frame
	const up = frame.UpVector
	const velocity = seat.AssemblyLinearVelocity
	const speed = frame.LookVector:Dot(velocity)
	const mass = seat.AssemblyMass
	const wheelMass = mass / #vehicle.wheels
	const centerOfMass = seat.AssemblyCenterOfMass

	-- Default controls normalise the input diagonal (W+D gives 0.7 each), so stretch it back to a square
	local throttle, steerInput = seat.ThrottleFloat, seat.SteerFloat
	const inputMax = math.max(math.abs(throttle), math.abs(steerInput))
	if inputMax > 0 then
		const scale = math.min(math.sqrt(throttle ^ 2 + steerInput ^ 2), 1) / inputMax
		throttle *= scale
		steerInput *= scale
	end

	const steerStep = config.STEER_SPEED * dt
	vehicle.steer += math.clamp(steerInput - vehicle.steer, -steerStep, steerStep)
	const speedFraction = math.min(math.abs(speed) / config.MAX_SPEED, 1)
	const steerAngle = -vehicle.steer
		* math.rad(config.STEER_ANGLE + (config.HIGH_SPEED_STEER_ANGLE - config.STEER_ANGLE) * speedFraction)

	const stiffness = wheelMass * (2 * math.pi * config.SUSPENSION_FREQUENCY) ^ 2
	const damping = 2 * config.SUSPENSION_DAMPING * math.sqrt(stiffness * wheelMass)
	const travel = config.SUSPENSION_TRAVEL
	const slipRate = math.min(config.SLIP_RATE, 0.5 / dt) -- One frame never pushes past zero slip

	rayParams.FilterDescendantsInstances = { vehicle.car }
	const hits: { [Wheel]: RaycastResult } = {}
	local groundedCount = 0
	for _, wheel in vehicle.wheels do
		local origin = seat.CFrame * wheel.rest + up * travel
		local hit = workspace:Raycast(origin, -up * (travel * 2 + wheel.radius), rayParams)
		if hit then
			hits[wheel] = hit
			groundedCount += 1
		end
	end

	const driveForce = if driving and groundedCount > 0
		then mass * getDriveAcceleration(config, throttle, speed, dt) / groundedCount
		else 0
	local totalForce, totalTorque = Vector3.zero, Vector3.zero

	for _, wheel in vehicle.wheels do
		local hit = hits[wheel]
		local wheelSteer = if wheel.isFront then steerAngle else 0
		local offset = -travel

		if hit then
			offset = travel - (hit.Distance - wheel.radius)
			-- Springs push along the ground normal, so a pitched chassis can't push itself forward
			local normal = hit.Normal
			local pointVelocity = seat:GetVelocityAtPosition(hit.Position)
			local load =
				math.max(wheelMass * workspace.Gravity + stiffness * offset - damping * normal:Dot(pointVelocity), 0)

			local forward = CFrame.fromAxisAngle(up, wheelSteer):VectorToWorldSpace(frame.LookVector)
			forward = (forward - normal * forward:Dot(normal)).Unit
			local right = forward:Cross(normal)

			local tire = right * (-right:Dot(pointVelocity) * wheelMass * slipRate) + forward * driveForce
			local maxTire = config.GRIP * load
			if tire.Magnitude > maxTire then tire = tire.Unit * maxTire end

			-- Tire forces act at centre-of-mass height so cornering never rolls the car over
			local tirePoint = hit.Position + up * up:Dot(centerOfMass - hit.Position)
			totalForce += normal * load + tire
			totalTorque += (hit.Position - centerOfMass):Cross(normal * load) + (tirePoint - centerOfMass):Cross(tire)
		end

		wheel.spin -= speed / wheel.radius * dt
		wheel.motor.Transform = CFrame.new(wheel.localUp * math.clamp(offset, -travel, travel))
			* CFrame.fromAxisAngle(wheel.localUp, wheelSteer)
			* CFrame.fromAxisAngle(wheel.localAxle, wheel.spin % (2 * math.pi))
	end

	vehicle.engineSound.Playing = seat.Occupant ~= nil
	vehicle.engineSound.PlaybackSpeed = config.ENGINE_IDLE_PITCH
		+ (config.ENGINE_MAX_PITCH - config.ENGINE_IDLE_PITCH) * speedFraction

	if not driving then return end

	vehicle.flipTime = if up.Y < 0.2 then vehicle.flipTime + dt else 0
	if vehicle.flipTime > config.FLIP_DELAY then
		vehicle.flipTime = 0
		flipUpright(vehicle)
	end

	const force, torque = vehicle.force, vehicle.torque
	if force and torque then
		force.Force = totalForce
		torque.Torque = totalTorque
	end
end

--[=[
	Options for `Raycer.initClient`.
	@interface ClientOptions
	@within Raycer
	.collisionGroup string? -- Collision group the cars' parts use. Suspension rays then follow that group's collision rules, e.g. skipping characters the cars drive through.
]=]
export type ClientOptions = {
	collisionGroup: string?,
}

--[=[
	Animates every car's wheels and drives the local player's car. Call once per client.
	@param options Optional settings shared by every car.
]=]
function Raycer.initClient(options: ClientOptions?)
	const vehicles: { [Instance]: Vehicle } = {}
	const rayParams = RaycastParams.new()
	rayParams.RespectCanCollide = true
	if options and options.collisionGroup then rayParams.CollisionGroup = options.collisionGroup end

	local function onCarAdded(car: Instance)
		if not car:IsA("Model") then return end
		local vehicle = buildVehicle(car)
		if vehicle and car:HasTag(CAR_TAG) then vehicles[car] = vehicle end
	end

	CollectionService:GetInstanceRemovedSignal(CAR_TAG):Connect(function(car)
		local vehicle = vehicles[car]
		if not vehicle then return end
		setDriving(vehicle, false)
		vehicle.engineSound:Destroy()
		vehicles[car] = nil
	end)
	CollectionService:GetInstanceAddedSignal(CAR_TAG):Connect(onCarAdded)
	for _, car in CollectionService:GetTagged(CAR_TAG) do
		task.spawn(onCarAdded, car)
	end

	RunService.PreSimulation:Connect(function(dt)
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		for _, vehicle in vehicles do
			local driving = humanoid ~= nil and vehicle.seat.Occupant == humanoid
			setDriving(vehicle, driving)
			stepVehicle(vehicle, dt, rayParams, driving)
		end
	end)
end

return Raycer
