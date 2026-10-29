extends RefCounted
## Native acknowledgement controls speed and TP; the icon never grants a boost.
var game:Node
var button:Button
var pending:int=-1

func build(owner_game:Node,parent:Control)->void:
	game=owner_game
	button=preload("res://scripts/hud_icon_button.gd").new();button.kind="run"
	button.position=Vector2(-626,110);button.size=Vector2(68,68);button.toggle_mode=true
	parent.add_child(button);button.set_anchors_preset(Control.PRESET_TOP_RIGHT,true)
	button.pressed.connect(press);button.hide()
	game.online.session.message_received.connect(func(message:Dictionary)->void:
		if str(message.get("op",""))!="run_mode":return
		pending=-1
		if not bool(message.get("ok",false)):game._toast(str(message.get("error","Run mode was not confirmed")))
		tick()
	)

func tick()->void:
	var combat:Dictionary=game.online.player.get("combat",{}) as Dictionary
	button.visible=game.started and game.online_mode and game.online.active and bool(combat.get("running_supported",false)) and not game._modal_open() and not game.welcome.visible
	button.set_pressed_no_signal(bool(combat.get("running",false)))
	button.disabled=pending>=0 or game.online.defeated
	var speed:float=1.5 if int((game.online.player.get("stats",{}) as Dictionary).get("class_id",0))==4 else 1.25
	button.tooltip_text="Run %s · ×%.2f speed · 1.5%% max TP/sec while enabled"%["enabled" if button.button_pressed else "disabled",speed]
	if not game.online.active:pending=-1

func press()->void:
	if button.disabled or not button.visible:return
	var enabled:bool=not bool((game.online.player.get("combat",{}) as Dictionary).get("running",false))
	pending=game.online.session.request("run_mode",{"enabled":enabled})
	if pending<0:game._toast("Run mode could not be sent")
	tick()
