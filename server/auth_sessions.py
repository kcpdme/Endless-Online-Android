"""In-memory, single-use reconnect proofs. Never persist credentials or tokens."""
import secrets,threading

class AuthSessions:
    def __init__(self):self.lock=threading.Lock();self.sessions={}
    def issue(self,username,handler):
        token=secrets.token_urlsafe(32)
        with self.lock:self.sessions[username]=(handler,token)
        return token
    def resume(self,username,token,handler):
        if not token:return False
        with self.lock:
            previous=self.sessions.get(username)
            if not previous or previous[0] is handler or not secrets.compare_digest(previous[1].encode(),token.encode()):return False
            del self.sessions[username]
        previous[0].end_session()
        return True
    def forget(self,handler):
        with self.lock:
            for username,(owner,_) in list(self.sessions.items()):
                if owner is handler:del self.sessions[username]
