extends Node2D

func _on_btn_create_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/create_account.tscn")
	
func _on_btn_login_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/signin.tscn")
