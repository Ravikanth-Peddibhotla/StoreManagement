# StoreManagement project guidance

These are the core product decisions that shape the architecture and implementation for this repository.

## Core domain decisions

- An Admin can own more than one store. The relationship is one Admin -> many Stores, not a 1:1.
- Admins can manage their own store's Users. SuperAdmin platform-wide oversight covers Add/Update/SoftDelete/View on Admin and User accounts, but day-to-day hiring and removal of workers is scoped to the owning Admin for their own store(s).
- Worker permissions are granular, not a single fixed "User" role. Capabilities should be configurable per worker such as process sales, adjust stock, and view reports.
- Soft delete is required everywhere via `IsDeleted`, `DeletedDate`, and `DeletedBy`, enforced through EF Core global query filters. Nothing is hard-deleted from the app layer.

## Architecture expectations

- Keep the solution layered and follow clean architecture boundaries between API, Application, Domain, Infrastructure, Shared, and Tests.
- Do not let API concerns leak into the Domain layer.
- Use dependency injection, interfaces, repository/service abstractions, and explicit contracts.
- Keep controllers and client-facing orchestration thin; place business rules in the application/domain layers.
- Prefer DTOs and mapping layers to keep API contracts decoupled from domain internals.

## Persistence and domain rules

- Respect soft-delete behavior in repositories, queries, and domain logic.
- Prefer EF Core query filters and explicit `IsDeleted` checks instead of manual hard-deletes.
- Model multi-store ownership and scoped authorization carefully so Admin access does not leak across stores.
- Treat authorization and permission granularity as first-class business rules rather than a hard-coded role flag.

## Testing expectations

- Add or update unit tests for business logic and validation rules.
- Add or update integration tests for end-to-end behavior involving persistence, filtering, and authorization boundaries.
- Validate regression risks around soft-delete behavior, role scoping, and multi-store ownership.

## Output expectations for code changes

- Explain the root cause and the exact responsibility affected.
- Note which project/layer changed and why.
- Include the validation commands run and their results.
- Highlight risks or follow-up work for authorization, permission granularity, or soft-delete behavior.
