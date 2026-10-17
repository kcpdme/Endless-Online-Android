"""Original quest-NPC dialogue, including Wise Man's native class/karma quest."""
from eo_session import EOError, Reader, number
from skills import npc_types


class QuestsMixin:
    quest_dialog=None
    quest_context=None

    def quest_open(self,npc_index,quest_id=0):
        self._standing();npc_index,quest_id=int(npc_index),int(quest_id)
        npc=next((n for n in self.state['npcs'] if n['index']==npc_index),None)
        if not npc or npc_types().get(npc['id'])!=15:raise EOError('Select a nearby quest NPC')
        if not 0<=quest_id<253**2:raise EOError('Invalid quest')
        context=dict(npc_index=npc_index,npc_id=npc['id'],map_id=self.state['map_id'],x=npc['x'],y=npc['y'])
        self._near_service(context)
        if quest_id:
            old=self.quest_dialog
            if not old or old['npc_index']!=npc_index or quest_id not in [q['id'] for q in old['quests']]:raise EOError('Choose one of this NPC’s offered quests')
        self.quest_dialog=None;self.quest_context=context;self.inn=None
        try:
            self.send(50,10,number(npc_index,2)+number(quest_id,2));self._wait_service(50,{34})
            if not self.quest_dialog:raise EOError('This NPC has no available conversation')
        except EOError as exc:
            self.quest_context=None;self.quest_dialog=None
            raise EOError('This NPC has no new quest dialogue right now. Finish the current quest objectives or talk to its starting NPC.') from exc
        except Exception:
            self.quest_context=None;self.quest_dialog=None
            raise
        self.shop=None;self.bank=None;self.locker=None;self.chest=None;self.skillmaster=None
        return self.snapshot()

    def quest_reply(self,action=None):
        self._standing();self._near_service(self.quest_context)
        dialog=self.quest_dialog
        if not dialog:raise EOError('Open this NPC’s conversation first')
        if action is not None:
            action=int(action)
            if not 0<action<=251 or action not in [link['id'] for link in dialog['links']]:raise EOError('Choose an offered dialogue option')
        payload=b''.join(number(dialog[k],2) for k in ('session_id','dialog_id','quest_id','vendor_id'))
        payload+=number(1 if action is None else 2,1)+(number(action,1) if action is not None else b'')
        self.send(50,2,payload)
        # Original closes this page; only a new native Dialog may open another.
        # Terminal actions can send class/karma updates without another Dialog.
        self.quest_dialog=None;self.dirty=True
        return self.snapshot()

    def quest_close(self):
        # Original Cancel/X does not send an OK or choose a link.
        self.quest_dialog=None;self.quest_context=None
        return self.snapshot()

    def apply_quest_packet(self,f,a,p):
        if (f,a)==(50,34):
            context=self.quest_context
            if not context or not self.state or context['map_id']!=self.state['map_id']:return
            r=Reader(p);count=r.num()
            data=dict(vendor_id=r.num(2),quest_id=r.num(2),session_id=r.num(2),dialog_id=r.num(2))
            if not 0<count<=100 or r.take(1)!=b'\xff':raise EOError('Malformed native quest header')
            data.update(quests=[dict(id=r.num(2),name=r.text()) for _ in range(count)],pages=[],links=[])
            while r.rest():
                entry=r.num(2)
                if entry==1:data['pages'].append(r.text())
                elif entry==2:data['links'].append(dict(id=r.num(2),text=r.text()))
                else:raise EOError('Unknown native dialogue entry')
            if data['quest_id'] not in [q['id'] for q in data['quests']]:raise EOError('Native quest title is missing')
            self.quest_dialog=dict(context,**data);self.dirty=True
        elif (f,a)==(35,13):
            self.events[-1].update(kind='quest_hint',message=p.decode('latin1'));self.dirty=True
        elif (f,a) in ((42,18),(42,3)):
            self.dirty=True
        elif (f,a)==(14,11):
            r=Reader(p);item_id=r.num(2);remaining=r.num(4);weight=r.num()
            self._set_amount(item_id,remaining);self.weight=weight;self.stats['weight']=weight;self.dirty=True
