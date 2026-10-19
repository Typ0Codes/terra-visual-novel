# Globals.gd
extends Node

signal misgendered_triggered
var spoons := 10

func misgender() -> void:
	spoons -= 1
	misgendered_triggered.emit()
