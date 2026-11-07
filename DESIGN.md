---
name: Quota Signal
description: "A native macOS instrument for reading a Claude account’s weekly usage and reset."
colors:
  signal-cyan: "rgb(35% 89% 94%)"
  warning-amber: "rgb(100% 74% 43%)"
  graphite-frame: "rgb(7.8% 9.1% 10.5%)"
  graphite-plate: "rgb(10.5% 12.2% 13.9%)"
  plot-well: "rgb(6.8% 8.1% 9.6%)"
  seam: "rgb(21% 24% 27%)"
  cool-ink: "rgb(92% 95% 97%)"
  muted-ink: "rgb(62% 68% 73%)"
typography:
  usage-display:
    fontFamily: "SF Mono, monospace"
    fontSize: "43px"
    fontWeight: 500
    letterSpacing: "-1.5px"
  empty-title:
    fontFamily: "-apple-system, system-ui"
    fontSize: "25px"
    fontWeight: 600
  editor-title:
    fontFamily: "-apple-system, system-ui"
    fontSize: "21px"
    fontWeight: 600
  widget-title:
    fontFamily: "-apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 600
  empty-body:
    fontFamily: "-apple-system, system-ui"
    fontSize: "14px"
    fontWeight: 400
  usage-label:
    fontFamily: "-apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 500
  history-title:
    fontFamily: "-apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 600
  row-label:
    fontFamily: "-apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 400
  detail:
    fontFamily: "-apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 400
  demo-label:
    fontFamily: "-apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 500
  scale:
    fontFamily: "SF Mono, monospace"
    fontSize: "10px"
    fontWeight: 400
rounded:
  plate: "14px"
  well: "8px"
spacing:
  seam: "1px"
  segment-gap: "2px"
  stack: "8px"
  plot-inset: "10px"
  plate-inset: "14px"
  header-inset: "16px"
  editor-inset: "19px"
components:
  widget-frame:
    backgroundColor: "{colors.graphite-frame}"
    width: "398px"
    height: "475px"
  inset-plate:
    backgroundColor: "{colors.graphite-plate}"
    textColor: "{colors.cool-ink}"
    rounded: "{rounded.plate}"
    padding: "{spacing.plate-inset}"
  usage-readout:
    textColor: "{colors.cool-ink}"
    typography: "{typography.usage-display}"
  segmented-meter:
    backgroundColor: "{colors.seam}"
    height: "7px"
  history-well:
    backgroundColor: "{colors.plot-well}"
    rounded: "{rounded.well}"
    padding: "{spacing.plot-inset}"
  demo-badge:
    textColor: "{colors.warning-amber}"
    typography: "{typography.demo-label}"
    padding: "3px 7px"
  reset-row:
    textColor: "{colors.muted-ink}"
    typography: "{typography.row-label}"
    height: "40px"
  offer-row:
    textColor: "{colors.muted-ink}"
    typography: "{typography.row-label}"
    height: "32px"
---

# Design System: Quota Signal

## Overview

**Creative North Star: "A weekly cycle readout"**

Quota Signal borrows its visual language from a compact instrument. A cool graphite frame contains a single working plate. A large number establishes the reading, and the segmented meter and recessed history plot give it scale.

The weekly reset and the reading’s source sit below the measurements, where they can be checked at a glance. Account selection and editing use macOS controls within the instrument.

**Key Characteristics**

- A cool, dark surface hierarchy with thin seams.
- Cyan links the meter, plot and current reading source.
- Fixed-width figures make changing measurements easy to scan.
- Native dark appearance governs menus, controls and sheets.

## Colors

### Primary

- **Signal cyan** marks the waveform, empty-state chart icon, filled meter segments, history trace, latest plot point, recorded-reading dot and the available free reset state.

### Secondary

- **Warning amber** identifies the demo badge and invalid manual reading guidance.

### Neutral

- **Graphite frame** sits behind the header and surrounds the inset plate.
- **Graphite plate** supports the main readout, reset rows and empty state.
- **Plot well** recesses the history area.
- **Seam** defines the plate stroke, unfilled segments, grid, reset divider and badge outline.
- **Cool ink** carries the usage number, headings and primary values.
- **Muted ink** carries supporting text, time and scale labels, provenance, and missing-reading states.

**The Signal Rule.** Use cyan for the instrument mark and meaningful measurement or availability cues.

## Typography

The UI uses macOS system type. The usage number uses the monospaced design at 43 points with medium weight and −1.5 points of tracking. Meter endpoints and the plot’s vertical scale use 10-point mono, while the reset countdown keeps its proportional system face and uses tabular digits.

The widget title is 15-point semibold, the empty-state title is 25-point semibold, and the account editor title is 21-point semibold. The 13-point medium usage label, 12-point chart and reset text, and 11-point provenance carry the next levels of the hierarchy. The editor leaves field controls and section headline metrics to SwiftUI.

**The Figures Rule.** Keep the main reading, chart scale and countdown stable as their digits change.

## Layout

The frontmatter uses CSS-compatible units for tooling. Each `px` value represents the same number of macOS logical points in the source. The fixed 398 × 475-point panel has a 49-point header, an 8-point inset around the plate’s sides and bottom, and 14 points of padding within the plate. The header groups its mark and title on the left and window actions on the right.

The selected-account layout stacks the picker, usage readout, meter, history and reset rows. A flexible spacer anchors the provenance and Claude Usage link near the plate’s bottom edge. The empty state centers its content vertically while keeping it left aligned. The account editor uses a 374-point-wide sheet.

## Elevation & Depth

The graphite frame, lighter plate and darker chart well create the depth inside the widget. A one-point border separates the plate from the frame. AppKit supplies the window treatment, while the custom SwiftUI surfaces rely on tonal separation.

## Shapes

The plate has 14-point corners and the history well has 8-point corners. A capsule outlines the demo badge. The meter uses square segments, and circular dots identify the latest chart point and source. SF Symbols provide icons in the panel and menu bar.

## Components

- **Account picker and actions.** The native picker has a 172-point slot with an account count alongside. Borderless controls handle hiding the widget, adding or editing accounts, viewing or exiting demo, and yield to the standard large Add account button in the empty state.
- **Usage readout and meter.** The readout retains the same type hierarchy when a dash stands in for unavailable usage. Twenty-four segments are 7 points high and separated by 2-point gaps. The active segment can fill partially, and 0% and 100% labels anchor the scale.
- **Weekly history.** The recessed well has a 78-point plot, 0/50/100 guides and a 1.5-point trace ending in a 6-point dot. The horizontal axis spans cycle start to scheduled reset. The header reports the observation count, and an inline message occupies the plot when it has no observations.
- **Reset rows and source.** The weekly reset pairs a countdown with the scheduled local time. The free reset row places a named state at the right edge and uses cyan for Available. The footer identifies the source and observation time or reports that no readings exist. The Claude Usage link sits opposite it.
- **Account editor.** Standard labeled fields, date picker, reset menu, and save and cancel actions use native dark styling. The reset date and validation message appear as needed when entering a manual reading. Removal uses the system destructive alert.
- **Demo badge.** An amber label with a seam-colored capsule identifies sample data in the header.

**The Account Rule.** Update the reading, history and reset together when the account changes.

## Do's and Don'ts

### Do

- **Do** pair the usage display with its textual source and reset context.
- **Do** let native macOS controls supply keyboard focus and interaction states.
- **Do** keep the demo badge visible while sample data is shown.

### Don't

- **Don't** fill an unobserved cycle with an invented trace.
- **Don't** use the free reset accent for an unknown or unavailable offer.
