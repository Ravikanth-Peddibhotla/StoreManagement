/* =================================================================
   StoreManagement — SQL Server Database Schema
   Target: Microsoft SQL Server 2019+
   Organized into schemas that mirror the application's modules:
     auth   -> identity, roles, refresh tokens
     store  -> stores, workers, permissions, catalog
     sales  -> transactions
     audit  -> change history
   ================================================================= */

-- =================================================================
-- 0. DATABASE + SCHEMAS
-- =================================================================
-- CREATE DATABASE StoreManagementDb;
-- GO
-- USE StoreManagementDb;
-- GO

CREATE SCHEMA auth AUTHORIZATION dbo;
GO
CREATE SCHEMA store AUTHORIZATION dbo;
GO
CREATE SCHEMA sales AUTHORIZATION dbo;
GO
CREATE SCHEMA audit AUTHORIZATION dbo;
GO

-- =================================================================
-- 1. AUTH SCHEMA
-- Users/Roles/UserRoles mirror what ASP.NET Core Identity expects
-- (AspNetUsers/AspNetRoles/AspNetUserRoles). EF Core migrations will
-- also generate AspNetUserClaims, AspNetRoleClaims, AspNetUserLogins
-- and AspNetUserTokens automatically -- not hand-written here since
-- this design doesn't add custom columns to them.
-- =================================================================

CREATE TABLE auth.Users (
    Id                      UNIQUEIDENTIFIER    NOT NULL DEFAULT NEWID(),
    UserName                NVARCHAR(256)       NOT NULL,
    NormalizedUserName      NVARCHAR(256)       NOT NULL,
    Email                   NVARCHAR(256)       NOT NULL,
    NormalizedEmail         NVARCHAR(256)       NOT NULL,
    EmailConfirmed          BIT                 NOT NULL DEFAULT 0,
    PasswordHash            NVARCHAR(MAX)       NOT NULL,
    SecurityStamp           NVARCHAR(MAX)       NULL,
    ConcurrencyStamp        NVARCHAR(MAX)       NULL,
    PhoneNumber             NVARCHAR(20)        NULL,
    PhoneNumberConfirmed    BIT                 NOT NULL DEFAULT 0,
    TwoFactorEnabled        BIT                 NOT NULL DEFAULT 0,
    LockoutEnd              DATETIMEOFFSET      NULL,
    LockoutEnabled          BIT                 NOT NULL DEFAULT 1,
    AccessFailedCount       INT                 NOT NULL DEFAULT 0,

    -- Application-specific columns
    FirstName               NVARCHAR(100)       NOT NULL,
    LastName                NVARCHAR(100)       NOT NULL,
    ProfileImageUrl         NVARCHAR(500)       NULL,
    IsActive                BIT                 NOT NULL DEFAULT 1,
    IsDeleted               BIT                 NOT NULL DEFAULT 0,
    CreatedDate             DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy               UNIQUEIDENTIFIER    NULL,
    ModifiedDate            DATETIME2           NULL,
    ModifiedBy              UNIQUEIDENTIFIER    NULL,
    DeletedDate             DATETIME2           NULL,
    DeletedBy               UNIQUEIDENTIFIER    NULL,

    CONSTRAINT PK_Users PRIMARY KEY CLUSTERED (Id)
);
GO

CREATE UNIQUE INDEX UX_Users_NormalizedUserName ON auth.Users(NormalizedUserName);
CREATE UNIQUE INDEX UX_Users_NormalizedEmail ON auth.Users(NormalizedEmail) WHERE IsDeleted = 0;
CREATE INDEX IX_Users_IsDeleted_IsActive ON auth.Users(IsDeleted, IsActive);
GO

CREATE TABLE auth.Roles (
    Id                  UNIQUEIDENTIFIER    NOT NULL DEFAULT NEWID(),
    Name                NVARCHAR(256)       NOT NULL,
    NormalizedName      NVARCHAR(256)       NOT NULL,
    ConcurrencyStamp    NVARCHAR(MAX)       NULL,
    Description         NVARCHAR(500)       NULL,

    CONSTRAINT PK_Roles PRIMARY KEY CLUSTERED (Id)
);
GO

CREATE UNIQUE INDEX UX_Roles_NormalizedName ON auth.Roles(NormalizedName);
GO

CREATE TABLE auth.UserRoles (
    UserId  UNIQUEIDENTIFIER NOT NULL,
    RoleId  UNIQUEIDENTIFIER NOT NULL,

    CONSTRAINT PK_UserRoles PRIMARY KEY CLUSTERED (UserId, RoleId),
    CONSTRAINT FK_UserRoles_Users FOREIGN KEY (UserId) REFERENCES auth.Users(Id) ON DELETE CASCADE,
    CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleId) REFERENCES auth.Roles(Id) ON DELETE CASCADE
);
GO

CREATE TABLE auth.RefreshTokens (
    Id              INT IDENTITY(1,1)   NOT NULL,
    UserId          UNIQUEIDENTIFIER    NOT NULL,
    Token           NVARCHAR(500)       NOT NULL,
    JwtId           NVARCHAR(100)       NOT NULL,
    ExpiresAtUtc    DATETIME2           NOT NULL,
    IsRevoked       BIT                 NOT NULL DEFAULT 0,
    IsUsed          BIT                 NOT NULL DEFAULT 0,
    CreatedDate     DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedByIp     NVARCHAR(50)        NULL,

    CONSTRAINT PK_RefreshTokens PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_RefreshTokens_Users FOREIGN KEY (UserId) REFERENCES auth.Users(Id) ON DELETE CASCADE
);
GO

CREATE INDEX IX_RefreshTokens_UserId ON auth.RefreshTokens(UserId);
CREATE UNIQUE INDEX UX_RefreshTokens_Token ON auth.RefreshTokens(Token);
GO

-- =================================================================
-- 2. STORE SCHEMA
-- =================================================================

CREATE TABLE store.Stores (
    Id              INT IDENTITY(1,1)   NOT NULL,
    AdminId         UNIQUEIDENTIFIER    NOT NULL,      -- owning Admin, auth.Users
    StoreName       NVARCHAR(200)       NOT NULL,
    StoreCode       NVARCHAR(20)        NOT NULL,
    AddressLine1    NVARCHAR(200)       NULL,
    AddressLine2    NVARCHAR(200)       NULL,
    City            NVARCHAR(100)       NULL,
    State           NVARCHAR(100)       NULL,
    Country         NVARCHAR(100)       NULL,
    PostalCode      NVARCHAR(20)        NULL,
    Phone           NVARCHAR(20)        NULL,
    Email           NVARCHAR(256)       NULL,
    LogoUrl         NVARCHAR(500)       NULL,
    IsActive        BIT                 NOT NULL DEFAULT 1,
    IsDeleted       BIT                 NOT NULL DEFAULT 0,
    CreatedDate     DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy       UNIQUEIDENTIFIER    NULL,
    ModifiedDate    DATETIME2           NULL,
    ModifiedBy      UNIQUEIDENTIFIER    NULL,
    DeletedDate     DATETIME2           NULL,
    DeletedBy       UNIQUEIDENTIFIER    NULL,

    CONSTRAINT PK_Stores PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_Stores_Admin FOREIGN KEY (AdminId) REFERENCES auth.Users(Id)
);
GO

CREATE UNIQUE INDEX UX_Stores_StoreCode ON store.Stores(StoreCode) WHERE IsDeleted = 0;
CREATE INDEX IX_Stores_AdminId ON store.Stores(AdminId);
GO

-- Maps workers (Users with role = User) to the store(s) they work at
CREATE TABLE store.StoreUsers (
    Id              INT IDENTITY(1,1)   NOT NULL,
    StoreId         INT                 NOT NULL,
    UserId          UNIQUEIDENTIFIER    NOT NULL,
    JoinedDate      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    IsActive        BIT                 NOT NULL DEFAULT 1,
    IsDeleted       BIT                 NOT NULL DEFAULT 0,
    CreatedDate     DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy       UNIQUEIDENTIFIER    NULL,
    ModifiedDate    DATETIME2           NULL,
    ModifiedBy      UNIQUEIDENTIFIER    NULL,
    DeletedDate     DATETIME2           NULL,
    DeletedBy       UNIQUEIDENTIFIER    NULL,

    CONSTRAINT PK_StoreUsers PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_StoreUsers_Store FOREIGN KEY (StoreId) REFERENCES store.Stores(Id),
    CONSTRAINT FK_StoreUsers_User FOREIGN KEY (UserId) REFERENCES auth.Users(Id),
    CONSTRAINT UQ_StoreUsers_Store_User UNIQUE (StoreId, UserId)
);
GO

CREATE INDEX IX_StoreUsers_UserId ON store.StoreUsers(UserId);
GO

-- Master list of grantable capabilities, seeded once
CREATE TABLE store.Permissions (
    Id              INT IDENTITY(1,1)   NOT NULL,
    PermissionCode  NVARCHAR(50)        NOT NULL,
    PermissionName  NVARCHAR(150)       NOT NULL,
    Module          NVARCHAR(50)        NOT NULL,    -- e.g. Inventory, Sales, Reports
    Description     NVARCHAR(300)       NULL,

    CONSTRAINT PK_Permissions PRIMARY KEY CLUSTERED (Id)
);
GO

CREATE UNIQUE INDEX UX_Permissions_Code ON store.Permissions(PermissionCode);
GO

-- Which permissions a specific worker holds at a specific store
CREATE TABLE store.StoreUserPermissions (
    Id              INT IDENTITY(1,1)   NOT NULL,
    StoreUserId     INT                 NOT NULL,
    PermissionId    INT                 NOT NULL,
    IsGranted       BIT                 NOT NULL DEFAULT 1,
    GrantedDate     DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    GrantedBy       UNIQUEIDENTIFIER    NULL,

    CONSTRAINT PK_StoreUserPermissions PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_SUP_StoreUser FOREIGN KEY (StoreUserId) REFERENCES store.StoreUsers(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SUP_Permission FOREIGN KEY (PermissionId) REFERENCES store.Permissions(Id),
    CONSTRAINT UQ_StoreUserPermissions UNIQUE (StoreUserId, PermissionId)
);
GO

CREATE TABLE store.Categories (
    Id                  INT IDENTITY(1,1)   NOT NULL,
    StoreId             INT                 NOT NULL,
    CategoryName        NVARCHAR(150)       NOT NULL,
    ParentCategoryId    INT                 NULL,
    IsActive            BIT                 NOT NULL DEFAULT 1,
    IsDeleted           BIT                 NOT NULL DEFAULT 0,
    CreatedDate         DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy           UNIQUEIDENTIFIER    NULL,
    ModifiedDate        DATETIME2           NULL,
    ModifiedBy          UNIQUEIDENTIFIER    NULL,

    CONSTRAINT PK_Categories PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_Categories_Store FOREIGN KEY (StoreId) REFERENCES store.Stores(Id),
    CONSTRAINT FK_Categories_Parent FOREIGN KEY (ParentCategoryId) REFERENCES store.Categories(Id)
);
GO

CREATE INDEX IX_Categories_StoreId ON store.Categories(StoreId);
GO

CREATE TABLE store.Products (
    Id                  INT IDENTITY(1,1)   NOT NULL,
    StoreId             INT                 NOT NULL,
    CategoryId          INT                 NULL,
    ProductName         NVARCHAR(200)       NOT NULL,
    SKU                 NVARCHAR(50)        NOT NULL,
    Barcode             NVARCHAR(50)        NULL,
    Description         NVARCHAR(500)       NULL,
    UnitPrice           DECIMAL(18,2)       NOT NULL DEFAULT 0,
    CostPrice           DECIMAL(18,2)       NOT NULL DEFAULT 0,
    StockQuantity       INT                 NOT NULL DEFAULT 0,
    ReorderLevel        INT                 NOT NULL DEFAULT 0,
    UnitOfMeasure       NVARCHAR(20)        NULL,
    ImageUrl            NVARCHAR(500)       NULL,
    IsActive            BIT                 NOT NULL DEFAULT 1,
    IsDeleted           BIT                 NOT NULL DEFAULT 0,
    CreatedDate         DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy           UNIQUEIDENTIFIER    NULL,
    ModifiedDate        DATETIME2           NULL,
    ModifiedBy          UNIQUEIDENTIFIER    NULL,

    CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_Products_Store FOREIGN KEY (StoreId) REFERENCES store.Stores(Id),
    CONSTRAINT FK_Products_Category FOREIGN KEY (CategoryId) REFERENCES store.Categories(Id),
    CONSTRAINT CK_Products_Price CHECK (UnitPrice >= 0 AND CostPrice >= 0),
    CONSTRAINT CK_Products_Stock CHECK (StockQuantity >= 0)
);
GO

CREATE UNIQUE INDEX UX_Products_Store_SKU ON store.Products(StoreId, SKU) WHERE IsDeleted = 0;
CREATE INDEX IX_Products_StoreId ON store.Products(StoreId);
GO

CREATE TABLE store.StockTransactions (
    Id                  BIGINT IDENTITY(1,1)    NOT NULL,
    ProductId           INT                     NOT NULL,
    TransactionType     NVARCHAR(20)            NOT NULL,   -- IN, OUT, ADJUSTMENT
    Quantity            INT                     NOT NULL,
    ReferenceType       NVARCHAR(50)            NULL,       -- e.g. Sale, PurchaseOrder, Manual
    ReferenceId         BIGINT                  NULL,
    Notes               NVARCHAR(300)           NULL,
    TransactionDate     DATETIME2               NOT NULL DEFAULT SYSUTCDATETIME(),
    PerformedByUserId   UNIQUEIDENTIFIER        NOT NULL,

    CONSTRAINT PK_StockTransactions PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_StockTx_Product FOREIGN KEY (ProductId) REFERENCES store.Products(Id),
    CONSTRAINT FK_StockTx_User FOREIGN KEY (PerformedByUserId) REFERENCES auth.Users(Id),
    CONSTRAINT CK_StockTx_Type CHECK (TransactionType IN ('IN', 'OUT', 'ADJUSTMENT'))
);
GO

CREATE INDEX IX_StockTransactions_ProductId ON store.StockTransactions(ProductId);
GO

-- =================================================================
-- 3. SALES SCHEMA
-- =================================================================

CREATE TABLE sales.Sales (
    Id                  BIGINT IDENTITY(1,1)    NOT NULL,
    StoreId             INT                     NOT NULL,
    SaleNumber          NVARCHAR(30)            NOT NULL,
    SaleDate            DATETIME2               NOT NULL DEFAULT SYSUTCDATETIME(),
    ProcessedByUserId   UNIQUEIDENTIFIER        NOT NULL,
    CustomerName        NVARCHAR(150)           NULL,
    CustomerPhone       NVARCHAR(20)            NULL,
    SubTotal            DECIMAL(18,2)           NOT NULL DEFAULT 0,
    TaxAmount           DECIMAL(18,2)           NOT NULL DEFAULT 0,
    DiscountAmount      DECIMAL(18,2)           NOT NULL DEFAULT 0,
    TotalAmount         DECIMAL(18,2)           NOT NULL DEFAULT 0,
    PaymentMethod       NVARCHAR(30)            NULL,       -- Cash, Card, UPI, etc.
    PaymentStatus       NVARCHAR(20)            NOT NULL DEFAULT 'Paid',
    IsVoided            BIT                     NOT NULL DEFAULT 0,
    CreatedDate         DATETIME2               NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Sales PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_Sales_Store FOREIGN KEY (StoreId) REFERENCES store.Stores(Id),
    CONSTRAINT FK_Sales_User FOREIGN KEY (ProcessedByUserId) REFERENCES auth.Users(Id)
);
GO

CREATE UNIQUE INDEX UX_Sales_StoreId_SaleNumber ON sales.Sales(StoreId, SaleNumber);
CREATE INDEX IX_Sales_StoreId_SaleDate ON sales.Sales(StoreId, SaleDate);
GO

CREATE TABLE sales.SaleItems (
    Id              BIGINT IDENTITY(1,1)    NOT NULL,
    SaleId          BIGINT                  NOT NULL,
    ProductId       INT                     NOT NULL,
    Quantity        INT                     NOT NULL,
    UnitPrice       DECIMAL(18,2)           NOT NULL,
    DiscountAmount  DECIMAL(18,2)           NOT NULL DEFAULT 0,
    LineTotal       AS (Quantity * UnitPrice - DiscountAmount) PERSISTED,

    CONSTRAINT PK_SaleItems PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_SaleItems_Sale FOREIGN KEY (SaleId) REFERENCES sales.Sales(Id) ON DELETE CASCADE,
    CONSTRAINT FK_SaleItems_Product FOREIGN KEY (ProductId) REFERENCES store.Products(Id),
    CONSTRAINT CK_SaleItems_Qty CHECK (Quantity > 0)
);
GO

CREATE INDEX IX_SaleItems_SaleId ON sales.SaleItems(SaleId);
GO

-- =================================================================
-- 4. AUDIT SCHEMA
-- General-purpose change log, used heavily for SuperAdmin oversight
-- of Add/Update/SoftDelete actions on Admin and User accounts.
-- =================================================================

CREATE TABLE audit.AuditLogs (
    Id                      BIGINT IDENTITY(1,1)   NOT NULL,
    TableName               NVARCHAR(128)          NOT NULL,
    RecordId                NVARCHAR(50)           NOT NULL,
    ActionType              NVARCHAR(20)           NOT NULL,  -- Insert, Update, SoftDelete, Restore
    OldValues               NVARCHAR(MAX)          NULL,
    NewValues               NVARCHAR(MAX)          NULL,
    PerformedByUserId       UNIQUEIDENTIFIER       NULL,
    PerformedDate           DATETIME2              NOT NULL DEFAULT SYSUTCDATETIME(),
    IpAddress               NVARCHAR(50)           NULL,

    CONSTRAINT PK_AuditLogs PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT FK_AuditLogs_User FOREIGN KEY (PerformedByUserId) REFERENCES auth.Users(Id) ON DELETE SET NULL
);
GO

CREATE INDEX IX_AuditLogs_Table_Record ON audit.AuditLogs(TableName, RecordId);
CREATE INDEX IX_AuditLogs_PerformedByUserId ON audit.AuditLogs(PerformedByUserId);
GO

-- =================================================================
-- 5. SEED DATA
-- =================================================================

INSERT INTO auth.Roles (Id, Name, NormalizedName, Description) VALUES
(NEWID(), 'SuperAdmin', 'SUPERADMIN', 'Application owner. Adds, updates, soft-deletes and views Admin and User accounts.'),
(NEWID(), 'Admin',      'ADMIN',      'Store owner. Manages own store(s) and the Users who work there.'),
(NEWID(), 'User',       'USER',       'Store worker. Limited to permissions granted by their Admin.');
GO

INSERT INTO store.Permissions (PermissionCode, PermissionName, Module, Description) VALUES
('INVENTORY_VIEW',   'View inventory',       'Inventory', 'View product and stock listings'),
('INVENTORY_MANAGE', 'Manage inventory',     'Inventory', 'Add/update products, adjust stock levels'),
('SALES_PROCESS',    'Process sales',        'Sales',     'Create new sales transactions'),
('SALES_VIEW',       'View sales history',   'Sales',     'View past sales records'),
('SALES_VOID',       'Void sales',           'Sales',     'Cancel or void a completed sale'),
('REPORTS_VIEW',     'View reports',         'Reports',   'Access store performance reports');
GO
