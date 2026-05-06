# Test Doubles

A technique for isolating external dependencies to make tests fast and stable.

## Implementing Test Doubles in Rust

In Rust, test doubles are implemented using traits.
Main approaches: hand-written trait implementations, or the `mockall` crate.

## The Five Kinds of Test Doubles

### 1. Dummy

Only fills a parameter slot; never actually used.

```rust
struct DummyLogger;
impl Logger for DummyLogger {
    fn log(&self, _msg: &str) {}
}
```

### 2. Stub

Returns a fixed value.

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

When to use:
- You want to fix the result returned from the DB
- You want to control external API responses

### 3. Spy

Records calls.

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

### 4. Mock

Verifies expected calls. Use the `mockall` crate.

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
    // Expectations are verified automatically when the mock is dropped
}
```

Mock vs Spy:
- Mock: set expectations up front and verify them (behavior verification)
- Spy: record actual calls and check them later (state verification)

### 5. Fake

A simplified implementation (e.g. an in-memory DB).

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

When to use:
- Testing complex business logic
- Tests that combine multiple operations
- When realistic behavior is required

## How to Choose a Test Double

```
What do you want to test?
  ├─ Just the return value -> Stub
  ├─ Whether it was called -> Mock (mockall)
  ├─ Call history -> Spy
  ├─ Complex state transitions -> Fake
  └─ Nothing -> Dummy
```

| Situation | Recommended | Reason |
|-----------|-------------|--------|
| DB access | Fake (InMemory) / Stub | Fast, manages state |
| External API call | Stub / Mock | Fixed response, call verification |
| Side effects like email | Spy / Mock | Verify send history |
| Time / random values | Stub (via trait) | Fixed values for reproducibility |

## Antipatterns

### Excessive Use of Mocks

```rust
// Bad: mock everything
#[test]
fn calculate_price() {
    let mut mock_item = MockItem::new();
    mock_item.expect_price().returning(|| 100);
    // So many mocks that what is being tested becomes unclear
}

// Good: combine real objects
#[test]
fn calculate_price() {
    let item = Item { name: "Book".into(), price: 100 };
    let mut cart = ShoppingCart::new();
    cart.add_item(item);
    assert_eq!(cart.total(), 100);
}
```

Principle: use the simplest test double that works. When in doubt, start from a Stub.
