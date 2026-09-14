class_name RunUnitTitleScreen
extends CanvasLayer

signal start_requested(level_index: int)

const LEVEL_DATA: Array[Dictionary] = [
	{"name": "MAINTENANCE SHAFT", "description": "Wake protocol active. The first route to Beacon 9 begins below the city."},
	{"name": "MANUFACTURING DISTRICT", "description": "Power is fluctuating. Machinery may operate outside normal safety limits."},
	{"name": "THERMAL SECTOR", "description": "Temperatures are falling. Heating priority has been reassigned to nobody."},
	{"name": "FREIGHT NETWORK", "description": "Express freight route available. Estimated arrival: 01:42. Conditions unstable."},
	{"name": "HABITATION GARDENS", "description": "Public district population: 0. The city was built for someone."},
	{"name": "POWER SPINE", "description": "Power reserve: 11%. Mission success probability is no longer considered reliable."},
	{"name": "BEACON APPROACH", "description": "Beacon 9 is visible. Signal corruption detected. Keep the core moving."},
	{"name": "BEACON 9", "description": "Manual ignition port available. Insert the Solar Ignition Core."}
]

@onready var start_button: Button = %StartButton
@onready var selection_label: Label = %SelectionLabel
@onready var selection_description: Label = %SelectionDescription
@onready var level_buttons: Array[Button] = [%Level01, %Level02, %Level03, %Level04, %Level05, %Level06, %Level07, %Level08]

var selected_level_index: int = 0

func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	var button_group: ButtonGroup = ButtonGroup.new()
	for index: int in level_buttons.size():
		var button: Button = level_buttons[index]
		button.button_group = button_group
		button.pressed.connect(_on_level_button_pressed.bind(index))
		button.focus_entered.connect(_on_level_button_focused.bind(index))
	select_level(0)

func open() -> void:
	show()
	call_deferred("_focus_start_button")

func close() -> void:
	hide()

func _focus_start_button() -> void:
	start_button.grab_focus()

func select_level(level_index: int) -> void:
	selected_level_index = clampi(level_index, 0, LEVEL_DATA.size() - 1)
	var level: Dictionary = LEVEL_DATA[selected_level_index]
	selection_label.text = "SECTOR %02d  //  %s" % [selected_level_index + 1, str(level["name"])]
	selection_description.text = str(level["description"])
	level_buttons[selected_level_index].button_pressed = true

func _on_level_button_pressed(level_index: int) -> void:
	select_level(level_index)

func _on_level_button_focused(level_index: int) -> void:
	select_level(level_index)

func _on_start_button_pressed() -> void:
	start_requested.emit(selected_level_index)
