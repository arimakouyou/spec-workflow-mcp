# Test Case Design Guide

## 5-Category Taxonomy

Cover integration test cases using the following 5 categories.

| Category | Description | Examples |
|----------|-------------|----------|
| **Happy path** | Expected results for correct input | Successful user creation, list retrieval |
| **Error path** | Invalid input or error conditions | Validation errors, authentication errors |
| **Boundary** | Boundary condition behavior | Empty list, max length, page boundary |
| **Edge cases** | Special situations | Duplicate data, concurrent updates, empty strings |
| **External dependency errors** | External system failures | DB connection error, external API timeout |

## Required Test Cases by HTTP Method

### GET list

| Category | Test case |
|----------|-----------|
| Happy path | Returns all records when data exists |
| Boundary | Returns an empty array when no data exists |
| Happy path | Pagination works correctly |
| Boundary | Item count on the last page is correct |
| Error path | Returns 401 without authentication |

### GET detail

| Category | Test case |
|----------|-----------|
| Happy path | Returns the correct record for an existing ID |
| Error path | Returns 404 for a non-existent ID |
| Error path | Returns 400 for an invalid ID format |
| Error path | Returns 401 without authentication |

### POST create

| Category | Test case |
|----------|-----------|
| Happy path | Returns 201 + persists to DB for valid input |
| Error path | Returns 400 when a required field is missing |
| Error path | Returns 400 on validation failure |
| Edge case | Returns 409 (Conflict) for duplicate data |
| External dependency | Rolls back when the external API errors |
| Error path | Returns 401 without authentication |

### PUT/PATCH update

| Category | Test case |
|----------|-----------|
| Happy path | Successful update for valid input + reflected in DB |
| Error path | Returns 404 for a non-existent ID |
| Error path | Returns 400 on validation failure |
| Boundary | Returns successfully when there are no changes (same value) |
| Error path | Returns 401 without authentication |

### DELETE

| Category | Test case |
|----------|-----------|
| Happy path | Returns 204 + removes from DB for an existing ID |
| Error path | Returns 404 for a non-existent ID |
| Edge case | Behavior when related data exists |
| Error path | Returns 401 without authentication |

## Test Case Derivation Procedure

1. **Read the handler**: identify the endpoint list from route definitions
2. **Read request/response types**: derive validation conditions from the DTO structure
3. **Read the repository**: identify edge cases from query logic
4. **Map to the 5-category matrix**: enumerate cases referencing the tables above

## Case Count Targets

| Endpoint type | Minimum case count |
|---------------|:------------------:|
| GET list | 4-5 |
| GET detail | 3-4 |
| POST create | 5-6 |
| PUT/PATCH update | 4-5 |
| DELETE | 3-4 |

## Separation From UT

| Test type | Scope | DB | External API |
|-----------|-------|:--:|:------------:|
| UT | Business logic in isolation | mock/fake | mock |
| IT | All layers HTTP → handler → repository → DB | Real DB (testcontainers) | trait DI |
