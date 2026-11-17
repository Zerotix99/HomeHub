@echo off
cd /d "%~dp0"
echo Pushe HomeHub zu GitHub (https://github.com/Zerotix99/HomeHub.git)...
git push -u origin main
echo.
echo Fertig! GitHub Actions baut jetzt automatisch deine HomeHub.ipa unter:
echo https://github.com/Zerotix99/HomeHub/actions
pause

