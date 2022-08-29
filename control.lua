require("config")
require("stdlib.util")

local proxy = require("scripts.proxy")
local fuel = require("scripts.fuel")
local locomotive = require("scripts.locomotive")
local tender = require("scripts.tender")

local function prioritize(loco)
--[[ Give locomotive priority so that it updates on every tick ]]
	global.high_prio_loco[loco.unit_number] = loco
end

local function deprioritize(loco)
--[[ Remove locomotive priority ]]
	global.high_prio_loco[loco.unit_number] = nil
end

local function verifyInternalData()
	for uid, loco in pairs(global.high_prio_loco) do
		if not loco.valid then
			global.high_prio_loco[uid] = nil
			global.temperatures[uid] = nil
			proxy.forceKillProxy(uid)
		end
	end
	
	for _,slot in pairs(global.low_prio_loco) do
		for uid, loco in pairs(slot) do
			if not loco.valid then
				slot[uid] = nil
				global.temperatures[uid] = nil
				proxy.forceKillProxy(uid)
			end
		end
	end
	
	for _,slot in pairs(global.tender_queue) do
		for uid, loco in pairs(slot) do
			if not loco.valid then
				slot[uid] = nil
				global.known_locos[uid] = nil
			end
		end
	end
end

local function update_loco(loco, exception)
--[[ If locomotive is idle, the fuel will be updated or a proxy_tank will be created
	if the locomotive is moving, proxy_tank will be destroyed
	Also put the locomotive to its appropriate priority ]]
	if not loco.valid then
		verifyInternalData()
		return
	end
	if loco.train.speed == 0 then
		local no_update_ticks = locomotive.update_loco_fuel(loco)
		if no_update_ticks == -1 then
			proxy.create_proxy(loco, exception)
		elseif no_update_ticks <= IDLE_TICK_BUFFER then
			prioritize(loco)
		else
			deprioritize(loco)
		end
	else
		proxy.destroy_proxy(loco)
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
		global.tender_queue[entity.unit_number % TENDER_UPDATE_TICK+1][entity.unit_number] = entity
		global.known_locos[entity.unit_number] = true
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
				proxy.refresh_proxy(loco, nil)
			end
		end
	end
end

local function ON_DESTROYED(event)
--[[ Handler for when entity is destroyed ]]
	local entity = event.entity 
	if global.loco_tank_pair_list[entity.name] then
		proxy.destroy_proxy(entity)
		global.known_locos[entity.unit_number] = nil
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
				proxy.refresh_proxy(loco, entity.unit_number)
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
		proxy.destroy_proxy(entity)
		entity.burner.inventory.clear()
	end
end

local function readSettings(sets)
	sets.tender = settings.global["fluidTrains_enable_tender"].value
	sets.mode = settings.global["fluidTrains_tender_mode"].value
	sets.threshold = settings.global["fluidTrains_tender_threshold"].value
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
	
	local tenders = global.tender_queue[event.tick % TENDER_UPDATE_TICK + 1]
	local tenderSettings = nil
	for uid, loco in pairs(tenders) do
		if not loco.valid then
			tenders[uid] = nil
		else
			if not tenderSettings then
				tenderSettings = {}
				readSettings(tenderSettings)
				if tenderSettings.tender == "never" then
					return
				end
			end
			tender.update(uid, loco, tenderSettings)
		end
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
			proxy.destroy_proxy(loco)
		end
		for _,loco in pairs(train.locomotives.back_movers) do
			proxy.destroy_proxy(loco)
		end
	end
end

local function ON_PLAYER_CURSOR_STACK_CHANGED(event)
--[[ Handler for when cursor pick up or put down something ]]
	local player = game.players[event.player_index]
	local taken_item = player.cursor_stack
	if taken_item and taken_item.valid_for_read and fuel.is_fake_item(taken_item) and player.opened and global.loco_tank_pair_list[player.opened.name] then
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
				proxy.refresh_proxy(loco, nil)
			end
		end
	elseif global.loco_tank_pair_list[entity.name] then
		proxy.refresh_proxy(entity, nil)
	end
end

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity, defines.events.script_raised_built, defines.events.script_raised_revive}, ON_BUILT)
script.on_event({defines.events.on_player_mined_entity, defines.events.on_entity_died, defines.events.on_robot_mined_entity, defines.events.script_raised_destroy}, ON_DESTROYED)
script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined}, ON_PRE_PLAYER_MINED_ITEM)
script.on_event({defines.events.on_player_rotated_entity}, ON_PLAYER_ROTATED_ENTITY)
script.on_event({defines.events.on_tick}, ON_TICK)
script.on_event({defines.events.on_train_changed_state}, ON_TRAIN_CHANGED_STATE)
script.on_event({defines.events.on_player_cursor_stack_changed}, ON_PLAYER_CURSOR_STACK_CHANGED)
script.on_event({defines.events.on_player_main_inventory_changed}, ON_PLAYER_MAIN_INVENTORY_CHANGED)

local function addLocomotive(locoName, tankSize, options)
	-- TODO: verify tank size
	if (game.entity_prototypes["fluidTrains-proxy-tank-"..tankSize.."-0"]) then
		global.loco_tank_pair_list[locoName] = "fluidTrains-proxy-tank-"..tankSize.."-"
		global.loco_sizes[locoName] = tankSize
	else
		error("unsupported tank size: "..tankSize)
	end
	
	if options then
		global.loco_options[locoName] = options
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
		global.item_fluid_map[item[1]] = {fluidName, item[3], item[2]}
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
	for k,v in pairs(global.loco_sizes) do
		game.forces.player.print(" - "..k..": "..v)
		if global.loco_options[k] then
			game.forces.player.print(serpent.block(global.loco_options[k]))
		end
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
	global.tender_queue = global.tender_queue or {}
	for i=1,TENDER_UPDATE_TICK do
		global.tender_queue[i] = global.tender_queue[i] or {}
	end
	global.high_prio_loco = global.high_prio_loco or {}
	global.generator = nil
	global.loco_tank_pair_list = {}
	global.fluid_map = {}
	global.item_fluid_map = {}
	global.temperatures = global.temperatures or {}
	global.known_locos = global.known_locos or {}
	global.loco_sizes = {}
	global.loco_options = {}
	
	verifyInternalData()
end

script.on_init(ON_INIT)
script.on_configuration_changed(ON_INIT)