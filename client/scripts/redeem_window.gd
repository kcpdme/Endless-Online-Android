extends RefCounted
## Server-owned, once-per-account rewards. A successful native reply updates the bag.
var game: Node
var panel: Control
var code: LineEdit
var status: Label
var submit: Button
var submitting: bool = false

func build(owner_game: Node, parent: Control) -> void:
	game = owner_game
	panel = game._modal(parent, Vector2(580, 370))
	var card: Control = panel.get_child(0) as Control
	game._wood_card(card)
	game._label(card, "Redeem Code", Vector2(28, 24), 30, game.GOLD)
	game._label(card, "A little treasure for your journey.", Vector2(30, 72), 18, game.MUTED)
	code = LineEdit.new()
	code.position = Vector2(30, 112)
	code.size = Vector2(520, 56)
	code.placeholder_text = "Enter your code"
	code.max_length = 32
	code.add_theme_font_size_override("font_size", 23)
	card.add_child(code)
	code.text_submitted.connect(func(_value: String) -> void: confirm())
	status = game._label(card, "One redemption per account.", Vector2(30, 182), 18, game.MUTED)
	status.size = Vector2(520, 88)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game._button(card, "Close", Vector2(30, 290), Vector2(244, 54), close)
	submit = game._button(card, "Claim rewards", Vector2(296, 290), Vector2(254, 54), confirm, true)
	panel.hide()

func open() -> void:
	if not game.online_mode or not game.online.active:
		game._toast("Enter the online world to redeem a code.")
		return
	game.menu.hide()
	game._cancel_controls()
	status.text = "One redemption per account."
	panel.show()

func close() -> void:
	code.release_focus()
	DisplayServer.virtual_keyboard_hide()
	panel.hide()

func confirm() -> void:
	if submitting: return
	if not game.online_mode or not game.online._action_ready():
		status.text = "Reconnect and stop moving before redeeming."
		return
	var value: String = code.text.strip_edges().to_upper()
	if value.is_empty():
		status.text = "Enter your code first."
		return
	code.release_focus()
	DisplayServer.virtual_keyboard_hide()
	if game.online.session.request("redeem_code", {"code": value}) < 0:
		status.text = "Connection lost. Reconnect to check your bag."
		return
	submitting = true
	submit.disabled = true
	code.editable = false
	status.text = "Claiming your rewards…"

func response(message: Dictionary) -> void:
	if str(message.get("op", "")) != "redeem_code": return
	submitting = false
	submit.disabled = false
	code.editable = true
	if bool(message.get("ok", false)):
		code.text = ""
		status.text = str((message.get("data", {}) as Dictionary).get("reward_message", "Rewards are in your bag!"))
	else:
		status.text = str(message.get("error", "Could not redeem this code."))

func disconnected() -> void:
	submitting = false
	submit.disabled = false
	code.editable = true
	close()
