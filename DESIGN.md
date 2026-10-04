# thenotch design system

The island is a small, glanceable surface that grows out of the MacBook notch. It shows one thing at a time: what's playing, the files waiting on the shelf, or the battery for a moment. Everything here serves that: black like the hardware, large and heavy type, few controls, and color only where it carries meaning.

The code lives in `thenotch/Core/UI/DesignSystem/` (tokens) and `thenotch/Core/UI/Components/` (shared views). `thenotchTests/DesignSystemTests.swift` checks the rules marked ✓ below. Guidance is quoted from Apple's Human Interface Guidelines (HIG) by page › section.

## Principles

1. **Glanceable.** "Use large, heavier-weight text — a medium weight or higher" (HIG Live Activities › Ensure text is easy to read). Nothing smaller than 11 pt.
2. **Black, like the notch.** The island renders under a forced dark color scheme. "In rare cases, consider using only a dark appearance in the interface" (HIG Dark Mode › Best practices). Live Activities in the Dynamic Island do the same.
3. **One color, one meaning.** "Avoid using the same color to mean different things" (HIG Color › Best practices). White carries the content. A few system colors carry status. The artwork brings its own color.
4. **Snug and concentric.** Compact content hugs the notch. Rounded shapes near the edge share the island's corner center (HIG Live Activities › Use consistent margins and concentric placement).
5. **Motion is optional.** The island springs open, and only fades under Reduce Motion. Nothing important is said by motion alone.

## Color — `IslandColors.swift`

| Token | Value | Use | Contrast on black |
|---|---|---|---|
| `IslandColors.surface` | `Color.black` | The island | — |
| `.primary` | label, ≈ 85 % white | Titles, values, active controls | 14.8:1 |
| `.secondary` | secondary label, ≈ 55 % white | Subtitles, captions, controls at rest | 6.3:1 |
| ~~`.tertiary`~~ | ≈ 25 % white | **Never for text** ✓ | 2.0:1 |

Semantic label colors follow Increase Contrast by themselves.

### Fills — `IslandFill`, used as `.fill(.island(.hover))`

White overlays for shapes, never for text. Each level has an Increase Contrast variant ("supply … an increased contrast option for each variant", HIG Color › Best practices) that never gets weaker ✓.

| Level | Standard | Increase Contrast | Use |
|---|---|---|---|
| `clear` | 0 % | 0 % | A control at rest |
| `hover` | 12 % (#1F1F1F, 1.3:1) | 20 % (#333, 1.7:1) | Under the pointer |
| `selected` | 22 % (#383838, 1.8:1) | 35 % (#595959, 3.0:1) | Selected or always-filled controls (the favorite star) |
| `pressed` | 30 % (#4D4D4D, 2.5:1) | 45 % (#737373, 4.4:1) | While clicked |
| `track` | 20 % | 35 % | Unplayed part of a progress bar |
| `progress` | 70 % (10:1) | 100 % (21:1) | Played part; against `track`: 6.0:1 / 7.0:1 ✓ |
| `outline` | 45 % (#737373, 4.4:1) | 70 % (10:1) | Drop zone edge; ≥ 3:1 ✓ |
| `outlineActive` | 100 % | 100 % | Drop zone or island border with files over it (white) |

Text on any fill stays legible: secondary on `hover` is 4.9:1, primary on `pressed` is 6.0:1.

### Signals — `IslandSignal`

System colors adapt to Increase Contrast. Each signal comes with a shape, never color alone ("Convey information with more than color alone", HIG Accessibility › Vision).

| Token | Color | Paired with | Contrast on black |
|---|---|---|---|
| `favorite` | system yellow | filled star | 14.9:1 |
| `charging` | system green | bolt | 10.4:1 |
| `critical` | system red | empty battery | 6.2:1 |
| `selection` | accent at 55 % | the tile's rounded fill | primary text on it: 6.4:1 |

`selection` is the only use of the accent color ("Apply your app's accent color judiciously", HIG Branding › Best practices).

### Content color

The level meter takes its color from the album artwork (`ArtworkTint`). The color is brightened until it reads on black, and falls back to white for gray covers. This is the island's signature: the music colors the notch.

## Typography — `IslandTypography.swift`

SF Pro, through the macOS built-in text styles ("Consider using the built-in text styles", HIG Typography › Using system fonts). Medium weight or heavier. Numbers that change use tabular digits so they don't jitter. macOS has no Dynamic Type; the 13 pt default and 10 pt minimum apply (HIG Accessibility › Vision).

| Token | Style | Size / weight | Use |
|---|---|---|---|
| `.islandValue` | Title 1 | 22 semibold, tabular | A value that is the whole message (battery %) |
| `.islandTitle` | Title 2 | 17 semibold | Main line (track title) |
| `.islandSubtitle` | Title 3 | 15 medium | Line under the title (artist) |
| `.islandHeadline` | Headline | 13 bold | Empty-state heading |
| `.islandCompact` | Body | 13 semibold, tabular | Text in a compact wing |
| `.islandLabel` | Callout | 12 medium | Buttons, labels, messages |
| `.islandNumeric` | Callout | 12 medium, tabular | Times, counts |
| `.islandCaption` | Subheadline | 11 medium | File names; the smallest text |

Buttons and menu items use title-style capitalization ("Show in Finder", "AirDrop All…"). An ellipsis marks actions that need more input.

### Symbols — `Font.islandSymbol(_:weight:)`

SF Symbols scale with the font, never with `scaleEffect`, so they stay sharp. In compact wings they are semibold, to match the text beside them.

| `SymbolSize` | pt | Use |
|---|---|---|
| `small` | 10 | Small secondary buttons (`smallControl`) |
| `compact` | 13 | Compact wings |
| `control` | 17 | Icon buttons |
| `large` | 22 | Previous/next, drop zones, empty states |
| `hero` | 30 | Play/pause, the battery glyph |

## Layout — `IslandStyle.swift`

### Spacing — `IslandStyle.Spacing`, 4 pt grid ✓

| Token | pt | Use |
|---|---|---|
| `xxs` | 2 | Lines of one text block |
| `xs` | 4 | Tight items (tiles, symbol + label) |
| `s` | 8 | Items in a group |
| `m` | 12 | Between groups; around bezeled elements |
| `l` | 16 | Wider gaps |
| `xl` | 24 | Around unbezeled controls |

The 12 and 24 pt values come from HIG Accessibility › Mobility: "add about 12 points of padding around elements that include a bezel. For elements without a bezel, about 24 points".

Semantic spacing:
- `content` is 24 (`xl`): the margin between expanded content and the island's edge. Modules apply it with `.islandContentMargins()` (left, right, bottom); `IslandView` adds it below the notch.

### Equal padding

Content sits the same `content` margin (24 pt) from the island's **visible** edge on every side: left, right, bottom, and below the notch. Both ends of that measure are what people see.

- **The island's edge is its black body.** The top flares are not part of it, so `IslandView` insets expanded content by `Radius.islandFlare` on each side before the margin.
- **Content is what shows at rest.**
  - Text is measured by its line box. A glyph's own ascender space, about 2 pt at 12–13 pt, is part of the type, not extra padding.
  - Symbols are measured by their frame.
  - Filled shapes are measured by their fill.
- **Controls at an edge show their edge.**
  - The player's favorite and output buttons sit on filled circles, so their fill touches the margin.
  - Borderless buttons line up their text with the margin and let the hover capsule reach into it (`IslandTextButtonStyle.verticalInset`, horizontal `Spacing.s`).
  - Shelf tiles do the same with their 4 pt padding, where the selection fill shows (tiles have no hover fill, as in Finder). The shelf's stack has no hover or selection fill: it is one object, not a list of choices.
- **Heights are exact.** Each module's `expandedContentHeight` is the sum of its rows plus the bottom margin, built from tokens (`NowPlayingExpandedView.contentHeight`, `ShelfStackView.contentHeight`, `ShelfListView.contentHeight`, `BatteryExpandedView.contentHeight`, `IslandEmptyState.contentHeight`). No slack ends up under the content.
- **Corners are concentric.** The island's bottom radius (36) is the margin (24) plus the radius of a container in the corner (12).

#### The compact island

The same principle applies at a smaller scale.

- **Padding.** Wing content is `compactContent` (20 pt) tall and centered in the notch's height. That leaves `IslandState.compactPadding` = (notch height − 20) / 2, which is 6 pt under a 32 pt notch. The content gets this padding on every side: top, bottom, toward the island's outer edge, and toward the notch.
- **Wing width.** The width follows the module rather than a fixed value: `compactContentWidth` (default 20; Battery 40 for "100%") plus the padding on both sides.
- **Snug toward the notch.** Both wings share one width so the island stays centered on the notch. Content narrower than that width, such as "30%" in the battery wing, sits snug against the notch ("don't add padding between content and the TrueDepth camera", HIG Live Activities › Compact presentation); the slack goes to the outer side.
- **Corners.** With wings, the bottom corners are concentric with the content: `Radius.small` (5) + padding (6) = 11. The bare notch keeps `Radius.compact` (8).

Measured on a rendered island (32 pt notch): Now Playing's artwork frame sits 6 pt from the top, the bottom, the outer edge and the notch.

Measured on rendered islands (32 pt notch, with a 12 pt margin; the layout scales with the token): left, right and bottom margins equal the margin in the player, shelf, battery and empty states. The top margin equals it to the line box.
### Corner radius — `IslandStyle.Radius` (continuous corners)

| Token | pt | Use |
|---|---|---|
| `island` | 36 = `large` + `content` ✓ | Bottom corners of the open island |
| `islandFlare` | 14 | Outward flare into the menu bar |
| `compact` | 8 | Bottom corners of the bare notch; with wings, `small` + compact padding |
| `large` | 12 | Drop zones, large artwork |
| `medium` | 8 | Shelf tiles |
| `small` | 5 | Compact artwork |

### Sizes — `IslandStyle.Size`

| Token | pt | |
|---|---|---|
| `control` | 28 | Minimum hit target, the macOS default (HIG Accessibility › Mobility) ✓ |
| `smallControl` | 20 | Small secondary buttons (the shelf stack's ✕ and …), the macOS minimum ✓ |
| `playerControl` | 40 | The player's row: favorite and output (filled circles), previous, play/pause, next |
| `labelLine` | 16 | One line of `islandLabel`/`islandNumeric` text |
| `compactContent` | 20 | Height of wing content (and width of square content like artwork); sets the compact padding |
| `artwork` | 64 | Player artwork; also the leading column width (battery glyph) |
| `hudLevel` | 64 | The volume and brightness level bar in the trailing wing (the leading wing shows the symbol, against the notch) |
| `thumbnail` | 44 | Shelf file preview |
| `stackThumbnail` | 88 | A file in the shelf's stack (the stack is 104, for the files fanned out behind) |
| `tileLabelWidth` | 68 | Shelf file name, two lines |
| `progressBar` / `levelMeter` | 6 / 14 | Heights |
| `dropBorder` / `dropBorderActive` | 1.5 / 3 | The island's border while files are dragged in / over it |

Island geometry lives in `IslandState`: wing width (from the content, see *The compact island*), expanded width 520. A module gives its `expandedContentHeight`: its content plus the bottom margin (Now Playing 164, Shelf list 128, Shelf stack 196, Battery 70, empty state 60), and may give a narrower `expandedWidth` (the shelf's stack: 256, about as wide as the island is tall). The island adds the notch height and the margin below it, so the content clears the notch on every Mac, and the 40 pt tab row when the tabs don't fit beside the notch. The total must fit the 320 pt panel, even under a 38 pt notch with the tab row ✓.

### The shelf: stack and list

The shelf opens as a small square, like Dropover's shelf: the three newest files stacked, fanned out by ±8° and 8 pt, the newest on top, with no file name or caption (the count is beside the notch); "Show All" centered under it, and above it, in a row of their own so they stay clear of the files, a small (`smallControl`, 20 pt, `.small` 10 pt symbol) filled ✕ (Clear Shelf) on the left and … (More: AirDrop…, Show in Finder, Show All, an AppKit pop-up menu) on the right. An empty shelf (files being dragged in) shows a small AirDrop zone in the bottom-left corner instead (`IslandDropZone(isCompact: true)`: the symbol only, one control tall). Dragging the stack drags every file; double-clicking opens the file, or shows them all. "Show All" widens the island to the list (one tile per file, at the standard width) with the open spring, until the island closes. While files are dragged in, the whole island is the drop target: it gets a `dropBorder` (1.5 pt, `outline`) that turns `dropBorderActive` (3 pt) and white (`outlineActive`) once the files are over it, and the stack gives way to the words "Drop here" (the list keeps its AirDrop zone beside them). Over an AirDrop zone, the border stays thin: the files go there instead.

### Anatomy of the open island

```
╭──────────────╮  notch  ╭──────────────╮   ← flare 14
│                                         │   content 24
│  ┌──────┐  Title (islandTitle)    ▍▌▍▌ │   artwork 64 · gap m
│  │ art  │  Artist (islandSubtitle)      │
│  └──────┘                               │   m
│  0:42 ━━━━━━━━━━━━──────────────── 3:15 │   islandNumeric · bar 6
│                                         │   s
│  (★)        ◀◀    ▶❙❙    ▶▶        (🔈) │   playerControl 40 · spacing xl
╰─────────────────────────────────────────╯   content 24 · radius 36
 ↔ flare 14, then content 24 on the left and right
```

## Motion — `IslandStyle`

| Token | Value | Under Reduce Motion |
|---|---|---|
| `openAnimation` | spring 0.38 s, damping 0.8 | `fade` |
| `closeAnimation` | spring 0.45 s, damping 1 (no bounce) | `fade` |
| `fade` | ease-out 0.15 s | — |
| `levelMeterTick` | 0.3 s, only while playing | Still bars |

The content transition is opacity plus a 0.9 scale from the top. Under Reduce Motion it is opacity only, following "Replacing transitions in x-, y-, and z-axes with fades" (HIG Accessibility › Cognitive). Frequent interactions such as hover and selection don't animate (HIG Motion › Providing feedback).

## Components — `Core/UI/Components/`

| Component | What it gives you |
|---|---|
| `.buttonStyle(.islandIcon(isSelected:isFilled:isProminent:size:))` | Circular icon button with a 28 pt minimum (`size: smallControl` for a 20 pt one), hover/pressed/selected fills, and secondary → primary on hover. Give it a `Label` so VoiceOver has a name. |
| `.buttonStyle(.islandText)` | Capsule text button in `islandLabel`, at least 20 pt tall. |
| `IslandEmptyState(title:message:symbol:)` | Centered heading and message that invites the next step ("Play something in Music or Spotify."). |
| `IslandDropZone(symbol:title:isCompact:onDrop:)` | Dashed target for dragged files that fills while targeted; `isCompact` makes it a small symbol-only box in a row of controls (VoiceOver reads the title). It only reports its frame (`IslandDropTarget`); `IslandView` takes the drop and hands the loaded files to the zone under the pointer. Never put `onDrop` inside the island: AppKit misplaces those views inside its clip shape, and drops miss them. |
| `IslandProgressBar(fraction:isHighlighted:)` | Determinate capsule progress, hidden from VoiceOver (the caller labels the value). The player's bar seeks: clicking or dragging along it (a hit area the row's height plus 4 pt) moves the elapsed time with the pointer and seeks on release; `isHighlighted` turns the played part primary under the pointer. VoiceOver adjusts it 10 s at a time. |
| `.islandContentMargins()` | The standard expanded margins. |
| Module tabs (`IslandView`) | One `.islandIcon` per module with content (`ModuleKind.symbol`), in the band left of the notch, aligned with the content margin; when the island is too narrow for that (the shelf's stack), in a row under the notch, above the content (`IslandState.tabsBesideNotch`). They appear only when two or more modules have content (`IslandState.showsTabs`), never while files are dragged in. The shown module's tab is filled; the choice lasts until the island closes. Switching tabs slides the content toward the chosen tab's side while the island resizes to the new page (`ModulePager`: pages side by side, each its module's width, scrolled with the open spring; hidden pages take no pointer or VoiceOver); under Reduce Motion it cross-fades. When the island shrinks under the pointer, the region it covered keeps it open until the pointer is back over it (`HoverPolicy.ShrinkGrace`). |

## Checklist for a new module

- [ ] Uses only tokens: no literal sizes, opacities, radii or colors in views.
- [ ] Compact wings use `islandCompact` and `islandSymbol(.compact, weight: .semibold)`, fit in 20 pt of height, report their `compactContentWidth`, and read as one piece of information.
- [ ] Expanded content uses `.islandContentMargins()`, and `expandedContentHeight` fits it.
- [ ] Every control is ≥ 28 pt and every icon-only control has a `Label`/`help` text.
- [ ] Status color comes from `IslandSignal` and always has a shape or a word beside it.
- [ ] Empty state uses `IslandEmptyState` with a message that says what to do.
- [ ] Moving content honors `accessibilityReduceMotion`.
- [ ] Checked with Increase Contrast and Reduce Motion on.

The Settings window is a standard SwiftUI `Form`. It uses system components and system colors, not island tokens.
