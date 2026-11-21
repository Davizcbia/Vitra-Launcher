@echo off
rem Compiles the frontend shaders from source into tests\.qsb for the QML tests
rem (tests\ui and "liquid glass test\tests"), so a test never runs an old shader
rem left in build-win11. Same targets as the Glass Lab's live compiler.
rem   compile_shaders.cmd   (run by run_ui_tests.cmd and run_tests.cmd)
setlocal
set "QT_BIN=C:\Qt\6.12.0\msvc2022_64\bin"
set "SRC=%~dp0..\shaders"
set "OUT=%~dp0.qsb"
if not exist "%OUT%" mkdir "%OUT%"
for %%S in (liquidglass continuousclip sidebarglow) do (
    "%QT_BIN%\qsb.exe" --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "%OUT%\%%S.frag.qsb" "%SRC%\%%S.frag"
    if errorlevel 1 (
        echo Shader %%S.frag failed to compile.
        exit /b 1
    )
)
exit /b 0
