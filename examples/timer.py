#!/usr/bin/env python3
"""NotchHub'a Swift olmadan bağlanma örneği: çentikte geri sayan bir zamanlayıcı.
Kullanım: python3 examples/timer.py [saniye]   — "Durdur" düğmesine basınca biter."""
import json, os, socket, sys, time

SOCK = os.path.expanduser("~/Library/Application Support/NotchHub/hub.sock")
total = int(sys.argv[1]) if len(sys.argv) > 1 else 300

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(SOCK)
s.setblocking(False)
send = lambda m: s.sendall((json.dumps(m) + "\n").encode())

send({"type": "hello", "client": {"id": "ornek.zamanlayici", "name": "Zamanlayıcı"}})
start = time.time()
buf = b""
while True:
    left = max(0, total - int(time.time() - start))
    send({"type": "activity", "activity": {
        "id": "timer", "priority": 1,
        "leading": {"symbol": {"_0": "timer", "tint": "orange"}},
        "trailing": {"text": {"_0": f"{left // 60}:{left % 60:02d}", "tint": "orange"}},
        "image": {"symbol": {"_0": "timer"}},
        "title": "Çay demleniyor", "subtitle": f"{left // 60} dk {left % 60} sn kaldı",
        "buttons": [{"action": "stop", "symbol": "stop.fill", "tint": "orange", "prominent": True}],
        "progress": {"elapsed": total - left, "total": total, "rate": 1, "at": time.time()},
    }})
    try:
        buf += s.recv(65536)
    except BlockingIOError:
        pass
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        ev = json.loads(line).get("event", {})
        print("olay:", ev)
        if ev.get("action") == "stop":
            left = 0
    if left == 0:
        send({"type": "end", "id": "timer"})
        break
    time.sleep(1)
