extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await get_tree().create_timer(2.5).timeout   
	Globals.day += 1
	if Globals.day == 7:
		Globals.day = 1
		Globals.week += 1
	await get_tree().create_timer(3.5).timeout  
	print("over") 
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	$Label.text = "DAY " + str(Globals.day)
	$Label2.text = "WEEK " + str(Globals.week)
	
