@echo off
REM 一鍵啟動:背景執行手勢辨識(不開視窗),只顯示錦鯉池藝術畫面這一個視窗。
REM 想看攝影機除錯畫面的話,把下面那行 osc_bridge.py 後面加上 --show-camera 再執行。
cd /d "%~dp0src"
start "" /min "..\.venv\Scripts\pythonw.exe" osc_bridge.py
cd /d "%~dp0processing_sketch\gesture_koi_app"
start "" "gesture_koi.exe"
