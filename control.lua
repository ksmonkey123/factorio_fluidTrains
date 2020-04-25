require("config")
require("stdlib.util")

local connection_array = {{1.5, 1.5}, {1.5, 0.5}, {1.5, -0.5}, {-1.5, 1.5}, {-1.5, 0.5}, {-1.5, -0.5}}
local function prioritize(loco)
--[[ Give locomotive priority so that it updates on every tick ]]
	global.high_prio_loco[loco.unit_number] = loco
end

local function deprioritize(loco)
--[[ Remove locomotive priority ]]
	global.high_prio_loco[loco.unit_number] = nil
end

local function determineItemForFluid(fluid, fuel_category)
	local temp = fluid.temperature
	local candidates = global.fluid_map[fuel_category][fluid.name]
	
	for _, item in pairs(candidates) do
		if item[2] <= temp then
			return item
		end
	end
	
	return nil
end

local function getBurnerFuelCategory(burner)
	local categories = burner.fuel_categories
	for k,v in pairs(categories) do
		if v then
			return k
		end
	end
	return nil
end

local function update_loco_fuel(loco)
--[[ Update locomotive remaining fuel depends on amount of fluid in proxy_tank 
	if no proxy_tank found (update fail) return -1
	else return number of tick since fluid amount in proxy_tank last changed ]]
	local proxy = global.proxies[loco.unit_number]
	if not (proxy and proxy.tank and proxy.tank.valid) then
		return (-1)
	end
	local burner_inventory = loco.burner.inventory
	local is_the_same = true
		local fluid = proxy.tank.fluidbox[1]
		local fluid_name = fluid and fluid.name
		local fluid_amount = fluid and fluid.amount or 0
		local item = fluid and determineItemForFluid(fluid, getBurnerFuelCategory(loco.prototype.burner_prototype)) or nil
		if proxy.last_amount == fluid_amount then
			is_the_same = is_the_same and true
		else
			local amount = 0
			if item then
				amount = round(fluid_amount / item[3])
			end
			if burner_inventory[1].valid then
				if (amount>0) then
					burner_inventory[1].set_stack{name=item[1], count = amount}
					global.temperatures[loco.unit_number] = fluid.temperature
				else
					burner_inventory[1].clear()
				end
			end
			is_the_same = is_the_same and false
			proxy.tick = game.tick
			proxy.last_amount = fluid_amount
		end
	if is_the_same then
		return game.tick-proxy.tick
	else
		proxy.tick = game.tick
		return 0
	end
end

local function reconstructFluid(locoUid, itemStack)
	local reverseMap = global.item_fluid_map[itemStack.name]
	
	if reverseMap then
		local fluidName = reverseMap[1]
		local amount = itemStack.count * reverseMap[2]
		return {name = fluidName, amount = amount, temperature = global.temperatures[locoUid]}
	else
		return nil
	end
end

local function is_fake_item(item_stack)
	return global.item_fluid_map[item_stack.name] and true or false
end

local function determineConnectivity(loco, exception, forcedFluidName)
	local tank_type = 0
	
	local burner_inventory = loco.burner.inventory
	if burner_inventory[1] and burner_inventory[1].valid_for_read then
		if not is_fake_item(burner_inventory[1]) then
			return 0
		end
	end
	
	local legalFluids = {}
	local tankForced = false
			
	if forcedFluidName then
		legalFluids[forcedFluidName] = true
		tankForced = true
	else
		local burner_inventory = loco.burner.inventory
		if burner_inventory[1] and burner_inventory[1].valid_for_read then
			local fluid = reconstructFluid(loco.unit_number, burner_inventory[1])
			if fluid.amount > 0 then
				legalFluids[fluid.name] = true
				tankForced = true
			end
		end
	end
	
	if next(legalFluids) == nil then
		for category, v in pairs(loco.prototype.burner_prototype.fuel_categories) do
			if v then
				for fluid, _ in pairs(global.fluid_map[category]) do
					legalFluids[fluid] = true
				end
			end
		end
	end

	local pumps = {}
	
	for j = 1, 6 do
		local found_pumps = loco.surface.find_entities_filtered{
			name = "pump",
			position = moveposition(
				{x = round(loco.position.x),y = round(loco.position.y)},
				ori_to_dir(loco.orientation),
				{x = connection_array[j][1], y = connection_array[j][2]}
			)
		}
		if found_pumps[1] and not(found_pumps[1].unit_number == exception) then
			local systemFluid = found_pumps[1].fluidbox.get_locked_fluid(1)
			if systemFluid then
				if legalFluids[systemFluid] then
					pumps[systemFluid] = (pumps[systemFluid] or 0) + 2^(j-1)
				end
			else
				pumps[0] = (pumps[0] or 0) + 2^(j-1)
			end
		end
	end
	
	for fluid,_ in pairs(legalFluids) do
		local configuration = pumps[fluid]
		if configuration then
			game.forces.player.print("selected: " .. fluid)
			tank_type = configuration
			break
		end
	end
	
	if tank_type > 0 or tankForced then
		tank_type = tank_type + (pumps[0] or 0)
	end
	
	return tank_type
end

local function create_proxy(loco, exception)
--[[ Create proxy_tank for a locomotive and inserting the proxy_tank to global.proxies 
	if proxy_tank successfully created return 0, else return -1 ]]
	local uid = loco.unit_number
	local proxy = global.proxies[uid]
	if not(proxy and proxy.tank and proxy.tank.valid) and math.floor(4 * loco.orientation) == 4 * loco.orientation then
		local proxy_tank
		local fluid_amount
		local tank_type = determineConnectivity(loco, exception)
		proxy_tank = loco.surface.create_entity{
			name = global.loco_tank_pair_list[loco.name]..tank_type,
			position = moveposition(loco.position, ori_to_dir(loco.orientation), {x = 0, y = 0}),
			force = loco.force,
			direction = ori_to_dir(loco.orientation)
		}
		if (not proxy_tank) then return -1 end
		if tank_type > 0 then
			proxy_tank.fluidbox.set_filter(1, { name = proxy_tank.fluidbox.get_locked_fluid(1)})
		end
		proxy_tank.destructible = false
		local burner_inventory = loco.burner.inventory
		fluid_amount = 0
		if burner_inventory[1] and burner_inventory[1].valid_for_read then
			local fluid = reconstructFluid(uid, burner_inventory[1])
			if fluid then
				fluid_amount = fluid.amount
				proxy_tank.fluidbox[1] = fluid
			end
		end
		global.proxies[uid] = {tank = proxy_tank, last_amount = fluid_amount, tick = game.tick}
		local update_tick = uid % SLOW_UPDATE_TICK + 1
		global.update_tick[uid] = update_tick
		global.low_prio_loco[update_tick][uid] = loco
		global.high_prio_loco[uid] = loco
		return 0
	end
	return -1
end

local function destroy_proxy(loco)
--[[ Update the locomotive then destroy the proxy_tank
	return number of ticks since last fluid change in proxy_tank
	return -1 if locomotive has no proxy_tank ]]
	local uid = loco.unit_number
	local no_update_ticks = update_loco_fuel(loco)
	if no_update_ticks >= 0 then
		global.proxies[uid].tank.destroy()
		global.low_prio_loco[global.update_tick[uid]][uid] = nil
	end
	global.proxies[uid] = nil
	global.update_tick[uid] = nil
	global.high_prio_loco[uid] = nil
	return no_update_ticks
end

local function refresh_proxy(loco, exception)
	local proxy = global.proxies[loco.unit_number]
	if proxy and proxy.tank and proxy.tank.valid then
		local fluid_name = proxy.tank.fluidbox and proxy.tank.fluidbox[1] and proxy.tank.fluidbox[1].name
		local tank_type = determineConnectivity(loco, exception, fluid_name)
		if not (proxy.tank.name == global.loco_tank_pair_list[loco.name]..tank_type) then
			local fluid_amount = proxy.tank.fluidbox and proxy.tank.fluidbox[1] and proxy.tank.fluidbox[1].amount
			local fluid_temp   = proxy.tank.fluidbox and proxy.tank.fluidbox[1] and proxy.tank.fluidbox[1].temperature
			proxy.tank.destroy()
			proxy.tank = loco.surface.create_entity{
				name = global.loco_tank_pair_list[loco.name]..tank_type,
				position = moveposition(loco.position, ori_to_dir(loco.orientation), {x = 0, y = 0}),
				force = loco.force,
				direction = ori_to_dir(loco.orientation)
			}
			if tank_type > 0 then
				local lock = proxy.tank.fluidbox.get_locked_fluid(1)
				if lock then
					proxy.tank.fluidbox.set_filter(1, { name = lock})
				end
			end
			proxy.tank.destructible = false
			if fluid_name then
				proxy.tank.fluidbox[1] = {name = fluid_name, amount = fluid_amount, temperature = fluid_temp}
			end
		end
	else
		create_proxy(loco, exception)
	end
end

local function update_loco(loco, exception)
--[[ If locomotive is idle, the fuel will be updated or a proxy_tank will be created
	if the locomotive is moving, proxy_tank will be destroyed
	Also put the locomotive to its appropriate priority ]]
	if loco.train.speed == 0 then
		local no_update_ticks = update_loco_fuel(loco)
		if no_update_ticks == -1 then
			create_proxy(loco, exception)
		elseif no_update_ticks <= IDLE_TICK_BUFFER then
			prioritize(loco)
		else
			deprioritize(loco)
		end
	else
		destroy_proxy(loco)
	end
end

local function train_ridden()
--[[ Return array of trains that is in manual_control and ridden by a player]]
	local trains = {}
	for i,p in pairs(game.players) do
		if (
			p.vehicle and
			(
				p.vehicle.type == "fluid-wagon" or 
				p.vehicle.type == "cargo-wagon" or
				p.vehicle.type == "locomotive" or
				p.vehicle.type == "artillery-wagon"
			) and
			p.vehicle.train.state == defines.train_state.manual_control
		) then
			trains[i] = p.vehicle.train
		end
	end
	return trains
end

local function update_train(train)
--[[ Update all locomotives in train ]]
	for _,l in pairs(train.locomotives.front_movers) do
		if global.loco_tank_pair_list[l.name] then
			update_loco(l, nil)
		end
	end
	for _,l in pairs(train.locomotives.back_movers) do
		if global.loco_tank_pair_list[l.name] then
			update_loco(l, nil)
		end
	end
end

local function ON_BUILT(event)
--[[ Handler for when entity is built ]]
	local entity = event.created_entity
	if global.loco_tank_pair_list[entity.name] then
		update_loco(entity, nil)
	end
	if entity.name == "pump" then
		local locos = entity.surface.find_entities_filtered{
			type = "locomotive",
			area = {
				moveposition(entity.position, 0, {x = -1.5, y = -1.5}),
				moveposition(entity.position, 0, {x = 1.5, y = 1.5})
			}
		}
		for _, loco in pairs(locos) do
			if loco.valid and global.loco_tank_pair_list[loco.name] then
				refresh_proxy(loco, nil)
			end
		end
	end
end

local function ON_DESTROYED(event)
--[[ Handler for when entity is destroyed ]]
	local entity = event.entity 
	if global.loco_tank_pair_list[entity.name] then
		destroy_proxy(entity)
	end
	if entity.name == "pump" then
		local locos = entity.surface.find_entities_filtered{
			type = "locomotive",
			area = {
				moveposition(entity.position, 0, {x = -1.5, y = -1.5}),
				moveposition(entity.position, 0, {x = 1.5, y = 1.5})
			}
		}
		for _, loco in pairs(locos) do
			if loco.valid and global.loco_tank_pair_list[loco.name] then
				refresh_proxy(loco, entity.unit_number)
			end
		end
	end
	if event.buffer then
		local buffer = event.buffer
		for name, count in pairs(buffer.get_contents()) do
			if game.item_prototypes[name].group == "fluidTrains_fake" then
				local amount = buffer.remove({name = name, count = buffer.get_item_count(name)})
			end
		end
	end
end

local function ON_PRE_PLAYER_MINED_ITEM(event)
	local entity = event.entity
	if global.loco_tank_pair_list[entity.name] then
		destroy_proxy(entity)
		entity.burner.inventory.clear()
	end
end

local function ON_TICK(event)
--[[ Handler for every tick ]]
	if TICK_UPDATE then
		for _, l in pairs(global.low_prio_loco[event.tick % SLOW_UPDATE_TICK + 1]) do
			update_loco(l, nil)
		end
		for _, l in pairs(global.high_prio_loco) do
			update_loco(l, nil)
		end
	end
	for _,t in pairs(train_ridden()) do
		update_train(t)
	end
end

local function ON_TRAIN_CHANGED_STATE(event)
--[[ Handler for when a train changed state ]]
	local train = event.train
	local state = train.state
	local train_state = defines.train_state
	local stopped = (
		(state == (train_state.no_schedule)) or
		(state == (train_state.no_path)) or
		(state == (train_state.wait_station)) or
		(state == (train_state.manual_control))
	)
	if not (state == train_state.wait_signal) then update_train(train) end
	if not stopped then
		for _,loco in pairs(train.locomotives.front_movers) do
			destroy_proxy(loco)
		end
		for _,loco in pairs(train.locomotives.back_movers) do
			destroy_proxy(loco)
		end
	end
end

local function ON_PLAYER_CURSOR_STACK_CHANGED(event)
--[[ Handler for when cursor pick up or put down something ]]
	local player = game.players[event.player_index]
	local taken_item = player.cursor_stack
	if taken_item and taken_item.valid_for_read and is_fake_item(taken_item) and player.opened and global.loco_tank_pair_list[player.opened.name] then
		local name = taken_item.name
		local amount = taken_item.count
		player.cursor_stack.clear()
		local fake_items
		for fake_name, fake_count in pairs (player.opened.burner.inventory.get_contents()) do
			if fake_name == name then
				fake_count = fake_count + amount
			end
			fake_items = {name = fake_name, count = fake_count}
		end
		player.opened.burner.inventory.clear()
		if not fake_items then
			fake_items = {name = name, count = amount}
		end
		if fake_items then
			player.opened.insert(fake_items)
		end
	end
end

local function ON_PLAYER_MAIN_INVENTORY_CHANGED(event)
--[[ Handler for when player main inventory changed ]]
	local player = game.players[event.player_index]
	local inventory = player.get_inventory(defines.inventory.character_main)
	if not inventory then return end
	for name, count in pairs(inventory.get_contents()) do
		if game.item_prototypes[name].group == "fluidTrains_fake" then
			local amount = inventory.remove({name = name, count = inventory.get_item_count(name)})
			if amount and amount > 0 and player.opened and global.loco_tank_pair_list[player.opened.name] then
				local fake_items
				for fake_name, fake_count in pairs (player.opened.burner.inventory.get_contents()) do
					if fake_name == name then
						fake_count = fake_count + amount
					end
					fake_items = {name = fake_name, count = fake_count}
				end
				player.opened.burner.inventory.clear()
				if not fake_items then
					fake_items = {name = name, count = amount}
				end
				if fake_items then
					player.opened.insert(fake_items)
				end
			end
		end
	end
end

local function ON_PLAYER_ROTATED_ENTITY(event)
	local entity = event.entity
	if entity.name == "pump" then
		local locos = entity.surface.find_entities_filtered{
			type = "locomotive",
			area = {
				moveposition(entity.position, 0, {x = -1.5, y = -1.5}),
				moveposition(entity.position, 0, {x = 1.5, y = 1.5})
			}
		}
		for _, loco in pairs(locos) do
			if loco.valid and global.loco_tank_pair_list[loco.name] then
				refresh_proxy(loco, nil)
			end
		end
	elseif global.loco_tank_pair_list[entity.name] then
		refresh_proxy(entity, nil)
	end
end

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, ON_BUILT)
script.on_event({defines.events.on_player_mined_entity, defines.events.on_entity_died, defines.events.on_robot_mined_entity}, ON_DESTROYED)
script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined}, ON_PRE_PLAYER_MINED_ITEM)
script.on_event({defines.events.on_player_rotated_entity}, ON_PLAYER_ROTATED_ENTITY)
script.on_event({defines.events.on_tick}, ON_TICK)
script.on_event({defines.events.on_train_changed_state}, ON_TRAIN_CHANGED_STATE)
script.on_event({defines.events.on_player_cursor_stack_changed}, ON_PLAYER_CURSOR_STACK_CHANGED)
script.on_event({defines.events.on_player_main_inventory_changed}, ON_PLAYER_MAIN_INVENTORY_CHANGED)

local function addLocomotive(locoName, tankSize)
	-- TODO: verify tank size
	if (game.entity_prototypes["fluidTrains-proxy-tank-"..tankSize.."-0"]) then
		global.loco_tank_pair_list[locoName] = "fluidTrains-proxy-tank-"..tankSize.."-"
	else
		error("unsupported tank size: "..tankSize)
	end
end

local function addFluid(fuelCategory, fluidName, itemConfigs)
	local items = {}
	for _,itemConfig in pairs(itemConfigs) do
		local itemName = itemConfig["item"]
		local minTemp = itemConfig["temp"] or 15
		local multiplier = itemConfig["multiplier"] or 1
		items[#items+1] = {itemName, minTemp, multiplier}
	end
	local categoryMap = global.fluid_map[fuelCategory] or {}
	categoryMap[fluidName] = items
	global.fluid_map[fuelCategory] = categoryMap
	for _,item in pairs(items) do
		global.item_fluid_map[item[1]] = {fluidName, item[3]}
	end
end

local function removeFluid(fuelCategory, fluidName)
	local categoryMap = global.fluid_map[fuelCategory]
	if categoryMap then
		if categoryMap[fluidName] then
			local items = categoryMap[fluidName]
			for _,item in pairs(items) do
				global.item_fluid_map[item[1]] = nil
			end
			categoryMap[fluidName] = nil
		end
	end
end

local function dumpConfig()
	game.forces.player.print("locomotives: ")
	for k,v in pairs(global.loco_tank_pair_list) do
		game.forces.player.print(" - "..k..": "..v)
	end
	for category, entry in pairs(global.fluid_map) do
		game.forces.player.print("fluidCategory: "..category)
		for fluid, items in pairs(entry) do
			game.forces.player.print(" - fluid: "..fluid)
			for _,item in pairs(items) do
				game.forces.player.print("   > "..item[1].." (>="..item[2].."°) x"..item[3])
			end
		end
	end
end

if not remote.interfaces["fluidTrains_hook"] then
	remote.add_interface("fluidTrains_hook", {
		addLocomotive = addLocomotive,
		addFluid = addFluid,
		removeFluid = removeFluid,
		dumpConfig = dumpConfig
	})
end

local function ON_INIT()
	global = global or {}
	global.proxies = global.proxies or {}
	global.update_tick = global.update_tick or {}
	global.low_prio_loco = global.low_prio_loco or {}
	for i=1,SLOW_UPDATE_TICK do
		global.low_prio_loco[i] = global.low_prio_loco[i] or {}
	end
	global.high_prio_loco = global.high_prio_loco or {}
	global.generator = game.create_random_generator()
	global.loco_tank_pair_list = global.loco_tank_pair_list or {}
	global.fluid_map = global.fluid_map or {}
	global.item_fluid_map = global.item_fluid_map or {}
	global.temperatures = global.temperatures or {}
end

script.on_init(ON_INIT)
script.on_configuration_changed(ON_INIT)