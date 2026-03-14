@echo off
REM lmupdate: push changes to GitHub and update the DEV server.
REM Run from repo root: lmupdate
REM Optional: set LMUPDATE_COMMIT_MSG=Your message
REM Optional: set LMUPDATE_SKIP_DEPLOY=1 to push only

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\lmupdate.ps1" %*
exit /b %ERRORLEVEL%
