@echo off
rem Runs the Windows chrome rendering tests (tests\ui) with freshly compiled
rem shaders. Optional argument: QT_SCALE_FACTOR (default 1), e.g. 1.25 or 2.
setlocal
call "%~dp0compile_shaders.cmd" || exit /b 1
set "PATH=C:\Qt\6.12.0\msvc2022_64\bin;%PATH%"
set "QSG_RHI_BACKEND=d3d11"
set "QT_SCALE_FACTOR=%~1"
if "%QT_SCALE_FACTOR%"=="" set "QT_SCALE_FACTOR=1"
qmltestrunner -input "%~dp0ui" -o "%~dp0.qsb\ui-results.txt,txt"
set "RESULT=%ERRORLEVEL%"
type "%~dp0.qsb\ui-results.txt"
exit /b %RESULT%
