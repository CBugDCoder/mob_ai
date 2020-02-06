pathfinder = {}

--[[
minetest.get_content_id(name)
minetest.registered_nodes
minetest.get_name_from_content_id(id)
local ivm = a:index(pos.x, pos.y, pos.z)
local ivm = a:indexp(pos)
minetest.hash_node_position({x=,y=,z=})
minetest.get_position_from_hash(hash)
start_index, target_index, current_index
^ Hash of position
current_value
^ {int:hCost, int:gCost, int:fCost, hash:parent, vect:pos}
]]--



local function walkable(pos, liquids_walkable)
	local node = minetest.get_node(pos)
	if liquids_walkable then
		return minetest.registered_nodes[node.name].walkable or minetest.registered_nodes[node.name].liquidtype ~= "none"
	else
		return minetest.registered_nodes[node.name].walkable
	end
end

local function is_fence(pos)
	local node = minetest.get_node(pos)
	if string.find(node.name,"fence") == nil then
		return false
	else
		return true
	end
end

local function get_ground_neighbors(pos, fall, jump, height, liquids_walkable)
	local neighbors = {}
	fall = fall or 4
	jump = jump or 1
	--Must subtract 1 or the check will be too high
	height = height-1 or 1
	liquids_walkable = (liquids_walkable ~= false)
	for x = -1,1 do
		for z = -1,1 do
			if z ~= 0 or x ~= 0 then
				local gl
				local fits = false
				for y = -fall,jump do
					if not walkable({x = pos.x+x, y = pos.y+y, z = pos.z+z}, liquids_walkable) then
						if walkable({x = pos.x+x, y = pos.y+y-1, z = pos.z+z}, liquids_walkable) and (not is_fence({x = pos.x+x, y = pos.y+y-1, z = pos.z+z})) then
							gl = pos.y+y
							fits = true
							for y1 = 0,height do
								if walkable({x = pos.x+x, y = gl+y1, z = pos.z+z}, liquids_walkable) then
									fits = false
									break
								end
							end
							if fits then
								if z ~= 0 and x ~= 0 then
									if gl < pos.y then
										for y2 = 0,height do
											if walkable({x = pos.x, y = pos.y+y2, z = pos.z+z}, liquids_walkable) or walkable({x = pos.x+x, y = pos.y+y2, z = pos.z}, liquids_walkable) then
												fits = false
												break
											end
										end
									else
										for y2 = 0,height do
											if walkable({x = pos.x, y = gl+y2, z = pos.z+z}, liquids_walkable) or walkable({x = pos.x+x, y = gl+y2, z = pos.z}, liquids_walkable) then
												fits = false
												break
											end
										end
									end
								end
								if gl > pos.y then
									for y3 = 0,height+gl-pos.y do
										if walkable({x = pos.x, y = pos.y+y3, z = pos.z}, liquids_walkable) then
											fits = false
											break
										end
									end
								end
							end
						end
					end
					if gl and fits then
						local hash = minetest.hash_node_position({x = pos.x+x, y = gl, z = pos.z+z})
						local g_cost = 10
						if z ~= 0 and x ~= 0 then
							g_cost = g_cost + 4
						end
						if gl > pos.y then
							g_cost = g_cost + 6
						end
						neighbors[hash] = {pos = {x = pos.x+x, y = gl, z = pos.z+z}, g_cost = g_cost}
					end
				end
			end
		end
	end
	return neighbors
end

--returns the h_cost value of pos when target_pos is the goal
local function get_h_cost(pos, target_pos)
	local distance = math.sqrt((pos.x-target_pos.x)^2 + (pos.y-target_pos.y)^2 + (pos.z-target_pos.z)^2)
	return math.floor(distance*10)
end


--returns the next node to be expanded
local function get_cheapest_node(list)
	local cheapest = "blank"
	
	for hash, node in pairs(list) do
		if cheapest ~= "blank" then
			if node.f_cost < list[cheapest].f_cost then
				cheapest = hash
			elseif node.f_cost == list[cheapest].f_cost then
				if node.h_cost < list[cheapest].h_cost then
					cheapest = hash
				end
			end
		else
			cheapest = hash
		end
	end
	
	return cheapest
end

--returns a returnable path built out of position hashes
local function get_path(list, current)
	local path = {}
	
	while true do
		table.insert(path,current)
		current = list[current].parent
		if current == "Start" then
			--We have reached the start of the path so stop looking for next point
			break
		end
	end
	
	--Reverse the order of path to go from start to end not end to start
	--[[local reordered_path = {}
	for i = #path, 1, -1 do
		table.insert(reordered_path,path[i])
		print(path[i])
	end]]
	return path
end


--[[path_types (
	0 = ground only, will swim on top of liquids but will not dive.
	1 = ground only, will sink in liquids
	2 = amphibious, can swim freely in liquids
	3 = flying, cannot move straight up and down
	4 = flying, can move straight up and down
)]]--

--[[
OPEN the set of nodes to be evaluated
CLOSED the set of nodes already evaluated

add the start node to OPEN

loop
	current = node in OPEN with the lowest f_cost
	remove current from OPEN
	add current to CLOSED
	
	if current is the target node
		return path
	
	foreach neighbor of the current node
		if neighbor is not transversable or neighbor is in CLOSED
			skip to the next neighbor
		
		if new path to neighbor is shorter OR neighbor is not in OPEN
			set f_cost of neighbor
			set parent of neighbor to current
			if neighbor is not in OPEN
				add neighbor to OPEN


]]--

function pathfinder.find_path(current_pos, target_pos, path_type, height, fall, jump)
	local time = minetest.get_us_time()
	--Initialize variables
	local open = {}
	local closed = {}
	local path = {}
	local liquids_walkable = true --Will set based on path_type later
	local height = height or 2
	local fall = fall or 4
	local jump = jump or 1
	local path_type = path_type or 0
	local get_neighbors = get_ground_neighbors
	
	--Initialize open to current pos
	--if statement forces construction variables to be purged
	if true then
		local h_cost = get_h_cost(current_pos,target_pos)
		local hash = minetest.hash_node_position(current_pos)
		open[hash] = {
			pos = current_pos, 
			g_cost = 0, 
			h_cost = h_cost, 
			f_cost = h_cost,--h_cost+g_cost and since g_cost = 0 f_cost = h_cost
			parent = "Start",
		}
	end
	
	--Loop until I find a path or tun out of time
	local counter = 0
	while counter < 400 do
		--Increment counter to prevent an infinite loop
		counter = counter + 1
		--Get node to expand
		local current = get_cheapest_node(open)
		
		--Put node in closed and remove from open
		closed[current] = {
			pos = open[current].pos, 
			g_cost = open[current].g_cost, 
			h_cost = open[current].h_cost, 
			f_cost = open[current].f_cost,
			parent = open[current].parent,
		}
		open[current] = nil
		
		--Am I at the end
		if closed[current].h_cost == 0 then
			--Yes, Hooray grab the path and run.
			path = get_path(closed,current)
			break
		end
		
		--Get neighbors
		local neighbors = get_neighbors(closed[current].pos, fall, jump, height, liquids_walkable)
		--Check all my neighbors especially the Petersons
		for hash, neighbor in pairs(neighbors) do
			--Has this node already been checked?
			if closed[hash] == nil then
				--No, Okay. Has it been expanded into yet?
				if open[hash] == nil then
					--No, Okay. Add node to open set
					local g_cost = closed[current].g_cost + neighbor.g_cost
					local h_cost = get_h_cost(neighbor.pos, target_pos)
					open[hash] = {
						pos = neighbor.pos,
						g_cost = g_cost,
						h_cost = h_cost,
						f_cost = g_cost + h_cost,
						parent = current,
					}
				else
					--Yes, Okay. Is this path a better option to get to this node?
					if open[hash].g_cost > closed[current].g_cost + neighbor.g_cost then
						--Yes. Well then, by all means update it.
						open[hash].g_cost = closed[current].g_cost + neighbor.g_cost
						open[hash].f_cost = open[hash].g_cost + open[hash].h_cost
						open[hash].parent = current
					end
				end
			end
		end--End For loop
	end--End While loop
	
	print(minetest.get_us_time()-time)
	-- Did I get a good path back?
	if path ~= {} then
		--Yes. Excellent then I will tell the user
		return path
	else
		--No? Why not? I am a perfect machine. Oh, well I guess I have to tell the user that I couldn't find a path. :'(
		return false
	end
end

minetest.register_chatcommand("neighbors",{
	description = "get players neighbors",
	func = function(name,param)
		local player = minetest.get_player_by_name(name)
		local pos = player:get_pos()
		pos = {
			x = math.floor(pos.x+0.5), 
			y = math.floor(pos.y+0.5), 
			z = math.floor(pos.z+0.5)
		} 
		local neighbors = get_ground_neighbors(pos, 4, 1, 2, false)
		for _,neighbor in pairs(neighbors) do
			minetest.set_node(neighbor.pos,{name = "default:stone"})
			local meta = minetest.get_meta(neighbor.pos)
			meta:set_string("infotext", tostring(neighbor.g_cost))
		end
	end
})

local target = {x = 0, y = 0, z = 0}
minetest.register_chatcommand("set_target",{
	description = "set target point",
	func = function(name,param)
		local player = minetest.get_player_by_name(name)
		local pos = player:get_pos()
		pos = {
			x = math.floor(pos.x+0.5), 
			y = math.floor(pos.y+0.5), 
			z = math.floor(pos.z+0.5)
		} 
		target = pos 
	end
})

minetest.register_chatcommand("get_path",{
	description = "get path to target",
	func = function(name,param)
		local player = minetest.get_player_by_name(name)
		local pos = player:get_pos()
		pos = {
			x = math.floor(pos.x+0.5), 
			y = math.floor(pos.y+0.5), 
			z = math.floor(pos.z+0.5)
		}
		local path = pathfinder.find_path(pos, target, 0, 2, 4, 1)
		for _,hash in pairs(path) do
			minetest.set_node(minetest.get_position_from_hash(hash),{name = "default:glass"})
		end
	end
})
