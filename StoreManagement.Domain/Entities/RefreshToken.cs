using StoreManagement.Domain.Common;

namespace StoreManagement.Domain.Entities;

public class RefreshToken : AuditableEntity
{
    public int Id { get; set; }
    public Guid UserId { get; set; }
    public string Token { get; set; } = string.Empty;
    public string JwtId { get; set; } = string.Empty;
    public DateTime ExpiresAtUtc { get; set; }
    public bool IsRevoked { get; set; }
    public bool IsUsed { get; set; }
    public string? CreatedByIp { get; set; }
}
