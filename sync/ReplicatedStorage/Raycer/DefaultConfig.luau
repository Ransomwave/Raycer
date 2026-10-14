--!strict
--[=[
	Default tune for Raycer. A car's own config only needs the values it changes. Speeds are in studs/s, accelerations in studs/s², angles in degrees.
]=]
return table.freeze({
	MAX_SPEED = 90,
	REVERSE_SPEED = 35,
	ACCELERATION = 60,
	BRAKE_DECELERATION = 130,
	--- Slowdown with no throttle held.
	COAST_DECELERATION = 20,

	--- Front wheel angle at full lock when stopped, shrinking to HIGH_SPEED_STEER_ANGLE at MAX_SPEED.
	STEER_ANGLE = 30,
	HIGH_SPEED_STEER_ANGLE = 10,
	--- Full locks per second the steering can move.
	STEER_SPEED = 5,

	--- Max tire force, in multiples of the load on that wheel.
	GRIP = 1.8,
	--- How fast each tire cancels its sideways sliding, per second.
	SLIP_RATE = 25,

	--- Wheel travel each way from rest.
	SUSPENSION_TRAVEL = 0.4,
	SUSPENSION_FREQUENCY = 3, -- Hz
	SUSPENSION_DAMPING = 0.7, -- 1 = critically damped

	--- Seconds upside down before the car flips itself back over.
	FLIP_DELAY = 2,

	ENGINE_SOUND_ID = "rbxassetid://358130654",
	ENGINE_VOLUME = 0.35,
	--- Engine sound PlaybackSpeed when stopped and at MAX_SPEED.
	ENGINE_IDLE_PITCH = 0.17,
	ENGINE_MAX_PITCH = 1.42,
})
