# Newton Library

A Mac app for organising Apple Newton software, a bit like iTunes for Newton
packages. Runs on macOS 12 Monterey and later. Written by Matt Hare and AI agent Claude.

## Using it

- **Adding packages:** drag `.pkg` files, or whole folders of them, onto the
  window. You can also use **File > Add to Library…** (⌘O) or the **+**
  button. Each package is read, and a copy goes into your library folder,
  filed as `Developer / Kind / Title / file.pkg`. Packages in MacBinary (as
  old Mac archives and downloads often left them) are read too, and the
  library keeps just the package. (A developer folder that's
  already there under another spelling, like "Apple Computer, Inc." for
  "Apple Computer Inc.", is used rather than making a second one.)
  Files that aren't Newton packages are skipped. A package that's already in
  the library (the same file, whatever its name) isn't added twice; it's
  selected instead.
- **Archives:** drop a zip, StuffIt (`.sit`, `.sea`), BinHex (`.hqx`),
  `.tar`, `.gz`, 7-Zip, RAR or other archive, or a folder with archives in
  it, and the archive is opened and the packages inside are added (archives
  inside archives too, four deep). Nothing else in the archive is kept, and
  the archive itself is left as it was. This uses `unar`, The Unarchiver's
  command-line tool: install it with `brew install unar`. Without it, only zip
  files can be opened.
- **Runs on:** the **Runs on** row under Newton OS in the sidebar has two
  menus, from one version to another. It lists the packages that work on every
  version in that range: their Min OS is no newer than the first, and their
  Max OS (if known) no older than the last. Choose the same version twice
  (2.1 to 2.1) to see everything that runs on one Newton. Choose **Any** on
  one side to check only the other: "2.0 to Any" lists packages whose Min OS
  is 2.0 or older, "Any to 2.2" those whose Max OS is 2.2 or newer (or has no
  known limit).
- **Browsing:** the sidebar filters by Newton OS version, by kind
  (applications, games, books, sounds, extensions, system updates, drivers…) and by
  developer. The search field searches titles, developers, package names,
  copyright lines, languages and your notes. Click a column heading to sort.
- **Details:** the pane on the right summarises the selected package: its
  icon, package name and signature, copyright, version, creation date, parts,
  the Newton protos it uses, and why it was given its Newton OS version. A
  pencil marks anything you've changed.
- **Get Info (⌘I):** opens a window with every field read from the package,
  all editable: title, developer, author, language, kind, minimum and maximum Newton OS,
  version, creation date, copyright, package name, signature, Extras name, app symbol, ISBN and
  notes. For Kind you can also choose **New Kind…** and type your own, such
  as "Game" or "Utility"; kinds you make get their own place in the sidebar
  and appear in the Kind menu from then on. **Save** keeps your changes, **Cancel** closes without saving. A
  changed field gets a ↺ button that puts back what was read from the
  package, and **Use Package Values** puts back everything. The window also
  opens by itself when you drop a single package. Your changes are kept in
  the library; the package file itself is never changed.
- **Changing several at once:** with several packages selected, the details
  pane lets you set the minimum or maximum Newton OS, the kind (including a
  new one) or the developer for all of them.
- **Window layout:** the window's size and place, the widths of the sidebar
  and details pane, whether the sidebar is hidden, and the list's column
  widths are remembered and put back the next time the app opens (macOS's own
  window restoring is off when "Close windows when quitting an application"
  is set, and never covers panes or columns).
- **Add-ons in the list:** when the sidebar shows Applications, Games or
  another kind of application, a package with add-ons has a triangle beside
  its title. Click it to show its add-ons (sounds, decks, plug-ins…)
  indented under it, and again to hide them; they start hidden. An add-on
  that's an application itself (like PocketMoney's ExCHANGE) is listed under
  its main package rather than on its own. Select any mix of packages and
  their add-ons (⌘-click, ⇧-click) to drag them out, get their details or
  change them together.
- **Dragging out:** drag packages from the list (one or several) onto the
  Finder to copy them, or onto another app, such as the Einstein emulator to
  install them. The library keeps its own copies. (Dropping them back on the
  list does nothing.)
- **Removing:** press Delete, or click the trash button. You can remove the
  package from the library only, or also move its copy to the Trash. A
  folder that's left empty goes to the Trash with it, and so does each
  folder above it that's then empty, up to (but not including) the library
  folder.
- **Missing files:** **Library > Check for Missing Files** looks for every
  package's file. Any that can't be found are listed under **Missing** in the
  sidebar (and nowhere else), and the folders in the library folder they were
  in are removed if that leaves them empty, along with the folders above them
  up to the library folder. The same is done quietly each time the app
  opens. Add the file to the
  library again, from wherever it is, and the package goes back where it
  belongs, keeping everything you'd set for it.
- **Icons:** Newton icons are shown on a tile the green of a MessagePad 2100's
  backlight. Change the colour under **Icon background** in Preferences
  (**Reset** brings the green back).
- **Preferences (⌘,):** choose the library folder. The default is
  `~/Documents/Newton Packages`. If you change it, packages already in the
  library stay where they are until you click **Copy Them into This Folder**.
- **Library menu:** **Re-read All Packages** reads every package again, for
  example after the app is improved; your own edits are kept. **Organize
  Library Folder** files every package in the library folder into its
  Developer / Kind / Title folder (useful for packages added before the app
  did this).

When the library has different versions of the same package (the same
developer, kind and title), each version gets its own folder, named with
its version: `Sean Luke / Application / Hemlock 1.2.2` and `… / Hemlock 2.1`.
Copies of the same version share a folder, and when only one version is
left its folder goes back to the plain title. (The version is the one shown
in the list, so packages whose versions aren't known apart stay together.)

When you change a package's developer, kind, title or version, its file
moves to the matching folder, and folders left empty are removed. Characters that can't go
in folder names (`/` and `:`) become `-`.

You can also drop packages on the Dock icon, or use **Open With > Newton
Library** in the Finder. The exception is a `.pkg` file downloaded from the
internet: macOS treats it as a Mac installer and blocks opening it that way.
Dragging such files onto the window always works.

## Games

An application is classed as a **Game** when it shows signs of being one:

- **Strong signs:** "New Game", "Game Over", "High Scores" or "Play Again",
  or names in its code like `newGame`, `gameOver` or `highScores`. One is
  enough.
- **Weak signs:** "You Win", "You Lose", "Your Turn" or "Congratulations".
  It takes two.

Phrases only count in short strings, as on a button, a label or an alert,
not in long text: a novel or a help screen can say "you won't need to…"
without being a game. Common words like "score" or "player" don't count,
since help books and utilities use them too. The details pane says which
signs were found. Only applications can be games: an extension that belongs
to a game (sounds, card decks, game data) stays an extension, but it's
listed with its game and stored in the game's folder.

Some games show none of these signs (puzzle apps like crosswords, or a flight
simulator): set their kind to Game with Get Info.

## Sounds

A package that's mostly sound is classed as a **Sound**. Newton packages label
their data by type, and two types are sound: `samples`, the recorded audio
inside every Newton sound, and `modFile`, the music modules ModPlayer plays.

- Newton sound data making up at least half of an extension or data package,
  or nearly all (90%) of an application. Applications built around sound,
  like a guitar tuner or a tricorder, are usually 60–85% sound and stay
  applications; games stay games.
- A music module making up at least half of any package (the music modules
  are applications in form, but each is almost all music).

A sound pack that goes with a game or app (NewtHack Sounds, Columns Sound)
is still listed with it and stored in its folder. The details pane shows how
much of the package is sound.

## E-books

Many Newton books are small applications with their own reader (made with
Paperback and other book makers) rather than Newton books. When one string
of text makes up at least 40% of an application, it's classed as a **Book**.
Real applications don't come close: in a test of 3,000 packages none went
above a third, while most of these e-books are over half text.

## Languages

Each package's language is worked out from its own text, using macOS's
language recogniser. The strings in it that read like sentences (a few words,
or 20 letters or more) are each recognised on their own, and those the
recogniser is fairly sure of count by their number of letters; a language
needs a clear majority, of at least 100 letters. So the three Avi's Backdrop
1.30 packages show German, English and French, though they share a name,
title and version. Strings are judged one at a time because packages often
hold a few words in many languages (Avi's Backdrop has "Birthdays" in six,
and a menu of language names), and lists of names or places (mostly
capitalised words, like a book of ZIP codes) are left out, since they read as
almost any language. A package with too little text (many small extensions,
fonts and drivers) shows no language; set it in Get Info if you like.

## Developers

The developer comes first from the **signature** in the package name, the
part after the colon ("Mahjongg:Scrawl" gives Scrawl): the name developers
registered with Apple. When the copyright holder (or a book's author) is a
fuller form of the signature, that's used instead:

- the signature is how the name starts from one of its words:
  "TeleTypesetting" → TeleTypesetting, Inc.; "Tactile" → Tactile Systems, Inc.;
  "seanl" → Sean Luke;
- or its initials, or the initials of some of its words: "ICS" →
  Innovative Computer Solutions; "SAS" → Ben Gottlieb & Stand Alone Software;
- or its letters in order, each capital starting a word: "CVis" →
  Coherent Visual; "JoBS" → Joachim Bondo Schultz;
- or it contains one of the name's distinctive words: "ChrisDopp" →
  Christopher Dopp (but not common ones like "Software" or "Systems").

Otherwise the signature is used as it is. A package with no signature gets
the book's author, else the copyright holder.

From the copyright line, the holder is:

- what follows the last ©, "(c)", "Copyright" or "Copyleft" (with several
  holders, the last), or what follows the years when the line starts with
  them ("1994-1996 MAR Software."). "@1997" and "_1998" count as ©;
- up to "All rights reserved" (or "Alle Rechte vorbehalten"…), three
  spaces or a new line, since credits and serial numbers often follow;
- without the years ("1995-7", "'96, '97"), versions, prices, phone numbers,
  e-mail and web addresses, or credits after the name ("Netstrategy
  Software, by Les R. Titze"; "…, Portions Apple Computer"). "Someone for
  Company" gives the company, and an e-mail address alone is kept;
- with no copyright, a credit gives the name ("Built by V. Rehorst, code
  by…" gives "V. Rehorst").

## Titles

Titles are tidied: put on one line ("Voice Notes", not two lines as in the
Extras drawer), without decorations ("•  NanoCAD 1.0  •", "*QP*", quotation
marks), file extensions ("GOETZE01.TXT"), the developer's signature
("BikePower:Source") or underscores.

## Packages that belong together

Add-ons (sounds, card decks, game data, extra modules) are linked to the
package they're for. The detail pane and Get Info show a **Related Packages**
section: "Add-on for…" with a link to the main package, the add-ons a package
has, and "Needs …, which isn't in your library" when an add-on is for an app
you don't have. Click a package there to select it. In the list, add-ons have
a link mark after their title. An add-on's file is stored in its main
package's folder, and moves there by itself when the main package is added
later (or back to its own folder if the main package is removed).

Newton packages refer to each other by registered names ("Name:Signature",
like `NewtHack:ChrisDopp`), so the links are worked out like this:

| Clue | Example |
|---|---|
| A package mentions another's package name or app symbol | NewtHack Sounds puts its sounds in `NewtHack:ChrisDopp`, NewtHack's app symbol |
| …or a longer name ending in it | the Solito DX decks use `Extras:SoloDx:Tactile` |
| An add-on and exactly one app look up the same name | the Infocom games leave their data in `zparse:Gmad`, which YAZI reads |
| …or use the same soup, named like a registered name | the Dell puzzle packs add their puzzles to the soup `DELLCW:BBANDCO`, which Dell Crosswords reads |
| A package defines a global, under its developer's registered name, that one of the developer's apps reads (even if it's an app itself) | SoundPak defines `AddedSounds:ALLAN` (with DefGlobalVar), the extra sounds AlarmPak 2.0 reads |
| Probably: an add-on's name starts with an app's name, same signature | Columns Sound and Columns |
| Probably: an add-on shares a registered name with exactly one app | Demo and Motile share `MoData:Tactile` |

Of two linked packages, the main one is the application rather than the
add-on, else the one with more links; but where an add-on names one of them
itself, that one (so a set of gesture scripts that names every app it
launches isn't their main package). Names shared by several unrelated apps
(like a shareware registration add-on several games use) don't link them,
and nor does a global that's some other package's registered name, or one an
app defines too (its own registry of plug-ins).

Versions of the same package (the same package name and kind) are never
linked to each other, and neither are two applications from different
developers (different signatures) that name each other: that's one working
with the other, not an add-on. Avi's Backdrop names MoreInfo because it can
show MoreInfo's data, and a registration app names the dozen apps it
registers, but none of them belongs to the other. When a package names something several versions in
the library share (two PocketMoneys are both "PocketMoney:VtHick"), it goes
with the version made nearest in time: with PocketMoney 2.16 and 3.05 both
in the library, each version's reports and its ExCHANGE go with it, and each
version gets its own folder; with AlarmPak 1.4.2 and 2.0b9, each manual goes
with its own AlarmPak. Of two applications that name each other and are
equally linked (PocketMoney and ExCHANGE), the bigger is the main one.

To change a link, select one or more packages and choose **File > Set Main
Package…** (⇧⌘M, or the button in the details pane): Automatic (what was
found), None (they stand alone), or any other package in the library, found
by typing part of its name. Get Info's **Main package** row opens the same
chooser.

## The version number

A package's header holds its version as one whole number, so developers
often wrote "1.2.3" in the title and 123 in the header. The library looks
for a version written out ("1.2.3", "1.1i", "v2.0b3") in the package's
names (title, Extras name, package name, file name, copyright), in slots the
developer named for one (`version`, `versionString`, `kAppVersion`…, but
not `osVersion` and the like), and in its other text (About boxes, help).
File names with "_" for "." count too ("heapsav 1_07").

- **Header more than 1:** the written version is used when its digits are
  the header's number: "1.2.3" for 123, "1.1i" for 11, "2.0b3" for 203 or
  20. Zeros at the end don't matter: "1.2" goes with 120 (as 1.2.0), and
  "2.0" with 2, though in the other text only after a word like "Version".
- **Header 1**, usually just NTK's default: the first version in the names
  is used, else one in a version slot, else one in the other text that
  follows "Version", "ver", "v" or the package's own name ("Scramble 1.1");
  if the text gives several, the one given most often.

A Newton OS version (1.0 to 2.2) after "OS", "System" or "Newton" ("for
Newton 2.0") is what the package needs, not its own version, so it's left
out; so is a number like "01.1" (a chapter, as in "01.1 Nephi"). If nothing
is found, the header's number is shown. The details pane and Get Info show
the header's number beside the written version, and in Get Info you can type
any version you like.

## How the Newton OS version is worked out

A package doesn't say which Newton OS it needs, so the app looks for clues:

| Clue | Means |
|---|---|
| The `package1` format | Newton OS 2.0 or later: 1.x can't read it |
| Protos added in 2.0, such as the NewtApp `newt…` protos, `protoInfoButton`, `protoPopupButton` or the `protoStatus…` family | 2.0 or later |
| Calls to functions added in 2.0, such as `GetUserConfig`, `RegUnionSoup` or `RegDataDef` | 2.0 or later |
| Native ARM code, or a store (soup) part | 2.0 or later |
| A "System Update 2.1" package | 2.1 |
| Nothing from this table | **1.x and 2.x**: nothing was found that needs 2.0 |

Greyscale icons, ROM patches and unknown system objects are listed as notes,
but don't change the result.

Each package gets a **Min OS** and **Max OS** from the same clues: a 2.0
feature makes the minimum 2.0, a 2.1 system update makes both 2.1, and a
package with nothing that needs 2.0 gets "1.x" (it should run on 1.x, but
nothing in a package shows which 1.x version it needs). The maximum is only
filled in when a package is made for one version, like a system update;
otherwise it's left as "no limit known". The sidebar's Newton OS groups come
from these two values, so changing them in Get Info moves a package between
groups. The versions you can choose are 1.0–1.3, 2.0, 2.1 and 2.2 (the
eMate 300).

Finding a 2.0 feature is reliable. "1.x and 2.x" only means no 2.0 feature was
found; it hasn't been tried on a 1.x Newton. Where you know better, change the minimum
and maximum with Get Info. Values you set show in a different colour in the
list.

## Building

Open `NewtonLibrary.xcodeproj` in Xcode 13 or later and press Run. To build
from Terminal instead:

```
xcodebuild -project NewtonLibrary.xcodeproj -target NewtonLibrary -configuration Release SYMROOT=$PWD/build
```

The app is in `build/Release/Newton Library.app`. It's a universal app (Apple
Silicon and Intel).

## Files

| Path | What it is |
|---|---|
| `NewtonLibrary/Package/PackageReader.swift` | Reads a package: header, parts, object tree, icon, and the Newton OS clues. |
| `NewtonLibrary/Package/PackageInfo.swift` | What's learned from a package. |
| `NewtonLibrary/Package/MagicPointers.swift` | Names of the Newton OS 2.1 system objects, made by `tools/make_magic_pointers.py`. |
| `NewtonLibrary/Library/LibraryDatabase.swift` | The SQLite database, in `~/Library/Application Support/Newton Library/Library.sqlite`. |
| `NewtonLibrary/Library/LibraryStore.swift` | Adding, copying, editing and removing packages. |
| `NewtonLibrary/Library/Relations.swift` | Works out which packages belong together. |
| `NewtonLibrary/Library/Archives.swift` | Recognises archives and unpacks them (with `unar`, or `ditto` for zip files). |
| `NewtonLibrary/Views/` | The window: sidebar, package table, details pane and preferences. `TableDragSupport.swift` lets rows be dragged out (SwiftUI's Table can't on macOS 12). |
| `tools/make_project.py` | Writes the Xcode project file. Add new source files to it and run it. |
| `tools/make_icon.swift` | Draws the app icon. |
| `tests/run_inspect.sh` | Runs the package reader from Terminal on any files: `tests/run_inspect.sh ~/Newton/*.pkg`. |

The database stores what was read from each package as JSON, plus your edits
in separate columns. Deleting the database file starts an empty library; it
doesn't touch the package copies in your library folder.

For testing, launch the app with `-LibraryDatabasePath <file>` and
`-LibraryFolder <folder>` to use a separate library. Debug builds also accept
`-SnapshotPath <file.png>`, which saves a picture of the window every second.
