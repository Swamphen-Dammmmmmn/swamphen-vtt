extends Control

# Initial UI only: no network requests, game actions or automated input.
const PageShell = preload("res://ui/components/page_shell.tscn")
const FormPanel = preload("res://ui/components/layout/form_panel.gd")
const HostForm = preload("res://ui/components/features/network/host_form.gd")

func _ready() -> void:
	BoardUiStyle.configure()
	var page = PageShell.instantiate()
	add_child(page)
	page.configure_fluent("联机房间")
	var form_panel := FormPanel.new()
	page.content.add_child(form_panel)
	form_panel.content_area.add_child(HostForm.new())
	print("[HostFormReview] Static initial UI ready; no network operations.")
