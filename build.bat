@echo off
set bat_dir=%~dp0
pushd %bat_dir%
IF NOT EXIST .\build mkdir .\build
IF NOT EXIST .\build_debug mkdir .\build_debug

:: Debug = 0, Release = 1
if "%1" == "1" (
	set release_mode=1
) else if "%1" == "release" (
	set release_mode=1
) else (
	set release_mode=0
)

set compiler_flags=-strict-style

if %release_mode% EQU 0 ( rem Debug
    set compiler_flags=%compiler_flags% -debug
    pushd build_debug
) else ( rem Release
    REM set compiler_flags=%compiler_flags%
    pushd build
)

odin build ../src/ -out:project.exe %compiler_flags% -show-timings
if %errorlevel% neq 0 echo "EXE BUILD CRASHED"
echo Exe Built

popd popd
