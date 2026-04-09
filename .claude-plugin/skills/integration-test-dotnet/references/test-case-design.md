# Test Case Design Guide

## 5-Category System

Integration test cases are covered using the following 5 categories:

| Category | Description | Examples |
|----------|-------------|----------|
| **Happy Path** | Correct inputs producing expected results | User creation succeeds, list retrieval returns data |
| **Error Path** | Invalid inputs or error conditions | Validation errors, authentication failures |
| **Boundary** | Boundary condition behavior | Empty collections, max-length strings, pagination edges |
| **Edge Cases** | Special or unusual situations | Duplicate data, concurrent updates, empty strings |
| **External Dependency Errors** | External system failures | DB connection errors, external API timeouts |

## Required Test Cases by HTTP Method

### GET (List)

| Category | Test Case |
|----------|-----------|
| Happy Path | Returns all items when data exists |
| Boundary | Returns empty array when no data exists |
| Happy Path | Pagination works correctly |
| Boundary | Last page returns correct count |
| Error Path | Returns 401 without authentication |

### GET (Detail)

| Category | Test Case |
|----------|-----------|
| Happy Path | Returns correct data for existing ID |
| Error Path | Returns 404 for non-existent ID |
| Error Path | Returns 400 for invalid ID format |
| Error Path | Returns 401 without authentication |

### POST (Create)

| Category | Test Case |
|----------|-----------|
| Happy Path | Returns 201 with valid input + persisted to DB |
| Error Path | Returns 400 when required field is missing |
| Error Path | Returns 400 on validation violation |
| Edge Case | Returns 409 (Conflict) on duplicate data |
| External Dep | Rolls back on external API error |
| Error Path | Returns 401 without authentication |

### PUT/PATCH (Update)

| Category | Test Case |
|----------|-----------|
| Happy Path | Updates successfully with valid input + reflected in DB |
| Error Path | Returns 404 for non-existent ID |
| Error Path | Returns 400 on validation violation |
| Boundary | Normal response when no values change (same values) |
| Error Path | Returns 401 without authentication |

### DELETE

| Category | Test Case |
|----------|-----------|
| Happy Path | Returns 204 for existing ID + removed from DB |
| Error Path | Returns 404 for non-existent ID |
| Edge Case | Behavior when related data exists |
| Error Path | Returns 401 without authentication |

## Test Case Derivation Procedure

1. **Read the controller**: Identify all endpoints from route definitions and action methods
2. **Read request/response DTOs**: Identify validation rules from data annotations and FluentValidation rules
3. **Read the service/repository**: Identify edge cases from query logic and business rules
4. **Apply the 5-category matrix**: Enumerate cases using the tables above as reference

## Recommended Case Count

| Endpoint Type | Minimum Cases |
|--------------|:------------:|
| GET (List) | 4-5 |
| GET (Detail) | 3-4 |
| POST (Create) | 5-6 |
| PUT/PATCH (Update) | 4-5 |
| DELETE | 3-4 |

## Separation from Unit Tests

| Test Type | Target | DB | External API |
|-----------|--------|:--:|:----------:|
| Unit Test | Business logic in isolation | Mock/Fake | Mock |
| Integration Test | HTTP -> Controller -> Service -> Repository -> DB (full stack) | Real DB (Testcontainers) | WireMock.NET |
