extends RefCounted
## Bounded recovery of one verified account/character; credentials stay in memory.
const DELAYS: Array[float] = [1.0,2.0,4.0]
const LIMIT_SECONDS: float = 30.0
var online: Node
var panel: Control
var status: Label
var credentials: Dictionary = {}
var character_id: int = 0
var character_name: String = ""
var running: bool = false
var awaiting: bool = false
var attempts: int = 0
var elapsed: float = 0.0
var started_at: int = 0
var wait_seconds: float = 0.0

func build(owner: Node, parent: Control) -> void:
	online = owner
	panel = online.game._modal(parent,Vector2(640,300))
	panel.color = Color("091719")
	var card: Control = panel.get_child(0)
	online.game._label(card,"Connection lost",Vector2(30,26),30,online.game.GOLD)
	status = online.game._label(card,"",Vector2(30,88),22)
	status.size = Vector2(580,100); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online.game._button(card,"Return to login",Vector2(30,218),Vector2(580,56),func() -> void:online._on_closed("Reconnect cancelled. Please log in again.",false),true)
	panel.hide()

func can_retry() -> bool:
	return not credentials.get("password","").is_empty() and character_id > 0 and not character_name.is_empty()

func lost() -> bool:
	if not can_retry(): return false
	if not running: attempts = 0; elapsed = 0.0; started_at = Time.get_ticks_msec()
	if attempts >= DELAYS.size() or elapsed >= LIMIT_SECONDS: return false
	running = true; awaiting = false; wait_seconds = DELAYS[attempts]
	online.panel.hide(); panel.get_parent().move_child(panel,-1); panel.show()
	status.text = "Reconnecting… (%d/%d)\nTrying to restore your session." % [attempts+1,DELAYS.size()]
	online._set_status("Connection lost. Reconnecting…")
	return true

func process(delta: float) -> void:
	if not running: return
	elapsed = maxf(elapsed+delta,(Time.get_ticks_msec()-started_at)/1000.0)
	if elapsed >= LIMIT_SECONDS:
		online._on_closed("Could not reconnect. Please log in again.",false); return
	if awaiting: return
	wait_seconds -= delta
	if wait_seconds > 0: return
	attempts += 1; awaiting = true
	status.text = "Reconnecting… (%d/%d)\nPlease wait, or return to login." % [attempts,DELAYS.size()]
	online._retry_connection()

func entered(player: Dictionary) -> void:
	character_id = int(player.get("character_id",0)); character_name = str(player.get("name",""))

func restored() -> void:
	running = false; awaiting = false; attempts = 0; elapsed = 0.0
	panel.hide()

func forget() -> void:
	running = false; awaiting = false; attempts = 0; elapsed = 0.0
	credentials.clear(); character_id = 0; character_name = ""
	if panel != null: panel.hide()
