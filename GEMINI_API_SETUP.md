# Gemini API 키 시스템 환경변수 설정 가이드

## 권장 환경변수명

```bash
GEMINI_API_KEY=your_api_key_here
```

## 운영체제별 설정 방법

### Windows

#### 방법 1: GUI를 통한 설정 (권장)
1. **시작 메뉴** → "환경 변수" 검색
2. **"시스템 환경 변수 편집"** 클릭
3. **"환경 변수"** 버튼 클릭
4. **사용자 변수** 섹션에서 **"새로 만들기"** 클릭
5. 변수 이름: `GEMINI_API_KEY`
6. 변수 값: `your_actual_api_key_here`
7. **확인** → **확인** → **확인**

#### 방법 2: PowerShell (관리자 권한)
```powershell
# 현재 사용자용 설정
[Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "your_api_key_here", "User")

# 시스템 전체용 설정 (선택사항)
[Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "your_api_key_here", "Machine")
```

#### 방법 3: 명령 프롬프트 (임시)
```cmd
set GEMINI_API_KEY=your_api_key_here
```

### macOS

#### 방법 1: ~/.zshrc 또는 ~/.bash_profile 수정
```bash
# 터미널에서 실행
echo 'export GEMINI_API_KEY="your_api_key_here"' >> ~/.zshrc
source ~/.zshrc
```

#### 방법 2: 직접 파일 편집
```bash
# zsh (macOS 기본)
nano ~/.zshrc

# bash
nano ~/.bash_profile
```
파일에 다음 라인 추가:
```bash
export GEMINI_API_KEY="your_api_key_here"
```

### Linux

#### ~/.bashrc 수정
```bash
echo 'export GEMINI_API_KEY="your_api_key_here"' >> ~/.bashrc
source ~/.bashrc
```

#### 시스템 전체 설정 (/etc/environment)
```bash
sudo echo 'GEMINI_API_KEY="your_api_key_here"' >> /etc/environment
```

## 설정 확인 방법

### Windows PowerShell
```powershell
$env:GEMINI_API_KEY
```

### macOS/Linux Terminal
```bash
echo $GEMINI_API_KEY
```

### R에서 확인
```r
# R 콘솔에서 실행
Sys.getenv("GEMINI_API_KEY")

# 또는 더 안전한 확인
if (Sys.getenv("GEMINI_API_KEY") != "") {
  cat("[OK] API 키가 정상적으로 설정되었습니다.\n")
  cat("키 길이:", nchar(Sys.getenv("GEMINI_API_KEY")), "자\n")
} else {
  cat("[ERROR] API 키가 설정되지 않았습니다.\n")
}
```

## 보안 주의사항

### 권장사항
- **시스템 환경변수 사용** (이 가이드의 방법)
- API 키를 Git 저장소에 **절대 커밋하지 않기**
- `.gitignore`에 `.env`, `.Renviron` 파일 추가
- API 키 공유 시 마스킹 처리

### 피해야 할 것
- 코드에 직접 하드코딩
- 공개된 저장소에 API 키 노출
- 불필요한 권한 부여

## R 코드에서 사용법

```r
# 환경변수에서 API 키 가져오기
api_key <- Sys.getenv("GEMINI_API_KEY")

# 키 유효성 검사
if (api_key == "" || is.na(api_key)) {
  stop("ERROR: GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")
}

# gemini.R 패키지에서 사용
library(gemini.R)
setAPI(api_key)
```

## IDE별 설정

### RStudio
1. 환경변수 설정 후 **RStudio 완전 재시작**
2. **Tools** → **Global Options** → **General** → **Basic** → **Restore .RData into workspace at startup** 체크 해제 권장

### VSCode
1. 환경변수 설정 후 **VSCode 완전 재시작**
2. R Extension이 환경변수를 자동으로 인식

## 재시작 필요성

**중요**: 환경변수 설정 후 다음을 모두 재시작해야 합니다:
- R/RStudio/VSCode 등 개발 환경
- Windows의 경우 때로는 시스템 재부팅 필요

## 문제 해결

### 환경변수가 인식되지 않는 경우
1. **완전 재시작** 확인
2. **오타 확인** (`GEMINI_API_KEY` 정확한 철자)
3. **권한 확인** (사용자 변수 vs 시스템 변수)
4. **IDE 설정 확인** (특히 RStudio)

### API 키 관련 오류
```r
# 디버깅용 코드
cat("API 키 존재 여부:", Sys.getenv("GEMINI_API_KEY") != "", "\n")
cat("API 키 길이:", nchar(Sys.getenv("GEMINI_API_KEY")), "\n")
cat("API 키 형식:", substr(Sys.getenv("GEMINI_API_KEY"), 1, 6), "...\n")
```

---

**팁**: 팀 프로젝트의 경우 이 가이드를 팀원들과 공유하여 일관된 환경 설정을 유지하세요.