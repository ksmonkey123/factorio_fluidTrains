require("config")
require("stdlib.util")

local locomotive = require("scripts.locomotive")
local fuel = require("scripts.fuel")

local public = {}

local function findTenderWagon(loco_uid, train)
	local index
	for i, carriage in pairs(train.carriages) do
		if carriage.unit_number and carriage.unit_number == loco_uid then
			index = i
		end
	end
	
	local isFrontMover = false
	
	for _,l in pairs(train.locomotives["front_movers"]) do
		if l.unit_number == loco_uid then
			isFrontMover = true
		end
	end
	
	local seekDirection = isFrontMover and 1 or -1
	local directional_locos = isFrontMover and train.locomotives["front_movers"] or train.locomotives["back_movers"]
	
	local blockMembers = {}
	for _,l in pairs(directional_locos) do
		blockMembers[l.unit_number] = true
	end
	
	local pointer = index
	
	while true do
		pointer = pointer + seekDirection
		local candidate = train.carriages[pointer]
		
		if not candidate then
			return nil
		end
		
		if not blockMembers[candidate.unit_number] then
			if candidate.prototype.type == "fluid-wagon" then
				return candidate
			else
				return nil
			end
		end
	end
end

local function supportsTenders(loco, defaultSettings)
	local options = global.loco_options[loco.prototype.name]
	
	if defaultSettings == "always" then
		return true
	elseif defaultSettings == "only-enabled" then
		return options and options["tender"] == "yes"
	elseif options and options["tender"] ~= "yes" then
		return false
	else
		return true
	end
end

function public.update(unit_number, loco, defaultSettings)
	if not supportsTenders(loco, defaultSettings) then
		return
	end

	local demand = locomotive.getFluidDemand(loco)
	if not demand then
		return
	end
	
	local tender = findTenderWagon(unit_number, loco.train)
	if not tender then
		return
	end
	
	local amount = tender.remove_fluid(demand)
	if amount == 0 then
		return
	end
	
	local item = fuel.convertFluidToItem(
		{name = demand.name, amount = amount, temperature = demand.minimum_temperature},
		fuel.getBurnerFuelCategory(loco.prototype.burner_prototype))
	
	if not item then
		return
	end
	
	local count = loco.burner.inventory.insert(item)
end

return public