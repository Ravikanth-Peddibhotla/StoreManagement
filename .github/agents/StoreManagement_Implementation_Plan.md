# StoreManagement — Implementation Plan

A modular, role-based store management system: **ASP.NET Core Web API** (.NET 10) backend + **Angular 20** frontend, backed by **SQL Server**.

---

## 1. Assumptions made explicit

These shape the whole design, so they're worth confirming before build starts:

| # | Assumption | Why |
|---|---|---|
| 1 | An **Admin can own multiple Stores** (1 Admin → many Stores) | More flexible than 1:1; easy to constrain later with a unique index if you'd rather cap it at one store per Admin |
| 2 | **Admins can Add/Update/SoftDelete/View Users within their own store(s)** | "Manage their store activities" realistically includes hiring/removing workers. SuperAdmin's control is platform-wide and unrestricted; Admin's is scoped to their own store |
| 3 | **User permissions are granular per store**, not a single fixed bundle | "Can do only specific works" reads as configurable — an Admin grants exactly which tasks (process sales, adjust stock, view reports, etc.) each worker can perform |
| 4 | **Soft delete only** — `IsDeleted` + `DeletedDate`/`DeletedBy` on every business entity, enforced via EF Core global query filters. Nothing is hard-deleted from the app layer | Preserves audit trail and referential integrity |
| 5 | Auth is **JWT access token + refresh token**, credentials stored via **ASP.NET Core Identity** | Stateless API, standard Angular SPA pattern |

If any of these don't match your intent (e.g. one store per Admin, or fixed role-based permissions instead of granular ones), the schema and API design in this plan flex easily — flag it early since it touches most modules.

---

## 2. Technology stack

| Layer | Choice |
|---|---|
| Backend runtime | .NET 10 (LTS, supported through Nov 2028) |
| Backend framework | ASP.NET Core Web API, Controllers (MVC pattern) |
| ORM | EF Core 10 |
| Auth | ASP.NET Core Identity + JWT Bearer + refresh tokens |
| Validation | FluentValidation |
| Mapping | Mapster or AutoMapper |
| Logging | Serilog → Seq / Application Insights |
| Backend tests | xUnit, NSubstitute/Moq, `WebApplicationFactory` for integration tests |
| Frontend framework | Angular 20 — standalone components (default), Signals, new `@if`/`@for` control flow |
| UI kit | Angular Material or PrimeNG (pick one; both work cleanly with standalone APIs) |
| Frontend tests | Jasmine/Karma (or Vitest) + Playwright/Cypress for e2e |
| Database | SQL Server 2019+ |
| Containerization | Docker (API + SQL Server via `docker-compose` for local dev) |
| CI/CD | GitHub Actions or Azure DevOps Pipelines |

---

## 3. WebAPI — solution structure

Clean Architecture layering (vertical) with feature-module folders (horizontal) inside `Application` and `API`. Each feature folder is self-contained enough to later be pulled out into its own project — or even its own service — without restructuring.

```
StoreManagement.sln
│
├── src/
│   ├── StoreManagement.Domain/              # Entities, enums, interfaces — no dependencies
│   │   ├── Entities/
│   │   ├── Enums/
│   │   └── Common/                          # AuditableEntity, ISoftDelete base contracts
│   │
│   ├── StoreManagement.Application/         # Business logic, no EF Core / ASP.NET references
│   │   ├── Common/                          # ApiResponse<T>, PagedResult<T>, exceptions
│   │   ├── Identity/                        # Login, refresh, token issuing services + DTOs
│   │   ├── SuperAdmin/                      # Admin & User account management services + DTOs
│   │   ├── StoreOps/                        # Store CRUD, StoreUser assignment, permissions
│   │   ├── Inventory/                       # Categories, Products, stock adjustments
│   │   ├── Sales/                           # Sale creation, sale history
│   │   └── Reporting/                       # Dashboard aggregation queries
│   │
│   ├── StoreManagement.Infrastructure/      # EF Core DbContext, repositories, Identity wiring
│   │   ├── Persistence/
│   │   │   ├── ApplicationDbContext.cs
│   │   │   ├── Configurations/              # IEntityTypeConfiguration<T> per entity
│   │   │   └── Migrations/
│   │   ├── Identity/                        # ApplicationUser, ApplicationRole, TokenService
│   │   └── Repositories/
│   │
│   ├── StoreManagement.API/                 # Composition root
│   │   ├── Controllers/
│   │   │   ├── AuthController.cs
│   │   │   ├── SuperAdmin/AdminsController.cs
│   │   │   ├── SuperAdmin/UsersController.cs
│   │   │   ├── StoreOps/StoresController.cs
│   │   │   ├── StoreOps/WorkersController.cs
│   │   │   ├── Inventory/ProductsController.cs
│   │   │   ├── Sales/SalesController.cs
│   │   │   └── Reporting/DashboardController.cs
│   │   ├── Middleware/                      # Global exception handler, request logging
│   │   ├── Filters/                         # Validation filter, audit filter
│   │   ├── Policies/                        # Authorization policy definitions
│   │   └── Program.cs
│   │
│   └── StoreManagement.Shared/              # Cross-cutting constants, extension methods
│
└── tests/
    ├── StoreManagement.UnitTests/
    └── StoreManagement.IntegrationTests/
```

**Authorization model:** role-based (`[Authorize(Roles = "SuperAdmin")]`) for coarse checks, plus policy-based checks (`CanManageStore`, `HasPermission("SALES_PROCESS")`) for scoped/granular checks — a custom `IAuthorizationHandler` resolves the second kind by looking up `StoreUserPermissions` for the current user + store combination.

---

## 4. WebAPI — phase-wise plan

### Phase 0 — Foundation
- Solution scaffold with the layers above; NuGet packages installed (EF Core 10, Identity, JWT Bearer, FluentValidation, Serilog, Swashbuckle)
- Base entity contracts: `AuditableEntity` (CreatedBy/CreatedDate/ModifiedBy/ModifiedDate), `ISoftDelete` (IsDeleted/DeletedBy/DeletedDate)
- `ApplicationDbContext` with EF Core global query filter auto-excluding `IsDeleted = true` rows
- `ApiResponse<T>` envelope, global exception handling middleware → RFC 7807 `ProblemDetails`
- CORS policy scoped to the Angular origin
- Serilog configured (console + file/Seq sink)

### Phase 1 — Identity & auth module
- `ApplicationUser : IdentityUser<Guid>`, `ApplicationRole : IdentityRole<Guid>`
- Seed roles (SuperAdmin, Admin, User) and one bootstrap SuperAdmin account
- JWT issuing (short-lived access token ~15 min) + refresh token (longer-lived, rotated on use, stored in `auth.RefreshTokens`)
- Endpoints: `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `POST /auth/change-password`
- Custom authorization policies + handler for permission-based checks
- `SaveChanges` interceptor to auto-populate audit columns from the current user

### Phase 2 — SuperAdmin module
- Admin CRUD: create, update, soft-delete, get-by-id, paged list with search/filter (active/inactive/deleted)
- User (worker) CRUD at platform level — same shape, restricted to `SuperAdmin` role
- Activate/deactivate toggle (`IsActive`), independent from soft delete
- Platform summary endpoint (counts: total Admins, Users, Stores)

### Phase 3 — Store & worker management (Admin-facing)
- Store CRUD scoped to the authenticated Admin (`AdminId` pulled from the JWT claims, never from the request body)
- `StoreUsers` management: Admin adds/updates/soft-deletes workers *within their own store(s)* — enforced by checking `StoreId` ownership against the caller's `AdminId`
- Permission grant/revoke endpoints (`POST /stores/{storeId}/workers/{userId}/permissions`)

### Phase 4 — Inventory
- Category CRUD (self-referencing for subcategories)
- Product CRUD, stock adjustment endpoint, low-stock query
- `StockTransactions` written on every adjustment for traceability

### Phase 5 — Sales / POS
- Sale creation (line items, totals, payment method) — requires `SALES_PROCESS` permission
- Sale history with filters (date range, store, worker)
- Void-sale endpoint — requires `SALES_VOID` permission, writes a reversing stock transaction

### Phase 6 — Reporting
- Role-scoped dashboards: SuperAdmin sees platform-wide stats, Admin sees their store(s)' performance, User sees their own processed sales
- CSV export (optional, defer if timeline is tight)

### Phase 7 — Cross-cutting hardening
- API versioning (`/api/v1/...`)
- FluentValidation on every request DTO
- Health check endpoint (`/health`) covering DB connectivity
- Swagger/OpenAPI with JWT bearer support configured
- Unit tests for services, integration tests for controllers via `WebApplicationFactory`
- Rate limiting on `/auth/*` endpoints

### Phase 8 — Deployment
- Dockerfile (multi-stage build) + `docker-compose` for API + SQL Server local dev
- CI pipeline: build → test → publish image
- Environment-specific `appsettings`, secrets via Key Vault/User Secrets (never in source)
- EF Core migration bundle applied as a deploy step

---

## 5. Angular — project structure

Angular 20 defaults to **standalone components** — there's no NgModule tree to design. Modularity here comes from folder-per-feature plus **lazy-loaded routes**, so each feature is its own bundle chunk.

```
store-management-ui/
├── src/
│   ├── app/
│   │   ├── core/                      # Singleton services — provided once in app.config.ts
│   │   │   ├── auth/                  # auth.service.ts (signals for currentUser/isAuthenticated)
│   │   │   ├── interceptors/          # jwt.interceptor.ts, error.interceptor.ts
│   │   │   ├── guards/                # auth.guard.ts, role.guard.ts, permission.guard.ts
│   │   │   └── models/
│   │   │
│   │   ├── shared/                    # Reusable, presentational — imported where needed
│   │   │   ├── components/            # data-table, confirm-dialog, toast, empty-state
│   │   │   ├── pipes/
│   │   │   └── directives/            # hasPermission structural directive
│   │   │
│   │   ├── features/                  # Lazy-loaded via loadChildren/loadComponent
│   │   │   ├── auth/                  # login page
│   │   │   ├── superadmin/            # admin-list, admin-form, user-list, user-form, dashboard
│   │   │   ├── admin/                 # stores, workers, permissions, store-dashboard
│   │   │   ├── worker/                # task views scoped by granted permissions
│   │   │   ├── inventory/             # categories, products, stock
│   │   │   └── sales/                 # new-sale (POS), sales-history
│   │   │
│   │   ├── layout/                    # Shell shells: header, sidenav (menu items filtered by role)
│   │   ├── app.routes.ts              # Top-level routes, lazy + guarded
│   │   └── app.config.ts              # providers: HttpClient, interceptors, router
│   │
│   └── environments/
```

**Auth/token storage note (a trade-off worth stating explicitly):** storing the JWT in `localStorage` is the simpler path but is readable by any injected script (XSS risk). The more defensible pattern is access token held in memory only (an Angular signal, lost on refresh) plus the refresh token in an `HttpOnly`, `Secure`, `SameSite` cookie set by the API — which requires the API to support cookie-based refresh and `withCredentials` on the Angular side. Recommended for anything beyond a prototype; called out here so it's a deliberate choice, not a default you drift into.

---

## 6. Angular — phase-wise plan

### Phase 0 — Project setup
- `ng new` with standalone bootstrap (`bootstrapApplication`), routing enabled
- Folder scaffold as above; ESLint + Prettier configured
- UI kit installed (Angular Material or PrimeNG); base theme applied
- `HttpClient` provided with `withInterceptors([jwtInterceptor, errorInterceptor])`

### Phase 1 — Core & auth
- `AuthService`: `login()`, `refresh()`, `logout()`, `currentUser` signal, `hasRole()`, `hasPermission()`
- JWT interceptor attaches the bearer token; on 401, attempts one silent refresh before failing
- `authGuard` (must be logged in), `roleGuard` (role match), `permissionGuard` (granular check for worker routes)
- Login page, 403/unauthorized page, 404 page

### Phase 2 — Layout & shared components
- Role-aware shell: sidenav menu items filtered by `currentUser().role`
- Shared `DataTable` (sort/paginate/search — built once, reused everywhere), `ConfirmDialog`, toast notifications
- `*hasPermission="'SALES_PROCESS'"` structural directive to show/hide UI affordances

### Phase 3 — SuperAdmin feature
- Admin list (paged, search, active/deleted filter) + add/edit reactive form + soft-delete confirm flow
- User (worker) platform-oversight list/CRUD
- Platform dashboard widgets (Admin count, User count, Store count)

### Phase 4 — Admin feature
- Store list/CRUD for the logged-in Admin's own stores
- Worker management scoped to a selected store: list, add, edit, soft-delete
- Permission assignment UI — checkbox grid of `store.Permissions` per worker

### Phase 5 — Inventory feature
- Category management, product list/CRUD, stock adjustment form with reason/notes
- Low-stock badge/indicator on the product list

### Phase 6 — Sales/POS feature
- New-sale screen: product search → cart → checkout, gated behind `SALES_PROCESS`
- Sales history list with date/store/worker filters

### Phase 7 — Reporting
- Role-specific dashboard views with charts (ngx-charts, Chart.js, or ApexCharts)

### Phase 8 — Polish & deployment
- Responsive pass, accessibility check (focus states, contrast, ARIA on custom components)
- Unit tests (Jasmine/Karma or Vitest) + e2e smoke tests (Playwright/Cypress) for the three role journeys
- Production build, Nginx/static hosting config, CI pipeline (build → test → deploy)

**Sequencing note:** Angular phase *N* generally starts once WebAPI phase *N*'s core endpoints are stable — Phase 0/1 (setup + auth) are natural to build together since the frontend needs real login endpoints to test against from day one. Phases 2 onward can run with a short lag rather than strictly sequentially.

---

## 7. Role & permission matrix

| Capability | SuperAdmin | Admin | User (worker) |
|---|:---:|:---:|:---:|
| Add/update/soft-delete/view **any** Admin account | ✅ | ❌ | ❌ |
| Add/update/soft-delete/view **any** User account (platform-wide) | ✅ | ❌ | ❌ |
| Add/update/soft-delete/view Users **within own store** | — | ✅ | ❌ |
| Create/manage own Store(s) | ❌ | ✅ | ❌ |
| Grant/revoke worker permissions | ❌ | ✅ | ❌ |
| Manage inventory | ❌ | ✅ | Only if granted `INVENTORY_MANAGE` |
| Process a sale | ❌ | ✅ | Only if granted `SALES_PROCESS` |
| Void a sale | ❌ | ✅ | Only if granted `SALES_VOID` |
| View store reports | Platform-wide | Own store(s) | Only if granted `REPORTS_VIEW` |

---

## 8. Representative API surface

```
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
POST   /api/v1/auth/logout

GET    /api/v1/superadmin/admins?search=&page=
POST   /api/v1/superadmin/admins
PUT    /api/v1/superadmin/admins/{id}
DELETE /api/v1/superadmin/admins/{id}          # soft delete
GET    /api/v1/superadmin/users?search=&page=
POST   /api/v1/superadmin/users
PUT    /api/v1/superadmin/users/{id}
DELETE /api/v1/superadmin/users/{id}           # soft delete

GET    /api/v1/stores                          # scoped to caller's AdminId
POST   /api/v1/stores
PUT    /api/v1/stores/{id}
DELETE /api/v1/stores/{id}

GET    /api/v1/stores/{storeId}/workers
POST   /api/v1/stores/{storeId}/workers
PUT    /api/v1/stores/{storeId}/workers/{userId}
DELETE /api/v1/stores/{storeId}/workers/{userId}
PUT    /api/v1/stores/{storeId}/workers/{userId}/permissions

GET    /api/v1/stores/{storeId}/products
POST   /api/v1/stores/{storeId}/products
POST   /api/v1/stores/{storeId}/products/{id}/stock-adjustment

POST   /api/v1/stores/{storeId}/sales
GET    /api/v1/stores/{storeId}/sales?from=&to=
POST   /api/v1/stores/{storeId}/sales/{id}/void
```

---

## 9. Suggested sequencing

| Phase | Backend focus | Frontend focus |
|---|---|---|
| 1 | Foundation + Identity/Auth | Project setup + Core/Auth |
| 2 | SuperAdmin module | Layout/shared + SuperAdmin UI |
| 3 | Store & worker management | Admin UI |
| 4 | Inventory | Inventory UI |
| 5 | Sales/POS | Sales/POS UI |
| 6 | Reporting | Reporting UI |
| 7 | Hardening (tests, versioning, validation) | Polish, accessibility, testing |
| 8 | Deployment pipeline | Deployment pipeline |

Treat these as workstreams, not fixed calendar weeks — actual duration depends on team size; the ordering (what must exist before what) is the part worth keeping fixed.

---

## 10. Future extensions (not in initial scope)

- Split `StoreManagement.Application` feature folders into separate class libraries (or services) once module boundaries stabilize — the folder structure here is deliberately drawn so that's a mechanical move, not a rewrite
- Multi-tenancy hardening if Admins ever need full data isolation beyond row-level `AdminId`/`StoreId` scoping
- Notification module (low-stock alerts, daily sales summary emails)
- Customer/loyalty tracking (currently `Sales.CustomerName`/`CustomerPhone` are simple free-text fields)
- Purchase-order / supplier management feeding into `StockTransactions`
- Mobile app reusing the same Web API
