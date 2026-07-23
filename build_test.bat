@echo off
chcp 65001 >nul
echo ========================================
echo  Easy Memory - Build & Test
echo ========================================

echo.
echo [1/3] flutter analyze
call flutter analyze
if %ERRORLEVEL% neq 0 (
    echo FAILED: flutter analyze
    exit /b %ERRORLEVEL%
)

echo.
echo [2/3] flutter test
call flutter test
if %ERRORLEVEL% neq 0 (
    echo FAILED: flutter test
    exit /b %ERRORLEVEL%
)

echo.
echo [3/3] All checks passed!
echo ========================================