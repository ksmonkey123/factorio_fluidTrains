require("config")
require("stdlib.util")

local public = {}

function public.is_fake_item(item_stack)
	return global.item_fluid_map[item_stack.name] and true or false
end

function public.reconstructFluid(locoUid, itemStack)
	local reverseMap = global.item_fluid_map[itemStack.name]
	
	if reverseMap then
	
		local temp = global.temperatures[locoUid]
		if not temp then
			temp = reverseMap[3]
			global.temperatures[locoUid] = temp
		end
		local fluidName = reverseMap[1]
		local amount = itemStack.count * reverseMap[2]
		return {name = fluidName, amount = amount, temperature = temp}
	else
		return nil
	end
end

function public.determineItemForFluid(fluid, fuel_category)
	local candidates = global.fluid_map[fuel_category][fluid.name]
	
	for _, item in pairs(candidates) do
		if item[2] <= fluid.temperature then
			return item
		end
	end
	
	return nil
end

function public.convertFluidToItem(fluid, fuel_category)
	local item = public.determineItemForFluid(fluid, fuel_category)
	return {
		name = item[1],
		count = round(fluid.amount / item[3])
	}
end

function public.getBurnerFuelCategory(burner)
	local categories = burner.fuel_categories
	for k,v in pairs(categories) do
		if v then
			return k
		end
	end
	return nil
end

return public