# NotchHub

**English** · [Türkçe](README.tr.md)

![NotchHub demo: a focus timer takes the notch wings while music moves to the bubble, then all activities expand as cards](docs/demo.gif)

A host app for the MacBook notch (or a Dynamic Island–style pill on screens without one).
Apps don't put their own windows in the notch. Instead they **describe what to show** and NotchHub draws it,
much like iOS Live Activities. Many apps can share the notch at once without ever drawing over each other.

- Each client is a separate process talking JSON over a Unix socket. A crashing client can't take others down.
- Swift apps use the bundled **NotchKit** library; any other language just writes JSON lines.
- Requires macOS 14+.

## What it looks like

- **Collapsed:** the top-priority activity sits on the notch's left and right wings (e.g. album art + audio bars,
  ⏱ + `4:59`). The second activity appears in a small bubble to the right.
- **Expanded:** activities become side-by-side cards (up to 3) with image, title, subtitle, progress bar and buttons.
- **Pulse:** an app can briefly expand a moment, like "new song started", for a few seconds.
- **No notch** (external display, or a resolution that hides the notch): a black island in the middle of the menu bar.

Open behavior is chosen from the NotchHub menu bar icon: **on hover** or **on click**.
The same menu lists connected apps and has "Launch at Login".

## Build and install

```bash
./build.sh            # builds build/NotchHub.app
./build.sh --install  # copies to ~/Applications and launches it
```

The app is ad-hoc signed, not notarized, so building from source is the recommended way to install.

## Connecting your app

### Swift (NotchKit)

`Package.swift`:

```swift
dependencies: [.package(url: "https://github.com/hakanviolet/NotchHub", branch: "main")],
targets: [.executableTarget(name: "MyApp",
                            dependencies: [.product(name: "NotchKit", package: "NotchHub")])]
```

```swift
import NotchKit

let notch = NotchClient(id: "com.example.timer", name: "Timer")
notch.onEvent = { e in if e.action == "stop" { /* ... */ } }

notch.update(NotchActivity(
    id: "timer", priority: 1,
    leading: .symbol("timer", tint: .orange),
    trailing: .text("4:59", tint: .orange),
    title: "Tea is brewing",
    buttons: [NotchButton(action: "stop", symbol: "stop.fill", tint: .orange, prominent: true)],
    progress: NotchProgress(elapsed: 1, total: 300, rate: 1)))

notch.pulse("timer")   // highlight for a few seconds
notch.end("timer")     // remove
```

`NotchClient` waits while NotchHub isn't running and connects automatically once it starts, resending its latest state.
Identical content isn't resent, and progress advances on the hub side via `rate`, so you don't need per-second updates.

### Any other language (protocol)

Unix socket: `~/Library/Application Support/NotchHub/hub.sock`, one JSON message per line.
Full example: [`examples/timer.py`](examples/timer.py).

| Direction | Message |
|---|---|
| → hub | `{"type":"hello","version":1,"client":{"id":"com.example","name":"Example"}}` (must be first) |
| → hub | `{"type":"activity","activity":{...}}` add or update |
| → hub | `{"type":"end","id":"timer"}` · `{"type":"pulse","id":"timer"}` |
| hub → | `{"type":"welcome","version":1}` reply to `hello` |
| hub → | `{"type":"event","event":{"activity":"timer","action":"stop","value":null}}` |
| hub → | `{"type":"error","code":"unsupported-version","message":"..."}` then the connection closes |

#### Versioning

`version` in `hello` is the protocol version your client was written against (currently `1`; omitted means `1`).
New fields and message types are added as optional without bumping the version, so **ignore fields and message
types you don't recognize**. The version only goes up for a change that would break existing clients; the hub then
rejects clients older than its minimum with `unsupported-version`. Swift clients get this for free:
`NotchClient.hubVersion` holds the hub's version and `onError` reports a rejection.

Activity fields (only `id` and `title` are required):

```json
{
  "id": "timer", "priority": 1, "title": "Tea", "subtitle": "4 min left",
  "leading":  {"symbol": {"_0": "timer", "tint": "orange"}},
  "trailing": {"text":   {"_0": "4:59",  "tint": "orange"}},
  "image":    {"url": {"_0": "https://..."}},
  "buttons":  [{"action": "stop", "symbol": "stop.fill", "tint": "orange", "prominent": true}],
  "progress": {"elapsed": 60, "total": 300, "rate": 1, "at": 1760800000, "seekAction": "seek"},
  "tapAction": "show"
}
```

- Wing items: `symbol`, `text`, `image` (`{"image":{"_0":{"url":{"_0":"..."}}}}`), `bars` (`{"bars":{"animated":true}}`).
- Images: `url`, `symbol` (SF Symbol name), `data` (base64 PNG/JPEG).
- Colors: `white red orange yellow green blue purple pink gray`.
- `at` is a Unix timestamp in seconds. With `seekAction`, clicking the bar sends the position in seconds as `value`.
- `progress` optionally takes `startLabel` / `endLabel` (durations are shown otherwise) and `tint` for the filled part.
- When a client disconnects, all of its activities are removed.

## Conflict rules

1. Ordering: higher `priority` first; ties go to the most recently updated (progress-only changes don't reorder).
2. Collapsed: the first activity takes the wings, the second the bubble; the rest appear only when expanded.
3. A pulsed activity becomes first for 3 seconds and expands as a single card.

## Debugging

Run with `NOTCH_DEBUG=1` to log connections and events to the terminal and enable the `tools/notchctl.swift`
commands: `open`, `close`, `snapshot:/folder`, `tap:<client>/<activity>/<action>`.
`NOTCH_FORCE_ISLAND=1` forces the island style even on a notched display.
`NOTCH_SOCKET=/path/hub.sock` runs the hub (and NotchKit clients) on a different socket.

`python3 tools/demo.py` plays a scripted scene with made-up data for screenshots and recordings. It runs a
separate hub on its own socket, so your real clients' data never shows up, and restores NotchHub when done
(`--hold expanded`, `--island`, `--lang tr`; see `--help`).

## Layout

- `Sources/NotchKit/` — protocol types and `NotchClient` (the library clients link against)
- `Sources/NotchHub/HubServer.swift` — Unix socket server
- `Sources/NotchHub/HubModel.swift` — activities and ordering
- `Sources/NotchHub/NotchGeometry.swift` — notch/island measurements and layout
- `Sources/NotchHub/NotchWindow.swift` — per-screen panel, mouse tracking, expansion
- `Sources/NotchHub/NotchViews.swift` — notch shape, wings, cards

Code comments are in Turkish.

## License

[MIT](LICENSE)
