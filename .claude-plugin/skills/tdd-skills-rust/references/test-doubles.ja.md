# テストダブル（Test Double）

外部依存を切り離してテストを高速・安定化させる手法。

## Rust におけるテストダブルの実現方法

Rust では trait を活用してテストダブルを実現する。
主な方法: 手動の trait 実装、`mockall` クレート。

## テストダブルの5種類

### 1. Dummy（ダミー）

引数を埋めるだけで実際には使われない。

```rust
struct DummyLogger;
impl Logger for DummyLogger {
    fn log(&self, _msg: &str) {}
}
```

### 2. Stub（スタブ）

決まった値を返すだけ。

```rust
struct StubUserRepository;
impl UserRepository for StubUserRepository {
    fn find_by_id(&self, id: i64) -> Result<Option<User>, DbError> {
        Ok(Some(User { id, name: "Test User".into() }))
    }
}

#[test]
fn get_user_name() {
    let repo = StubUserRepository;
    let service = UserService::new(Box::new(repo));

    let name = service.get_user_name(1).unwrap();

    assert_eq!(name, "Test User");
}
```

使用場面:
- DB からの取得結果を固定したい
- 外部 API のレスポンスをコントロールしたい

### 3. Spy（スパイ）

呼び出しを記録する。

```rust
use std::sync::{Arc, Mutex};

struct SpyEmailService {
    sent_emails: Arc<Mutex<Vec<String>>>,
}

impl SpyEmailService {
    fn new() -> Self {
        Self { sent_emails: Arc::new(Mutex::new(vec![])) }
    }
}

impl EmailService for SpyEmailService {
    fn send(&self, to: &str, _subject: &str, _body: &str) {
        self.sent_emails.lock().unwrap().push(to.to_string());
    }
}

#[test]
fn send_welcome_email() {
    let spy = SpyEmailService::new();
    let emails = spy.sent_emails.clone();
    let service = RegistrationService::new(Box::new(spy));

    service.register("user@example.com").unwrap();

    let sent = emails.lock().unwrap();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0], "user@example.com");
}
```

### 4. Mock（モック）

期待する呼び出しを検証する。`mockall` クレートを使用。

```rust
use mockall::automock;

#[automock]
trait UserRepository: Send + Sync {
    fn find_by_id(&self, id: i64) -> Result<Option<User>, DbError>;
    fn save(&self, user: &NewUser) -> Result<User, DbError>;
    fn delete(&self, id: i64) -> Result<(), DbError>;
}

#[test]
fn delete_user_calls_repository() {
    let mut mock_repo = MockUserRepository::new();
    mock_repo
        .expect_delete()
        .with(mockall::predicate::eq(123))
        .times(1)
        .returning(|_| Ok(()));

    let service = UserService::new(Box::new(mock_repo));
    service.delete_user(123).unwrap();
    // mock のドロップ時に expect が満たされたか自動検証
}
```

Mock vs Spy:
- Mock: 期待を事前に設定して検証（振る舞い検証）
- Spy: 実際の呼び出しを記録して後で確認（状態検証）

### 5. Fake（フェイク）

簡易的な実装（インメモリ DB 等）。

```rust
use std::collections::HashMap;
use std::sync::Mutex;

struct FakeUserRepository {
    users: Mutex<HashMap<i64, User>>,
    next_id: Mutex<i64>,
}

impl FakeUserRepository {
    fn new() -> Self {
        Self {
            users: Mutex::new(HashMap::new()),
            next_id: Mutex::new(1),
        }
    }
}

impl UserRepository for FakeUserRepository {
    fn find_by_id(&self, id: i64) -> Result<Option<User>, DbError> {
        Ok(self.users.lock().unwrap().get(&id).cloned())
    }

    fn save(&self, new_user: &NewUser) -> Result<User, DbError> {
        let mut next_id = self.next_id.lock().unwrap();
        let user = User { id: *next_id, name: new_user.name.clone() };
        self.users.lock().unwrap().insert(*next_id, user.clone());
        *next_id += 1;
        Ok(user)
    }

    fn delete(&self, id: i64) -> Result<(), DbError> {
        self.users.lock().unwrap().remove(&id);
        Ok(())
    }
}
```

使用場面:
- 複雑なビジネスロジックのテスト
- 複数の操作を組み合わせたテスト
- 本物に近い振る舞いが必要

## テストダブルの選択基準

```
何をテストしたい？
  ├─ 戻り値だけ → Stub
  ├─ 呼び出されたか → Mock (mockall)
  ├─ 呼び出し履歴 → Spy
  ├─ 複雑な状態遷移 → Fake
  └─ 何も使わない → Dummy
```

| 状況 | 推奨 | 理由 |
|------|------|------|
| DB アクセス | Fake (InMemory) / Stub | 高速、状態管理 |
| 外部 API 呼び出し | Stub / Mock | 固定レスポンス、呼び出し検証 |
| メール送信等の副作用 | Spy / Mock | 送信履歴確認 |
| 時刻・乱数 | Stub (trait 経由) | 固定値で再現性確保 |

## アンチパターン

### 過度な Mock 使用

```rust
// 悪い: すべてを mock にする
#[test]
fn calculate_price() {
    let mut mock_item = MockItem::new();
    mock_item.expect_price().returning(|| 100);
    // mock だらけで何をテストしているか不明確
}

// 良い: 実際のオブジェクトと組み合わせ
#[test]
fn calculate_price() {
    let item = Item { name: "Book".into(), price: 100 };
    let mut cart = ShoppingCart::new();
    cart.add_item(item);
    assert_eq!(cart.total(), 100);
}
```

原則: 最もシンプルなテストダブルを使う。迷ったら Stub から始める。
