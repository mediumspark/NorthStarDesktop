Place Godot export builds here so the Love2D launcher can start the right binary per OS.

Expected layout (project name: NorthStarDesktop):

  build/windows/NorthStarDesktop.exe
  build/linux/NorthStarDesktop          (or NorthStarDesktop.x86_64)
  build/macos/NorthStarDesktop.app      (launcher uses "open", or runs the binary inside Contents/MacOS/)

If no file is found for the current OS, the launcher falls back to the Godot editor with project.godot
(GODOT environment variable or "godot" / "godot.exe" on PATH).
