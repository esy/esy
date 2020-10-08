@ECHO off
@SETLOCAL
@SET ESY__ESY_BASH=%~dp0node_modules/esy-bash
echo %ESY__ESY_BASH%
"%~dp0/_build/install/default/bin/esy.exe" %*
