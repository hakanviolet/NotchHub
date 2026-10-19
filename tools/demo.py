#!/usr/bin/env python3
"""README görselleri ve video kaydı için demo sahnesi.

Kurulu NotchHub'ı durdurur, aynı uygulamayı ayrı bir sokette (NOTCH_SOCKET) ve NOTCH_DEBUG ile başlatır,
uydurma verili üç istemciyle sahneyi oynatır, bitince (ya da Ctrl-C ile) gerçek NotchHub'ı geri açar.
Gerçek istemciler (müzik, kullanım...) varsayılan sokete bağlı olduğu için demo sırasında yalnızca beklerler;
gerçek şarkı adları ya da rakamlar görüntüye girmez.

Kullanım:
  python3 tools/demo.py                     # GIF zaman çizelgesi, 3 tur
  python3 tools/demo.py --loops 0           # durdurana kadar tekrar
  python3 tools/demo.py --hold collapsed    # ekran görüntüsü için sabit sahne (Enter ile çık)
  python3 tools/demo.py --hold expanded
  python3 tools/demo.py --island            # çentiksiz ekran görünümü
  python3 tools/demo.py --lang tr           # Türkçe metinler
  python3 tools/demo.py --snapshot /klasör  # her adımda pencere görüntüsü al (doğrulama için)
"""
import argparse, json, os, socket, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = Path.home() / "Applications/NotchHub.app"
SOCK = "/tmp/notchhub-demo/hub.sock"
COVER = ROOT / "docs/demo/cover.png"
CTL = ROOT / ".build/notchctl"

TEXT = {
    "en": dict(song="Neon Horizon", artist="Lumen Drive", focus="Deep work", focus_sub="Session 2 of 4",
               dl="Downloading", dl_file="sdk-26.3.dmg", dl_left="1.2 GB of 2.4 GB"),
    "tr": dict(song="Neon Ufuk", artist="Lumen Drive", focus="Derin çalışma", focus_sub="4 oturumdan 2.",
               dl="İndiriliyor", dl_file="sdk-26.3.dmg", dl_left="2,4 GB'ın 1,2 GB'ı"),
}


class Client:
    def __init__(self, cid, name):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        for _ in range(50):   # hub açılana kadar bekle
            try:
                self.s.connect(SOCK)
                break
            except OSError:
                time.sleep(0.1)
        else:
            sys.exit("demo hub'ına bağlanılamadı")
        self.send({"type": "hello", "version": 1, "client": {"id": cid, "name": name}})

    def send(self, m):
        self.s.sendall((json.dumps(m) + "\n").encode())

    def update(self, a):
        self.send({"type": "activity", "activity": a})

    def end(self, aid):
        self.send({"type": "end", "id": aid})


def ctl(cmd):
    subprocess.run([str(CTL), cmd], check=False)


def music(t, playing=True):
    art = {"url": {"_0": COVER.as_uri()}} if COVER.exists() else {"symbol": {"_0": "music.note"}}
    return {
        "id": "now-playing", "title": t["song"], "subtitle": t["artist"],
        "leading": {"image": {"_0": art}},
        "trailing": {"bars": {"animated": playing, "tint": "red"}},
        "image": art,
        "buttons": [
            {"action": "previous", "symbol": "backward.fill"},
            {"action": "toggle", "symbol": "pause.fill" if playing else "play.fill", "prominent": True},
            {"action": "next", "symbol": "forward.fill"},
            {"action": "like", "symbol": "heart.fill", "tint": "red"},
        ],
        "progress": {"elapsed": 74, "total": 213, "rate": 1 if playing else 0, "at": time.time()},
    }


def focus(t, remaining, total=25 * 60):
    return {
        "id": "focus", "priority": 2, "title": t["focus"], "subtitle": t["focus_sub"],
        "leading": {"symbol": {"_0": "brain.head.profile", "tint": "orange"}},
        "trailing": {"text": {"_0": f"{remaining // 60}:{remaining % 60:02d}", "tint": "orange"}},
        "image": {"symbol": {"_0": "brain.head.profile"}},
        "buttons": [
            {"action": "reset", "symbol": "arrow.counterclockwise", "tint": "gray"},
            {"action": "toggle", "symbol": "pause.fill", "tint": "orange", "prominent": True},
            {"action": "skip", "symbol": "forward.end.fill", "tint": "gray"},
        ],
        "progress": {"elapsed": total - remaining, "total": total, "rate": 1, "at": time.time(), "tint": "orange"},
    }


def download(t):
    return {
        "id": "download", "priority": -1, "title": t["dl"], "subtitle": t["dl_file"],
        "leading": {"symbol": {"_0": "arrow.down.circle.fill", "tint": "blue"}},
        "trailing": {"text": {"_0": "50%", "tint": "blue"}},
        "image": {"symbol": {"_0": "arrow.down.circle.fill"}},
        "buttons": [{"action": "cancel", "symbol": "xmark", "tint": "gray"}],
        "progress": {"elapsed": 50, "total": 100, "rate": 0, "at": time.time(), "tint": "blue",
                     "startLabel": t["dl_left"], "endLabel": "2 min"},
    }


def start_hub(island):
    subprocess.run(["pkill", "-x", "NotchHub"], check=False)
    time.sleep(0.5)
    env = dict(os.environ, NOTCH_DEBUG="1", NOTCH_SOCKET=SOCK)
    if island:
        env["NOTCH_FORCE_ISLAND"] = "1"
    return subprocess.Popen([str(APP / "Contents/MacOS/NotchHub")], env=env, stdout=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--loops", type=int, default=3, help="tur sayısı, 0 = sonsuz")
    ap.add_argument("--hold", choices=["collapsed", "expanded"])
    ap.add_argument("--island", action="store_true")
    ap.add_argument("--lang", choices=TEXT, default="en")
    ap.add_argument("--snapshot", metavar="KLASÖR")
    args = ap.parse_args()
    t = TEXT[args.lang]

    if not APP.exists():
        sys.exit(f"{APP} yok; önce ./build.sh --install")
    if not CTL.exists():
        subprocess.run(["swiftc", "-o", str(CTL), str(ROOT / "tools/notchctl.swift")], check=True)

    shot_n = 0

    def shot(label):
        nonlocal shot_n
        if args.snapshot:
            shot_n += 1
            d = Path(args.snapshot) / f"{shot_n:02d}-{label}"
            d.mkdir(parents=True, exist_ok=True)
            time.sleep(0.6)   # animasyon otursun
            ctl(f"snapshot:{d}")
            time.sleep(0.8)   # bildirim hub'a ulaşıp dosya yazılsın

    hub = start_hub(args.island)
    try:
        player = Client("demo.music", "Music")
        timer = Client("demo.focus", "Focus")
        dl = Client("demo.downloads", "Downloads")
        time.sleep(1)

        if args.hold:
            player.update(music(t))
            timer.update(focus(t, 18 * 60 + 42))
            dl.update(download(t))
            time.sleep(0.5)
            if args.hold == "expanded":
                ctl("open")
            shot(args.hold)
            input("Sahne hazır. Çıkmak için Enter… ")
            return

        # Zaman çizelgesi: müzik → odak başlar (müzik baloncuğa) → açılır → kapanır, odak biter → başa.
        n = 0
        while args.loops == 0 or n < args.loops:
            n += 1
            player.update(music(t))
            dl.end("download")
            time.sleep(2.0)
            shot("music")

            remaining = 25 * 60
            timer.update(focus(t, remaining))
            for _ in range(3):   # metin istemci tarafında güncellenir, ilerleme hub'da akar
                time.sleep(1)
                remaining -= 1
                timer.update(focus(t, remaining))
            shot("focus")

            dl.update(download(t))
            ctl("open")
            time.sleep(3.0)
            shot("expanded")

            ctl("close")
            time.sleep(0.8)
            timer.end("focus")
            dl.end("download")
            time.sleep(1.2)
    except KeyboardInterrupt:
        pass
    finally:
        hub.terminate()
        hub.wait(timeout=5)
        subprocess.run(["open", str(APP)], check=False)   # gerçek NotchHub'ı geri aç
        print("Gerçek NotchHub yeniden başlatıldı.")


if __name__ == "__main__":
    main()
