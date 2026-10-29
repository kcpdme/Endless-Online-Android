extends SceneTree
class Probe extends "res://scripts/online_session.gd":
	var queued:Array[Dictionary]=[]
	var polls:int=0
	func _drain()->void:
		polls+=1
		for message:Dictionary in queued:_consume_message(JSON.stringify(message))
		queued.clear()
	func _poll_tcp(_delta:float)->void:_drain()
	func _poll_websocket(_delta:float)->void:_drain()
var checks:int=0
var failed:bool=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func make_probe(ws:bool)->Probe:
	var probe:Probe=Probe.new();root.add_child(probe);probe.set_process(false);probe.connected=true;probe.websocket_mode=ws;return probe
func run()->void:
	for ws:bool in [false,true]:
		var probe:Probe=make_probe(ws);probe.pending[1]={"op":"ping","age":19.9};probe.queued.assign([{"id":1,"op":"ping","ok":true}]);probe._process(.2)
		check(probe.connected and probe.pending.is_empty() and probe.polls==1,"Queued heartbeat ACK wins over a slow-frame timeout")
		probe.pending[2]={"op":"trade_add","age":29.9};probe.queued.assign([{"id":2,"op":"trade_add","ok":true}]);probe._process(.2)
		check(probe.connected and probe.pending.is_empty(),"Queued trade ACK is consumed before request deadline")
		probe.pending[3]={"op":"ping","age":8.0};probe._process(.2)
		check(probe.connected,"Brief mobile stall does not trigger the old eight-second cutoff")
		probe.pending[3].age=20.1;probe._process(0)
		check(not probe.connected and probe.pending.is_empty(),"A genuinely unanswered heartbeat still closes within its bound")
		probe.queue_free()
		probe=make_probe(ws);probe.pending[4]={"op":"trade_agree","age":30.1};probe.queued.assign([{"event":"world","ok":true}]);probe._process(0)
		check(not probe.connected,"Unrelated world traffic cannot mask an unanswered trade transaction")
		probe.queue_free()
	print("TRANSPORT TOLERANCE: ",checks," checks, failed=",failed);quit(1 if failed else 0)
