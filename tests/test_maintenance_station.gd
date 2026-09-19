extends GutTest

const STATION_SCENE: PackedScene = preload("res://scenes/props/maintenance_station.tscn")

func test_maintenance_station_is_visual_only_and_animated() -> void:
	var station: Node2D = STATION_SCENE.instantiate() as Node2D
	add_child_autofree(station)
	assert_not_null(station)
	assert_null(station.get_node_or_null("CollisionShape2D"))
	assert_not_null(station.get_node_or_null("Locker"))
	assert_not_null(station.get_node_or_null("Board"))
	assert_not_null(station.get_node_or_null("Barrel"))
	var screen: AnimatedSprite2D = station.get_node_or_null("StatusScreen") as AnimatedSprite2D
	assert_not_null(screen)
	assert_true(screen.autoplay != "", "The small status screen should keep the scenery alive")
