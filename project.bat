@echo off
set bat_dir=%~dp0
pushd %bat_dir%

:: Debug = 0, Release = 1
if "%1" == "1" (
	set release_mode=1
) else if "%1" == "release" (
	set release_mode=1
) else (
	set release_mode=0
)

pushd bin
if %release_mode% EQU 0 ( rem Debug
    set exe_path=..\build_debug\project.exe
) else ( rem Release
    set exe_path=..\build\project.exe
)
call %exe_path%
popd
popd
