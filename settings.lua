data:extend({
	{
		type = "string-setting",
		name = "fluidTrains_enable_tender",
		setting_type = "runtime-global",
		allowed_values = {"always", "unless-disabled", "only-enabled", "never"},
		default_value = "only-enabled"
	},
	{
		type = "string-setting",
		name = "fluidTrains_tender_mode",
		setting_type = "runtime-global",
		allowed_values = {"local", "global"},
		default_value = "local"
	},
	{
		type = "int-setting",
		name = "fluidTrains_tender_threshold",
		setting_type = "runtime-global",
		allowed_values = {1, 10, 50, 100, 500},
		default_value = 100
	}
})
