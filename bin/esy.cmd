@ECHO off
@SETLOCAL
@SET ESY__ESY_BASH=%~dp0../node_modules/esy-bash
"%~dp0../_build/install/default/bin/esy.exe" %*
