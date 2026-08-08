using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using StoreManagement.Domain.Entities;
using StoreManagement.Infrastructure.Identity;

namespace StoreManagement.Infrastructure.Persistence;

public class ApplicationDbContext : IdentityDbContext<ApplicationUser, ApplicationRole, Guid>
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<Store> Stores { get; set; }
    public DbSet<RefreshToken> RefreshTokens { get; set; }

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);

        builder.Entity<Store>(entity =>
        {
            entity.HasKey(x => x.Id);
            entity.Property(x => x.StoreName).HasMaxLength(200).IsRequired();
            entity.Property(x => x.StoreCode).HasMaxLength(20).IsRequired();
            entity.Property(x => x.Email).HasMaxLength(256);
            entity.HasIndex(x => x.StoreCode).IsUnique();

            entity.HasQueryFilter(x => !x.IsDeleted);
        });

        builder.Entity<RefreshToken>(entity =>
        {
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Token).HasMaxLength(500).IsRequired();
            entity.Property(x => x.JwtId).HasMaxLength(100).IsRequired();
            entity.HasIndex(x => x.Token).IsUnique();
            entity.HasIndex(x => x.UserId);

            entity.HasQueryFilter(x => !x.IsDeleted);
        });

        builder.Entity<ApplicationUser>(entity =>
        {
            entity.Property(x => x.FirstName).HasMaxLength(100).IsRequired();
            entity.Property(x => x.LastName).HasMaxLength(100).IsRequired();
            entity.HasIndex(x => x.UserName).IsUnique();
            entity.HasIndex(x => x.NormalizedEmail).IsUnique(false);
            entity.HasQueryFilter(x => !x.IsDeleted);
        });

        // Ensure all soft-deletable records are filtered by default.
        builder.Entity<ApplicationUser>().HasQueryFilter(x => !x.IsDeleted);
    }
}
