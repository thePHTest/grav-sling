@echo off
setlocal
set SRC=%~dp0..\..\deps\box2d
set BUILD=%SRC%\build

cmake -S "%SRC%" -B "%BUILD%" -DBUILD_SHARED_LIBS=ON ^
  -DBOX2D_SAMPLES=OFF -DBOX2D_UNIT_TESTS=OFF -DBOX2D_BENCHMARKS=OFF -DBOX2D_VALIDATE=OFF
if %ERRORLEVEL% NEQ 0 exit /b 1

cmake --build "%BUILD%" --config Release
if %ERRORLEVEL% NEQ 0 exit /b 1

copy /y "%BUILD%\src\Release\box2d.dll" "%~dp0box2d.dll" >nul
if %ERRORLEVEL% NEQ 0 exit /b 1
copy /y "%BUILD%\src\Release\box2d.lib" "%~dp0box2d.lib" >nul
if %ERRORLEVEL% NEQ 0 exit /b 1

echo box2d.dll and box2d.lib built into %~dp0
