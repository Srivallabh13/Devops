using Microsoft.AspNetCore.Mvc;
using RequestLogger.Models;
using System.Diagnostics;

namespace RequestLogger.Controllers
{
    public class HomeController : Controller
    {
        private readonly ILogger<HomeController> _logger;

        public HomeController(ILogger<HomeController> logger)
        {
            _logger = logger;
        }
        [HttpGet]

        public IActionResult Index()
        {
            var currentTime = DateTime.Now;

            string greetingMessage = $"Hello There! Current Server Time: {currentTime} ";

            ViewBag.GreetingMessage = greetingMessage;
            return View();
        }

        public IActionResult Privacy()
        {
            return View();
        }
        

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }
    }
}
