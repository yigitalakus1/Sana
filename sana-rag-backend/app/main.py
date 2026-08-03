"""FastAPI uygulama girişi."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import routes_chat, routes_health, routes_query, routes_reports, routes_terms
from app.core import config

app = FastAPI(
    title=config.APP_NAME,
    version=config.APP_VERSION,
    description=config.APP_DESCRIPTION,
)

# Development CORS: Flutter web her çalıştırmada farklı localhost portu açabildiği
# için sabit liste yerine port-regex kullanılır (örn. http://localhost:53031).
# Üretim için wildcard DEĞİL; yalnız localhost/127.0.0.1.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^http://(localhost|127\.0\.0\.1):\d+$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(routes_health.router, tags=["health"])
app.include_router(routes_query.router, tags=["query"])
app.include_router(routes_chat.router, tags=["chat"])
app.include_router(routes_terms.router, tags=["terms"])
app.include_router(routes_reports.router, tags=["reports"])
