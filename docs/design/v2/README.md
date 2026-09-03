# Design v2: approved front-end contract (September 2, 2026)

Ethan approved these on September 2 after the Phase 1 shell review. They supersede the Phase 0 prototype's Today, Journal, Goals, History, and Settings compositions. The Talk recording screen is unchanged from Phase 1.

- `today.html`: the Today screen on the Flo skeleton. Week strip, Talk circle with Write and Photo, compact mood with Check in, dark appointment band with Prep, one-goal "Up next" card. The page ends exactly on the tab bar.
- `screens.html`: the five tabs plus Talk on one board.

Live renders: https://candy-corn-ios-gallery.pages.dev/today-flo/ and https://candy-corn-ios-gallery.pages.dev/screens/

## Decisions carried by these files

- Tab bar order: Goals, Journal, Today, History, Settings. Today sits in the center.
- Prepare is no longer a tab. It opens from the appointment card's Prep button and from a session.
- Icons: Material Symbols Rounded in the mockups; SF Symbols in SwiftUI using the existing mapping in the prototype's `src/core/icons.tsx`.
- Every screen's first viewport ends on the tab bar with a constant 14 point gap between blocks. A blank tail under the last block is a defect.
- Goals on Today: one item plus a count, never a list.
- "Candy Corn noticed" patterns do not appear on Today; they live in History and the Prep brief.
- Tapping a day in the week strip opens History filtered to that day.

These HTML files are the pictures the SwiftUI front end is compared against. Render them at 390 by 844 with a headless browser to produce pins.
