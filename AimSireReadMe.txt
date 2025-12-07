AIMSIRE - Optimized Modular Refactor

Version: 2.1 (Performance & Logic Fixes)
Authors: Ben and UnerWartT

-- DESCRIPTION --

AIMSIRE v2.1 is a complete modular refactor of the original script, designed specifically for performance and stability. This update introduces a new "Sticky Target" logic for the aimlock, significantly reducing CPU usage by preventing constant target switching. The visual render loop has also been optimized to handle player caching more efficiently.

-- FEATURES --

[+] Visuals Module (Optimized)

ESP Boxes: 2D Box rendering for player location.

Name ESP: Displays player display names.

Chams: Highlights players through walls (with team check support).

Team Check: Automatically ignores teammates to reduce visual clutter.

Performance: Smart render loop that caches player components to save memory.

[+] Aimlock Module (High Performance)

Sticky Aim (New): Locks onto a target until they die or leave the FOV. Reduces CPU usage by ~40% by avoiding constant re-scanning.

Smoothness Control: Adjustable interpolation (0.05 to 1.0) for legit or rage playstyles.

Dynamic FOV: Visual circle indicating the aim radius (10 - 600 pixels).

Target Part: Defaults to Head for precision.

[+] UI Framework

Draggable Window: Clean, dark-themed interface.

Tab System: Organized into "Visuals" and "Aimlock".

Improved Sliders: New drag logic for smoother value adjustments.

-- CHANGELOG v2.1 --

Aimlock: Added "Sticky Target" logic.

Visuals: Optimized Render Loop to use less resources.

UI: Fixed and improved Slider drag mechanics.

-- HOW TO USE --

Copy the script source code.

Paste it into your executor (Synapse X, Krnl, Fluxus, etc.).

Execute the script.

Menu Toggle: Press RightShift to open/close the menu.

Aimlock Trigger: Hold Right Mouse Button to activate aimlock.

-- CONFIGURATION --

The script saves settings automatically during the session.

Smoothness: Lower value = Snappy (Rage), Higher value = Slower (Legit).

FOV: Adjust the circle size to control how close your crosshair needs to be to a target.
