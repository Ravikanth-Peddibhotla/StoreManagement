using Microsoft.AspNetCore.Identity;

namespace StoreManagement.Infrastructure.Identity;

public class ApplicationRole : IdentityRole<Guid>
{
    public string? Description { get; set; }
}
