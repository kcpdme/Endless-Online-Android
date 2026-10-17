"""Original Arena_Use/Drop/Spec/Accept notifications; warps stay native-owned."""
from eo_session import Reader,EOError

def decode_arena(action,payload):
    r=Reader(payload)
    def delimiter():
        if r.take(1)!=b'\xff':raise EOError('Malformed arena delimiter')
    if action==10:
        count=r.num();result=dict(kind='arena_start',players=count,message=f'{count} players entered the arena.')
    elif action==24:result=dict(kind='arena_busy',message='Arena round delayed: players are still fighting.')
    elif action==16:
        pid=r.num(2);delimiter();direction=r.num();delimiter();kills=r.num(4);delimiter();killer=r.text();victim=r.text()
        result=dict(kind='arena_kill',player_id=pid,direction=direction,kills=kills,killer=killer,victim=victim,message=f'{victim} was eliminated by {killer}.')
    elif action==2:
        winner=r.text();kills=r.num(4);delimiter();killer=r.text();victim=r.text()
        result=dict(kind='arena_win',winner=winner,kills=kills,killer=killer,victim=victim,message=f'{victim} was eliminated by {killer}. {winner} wins the arena!')
    else:return None
    if r.rest():raise EOError('Unexpected arena payload')
    return result
