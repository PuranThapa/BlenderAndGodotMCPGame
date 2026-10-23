extends Node3D
## Fixed early-morning lighting: low warm sun from the east, soft sky,
## SSAO and light aerial haze that doesn't hide hazards. Time never advances.

@export var sun_elevation_deg := 24.0
@export var sun_azimuth_deg := -115.0
@export var shadow_distance := 140.0


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-sun_elevation_deg, sun_azimuth_deg, 0)
	sun.light_color = Color(1.0, 0.87, 0.70)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = shadow_distance
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.33, 0.52, 0.80)
	sky_mat.sky_horizon_color = Color(0.88, 0.80, 0.70)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.80, 0.76, 0.70)
	sky_mat.ground_bottom_color = Color(0.55, 0.53, 0.50)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.80, 0.76)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
