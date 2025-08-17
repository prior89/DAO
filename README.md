# Biometric DAO Voting System

분산원장 기반 전자투표를 위한 하드웨어 보안 단말기와 연동되는 DAO 소프트웨어 시스템

## 시스템 개요

이 시스템은 생체인증 기반 하드웨어 투표 단말기와 연동하여 완전히 안전하고 투명한 DAO 투표를 제공합니다.

### 주요 특징

- **생체인증 기반 보안**: 지문 인식을 통한 신원 확인 및 블라인드 서명
- **하드웨어 보안**: 오프라인 투표 처리 및 물리적 침입 방지
- **영지식 증명**: 투표자 신원과 투표 내용의 완전한 분리
- **동형암호**: 개별 투표 내용 노출 없이 집계 가능
- **믹스넷 프로토콜**: 투표 순서 무작위화로 추적 방지

## 아키텍처

```
┌─────────────────┐    BLE     ┌──────────────────┐    HTTP/WSS    ┌─────────────────┐
│ Hardware        │ ◄─────────► │ Mobile/Desktop   │ ◄─────────────► │ Blockchain      │
│ Voting Terminal │             │ Application      │                 │ Network         │
│                 │             │                  │                 │                 │
│ • Biometric     │             │ • BLE Client     │                 │ • Smart         │
│ • ECDSA Chip    │             │ • Crypto Verify  │                 │   Contracts     │
│ • TPM/HSM       │             │ • UI/UX          │                 │ • Zero-Knowledge│
│ • Secure Storage│             │ • Data Relay     │                 │ • Homomorphic   │
└─────────────────┘             └──────────────────┘                 └─────────────────┘
```

## 프로젝트 구조

```
DAO/
├── contracts/          # 스마트 컨트랙트 (Solidity)
│   ├── governance/     # DAO 거버넌스 컨트랙트
│   ├── voting/         # 투표 관리 컨트랙트
│   ├── crypto/         # 암호학적 검증 컨트랙트
│   └── templates/      # 투표 템플릿 컨트랙트
├── hardwareclient/     # 하드웨어 통신 클라이언트
│   ├── ble/           # BLE 통신 모듈
│   ├── crypto/        # 암호화 검증 모듈
│   └── protocols/     # 프로토콜 구현
├── frontend/          # 웹 인터페이스
│   ├── components/    # React 컴포넌트
│   ├── pages/         # 페이지 컴포넌트
│   └── utils/         # 유틸리티 함수
├── backend/           # 백엔드 서비스
│   ├── api/           # REST API
│   ├── services/      # 비즈니스 로직
│   └── middleware/    # 미들웨어
├── docs/              # 문서
└── tests/             # 테스트 파일
```

## 보안 모델

### 1. 생체인증 기반 신원 확인
- 지문 특징점 추출 및 템플릿 매칭
- FAR(False Accept Rate) 0.001% 이하
- 생체 해시 생성으로 원본 데이터 보호

### 2. 블라인드 서명 시스템
- 투표 내용이 서명자에게도 노출되지 않음
- ECDSA 하드웨어 가속으로 안전한 서명 생성
- 블라인딩 팩터를 통한 프라이버시 보장

### 3. 영지식 증명
- 투표 자격 증명과 투표 내용 완전 분리
- 커밋먼트 스킴을 통한 신원 보호
- 일회용 익명 토큰 발급

### 4. 물리적 보안
- 전도성 메시를 통한 침입 감지
- 환경 센서로 글리치 공격 탐지
- 침입 시 데이터 자동 소거

## 설치 및 실행

### 요구사항
- Node.js 18+
- Ethereum 호환 블록체인 네트워크
- BLE 지원 디바이스

### 설치
```bash
npm install
npm run build
```

### 개발 모드 실행
```bash
npm run dev
```

### 테스트
```bash
npm test
```

## 사용 시나리오

### 1. DeFi 프로토콜 거버넌스
- 수수료율 조정 투표
- 유동성 인센티브 변경
- 새로운 자산 추가 결정

### 2. NFT 커뮤니티 운영
- 로드맵 결정
- 아티스트 선정
- 커뮤니티 규칙 변경

### 3. 기업 거버넌스
- 이사 선임
- 배당 정책 결정
- 사업 전략 투표

## 라이선스

MIT License

## 기여하기

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## ⚠️ 중요 고지

**이 프로젝트는 개념 증명(Proof of Concept) 및 연구 목적으로 개발되었습니다.**

- 실제 선거나 중요한 투표에 사용하기 전에 전문적인 보안 감사가 필요합니다
- 모든 암호화 및 보안 구현은 프로토타입 수준입니다
- 실제 하드웨어 보안 모듈(HSM) 통합이 필요합니다
- 정부 인증 및 규제 승인이 필요할 수 있습니다

**교육 및 연구 목적으로만 사용하시기 바랍니다.**