mob_ai = {}
mob_ai.registered_drivers = {}
mob_ai.registered_mobs = {}
mob_ai.spawns = true
--returns node def
local function get_node(pos,fallback)
	
	fallback = fallback or "default:dirt"

	local node = minetest.get_node_or_nil(pos)

	if not node then
		return minetest.registered_nodes[fallback]
	end

	if minetest.registered_nodes[node.name] then
		return node
	end

	return minetest.registered_nodes[fallback]
end

local function walkable(pos)
	local node = minetest.get_node(pos)
	local walkable = minetest.registered_nodes[node.name].walkable
	return walkable
end

--Add a Driver to the list of available drivers
function mob_ai.register_driver(name,def)
	mob_ai.registered_drivers[name] = def
end

--Change Drivers to a new one and run the necessary callbacks
local function change_drivers(self,driver,inputdata)
	self.driver_funcs.stop(self,driver,inputdata)
	mob_ai.registered_drivers[driver].start(self,self.driver,inputdata)
	self.driver = driver
	self.driver_funcs = mob_ai.registered_drivers[driver]
end

--Get the object related inputs such as can_see_player
local function get_obj_inputs(self)
	local pos = self.object:get_pos()
	local objects = minetest.get_objects_inside_radius(pos,self.view_range)
	self.inputs.can_see_player = {}
	self.inputs.can_see_same_mob = {}
	self.inputs.can_see_different_mob = {}
	for _,object in pairs(objects) do
		if object ~= self.object then
			if object:is_player() and minetest.line_of_sight(pos,object:get_pos()) then
				self.inputs.can_see_player[#self.inputs.can_see_player+1] = object
			else
				local luaent = object:get_luaentity()
				if luaent then
					if luaent.name == "__builtin:item" then
						self.inputs.can_see_item = true
					elseif luaent.is_mob == true then
						if luaent.name == self.name then
							self.inputs.can_see_same_mob[#self.inputs.can_see_same_mob+1] = object
						else
							self.inputs.can_see_different_mob[#self.inputs.can_see_different_mob+1] = object
						end
					end
				end
			end
		end
	end
	if self.inputs.can_see_player[1] == nil then
		self.inputs.can_see_player = nil
		self.inputs.cant_see_player = true
	end
	if self.inputs.can_see_same_mob[1] == nil then
		self.inputs.can_see_same_mob = nil
		self.inputs.cant_see_same_mob = true
	end
	if self.inputs.can_see_different_mob[1] == nil then
		self.inputs.can_see_different_mob = nil
		self.inputs.cant_see_different_mob = true
	end
end

--Check the inputs that have been gathered and change drivers if needed
local function check_inputs(self)
	local new_driver = ""
	local inputdata = nil
	if self.script[self.driver] == nil then
		minetest.log("error", "The driver "..self.driver.." does not appear in the mob script: "..self.name)
		return
	end
	for input,driver in pairs(self.script[self.driver]) do
		if self.inputs[input] ~= nil then
			new_driver = driver
			inputdata = self.inputs[input]
			break
		end
	end
	if new_driver ~= "" then
		change_drivers(self,new_driver,inputdata)
	end
end

--Am I on the ground?
local function is_on_ground(self)
	local pos = self.object:get_pos()
	local groundray = minetest.raycast(pos, {x=pos.x,y=pos.y-0.1+self.collisionbox[2],z=pos.z}, false, false)
	local ground = groundray:next()
	if ground ~= nil and walkable(ground.under) then
		return true
	else
		return false
	end
end

--Calculate physics
local function physics(self)
	if self.do_physics then
		local pos = self.object:get_pos()
		--Apply Gravity
		self.object:set_acceleration({x = 0,y = self.fall_speed,z = 0})
		--Am I in a liquid if so i float
		if self.float and minetest.registered_nodes[get_node({x = pos.x,y = pos.y+(self.collisionbox[2]+0.5),z = pos.z}).name].groups.liquid then
			self.object:set_acceleration({x = 0,y = 5,z = 0})
		end
	end
end

--Jump
local function jump(self)
	self.object:add_velocity({x=0,y=self.jump_height*5,z=0})
end

--Feed in a position and i will find a way
local function go_to(self, pos)
	pos = vector.round(pos)
	local mypos = self.object:get_pos()
	local path = pathfinder.find_path(vector.round(mypos), pos, 0, math.max(1, self.collisionbox[5]-self.collisionbox[2]), self.fear_height, self.jump_height)
	if type(path) == "table" then
		self.path = path
		self.following_path = true
		local next = minetest.get_position_from_hash(path[1])
		self.object:set_velocity(vector.new(0,0,0))
		local vec = vector.direction(mypos, next)
		local rot = math.atan2(vec.z,vec.x)-math.pi/2
		if rot < 0 then rot = rot + math.pi*2 end
		self:set_rot(rot, 0.5)
	else
		self.delayed_inputs["path_not_found"] = true
	end
end

--Follow the path I am on
local function follow_path(self)
	local pos = self.object:get_pos()
	local next = minetest.get_position_from_hash(self.path[1])
	local arrived = vector.distance(self.object:get_pos(), next) < 0.1
	if not arrived then
		local dir = vector.direction(pos, next)
		local rot = math.atan2(dir.z, dir.x)-math.pi/2
		if rot < 0 then rot = rot + math.pi*2 end
		local diff = math.abs(self.object:get_rotation().y-rot)
		if math.abs(self.object:get_rotation().y-rot) > 1 then
			arrived = true
		elseif diff > 0.5 then
			self:set_rot(rot, 0)
		end
	end
	if arrived then
		self.object:set_pos(vector.new(next.x, pos.y, next.z))
		self.object:set_velocity(vector.new(0,0,0))
		table.remove(self.path, 1)
		local next1 = self.path[1]
		if next1 ~= nil then
			next1 = minetest.get_position_from_hash(next1)
			local vec = vector.direction(next, next1)
			local rot = math.atan2(vec.z,vec.x)-math.pi/2
			self:set_rot(rot, 0.5)
		else
			self.following_path = false
			self.inputs["path_finished"] = true
		end
	else
		if pos.y+self.collisionbox[2]+0.75 < next.y and self:is_on_ground() then
			self:jump()
		end
		self:set_velocity(self.walk_speed)
	end
end

local function on_step(self, dtime)
	--Timer for finding when animations end
	self.time_till_anim_end = self.time_till_anim_end-dtime
	if self.time_till_anim_end <= 0 then
		self.inputs.anim_end = true
		if self.driver_funcs.on_anim_end then self.driver_funcs.on_anim_end(self,self.anim) end
	end
	--Timer to help with timed movements
	if self.timer > 0 then
		self.timer = self.timer - dtime
		if self.timer < 0 then
			self.inputs.timer = true
		end
	end
	--Smooth turning
	if self.rot_delay > 0 then	
		local rot = self.object:get_rotation()
		if self.rot_delay-dtime <= 0 then
			rot = self.target_rot
		else
			for _,axis in pairs({"x","y","z"}) do
				local dif = math.abs(rot[axis]-self.target_rot[axis])
				if rot[axis] > self.target_rot[axis] then
					if dif > math.pi then
						dif = 2*math.pi - dif
						-- need to add
						rot[axis] = rot[axis] + dif/self.rot_delay*dtime
					else
						-- need to subtract
						rot[axis] = rot[axis] - dif/self.rot_delay*dtime
					end
				elseif rot[axis] < self.target_rot[axis] then
					if dif > math.pi then
						dif = 2*math.pi - dif
						-- need to subtract
						rot[axis] = rot[axis] - dif/self.rot_delay*dtime
					else
						-- need to add
						rot[axis] = rot[axis] + dif/self.rot_delay*dtime
					end		
				end
				if rot[axis] > (math.pi*2) then rot[axis] = rot[axis]-(math.pi*2) end
				if rot[axis] < 0 then rot[axis] = rot[axis]+(math.pi*2) end
			end
		end
		self.rot_delay = self.rot_delay-dtime
		self.object:set_rotation(rot)
	end
	
	--If I am following a path continue
	if self.following_path and self.rot_delay <= 0 then
		follow_path(self)
	end
	
	--Do driver
	self.driver_funcs.step(self,dtime)
	--Check inputs
	get_obj_inputs(self)	
	check_inputs(self)
	--Calculate Physics
	physics(self)
	--Clear Inputs
	self.inputs = self.delayed_inputs
	self.delayed_inputs = {}
	
end

--When I get rightclicked, Tell my driver.
local function on_rightclick(self,clicker)
	self.inputs.rightclick = true
	if self.driver_funcs.on_rightclick then self.driver_funcs.on_rightclick(self,clicker) end
end

--Ouch called when I get punched
local function on_punch(self,puncher,time_from_last_punch,tool_capabilities,dir)
	self.inputs.punch = true
	if self.driver_funcs.on_punch then self.driver_funcs.on_punch(self,puncher,time_from_last_punch,tool_capabilities,dir) end
end

--Save
local function get_staticdata(self)
	local tmp = {}
	for var,val in ipairs(self) do
		local t = type(val)
		if  t ~= 'function'
		and t ~= 'nil'
		and t ~= 'userdata'
		and var ~= "driver" then
			tmp[var] = self[val]
		end
	end
	return minetest.serialize(tmp)
end

--Load
local function on_activate(self,staticdata,dtimes)
	local tmp = minetest.deserialize(staticdata)
	if tmp then
		for var,val in pairs(tmp) do
			self[var] = val
		end
	end
	self.object:set_armor_groups({fleshy = 100})
	self.object:set_hp(self.hp)
	self.driver_funcs = mob_ai.registered_drivers[self.driver]
	self.driver_funcs.start(self,"startup",nil)
end

--Umm I am now dead what do I do?
local function on_die(self,killer)
	if self.on_die then self.on_die(self,killer) end
	local pos = self.object:get_pos()
	self.drops = self.drops or {}
	for n = 1, #self.drops do
		if math.random(1,100) <= self.drops[n].chance then
			local obj = minetest.add_item(pos,
				ItemStack(self.drops[n].name .. " "
					.. math.random(self.drops[n].min, self.drops[n].max)))
			if obj then
				obj:setvelocity({
					x = math.random(-10, 10) / 9,
					y = 6,
					z = math.random(-10, 10) / 9,
				})
			end
		end
	end
end

--Helper function to set my rotation.
local function set_rot(self,rot,delay)
	if type(rot) == "number" then
		rot = vector.new(0, rot, 0)
	end
	if type(rot) ~= "table" then
		minetest.log("error", "Attempt to set rotation with a rot that is neither a number nor a table.")
		return
	end
	if vector.distance(rot, self.object:get_rotation()) < 0.1 then
		delay = 0
	end
	for axis,value in pairs(rot) do
		if value > math.pi*2 then value = value-(math.pi*2) end
		if value < 0 then value = value+(math.pi*2) end
		rot[axis] = value
	end
	if delay == 0 then
		self.object:set_rotation(rot)
	end
	self.target_rot = rot
	self.rot_delay = delay
end

--Helper function to set my velocity
local function set_velocity(self,velocity,use_target_rot)
	local cv = self.object:get_velocity()
	if type(velocity) == "number" then
		local rot = {}
		if use_target_rot then
			rot = self.target_rot
		else
			rot = self.object:get_rotation()
		end
		local y
		if rot.x == 0 then
			y = cv.y
		else
			y = velocity * math.sin(rot.x)
		end
		self.object:set_velocity({
			x = -velocity * math.cos(rot.x) * math.sin(rot.y),
			y = y,
			z = velocity * math.cos(rot.x) * math.cos(rot.y),
		})
		self.velocity = velocity
	elseif type(velocity) == "table" then
		velocity = {
			x = velocity.x or cv.x,
			y = velocity.y or cv.y,
			z = velocity.z or cv.z,
		}
		self.object:set_velocity(velocity)
		self.velocity = math.sqrt(velocity.x^2+velocity.y^2+velocity.z^2)
	else
		return false
	end
	return true
end

--Returns my instantaneous velocity
local function get_velocity(self)
	local vel = self.object:get_velocity()
	return math.sqrt(vel.x^2+vel.y^2+vel.z^2)
end

--Helper function to set my animation
local function set_animation(self,animation)
	local anim_data = self.animations[animation]
	local frame_range = {}
	if anim_data.start ~= nil then
		frame_range = {x = anim_data.start, y = anim_data.stop}
	elseif type(anim_data[1]) == "table" then
		local rand = math.random(1,#frame_range)
		frame_range = {x = anim_data[rand].start, y = anim_data[rand].stop}
	else
		return false
	end
	local frame_speed = anim_data.speed or 15 
	local frame_loop = anim_data.loop or true
	self.object:set_animation(frame_range, frame_speed, 0, frame_loop)
	self.time_till_anim_end = (frame_range.y-frame_range.x)/frame_speed
	self.anim = animation
	return true
end

function mob_ai.register_mob(name,def)
	local definition = {
		--Builtin Entity definitions
		hp                     = def.hp or 10,
		physical               = def.physical or true,
		collisionbox           = def.collisionbox or {-0.5, 0.0, -0.5, 0.5, 1.0, 0.5},
		selectionbox           = def.selectionbox or {-0.5, 0.0, -0.5, 0.5, 1.0, 0.5},
		visual                 = def.visual or "mesh",
		mesh                   = def.mesh or "",
		visual_size            = def.visual_size or {x = 1,y = 1},
		textures               = def.textures or {},
		colors                 = def.colors or {},
		spritediv              = def.spritediv or {x = 1, y = 1},
		initial_sprite_basepos = def.initial_sprite_basepos or {x = 0, y = 0},
		is_visible             = def.is_visible or true,
		makes_footstep_sound   = def.makes_footstep_sound or true,
		stepheight             = def.stepheight or 0.5,
		backface_culling       = def.backface_culling or true,
		infotext               = def.infotext or "",
		
		--Mob type definition vars
		drops                  = def.drops or {},
		animations             = def.animations,
		driver                 = def.driver,
		view_range             = def.view_range or 20,
		reach                  = def.reach or 5,
		script                 = def.script,
		on_die                 = def.on_die,
		damage                 = def.damage or 3,
		
		--Physics vars
 		do_physics             = def.do_physics or true,
		float                  = def.float or true,
		jump                   = def.jump or true,
		jump_height            = def.jump_height or 1,
		fall_speed             = def.fall_speed or -10,
		walk_speed             = def.walk_speed or 2,
		fear_height            = def.fear_height or 4,
		
		--Functions
		on_step                = on_step,
		on_death               = on_die,
		on_rightclick          = on_rightclick,
		on_punch               = on_punch,
		on_activate            = on_activate,
		get_staticdata         = get_staticdata,

		--mob vars
		inputs                 = {},
		delayed_inputs         = {},
		is_mob                 = true,
		rot_delay                  = 0,
		target_rot             = {yaw = 0, pitch = 0, roll = 0},
		time_till_anim_end     = 0,
		timer                  = 0,
		target                 = nil,
		velocity               = 0,
		anim                   = "",
		path                   = {},
		following_path         = false,

		--helper functions
		set_rot                = set_rot,
		set_velocity           = set_velocity,
		set_animation          = set_animation,
		get_velocity           = get_velocity,
		go_to                  = go_to,
		is_on_ground           = is_on_ground,
		jump                   = jump,
	}
	--Add driver specific variables
	for driver,_ in pairs(definition.script) do
		if mob_ai.registered_drivers[driver].custom_vars ~= nil then
			for var,init_val in pairs(mob_ai.registered_drivers[driver].custom_vars) do
				definition[var] = def[var] or init_val
			end		
		end
	end
	mob_ai.registered_mobs[name] = definition
	minetest.register_entity(name,definition)
end
