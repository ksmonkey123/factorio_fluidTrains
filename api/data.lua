local public = {}

function public.generateTank(size)
  for i=0,63 do
	local pipe_connections = {}

	if i%64 >= 32 then
		table.insert(pipe_connections, {position = {-1.5, -0.5}})
	end

	if i%32 >= 16 then
		table.insert(pipe_connections, {position = {-1.5, 0.5}})
	end

	if i%16 >= 8 then
		table.insert(pipe_connections, {position = {-1.5, 1.5}})
	end

	if i%8 >= 4 then
		table.insert(pipe_connections, {position = {1.5, -0.5}})
	end

	if i%4 >= 2 then
		table.insert(pipe_connections, {position = {1.5, 0.5}})
	end

	if i%2 >= 1 then
		table.insert(pipe_connections, {position = {1.5, 1.5}})
	end

	local proxy_tank = table.deepcopy(data.raw["storage-tank"]["storage-tank"])
	proxy_tank.name = "fluidTrains-proxy-tank-"..size.."-"..i
	proxy_tank.icon = "__core__/graphics/empty.png"
	proxy_tank.icon_size = 1
	proxy_tank.icon_mipmaps = 0
	proxy_tank.flags = {"placeable-neutral", "not-on-map"}
	proxy_tank.collision_mask = {}
	proxy_tank.selectable_in_game = false
	proxy_tank.minable = nil
	proxy_tank.next_upgrade = nil  -- Compatibility with other mods altering this value
	proxy_tank.max_health = nil
	proxy_tank.corpse = "small-remnants"
	proxy_tank.collision_box = {{-0.6, -1.6}, {0.6, 1.6}}
	proxy_tank.selection_box = {{-1, -1}, {1, 1}}
	proxy_tank.resistances = {}
	proxy_tank.fluid_box.pipe_covers = nil
	proxy_tank.fluid_box.pipe_connections = pipe_connections
	proxy_tank.fluid_box.base_area = size / 100
	proxy_tank.fluid_box.filter = nil
	proxy_tank.two_direction_only = false
	proxy_tank.pictures.picture.sheets =
	{
		{
			filename = "__core__/graphics/empty.png",
			frames = 1,
			width = 1,
			height = 1,
			shift = util.by_pixel(0, 0),
			hr_version =
			{
				filename = "__core__/graphics/empty.png",
				frames = 1,
				width = 1,
				height = 1,
				shift = util.by_pixel(0, 0)
			}
		},
		{
			filename = "__core__/graphics/empty.png",
			frames = 1,
			width = 1,
			height = 1,
			shift = util.by_pixel(0, 0),
			hr_version =
			{
				filename = "__core__/graphics/empty.png",
				frames = 1,
				width = 1,
				height = 1,
				shift = util.by_pixel(0, 0)
			}
		}
	}
	proxy_tank.pictures.fluid_background.filename = "__core__/graphics/empty.png"
	proxy_tank.pictures.fluid_background.width = 1
	proxy_tank.pictures.fluid_background.height = 1
	proxy_tank.pictures.window_background.filename = "__core__/graphics/empty.png"
	proxy_tank.pictures.window_background.width = 1
	proxy_tank.pictures.window_background.height = 1
	proxy_tank.pictures.window_background.hr_version.filename = "__core__/graphics/empty.png"
	proxy_tank.pictures.window_background.hr_version.width = 1
	proxy_tank.pictures.window_background.hr_version.height = 1
	proxy_tank.pictures.flow_sprite.filename = "__core__/graphics/empty.png"
	proxy_tank.pictures.flow_sprite.width = 1
	proxy_tank.pictures.flow_sprite.height = 1
	proxy_tank.pictures.gas_flow.filename = "__core__/graphics/empty.png"
	proxy_tank.pictures.gas_flow.width = 1
	proxy_tank.pictures.gas_flow.height = 1
	proxy_tank.pictures.gas_flow.line_length = 1
	proxy_tank.pictures.gas_flow.frame_count =1
	proxy_tank.pictures.gas_flow.animation_speed = 1
	proxy_tank.pictures.gas_flow.hr_version.filename = "__core__/graphics/empty.png"
	proxy_tank.pictures.gas_flow.hr_version.width = 1
	proxy_tank.pictures.gas_flow.hr_version.height = 1
	proxy_tank.pictures.gas_flow.hr_version.line_length = 1
	proxy_tank.pictures.gas_flow.hr_version.frame_count =1
	proxy_tank.pictures.gas_flow.hr_version.animation_speed = 1
	proxy_tank.vehicle_impact_sound = nil
	proxy_tank.circuit_wire_connection_points = {}
	proxy_tank.circuit_connector_sprites = {}
	proxy_tank.circuit_wire_max_distance = 0
	proxy_tank.localised_name = "Hidden"
	proxy_tank.order = "proxy-tank-"..size.."-"..i
	
	data:extend({proxy_tank})
  end
end

return public