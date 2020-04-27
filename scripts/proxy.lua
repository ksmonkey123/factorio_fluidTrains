require("config")
require("stdlib.util")

local fuel = require("scripts.fuel")
local locomotive = require("scripts.locomotive")

local connection_array = {{1.5, 1.5}, {1.5, 0.5}, {1.5, -0.5}, {-1.5, 1.5}, {-1.5, 0.5}, {-1.5, -0.5}}

local public = {}

local function determineConnectivity(loco, exception, forcedFluidName)
	local tank_type = 0
	
	local burner_inventory = loco.burner.inventory
	if burner_inventory[1] and burner_inventory[1].valid_for_read then
		if not fuel.is_fake_item(burner_inventory[1]) then
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
			local fluid = fuel.reconstructFluid(loco.unit_number, burner_inventory[1])
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
			tank_type = configuration
			break
		end
	end
	
	if tank_type > 0 or tankForced then
		tank_type = tank_type + (pumps[0] or 0)
	end
	
	return tank_type
end

function public.create_proxy(loco, exception)
--[[ Create proxy_tank for a locomotive and inserting the proxy_tank to global.proxies 
	if proxy_tank successfully created return 0, else return -1 ]]
	local uid = loco.unit_number
	
	if not global.known_locos[uid] then
		global.known_locos[uid] = true
		global.tender_queue[uid % 120][uid] = loco
	end
	
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
			local locked = proxy_tank.fluidbox.get_locked_fluid(1)
			if locked then
				proxy_tank.fluidbox.set_filter(1, { name = locked})
			end
		end
		proxy_tank.destructible = false
		local burner_inventory = loco.burner.inventory
		fluid_amount = 0
		if burner_inventory[1] and burner_inventory[1].valid_for_read then
			local fluid = fuel.reconstructFluid(uid, burner_inventory[1])
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

function public.destroy_proxy(loco)
--[[ Update the locomotive then destroy the proxy_tank
	return number of ticks since last fluid change in proxy_tank
	return -1 if locomotive has no proxy_tank ]]
	local uid = loco.unit_number
	local no_update_ticks = locomotive.update_loco_fuel(loco)
	if no_update_ticks >= 0 then
		global.proxies[uid].tank.destroy()
		global.low_prio_loco[global.update_tick[uid]][uid] = nil
	end
	global.proxies[uid] = nil
	global.update_tick[uid] = nil
	global.high_prio_loco[uid] = nil
	return no_update_ticks
end

function public.refresh_proxy(loco, exception)
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
		public.create_proxy(loco, exception)
	end
end

function public.forceKillProxy(uid)
	local proxy = global.proxies[uid]
	if proxy and proxy.tank and proxy.tank.valid then
		proxy.tank.destroy()
	end
	global.proxies[uid] = nil
end

return public