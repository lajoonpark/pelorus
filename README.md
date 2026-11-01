# Lodestar

A lightweight macOS menu-bar app. Press a shortcut, and your Safari bookmarks appear in a
radial menu **at your cursor**. Point and click, or just press the number — your hands never
leave the keys and the cursor never leaves the page.

A *lodestar* is the star a navigator steers by: the fixed point you set a course to. Same idea
here, for your bookmarks. (Formerly "Safari Radial", then briefly "Pelorus".)

```
        ┌───────────────┐
        │   1  GitHub   │
   ┌────┴───┐       ┌───┴────┐
   │ 9  X   │   ✕   │ 2  HN  │
   └────┬───┘       └───┬────┘
        │  3  4  5  6  7 │
        └───────────────┘
```

- **⌘E** (configurable in Settings) opens the dial at the cursor, anywhere in macOS.
- **1–9** opens that slice immediately. ← / → page through the rest.
- **✕** in the centre, **Esc**, or the shortcut again closes it. A click anywhere outside
  also dismisses.
- Menu bar app only: no Dock icon, no background CPU when closed.

## The window

The manager window is a leather desk with one section at a time, switched from a brass tab bar
(⌘1–⌘4). It is deliberately sparse: each tab does one job.

<p align="center">
  <img src="docs/screenshots/dial.webp" alt="The Dial tab: the live compass beside the slot you are aiming at" width="760">
</p>

| Tab | What it is for |
| --- | --- |
| **Dial** | The real compass, live: it tilts toward the cursor, aims at a wedge on hover, opens a link on click. The text beside it follows the needle, with Open, Edit and Remove for that slot. `1`–`9` open a slot and `←` `→` turn the page. |
| **Library** | Every slot in dial order, grouped by page. Drag a row onto another to move it there; search to filter (reordering waits until you clear it). |
| **Import** | Safari import and its Full Disk Access permission in one place. It shows a dry run first (what is new, what is already on your dial), then fills the slots on screen. |
| **Settings** | Shortcut, which browser links open in and how (go to an open tab, or a new tab you stay on or switch to), dial size (with a live preview) and startup. |

Each slot can override that default. In its Edit sheet (or right-click it in the Library), pick
**Go to open tab**, **New tab, stay here** or **New tab, switch to it**. Go to open tab can match
just the exact page or any page on the site, and falls back to a new tab when nothing is open.
Slots with their own behaviour carry a small brass glyph in the Library.

Adding a link is the floating **+** (⌘N), which opens into a small form and offers a link from
your clipboard. The menu-bar item offers the same thing as a quick panel.

<p align="center">
  <img src="docs/screenshots/library.webp" alt="The Library tab" width="380">
  <img src="docs/screenshots/import.webp" alt="The Import tab" width="380">
</p>

## Why this design

**Swift + AppKit, not Electron.** The app is small and idles at essentially zero CPU. A
radial menu lives or dies on how quickly it appears, and a native `NSPanel` shows up in a
frame or two. Electron would add ~150 MB of runtime to animate a circle.

**A radial, not a list.** The point is that the target doesn't move: the ring is anchored to
where your cursor already is, so opening it costs no mouse travel. Slices are laid out
clockwise from 12 o'clock so slice 1 is always in the same place relative to the pointer.

**Nine slices per page.** Ten or more and the wedges get too narrow to read at a glance, and
single-digit number keys run out. Beyond nine, arrow keys page.

**Order is the product.** Slice numbers are muscle memory, so importing from Safari never
reshuffles what you already have: existing links keep their position and only new ones are
appended. You can drag rows in the Library to reorder them.

## Two things worth knowing before you build

### 1. Safari bookmarks need Full Disk Access

There is no public, sandbox-safe API for another app to read Safari's bookmarks. Safari
keeps them in `~/Library/Safari/Bookmarks.plist`, behind TCC. The honest answer to your
question: **yes, it works, but only with Full Disk Access**, which the user grants manually
in System Settings › Privacy & Security › Full Disk Access.

So the app:

- Reads and parses the plist directly (`WebBookmarkTypeLeaf` / `TypeList` / `TypeProxy`
  tree, including nested folders and Safari's synthetic roots).
- Detects the permission failure specifically and offers a button that opens the right
  settings pane, instead of a generic "couldn't read file".
- Never blocks on it. You can add and manage bookmarks entirely by hand, and the app's own
  store (`~/Library/Application Support/Lodestar/bookmarks.json`) is the source of
  truth. Safari is an import source, not a live dependency.
- Skips the Reading List (those are "leaves" too, but not bookmarks you'd want in a radial).

**Full Disk Access is optional.** It is the only thing that unlocks the Safari import. The
dial, the manager, reordering, every setting and the shortcut all work without it, and the
onboarding screen says so plainly before asking.

**Ad-hoc signing caveat:** Full Disk Access is granted to a specific code signature. With
`./scripts/build.sh`'s default ad-hoc signing, every rebuild changes that signature and macOS
silently revokes the grant. If you're iterating, sign with a Developer ID, or re-grant after
rebuilds. This is a macOS policy, not something the app can work around.

### 2. The default shortcut is ⌘E, not ⌘R

⌘R is Safari's reload, and a Carbon global hot key is delivered *before* the frontmost app
sees the key — so registering ⌘R would quietly break reloading pages. The default is **⌘E**
instead, because ⌘E is not taken anywhere important and it avoids that trade-off entirely.

⌘E does shadow Safari's View › Use Selection for Find. That is minor and fully recoverable, so
the Settings pane names the owner and severity of any clash and offers a one-click escape to
**⌃⌘E**. Preferences written by an older build on the ⌘R default are migrated to ⌘E once;
any shortcut you pick yourself, including deliberately going back to ⌘R, is left alone.

### Why not a Safari extension?

You mentioned it as an option. It can't do the core interaction: a Safari extension cannot
receive a key command while Safari isn't focused, and it cannot draw an overlay over other
apps. The global-hotkey-plus-overlay part has to be a real app. A thin extension would still
be useful later — purely to read bookmarks via the WebExtensions `bookmarks` API without
Full Disk Access — and that's in the roadmap, not in this version.

## Build and run

Requires macOS 14+ and Xcode (or the Command Line Tools).

```bash
git clone <this-repo>
cd Safari-Bookmarks-Radial

swift test              # unit tests for the portable core
./scripts/build.sh --run
```

`build.sh` compiles, assembles `build/Lodestar.app` with an `Info.plist`
(`LSUIElement`, so no Dock icon), and ad-hoc signs it. `--install` copies to `/Applications`.

**Coming from Safari Radial or Pelorus?** The app's data folder moved to `Lodestar`.
The first launch copies your slots and settings across and leaves the old folder untouched, so
it is safe to delete once you are happy. The bundle ID changed too, so macOS treats this as a
new app: grant Full Disk Access again, turn "Open at login" off and on once, and remove the old
`SafariRadial.app` or `Pelorus.app` (and its entries under Full Disk Access and Login Items).

First run:

1. A short tour opens, with the live compass in it. The ring icon appears in the menu bar.
2. Add a link with the **+** button, or open the **Import** tab. If macOS blocks the read,
   click **Open Full Disk Access**, add the app, and come back: the lock opens by itself.
3. Press **⌘E** anywhere.

<p align="center">
  <img src="docs/screenshots/onboarding.webp" alt="The first-run tour" width="760">
</p>

If you'd rather build in Xcode: `open Package.swift`, select the `Lodestar` scheme, run.
Note that running from Xcode/`swift run` gives you an unsigned binary, which macOS treats as
a different app for TCC purposes — grant Full Disk Access to the built `.app` rather than to
Xcode's runner.

## Project layout

```
Sources/
  RadialCore/            portable Swift, no AppKit — fully unit tested on any platform
    RadialLayout.swift       slice geometry, hit testing, paging
    RadialSession.swift      the open/close/activate state machine
    BookmarkStore.swift      ordering, merge-without-reshuffle, JSON persistence
    SafariBookmarksReader.swift  plist parsing + permission errors
    HotkeySpec.swift         shortcut model, display names, validity
    HotkeyConflicts.swift    warns when a shortcut shadows a system one
    Bookmark.swift           URL normalisation, display fallbacks
    Preferences.swift        settings
  Lodestar/          the macOS app
    main.swift               NSApplication bootstrap
    AppDelegate.swift        menu bar item, windows, wiring
    GlobalHotkey.swift       Carbon RegisterEventHotKey (no Accessibility prompt)
    RadialPanel.swift        non-activating full-screen overlay
    RadialMenuView.swift     drawing + spring animations
    RadialController.swift   panel lifecycle, keyboard routing
    Animation.swift          spring integrator + frame driver
    BookmarkManagerView.swift  the tabbed window shell (Dial / Library / Import / Settings)
    ManagerTabs.swift          tab enum, router, brass tab bar
    BrassUI.swift              motion springs, pointer light, brass toggle/segmented/slider
    LiveCompass.swift          the overlay compass, embedded in the window (and the dial's keys)
    DialTabView / LibraryTabView / ImportTabView / SettingsView / AddComposer
Tests/RadialCoreTests/  unit tests for everything in RadialCore
preview/                 browser harnesses for the look: compass-preview.html (the instrument)
                         and manager-preview.html (the tabbed window, with its motion)
docs/screenshots/        README images
scripts/build.sh        .app assembly + signing
```

The split is deliberate: everything with rules lives in `RadialCore` and is tested
(`swift test` runs on Linux and macOS alike), while the AppKit layer only handles pixels and
input. That keeps the geometry and the "press the shortcut twice to close" behaviour
verifiable rather than only checkable by hand.

## Interaction details

| Input | Result |
| --- | --- |
| Shortcut | Open at cursor, or close if open |
| `1`–`9` | Open that slice of the current page |
| `←` / `→` | Previous / next page (wraps) |
| `Esc` | Close |
| Click centre ✕ | Close |
| Click outside | Close |
| Drag off a slice, release | Cancels that activation |

In the manager window:

| Input | Result |
| --- | --- |
| `⌘1` … `⌘4` | Dial, Library, Import, Settings |
| `⌘,` | Settings |
| `⌘N` | Add a link |
| `1`–`9`, `←` `→` (on the Dial tab) | Open a slot, turn the page |
| Drag a Library row onto another | Move it into that slot |

Opening overshoots slightly and settles (spring, not an easing curve). Hovering lifts a
slice, widens its wedge, brightens its gradient, and rotates the centre ✕ 45°. Pressing
pushes the slice inward. The frame driver stops entirely when nothing is moving, so the app
is idle when the menu is closed.

The lid is the one thing that is not a spring. It is a brass pan with a milled wall, a shoulder,
a cover on the outside and an engraved plate on the inside, hung on a hinge pin, and it is
animated by a small physical model (`RadialCore/LidHinge.swift`): it is flicked, slows as it goes
over the top, falls onto its stop with a little bounce that taps the case, and is pushed shut
on the way out. Because it is a real mesh swung on a real pivot, it shows its cover, turns
edge-on and shows its inside as it opens, and the pointer cannot reach the card until it has
cleared. `preview/compass-preview.html` renders the same lid in a browser (`?freeze=deg`,
`?at=ms` and `?closeat=ms` capture single frames of it).

The animations are springs integrated per frame rather than `NSAnimationContext` curves,
because the menu must respond to a pointer that can change its mind mid-animation: hovering
a second slice retargets the spring from its current value and velocity, with no restart and
no snap.

## Permissions this app asks for

| Permission | Why | When |
| --- | --- | --- |
| Full Disk Access | Read `~/Library/Safari/Bookmarks.plist` | Only for "Import from Safari"; everything else works without it |
| Automation (Apple Events) | Open a link in the *current* Safari tab or a new window | Only if you choose those targets; new-tab mode uses `NSWorkspace` and asks for nothing |

It deliberately does **not** ask for Accessibility: the shortcut uses Carbon's
`RegisterEventHotKey`, and the overlay handles its own clicks, so no event tap is needed.

## Roadmap

- Read bookmarks via a Safari web extension (WebExtensions `bookmarks` API) to avoid Full
  Disk Access entirely.
- Search-as-you-type: start typing after the menu opens to filter, with numbers reassigned
  to the results.
- Non-Safari sources (Chrome, Arc, Raindrop) behind the same `BookmarkStore` interface.
- Actions beyond URLs, since the radial is really a generic launcher ("open my dev server",
  "start a timer").

## License

MIT. See `LICENSE`.
