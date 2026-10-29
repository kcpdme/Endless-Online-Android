"""Run preference is acknowledged and charged by the native world."""
import time
from eo_session import EOError, Reader, number


class RunningMixin:
    def set_running(self, enabled):
        from balance_rules import profile
        if type(enabled) is not bool: raise EOError('Run mode must be enabled or disabled')
        if not self.state or not self.state.get('self'): raise EOError('Enter the world before changing Run mode')
        if not profile().get('running_rules'): raise EOError('Running is unavailable on this server')
        if enabled and (self.stats.get('dead') or self.stats.get('tp', 0) <= 0): raise EOError('You need TP to run')
        self.send(6, 10, number(int(enabled), 1))
        deadline = time.monotonic()+3
        while time.monotonic() < deadline:
            payload = self.wait(6, 10, timeout=max(.1, deadline-time.monotonic()))
            reader = Reader(payload)
            if reader.num(2) != self.player_id: continue
            if bool(reader.num()) != enabled: continue
            return self.snapshot()
        raise EOError('The server did not confirm Run mode')

    def apply_run_packet(self, family, action, payload):
        if (family, action) != (6, 10): return False
        if len(payload) != 7: raise EOError('Truncated native Run state')
        r = Reader(payload)
        pid, enabled, tp, speed = r.num(2), r.num(), r.num(2), r.num(2)
        if enabled not in (0, 1) or speed not in (1000, 1250, 1500): raise EOError('Invalid native Run state')
        multiplier = speed/1000
        if pid == self.player_id:
            self.running_enabled = bool(enabled)
            self.running_multiplier = multiplier
            self.stats['tp'] = tp
            if self.state: self.state['self']['tp'] = tp
        elif self.state:
            for row in self.state['characters']:
                if row['player_id'] == pid:
                    row['running'] = bool(enabled)
                    row['move_seconds'] = round(.42/multiplier, 4)
        self.events.append(dict(kind='run_state', player_id=pid, enabled=bool(enabled), multiplier=multiplier))
        self.dirty = True
        return True
