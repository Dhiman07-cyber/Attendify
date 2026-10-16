from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, HTMLResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
import httpx
import logging

from app.core.config import settings
from app.db.session import engine, Base, get_db
from app.api.v1.api import api_router
import app.models  # Ensure all models are registered

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("attendhub")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Auto-create tables on startup for local development / testing
    logger.info("Initializing AttendHub database tables...")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database initialized successfully.")
    yield
    # Shutdown
    logger.info("Shutting down AttendHub engine...")
    await engine.dispose()

app = FastAPI(
    title="AttendHub API",
    description="AttendHub Production-Grade Student Attendance Tracking & Analytics Engine",
    version=settings.VERSION,
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS setup
_cors_origins = [
    "http://localhost:5000",
    "http://127.0.0.1:5000",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:8080",
    "http://127.0.0.1:8080",
]
for origin in settings.CORS_ORIGINS:
    if origin != "*" and origin not in _cors_origins:
        _cors_origins.append(origin)

_cors_regex = (
    r"^https?://.*$"
    if "*" in settings.CORS_ORIGINS
    else r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_origin_regex=_cors_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def add_security_and_coop_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Cross-Origin-Opener-Policy"] = "same-origin-allow-popups"
    return response

# Mount API v1 router
app.include_router(api_router, prefix=settings.API_V1_STR)

from fastapi.exceptions import RequestValidationError

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    sanitized_errors = []
    for err in exc.errors():
        err_copy = dict(err)
        if "input" in err_copy and isinstance(err_copy.get("loc"), (list, tuple)):
            if any("password" in str(loc).lower() for loc in err_copy["loc"]):
                err_copy["input"] = "[REDACTED]"
        sanitized_errors.append(err_copy)
    logger.warning(f"Validation error on {request.method} {request.url}: {sanitized_errors}")
    origin = request.headers.get("origin")
    response = JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"detail": exc.errors()},
    )
    if origin:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"
    return response

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception(f"Unhandled exception on {request.method} {request.url}: {exc}")
    origin = request.headers.get("origin")
    response = JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "An internal server error occurred. Please try again."},
    )
    if origin:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"
    return response

@app.api_route("/health", methods=["GET", "HEAD"], tags=["Health"])
@app.api_route(f"{settings.API_V1_STR}/health", methods=["GET", "HEAD"], tags=["Health"])
async def health_check(db: AsyncSession = Depends(get_db)):
    """
    Health check & keep-alive endpoint for Render and cron jobs.
    Actively queries Supabase PostgreSQL and pings the Supabase REST gateway
    so neither Render nor the Supabase free-tier project goes to sleep/pauses.
    """
    db_status = "disconnected"
    try:
        await db.execute(text("SELECT COUNT(id) FROM users"))
        db_status = "connected"
    except Exception:
        try:
            await db.execute(text("SELECT 1"))
            db_status = "connected"
        except Exception as e:
            logger.warning(f"Database ping failed during health check: {e}")

    supabase_rest_status = "skipped"
    if settings.SUPABASE_URL and settings.SUPABASE_PUBLISHABLE_KEY:
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                resp = await client.get(
                    f"{settings.SUPABASE_URL.rstrip('/')}/rest/v1/",
                    headers={"apikey": settings.SUPABASE_PUBLISHABLE_KEY},
                )
                supabase_rest_status = "ok" if resp.status_code < 500 else f"http_{resp.status_code}"
        except Exception as e:
            logger.debug(f"Supabase REST keep-alive ping skipped/failed: {e}")
            supabase_rest_status = "unreachable"

    return {
        "status": "healthy" if db_status == "connected" else "degraded",
        "service": "AttendiFy Backend",
        "version": settings.VERSION,
        "database": db_status,
        "supabase_ping": supabase_rest_status,
    }

@app.get("/google1ca5ec019afa568b.html", tags=["Verification"])
async def google_site_verification():
    """Google Search Console site verification file."""
    return HTMLResponse(
        content="google-site-verification: google1ca5ec019afa568b.html",
        status_code=200,
        media_type="text/html; charset=utf-8",
    )

@app.get("/", tags=["General"])
async def root(request: Request):
    accept = request.headers.get("accept", "")
    if "application/json" in accept and "text/html" not in accept:
        return {
            "app": "AttendiFy",
            "tagline": "Track · Plan · Stay Above 75%",
            "version": settings.VERSION,
            "docs": "/docs",
            "privacy": "/privacy",
            "terms": "/terms",
        }
    return HTMLResponse(
        content="""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="google-site-verification" content="google1ca5ec019afa568b" />
    <title>AttendiFy — Student Attendance & Forecast Engine</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #F7F1EC; color: #2C2825; padding: 24px; max-width: 800px; margin: 40px auto; line-height: 1.6; }
        .card { background: #FFFFFF; border-radius: 16px; padding: 36px; box-shadow: 0 4px 24px rgba(0,0,0,0.05); border: 1px solid #EDE4DB; text-align: center; }
        h1 { color: #C96E5B; font-size: 32px; margin-bottom: 8px; }
        p.tagline { font-size: 18px; color: #57524E; margin-bottom: 24px; }
        p.desc { font-size: 15px; color: #6E6761; max-width: 600px; margin: 0 auto 28px; }
        .nav-links { display: flex; justify-content: center; gap: 16px; margin-top: 24px; flex-wrap: wrap; }
        .nav-links a { display: inline-block; padding: 10px 22px; border-radius: 10px; background: #FFFDFC; border: 1px solid #EDE4DB; color: #C96E5B; text-decoration: none; font-weight: 600; font-size: 14px; transition: all 0.2s; }
        .nav-links a:hover { background: #C96E5B; color: #FFFFFF; }
        .footer { margin-top: 40px; font-size: 12px; color: #8C827A; }
    </style>
</head>
<body>
    <div class="card">
        <h1>AttendiFy</h1>
        <p class="tagline">Track · Plan · Stay Above 75%</p>
        <p class="desc">AttendiFy is a student-first attendance tracking and forecasting utility designed to help university students maintain target thresholds and optimize safe absences.</p>
        <div class="nav-links">
            <a href="/privacy">Privacy Policy</a>
            <a href="/terms">Terms of Service</a>
            <a href="/docs">API Documentation</a>
        </div>
        <div class="footer">© 2026 AttendiFy. All rights reserved.</div>
    </div>
</body>
</html>"""
    )

@app.get("/privacy", response_class=HTMLResponse, tags=["Legal"])
async def privacy_policy():
    return """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="google-site-verification" content="google1ca5ec019afa568b" />
    <title>AttendiFy — Privacy Policy</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #F7F1EC; color: #2C2825; padding: 24px; max-width: 800px; margin: 0 auto; line-height: 1.6; }
        .card { background: #FFFFFF; border-radius: 16px; padding: 32px; box-shadow: 0 4px 20px rgba(0,0,0,0.04); border: 1px solid #EDE4DB; }
        h1 { color: #C96E5B; font-size: 26px; margin-top: 0; }
        h2 { color: #2C2825; font-size: 18px; margin-top: 24px; border-bottom: 1px solid #EDE4DB; padding-bottom: 6px; }
        p, li { font-size: 14px; color: #57524E; }
        .footer { margin-top: 32px; font-size: 12px; color: #8C827A; text-align: center; }
    </style>
</head>
<body>
    <div class="card">
        <h1>AttendiFy Privacy Policy</h1>
        <p><strong>Effective Date:</strong> October 2026</p>
        <p>AttendiFy ("we", "our", or "the app") provides a student-side attendance tracking and planning utility. We are committed to protecting your privacy and ensuring transparency in how your information is handled.</p>
        
        <h2>1. Information We Collect</h2>
        <p>When you sign up or authenticate with Google OAuth, we receive:</p>
        <ul>
            <li><strong>Profile Information:</strong> Your name and email address as provided by Google authentication to identify your student account.</li>
            <li><strong>Academic Attendance Data:</strong> Class schedules, subject lists, attendance statuses (attended, absent, cancelled), and target thresholds that you track.</li>
        </ul>

        <h2>2. How We Use Information</h2>
        <p>Your data is used solely to provide and improve the attendance tracking and forecasting features of AttendiFy:</p>
        <ul>
            <li>Calculating semester attendance percentages and safe absences.</li>
            <li>Syncing your routine and calendar schedules across your authorized devices.</li>
            <li>We do not sell, rent, or monetize your personal information.</li>
        </ul>

        <h2>3. Data Storage & Security</h2>
        <p>All data is encrypted in transit using industry-standard TLS/HTTPS protocols and stored securely. Object-level user isolation is strictly enforced.</p>

        <h2>4. Third-Party Services</h2>
        <p>We use Google OAuth strictly for student identity verification. No additional Google user data or sensitive files are accessed.</p>

        <h2>5. Contact & Data Deletion</h2>
        <p>If you have questions or request data deletion, please contact us at: <strong>dhimansaikia2007@gmail.com</strong></p>

        <div class="footer">© 2026 AttendiFy. All rights reserved.</div>
    </div>
</body>
</html>"""

@app.get("/terms", response_class=HTMLResponse, tags=["Legal"])
async def terms_of_service():
    return """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="google-site-verification" content="google1ca5ec019afa568b" />
    <title>AttendiFy — Terms of Service</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #F7F1EC; color: #2C2825; padding: 24px; max-width: 800px; margin: 0 auto; line-height: 1.6; }
        .card { background: #FFFFFF; border-radius: 16px; padding: 32px; box-shadow: 0 4px 20px rgba(0,0,0,0.04); border: 1px solid #EDE4DB; }
        h1 { color: #C96E5B; font-size: 26px; margin-top: 0; }
        h2 { color: #2C2825; font-size: 18px; margin-top: 24px; border-bottom: 1px solid #EDE4DB; padding-bottom: 6px; }
        p, li { font-size: 14px; color: #57524E; }
        .footer { margin-top: 32px; font-size: 12px; color: #8C827A; text-align: center; }
    </style>
</head>
<body>
    <div class="card">
        <h1>AttendiFy Terms of Service</h1>
        <p><strong>Effective Date:</strong> October 2026</p>
        <p>By accessing or using AttendiFy, you agree to be bound by these Terms of Service.</p>
        
        <h2>1. Purpose of the Application</h2>
        <p>AttendiFy is a student-first attendance tracking and forecasting utility. Attendance forecasts and safe absence calculations are deterministic guidelines to assist students in tracking university attendance policies.</p>

        <h2>2. User Accounts</h2>
        <p>You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account.</p>

        <h2>3. Acceptable Use</h2>
        <p>You agree not to use the application for any unlawful purpose or to attempt unauthorized access to other student accounts or server infrastructure.</p>

        <h2>4. Changes to Terms</h2>
        <p>We may update these terms periodically. Continued use of AttendiFy constitutes acceptance of any revised terms.</p>

        <h2>5. Contact</h2>
        <p>For questions regarding these terms, contact: <strong>dhimansaikia2007@gmail.com</strong></p>

        <div class="footer">© 2026 AttendiFy. All rights reserved.</div>
    </div>
</body>
</html>"""
