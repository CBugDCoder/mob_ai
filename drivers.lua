-------------------------------------
--Demo Drivers NOT MEANT TO BE USED--
-------------------------------------

mob_ai.register_driver("idle",{
	start = function(self,old_driver)
		self:set_velocity(0)
		self:set_animation("idle")
	end,
	step = function(self,dtime)
		
		
	end,
	stop = function(self,new_driver)
		
	end,

})
mob_ai.register_driver("attack",{
	start = function(self,old_driver,inputdata)
		self.target = inputdata[1]
		self:set_animation("walk")
	end,
	step = function(self,dtime)
		self.attack_timer = self.attack_timer+dtime
		if self.attack_timer>1 then
			local target_pos = self.target:get_pos()
			local pos = self.object:get_pos()
			local yaw = math.atan2(-(target_pos.x-pos.x),(target_pos.z-pos.z))
			self:set_set_rotation({x=0,y=yaw,z=0},5)
			self:set_velocity(1,true)
			local diff = {x = target_pos.x-pos.x,y = target_pos.y-pos.y,z = target_pos.z-pos.z}
			local distance = diff.x^2+diff.y^2+diff.z^2
			if distance < self.reach^2 and self.anim == "walk" then
				self:set_animation("punch")
			end

		end
	end,
	stop = function(self,new_driver)
		
	end,
	on_anim_end = function(self,anim)
		if anim == "punch" then
			self.target:punch(self.object, 1.0, {
				full_punch_interval = 1.0,
				damage_groups = {fleshy = self.damage}
			}, nil)
			self:set_animation("walk")
		end
	end,
	custom_vars = {attack_timer = 0}

})
mob_ai.register_driver("roam",{
	start = function(self,old_driver)
		self.timer = 6
		self.roam_turn_timer = 1
		self:set_animation("walk")
	end,
	step = function(self,dtime)
		self:set_velocity(2,false)
		self.roam_turn_timer = self.roam_turn_timer-dtime
		if self.roam_turn_timer < 0 then
			local rot = self.object:get_rotation()
			rot.y = rot.y+math.random()-0.5
			self:set_rot(rot,8)
			self.roam_turn_timer = 1
		end

	end,
	stop = function(self,new_driver)
		
	end,
	custom_vars = {roam_turn_timer = 0}

})
