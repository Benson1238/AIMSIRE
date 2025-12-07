AimRare Hub v6.2

Author: Ben
Version: 6.2 (Fixed Edition)

-- DESCRIPTION --
AimRare Hub is a lightweight, optimized script hub featuring Legit Aimbot
and comprehensive ESP visuals. This version focuses on performance,
stability, and visual accuracy.

-- SPECIAL THANKS & CREDITS --
A massive shoutout to Gemini AI for the technical assistance on this update.
Gemini was instrumental in fixing several critical errors that I (Ben) couldn't
solve alone, specifically the complex screen-coordinate math required for
the ESP Box sizing. This ensures the boxes now scale perfectly regardless
of distance or FOV changes.

-- FEATURES --
[+] Visuals (ESP)
- Box ESP (Dynamic sizing based on screen coordinates)
- Skeleton ESP (Optimized connection tables for better performance)
- Name & Health ESP (Health bars and distance displays)
- Team Check (Don't target allies)

[+] Legit Aimbot
- Smoothness Control (Human-like movement)
- FOV Radius (Visual circle to show aim range)
- Hit Chance % (Randomized missing for legit play)
- Target Part Switcher (Head, UpperTorso, RootPart)
- Visibility/Wall Check & Alive Check

[+] Settings & UI
- Clean, draggable GUI
- Customizable Menu Keybind (Default: RightShift)
- Performance Monitor (FPS Watermark)
- Safe Unload System (Prevents lag/crashes when closing)

-- HOW TO USE --

Copy the script from the .lua file.

Paste it into your executor.

Execute the script in-game.

Press 'RightShift' to open/close the menu.

-- CHANGELOG v6.2 --

Fixed: ESP Box sizing bug (Now calculates using ViewportPoint Y-values).

Fixed: Memory leaks in Skeleton ESP (Table reuse).

Optimized: Raycasting now reuses params to save CPU.

Optimized: Aimbot target scanning only runs when key is held.

Enjoy the script!
