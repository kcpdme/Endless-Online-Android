#!/usr/bin/env python3
"""Real EO v28 Init round trip. Verifies server challenge hash; no account is created."""
import argparse, json, socket

def encode(value, width):
    out = bytearray([254]*width)
    for i in range(width):
        if i == 0 or value:
            out[i] = value % 253 + 1
            value //= 253
    if value: raise ValueError('EO integer exceeds width')
    return bytes(out)

def decode(data):
    return sum(((1 if b == 254 else 128 if b == 0 else b)-1) * 253**i for i,b in enumerate(data))

def read_exact(sock, count):
    result = bytearray()
    while len(result) < count:
        part = sock.recv(count-len(result))
        if not part: raise RuntimeError('Server closed before a complete EO reply')
        result.extend(part)
    return bytes(result)

def handshake(host='127.0.0.1', port=8078):
    challenge = 12345
    # Init action/family are raw 255. Version fields and challenge use EO base-253 integers.
    payload = b'\xff\xff' + encode(challenge,3) + b''.join(encode(v,1) for v in [0,0,28,0,0]) + b'424242'
    packet = encode(len(payload),2) + payload
    with socket.create_connection((host,port),timeout=4) as sock:
        sock.sendall(packet)
        reply = read_exact(sock,decode(read_exact(sock,2)))
    if len(reply) != 12 or reply[:3] != b'\xff\xff\x02':
        raise RuntimeError(f'Not an accepted EO Init reply: {reply.hex()}')
    i = challenge+1
    expected = 110905 + (i%9+1)*((11092004-i)%((i%11+1)*119))*119 + i%2004
    actual = decode(reply[9:12])
    if actual != expected: raise RuntimeError(f'Challenge response mismatch: {actual} != {expected}')
    return {'result':'EO Init accepted','host':host,'port':port,'client_version':28,'challenge':challenge,
            'response':actual,'challenge_verified':True,'player_id':decode(reply[7:9]),
            'client_to_server_multiplier':reply[6],'server_to_client_multiplier':reply[5],
            'request_hex':packet.hex(),'response_hex':reply.hex(),
            'scope':'Initial handshake only; login, encrypted session, movement and combat are not tested.'}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--host',default='127.0.0.1');p.add_argument('--port',type=int,default=8078)
    a=p.parse_args();print(json.dumps(handshake(a.host,a.port),indent=2))
if __name__=='__main__':main()
