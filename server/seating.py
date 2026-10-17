"""Native Chair/Sit requests and self/peer acknowledgements (no predicted seating)."""
from eo_session import EOError, Reader, number


class SeatingMixin:
    def sit(self, x=None, y=None):
        self._standing()
        me=self.state['self'];seated=int(me.get('sitting',0))
        family=8 if seated==1 or (not seated and x is not None) else 41
        payload=number(2 if seated else 1,1)
        if not seated and family==8:
            x,y=int(x),int(y)
            if not (0<=x<=251 and 0<=y<=251) or abs(me['x']-x)+abs(me['y']-y)!=1:
                raise EOError('Approach an open side of the chair first')
            payload+=number(x,1)+number(y,1)
        self.send(family,1,payload)
        self._wait_service(family,{14 if seated else 8})
        if bool(self.state['self'].get('sitting',0))==bool(seated):
            raise EOError('This chair is occupied or cannot be reached from that side')
        self.shop=None;self.bank=None;self.locker=None;self.chest=None
        self.casting=None
        return self.snapshot()

    def apply_seating_packet(self,f,a,p):
        if not ((f in (8,41) and a in (8,14)) or (f==41 and a==4)):return
        if len(p)!=(6 if a==8 else 4):raise EOError('Malformed native seating acknowledgement')
        r=Reader(p);pid=r.num(2);x=r.num();y=r.num()
        sitting=(1 if f==8 else 2) if a==8 else 0
        direction=r.num() if a==8 else None
        row=self.state['self'] if pid==self.player_id else next((c for c in self.state['characters'] if c['player_id']==pid),None)
        if not row:return
        row.update(x=x,y=y,sitting=sitting)
        if direction is not None:row['direction']=direction
        if pid==self.player_id:
            self.casting=None;self.position_update=True
            if self.pending_moves:self.position_seq=self.pending_moves[-1]['seq']
            self.pending_moves.clear();self.expect_walk_refresh=False
        self.events[-1].update(kind='seating',player_id=pid,sitting=sitting,x=x,y=y)
        self.dirty=True
