local modpath = minetest.get_modpath("mob_ai")

dofile(modpath.."/api.lua")
dofile(modpath.."/drivers.lua")
dofile(modpath.."/pathfinder.lua")

minetest.register_chatcommand("pathtest",{
	description = "generate path at players feet",
	func = function(name,param)
		local player = minetest.get_player_by_name(name)
		local pos = player:get_pos()
		local pos2 = {x=pos.x+10,y=pos.y+0,z=pos.z+10}
		local path = pathfinder.find_path(pos,pos2,{collisionbox = {0,0,0,0,2,0}},0)
		print(dump(path))
		print(dump(pos))
		print(dump(pos2))
		if path then
			for _,step in pairs(path) do
				minetest.set_node(step,{name = "default:cloud"})
			end
		end
	end
})
