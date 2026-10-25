extends Node

signal misgendered_triggered
var spoons := 5

const MAX_SPOONS := 5

var day = 1

var week = 1

var telltaletest = false

var player_name = "PLAYER NAME NOT SET OH GOD"

func restore(amount: int = 1) -> void:
	spoons = min(spoons + amount, MAX_SPOONS)

func misgender() -> void:
	spoons -= 1
	misgendered_triggered.emit()
