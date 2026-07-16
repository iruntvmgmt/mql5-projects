@echo off
cd /d "C:\Program Files\MetaTrader 5"
start "MetaTester" "C:\Program Files\MetaTrader 5\metatester64.exe" /agent:"C:\Program Files\MetaTrader 5\Tester\Agent-127.0.0.1-3000" /address:127.0.0.1:3000
