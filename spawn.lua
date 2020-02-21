function mob_ai.spawn_mob(pos, mob)
	minetest.add_entity(pos, mob)
end

local formspec = [[
	size[8,4]
	field[1,2;5,1;input;Settings:;]
]]

minetest.register_node("mob_ai:spawner", {
	description = "Mob Spawner",
	drawtype = "allface",
	use_texture_alpha = true,
	tiles = {"mob_ai_spawner.png"},
	groups = {cracky = 1},
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", formspec)
	end,
	on_receive_fields = function(pos, formname, fields, sender)
		if fields.key_enter_field == "input" then
			local meta = minetest.get_meta(pos)
			local time, mob, min, max, range = string.match(fields.input, "(%d+)%s*(%a+:%a+)%s*(%d+)%s*(%d+)%s*(%d+)")
			assert(time)
			assert(mob)
			assert(min)
			assert(max)
			assert(range)
			time = tonumber(time)
			min = tonumber(min)
			max = tonumber(max)
			range = tonumber(range)
			meta:set_string("mob", mob)
			meta:set_int("time", time)
			meta:set_int("min", min)
			meta:set_int("max", max)
			meta:set_int("range", range)
			local timer = minetest.get_node_timer(pos)
			timer:start(time)
		end
	end,
	on_timer = function(pos, elapsed)
		local meta = minetest.get_meta(pos)
		local min = meta:get_int("min")
		local max = meta:get_int("max")
		local range = meta:get_int("range")
		local mob = meta:get_string("mob")
		math.randomseed(minetest.get_us_time())
		local ammount = math.random(min, max)
		for i = 1,ammount do
			local x,y,z = math.random(-range,range), math.random(-range,range), math.random(-range,range)
			local newpos = vector.new(pos.x+x, pos.y+y, pos.z+z)
			local node = minetest.get_node(newpos)
			if not minetest.registered_nodes[node.name].walkable then
				mob_ai.spawn_mob(newpos, mob)
			end
		end
		return true
	end
})


--[[
def = {
	nodes,
	neighbors,
	interval,
	chance,
	light = {min,max}
	height = {min, max}
}
]]
function mob_ai.register_spawner(name, def)
	if not mob_ai.registered_mobs[name] then
		return
	end
	if not def.nodes then return end
	def.neighbors = def.neighbors or {}
	def.interval = def.interval or 10
	def.chance = def.chance or 20
	def.light = def.light or {min = 0, max = 15}
	def.height = def.height or {min = -31000, max = 31000}
	
	minetest.register_abm({
		label = name .. " spawning",
		nodenames = def.nodes,
		neighbors = def.neighbors,
		interval = def.interval,
		chance = def.chance,
		catch_up = false,
		action = function(pos, node, active_object_count, active_object_count_wider)
			pos.y = pos.y + 1
			local timeofday = minetest.get_timeofday()
			local light = minetest.get_node_light(pos, timeofday)
			if light < def.light.min or light > def.light.max then
				return false
			end
			if pos.y < def.height.min or pos.y > def.height.max then
				return false
			end
			local mob = mob_ai.registered_mobs[name]
			local mob_height = math.ceil(mob.collisionbox[5]-mob.collisionbox[2])
			for y = pos.y,pos.y+mob_height do
				local node = minetest.get_node({x = pos.x, y = pos.y+y, z = pos.z})
				if minetest.registered_nodes[node.name].walkable then
					return
				end
			end
			mob_ai.spawn_mob(pos, name)
		end
	})
end
