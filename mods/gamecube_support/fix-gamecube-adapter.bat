@echo off
rem GameCube Controller Support: stops SDL's GameCube driver from turning the
rem adapter into extra controllers (up to 16, which hides other pads).
rem Sets a user environment variable; undo-gamecube-adapter-fix.bat removes it.
setx SDL_JOYSTICK_HIDAPI_GAMECUBE 0
echo.
echo Done. Fully exit Steam (tray icon, Exit) and start it again, then launch the game.
pause
