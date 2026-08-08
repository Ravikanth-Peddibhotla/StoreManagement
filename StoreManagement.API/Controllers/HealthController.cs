using Microsoft.AspNetCore.Mvc;

namespace StoreManagement.API.Controllers;

[ApiController]
[Route("api/v1")]
public class HealthController : ControllerBase
{
    [HttpGet("health")]
    public IActionResult Get() => Ok(new { status = "Healthy", timestampUtc = DateTime.UtcNow });
}
