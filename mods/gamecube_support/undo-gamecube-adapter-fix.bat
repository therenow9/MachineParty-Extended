@echo off
rem Removes the variable set by fix-gamecube-adapter.bat.
reg delete HKCU\Environment /v SDL_JOYSTICK_HIDAPI_GAMECUBE /f
echo.
echo Removed. Fully exit Steam and start it again for it to take effect.
pause
