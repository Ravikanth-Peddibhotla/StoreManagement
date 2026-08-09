using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using StoreManagement.Application.Identity;
using StoreManagement.Infrastructure.Identity;
using StoreManagement.Infrastructure.Persistence;

namespace StoreManagement.Infrastructure.Identity;

public class AuthService : IAuthService
{
    private readonly UserManager<ApplicationUser> _userManager;
    private readonly ApplicationDbContext _dbContext;
    private readonly JwtSettings _jwtSettings;

    public AuthService(
        UserManager<ApplicationUser> userManager,
        ApplicationDbContext dbContext,
        IOptions<JwtSettings> jwtSettings)
    {
        _userManager = userManager;
        _dbContext = dbContext;
        _jwtSettings = jwtSettings.Value;
    }

    public async Task<AuthResponse> LoginAsync(LoginRequest request, CancellationToken cancellationToken = default)
    {
        var user = await _userManager.FindByEmailAsync(request.Email);
        if (user is null || user.IsDeleted || !user.IsActive)
        {
            throw new UnauthorizedAccessException("Invalid credentials.");
        }

        var isValid = await _userManager.CheckPasswordAsync(user, request.Password);
        if (!isValid)
        {
            throw new UnauthorizedAccessException("Invalid credentials.");
        }

        var roles = await _userManager.GetRolesAsync(user);
        var accessToken = GenerateAccessToken(user, roles);
        var refreshToken = GenerateRefreshToken();

        var tokenEntity = new StoreManagement.Domain.Entities.RefreshToken
        {
            UserId = user.Id,
            Token = refreshToken,
            JwtId = Guid.NewGuid().ToString(),
            ExpiresAtUtc = DateTime.UtcNow.AddDays(7),
            CreatedByIp = "system",
            IsRevoked = false,
            IsUsed = false,
            CreatedDate = DateTime.UtcNow,
            CreatedBy = user.Id
        };

        _dbContext.RefreshTokens.Add(tokenEntity);
        await _dbContext.SaveChangesAsync(cancellationToken);

        return new AuthResponse
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresAtUtc = DateTime.UtcNow.AddMinutes(_jwtSettings.ExpiryMinutes),
            UserId = user.Id.ToString(),
            Email = user.Email ?? string.Empty,
            FirstName = user.FirstName,
            LastName = user.LastName,
            Roles = roles.ToList()
        };
    }

    public async Task<AuthResponse> RefreshTokenAsync(string refreshToken, CancellationToken cancellationToken = default)
    {
        var tokenRecord = await _dbContext.RefreshTokens
            .FirstOrDefaultAsync(x => x.Token == refreshToken && !x.IsDeleted, cancellationToken);

        if (tokenRecord is null || tokenRecord.IsRevoked || tokenRecord.IsUsed || tokenRecord.ExpiresAtUtc <= DateTime.UtcNow)
        {
            throw new UnauthorizedAccessException("Refresh token is invalid or expired.");
        }

        var user = await _userManager.FindByIdAsync(tokenRecord.UserId.ToString());
        if (user is null || user.IsDeleted || !user.IsActive)
        {
            throw new UnauthorizedAccessException("User is no longer active.");
        }

        tokenRecord.IsUsed = true;
        tokenRecord.IsRevoked = true;

        var roles = await _userManager.GetRolesAsync(user);
        var newAccessToken = GenerateAccessToken(user, roles);
        var newRefreshToken = GenerateRefreshToken();

        var replacement = new StoreManagement.Domain.Entities.RefreshToken
        {
            UserId = user.Id,
            Token = newRefreshToken,
            JwtId = Guid.NewGuid().ToString(),
            ExpiresAtUtc = DateTime.UtcNow.AddDays(7),
            CreatedByIp = "system",
            IsRevoked = false,
            IsUsed = false,
            CreatedDate = DateTime.UtcNow,
            CreatedBy = user.Id
        };

        _dbContext.RefreshTokens.Add(replacement);
        await _dbContext.SaveChangesAsync(cancellationToken);

        return new AuthResponse
        {
            AccessToken = newAccessToken,
            RefreshToken = newRefreshToken,
            ExpiresAtUtc = DateTime.UtcNow.AddMinutes(_jwtSettings.ExpiryMinutes),
            UserId = user.Id.ToString(),
            Email = user.Email ?? string.Empty,
            FirstName = user.FirstName,
            LastName = user.LastName,
            Roles = roles.ToList()
        };
    }

    public async Task LogoutAsync(string refreshToken, CancellationToken cancellationToken = default)
    {
        var tokenRecord = await _dbContext.RefreshTokens
            .FirstOrDefaultAsync(x => x.Token == refreshToken && !x.IsDeleted, cancellationToken);

        if (tokenRecord is null)
        {
            return;
        }

        tokenRecord.IsRevoked = true;
        tokenRecord.IsUsed = true;
        tokenRecord.DeletedDate = DateTime.UtcNow;
        tokenRecord.IsDeleted = true;

        await _dbContext.SaveChangesAsync(cancellationToken);
    }

    private string GenerateAccessToken(ApplicationUser user, IList<string> roles)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_jwtSettings.Key));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.UserName ?? user.Email ?? string.Empty),
            new(ClaimTypes.Email, user.Email ?? string.Empty),
            new("firstName", user.FirstName),
            new("lastName", user.LastName)
        };

        foreach (var role in roles)
        {
            claims.Add(new Claim(ClaimTypes.Role, role));
        }

        var token = new JwtSecurityToken(
            issuer: _jwtSettings.Issuer,
            audience: _jwtSettings.Audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_jwtSettings.ExpiryMinutes),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string GenerateRefreshToken()
    {
        var randomNumber = new byte[64];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(randomNumber);
        return Convert.ToBase64String(randomNumber);
    }
}
