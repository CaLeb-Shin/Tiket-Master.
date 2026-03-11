@echo off
chcp 65001 >nul
title 🎫 멜론티켓 발권 봇

cd /d C:\Users\LG\멜론티켓

echo ========================================
echo  멜론티켓 발권 봇 시작
echo ========================================
echo.

echo [1/3] Git Pull...
git pull
echo.

echo [2/3] 기존 봇 종료...
pm2 delete melon-ticket-bot 2>nul
echo.

echo [3/3] 봇 시작 + 로그 표시...
pm2 start scripts/ralph/telegram-command-bot.js --name melon-ticket-bot
echo.

echo ========================================
echo  봇 실행 중! 로그 실시간 표시:
echo  종료: Ctrl+C
echo ========================================
echo.

pm2 logs melon-ticket-bot
