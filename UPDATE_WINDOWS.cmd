@echo off
setlocal
for %%I in ("%~dp0.") do set "SOURCE=%%~fI"
set "TARGET=%USERPROFILE%\Downloads\Anivibe"
if not "%~1"=="" set "TARGET=%~1"
for %%I in ("%TARGET%") do set "TARGET=%%~fI"
if /I "%SOURCE%"=="%TARGET%" (
  echo ERROR: Extract the new archive into a separate folder first.
  pause
  exit /b 1
)
if not exist "%SOURCE%\Anivibe.xcodeproj\project.pbxproj" (
  echo ERROR: Run this script from the complete extracted project.
  pause
  exit /b 1
)
if not exist "%TARGET%\.git" (
  echo ERROR: Git repository not found in "%TARGET%".
  echo Usage: UPDATE_WINDOWS.cmd "C:\path\to\your\repository"
  pause
  exit /b 1
)
echo This replaces project files in "%TARGET%".
echo Your .git folder and Config\Secrets.xcconfig will be preserved.
echo Back up any additional local source changes before continuing.
choice /C YN /N /M "Continue? [Y/N] "
if errorlevel 2 exit /b 0
robocopy "%SOURCE%" "%TARGET%" /E /R:1 /W:1 /XD .git .build .swiftpm build build-simulator __pycache__ /XF Secrets.xcconfig *.log
if errorlevel 8 (
  echo ERROR: Copy failed. Do not commit until the copy succeeds.
  pause
  exit /b 1
)
echo.
echo Files updated. Review the diff, then commit and push from your repository:
echo cd /d "%TARGET%"
echo git diff --stat
echo git add Anivibe Config .github scripts docs .gitignore
echo git commit -m "Consolidate iOS build fixes"
echo git push origin main
pause
exit /b 0
