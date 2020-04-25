round = function(float)
	return math.floor(float + 0.5)
end

local dir = defines.direction
local directiontable = {
	dir.north,
	dir.northeast,
	dir.east,
	dir.southeast,
	dir.south,
	dir.southwest,
	dir.west,
	dir.northwest,
	dir.north
}

int_to_vector = {
	{x = 0, y = -1},
	{x = 1, y = -1},
	{x = 1, y = 0},
	{x = 1, y = 1},
	{x = 0, y = 1},
	{x = -1, y = 1},
	{x = -1, y = 1},
	{x = -1, y = 0},
	{x = -1, y = -1}
}
ori_to_dir = function(ori)
	return math.floor(8*ori)
end

dir_to_int = function(direction)
	for i, d in pairs(directiontable) do
		if direction == d then return (i) end
	end
end

function moveposition(position, direction, vector)

  if direction == 0 then
    return {x = position.x + vector.x, y = position.y + vector.y}
  end

  if direction == 2 then
    return {x = position.x - vector.y, y = position.y + vector.x}
  end

  if direction == 4 then
    return {x = position.x - vector.x, y = position.y - vector.y}
  end

  if direction == 6 then
    return {x = position.x + vector.y, y = position.y - vector.x}
  end
end