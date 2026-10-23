extends Node2D

@onready var spoon1 = $Spoon1
@onready var spoon2 = $Spoon2
@onready var spoon3 = $Spoon3
@onready var spoon4 = $Spoon4
@onready var spoon5 = $Spoon5

func _process(delta: float) -> void:
	spoon5.visible = Globals.spoons > 4
	spoon4.visible = Globals.spoons > 3
	spoon3.visible = Globals.spoons > 2
	spoon2.visible = Globals.spoons > 1
	spoon1.visible = Globals.spoons > 0

	if Globals.spoons <= 0:
		print("kill")  
