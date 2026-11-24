# 전세계약 도우미 로그인 연결

## 웹앱과 데이터베이스

1. Supabase 프로젝트를 만들고 SQL Editor에서 `jeonse-supabase.sql`을 실행한다. Data API에서 `public` 스키마를 사용할 수 있어야 한다.
   이어서 `001-listings-and-visit-checks.sql`을 실행한다. 이미 운영 중인 프로젝트에는 두 번째 SQL만 적용한다. 새 웹앱을 배포하기 전에 실행하며 기존 기록도 이 단계에서 옮겨진다.
2. `index.html`의 `cloudConfig`에 프로젝트 URL과 **Publishable key**를 넣는다. OAuth 비밀 키와 데이터베이스 비밀번호는 Supabase 대시보드에서 관리한다.
3. `index.html`과 `jeonse-example-rooms.png`를 같은 폴더에 두고 정적 웹 호스팅에 올린다. Supabase의 Authentication URL Configuration에서 배포한 웹 주소를 Site URL과 Redirect URLs에 등록한다.

## 로그인 방식별 설정

- **Google** · Google Cloud에서 웹 OAuth 클라이언트를 만든다. Google에는 Supabase가 표시하는 콜백 URL을 등록하고, Supabase의 Google 제공자 설정에 클라이언트 ID와 비밀 키를 입력한다. [Supabase Google 설정](https://supabase.com/docs/guides/auth/social-sign-in/auth-google)
- **이메일과 비밀번호** · Supabase의 Email 제공자와 이메일 확인 설정을 유지한다. 처음에는 Google로 로그인하고 **내 계정 → 이메일 로그인용 비밀번호 설정**에서 비밀번호를 만든다. 이후 같은 이메일과 비밀번호로 같은 계정에 로그인할 수 있다. 비밀번호를 잊었을 때도 Google로 로그인한 뒤 다시 설정한다. 이 흐름에는 이메일 발송 설정이 필요하지 않다. [Supabase 계정 연결](https://supabase.com/docs/guides/auth/auth-identity-linking)

활성화한 방식으로 로그인해 매물을 저장한다. 다른 브라우저에서 같은 계정으로 로그인해 매물과 멈춘 계약 질문을 확인한다. 별도의 계정에서는 이 기록을 읽거나 바꿀 수 없는지 확인한다.

비회원으로 만든 기록이 있으면 로그인 후 내 계정에서 기록을 옮길 수 있다. 기존 계정 매물에 추가하며, 서버 저장이 확인되면 이 브라우저의 비회원 기록을 정리한다. 여러 기기가 동시에 수정하면 최신 서버 기록을 덮어쓰기 전에 동기화를 멈추고 계정 화면에 표시한다.
