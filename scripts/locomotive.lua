require("config")
require("stdlib.util")

local fuel = require("scripts.fuel")

local public = {}

function public.update_loco_fuel(loco)
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
		local item = fluid and fuel.determineItemForFluid(fluid, fuel.getBurnerFuelCategory(loco.prototype.burner_prototype)) or nil
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

return public