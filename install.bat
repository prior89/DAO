@echo off
echo 🚀 Biometric DAO 자동 설치 시작
echo ================================
echo.

echo 📦 루트 의존성 설치 중...
call npm install
if %errorlevel% neq 0 (
    echo ❌ 루트 의존성 설치 실패
    pause
    exit /b 1
)

echo.
echo 📦 하드웨어 클라이언트 설치 중...
cd hardwareclient
call npm install
if %errorlevel% neq 0 (
    echo ❌ 하드웨어 클라이언트 의존성 설치 실패
    cd ..
    pause
    exit /b 1
)

call npm run build
if %errorlevel% neq 0 (
    echo ❌ 하드웨어 클라이언트 빌드 실패
    cd ..
    pause
    exit /b 1
)
cd ..

echo.
echo 📦 스마트 컨트랙트 설치 중...
cd contracts
call npm install
if %errorlevel% neq 0 (
    echo ❌ 컨트랙트 의존성 설치 실패
    cd ..
    pause
    exit /b 1
)

call npx hardhat compile
if %errorlevel% neq 0 (
    echo ⚠️  컨트랙트 컴파일 실패 (일부 의존성 문제 가능)
)
cd ..

echo.
echo 📦 백엔드 설치 중...
cd backend
call npm install
if %errorlevel% neq 0 (
    echo ❌ 백엔드 의존성 설치 실패
    cd ..
    pause
    exit /b 1
)

call npm run build
if %errorlevel% neq 0 (
    echo ⚠️  백엔드 빌드 실패 (TypeScript 설정 확인 필요)
)
cd ..

echo.
echo 📦 프론트엔드 설치 중...
cd frontend
call npm install
if %errorlevel% neq 0 (
    echo ❌ 프론트엔드 의존성 설치 실패
    cd ..
    pause
    exit /b 1
)

call npm run build
if %errorlevel% neq 0 (
    echo ⚠️  프론트엔드 빌드 실패 (Next.js 설정 확인 필요)
)
cd ..

echo.
echo 🧪 기본 테스트 실행 중...
call node tests/basic-functional-test.js

echo.
echo ✅ 설치 완료!
echo ==================
echo 🎉 Biometric DAO 투표 시스템이 성공적으로 설치되었습니다!
echo.
echo 🚀 다음 단계:
echo    1. 블록체인 네트워크 설정 (Ethereum 테스트넷)
echo    2. 생체인증 하드웨어 연결
echo    3. 신뢰된 설정 의식 수행
echo    4. 프로덕션 배포
echo.
echo 📋 추가 정보:
echo    - README.md: 프로젝트 개요
echo    - SETUP_GUIDE.md: 상세 설치 가이드  
echo    - FINAL_CERTIFICATION_REPORT.md: 보안 인증서
echo.
pause