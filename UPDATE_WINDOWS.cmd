@echo off
setlocal
for %%I in ("%~dp0.") do set "SOURCE=%%~fI"
set "TARGET=%USERPROFILE%\Downloads\Anivibe"
if not "%~1"=="" set "TARGET=%~1"
for %%I in ("%TARGET%") do set "TARGET=%%~fI"
if /I "%SOURCE%"=="%TARGET%" (
  echo ERROR: Extract the archive to a separate folder first.
  pause
  exit /b 1
)
if not exist "%TARGET%\.git" (
  echo ERROR: Existing Git repository not found in "%TARGET%".
  pause
  exit /b 1
)
for %%D in (Anivibe Anivibe.xcodeproj Config Packages .github scripts docs supabase) do (
  if not exist "%SOURCE%\%%D" (
    echo ERROR: Archive is incomplete: %%D missing.
    pause
    exit /b 1
  )
)
set "BACKUP=%TARGET%_backup_%RANDOM%_%RANDOM%"
echo This REPLACES managed project folders, including local source changes.
echo Existing folders will be MOVED to a backup outside your Git repository:
echo "%BACKUP%"
echo .git and root .env stay untouched; Config\Secrets.xcconfig is restored.
echo Close Xcode/editors/builds before continuing. Review your backup before push.
choice /C YN /N /M "Continue? [Y/N] "
if errorlevel 2 exit /b 0
mkdir "%BACKUP%"
if errorlevel 1 goto failed
for %%D in (Anivibe Anivibe.xcodeproj Config Packages .github scripts docs supabase) do (
  if exist "%TARGET%\%%D" (
    move "%TARGET%\%%D" "%BACKUP%\%%D" >nul
    if errorlevel 1 goto failed
  )
  robocopy "%SOURCE%\%%D" "%TARGET%\%%D" /E /R:1 /W:1 /XD .git .build .swiftpm __pycache__ .temp .branches /XF Secrets.xcconfig .env *.log
  if errorlevel 8 goto failed
)
if exist "%BACKUP%\Config\Secrets.xcconfig" (
  copy /Y "%BACKUP%\Config\Secrets.xcconfig" "%TARGET%\Config\Secrets.xcconfig" >nul
  if errorlevel 1 goto failed
)
if exist "%BACKUP%\supabase\.env" copy /Y "%BACKUP%\supabase\.env" "%TARGET%\supabase\.env" >nul
for %%F in (README.md project.yml .gitignore .env.example UPDATE_WINDOWS.cmd) do (
  if exist "%TARGET%\%%F" copy /Y "%TARGET%\%%F" "%BACKUP%\%%F" >nul
  copy /Y "%SOURCE%\%%F" "%TARGET%\%%F" >nul
  if errorlevel 1 goto failed
)
echo.
echo Updated. Backup: "%BACKUP%"
echo Review the diff and ignored secrets before committing:
echo cd /d "%TARGET%"
echo git diff --stat
echo git status --short
echo git add -A
echo git commit -m "Improve animations and playback reliability"
echo git push origin main
pause
exit /b 0
:failed
echo ERROR: Update did not complete. Do NOT commit or push.
echo Original moved folders are preserved in "%BACKUP%".
echo Restore affected folders from that backup before retrying.
pause
exit /b 1
