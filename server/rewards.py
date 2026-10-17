"""Account coupons: only the native atomic grant acknowledgement changes the bag."""
import re
import time
from eo_session import EOError, Reader

FAMILY = 230
ERRORS = {
    1: 'That redeem code is not valid.',
    2: 'This account has already redeemed that code.',
    3: 'Rewards are unavailable right now. Close any trade and try again.',
    4: 'A reward would exceed your item limit. Make room before redeeming.',
}

class RewardsMixin:
    def redeem_code(self, code):
        self._standing()
        code = code.strip().upper()
        if not re.fullmatch(r'[A-Z0-9]{1,32}', code):
            raise EOError('Enter a redeem code using letters and numbers.')
        now = time.monotonic()
        if now - getattr(self, 'last_redeem', 0) < 1:
            raise EOError('Wait a moment before redeeming again.')
        self.last_redeem = now
        self.send(FAMILY, 1, code.encode('ascii') + b'\xff')
        payload = self._wait_service(FAMILY, {3}, timeout=5)
        status = Reader(payload).num()
        if status:
            raise EOError(ERRORS.get(status, 'The server could not redeem this code.'))
        result = self.snapshot()
        result['reward_message'] = 'Rewards claimed! 1,000 Big Health Potions, 50,000 Gold and Lens of Truth are in your bag.'
        return result

    def apply_reward_packet(self, family, action, payload):
        if (family, action) != (FAMILY, 3):
            return
        r = Reader(payload)
        if r.num() != 0:
            return
        if len(r.rest()) != 20:
            raise EOError('Invalid reward acknowledgement; reconnect to check your bag.')
        weight, maximum = r.num(), r.num()
        rewards = [(r.num(2), r.num(4)) for _ in range(3)]
        if [item for item, amount in rewards] != [375, 1, 421]:
            raise EOError('Unexpected reward acknowledgement; reconnect to check your bag.')
        for item, amount in rewards:
            self._set_amount(item, amount)
        self.weight, self.max_weight = weight, maximum
        self.stats.update(weight=weight, max_weight=maximum)
        self.dirty = True
