"""Development CORS middleware testleri (Flutter web bağlanabilsin)."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

ORIGIN = "http://localhost:53031"  # Flutter web rastgele port örneği


def test_preflight_health_is_not_405():
    r = client.options(
        "/health",
        headers={
            "Origin": ORIGIN,
            "Access-Control-Request-Method": "GET",
        },
    )
    # Eskiden 405 dönüyordu; CORS middleware ile preflight 200 olmalı
    assert r.status_code == 200
    assert r.headers.get("access-control-allow-origin") == ORIGIN


def test_get_health_has_cors_header():
    r = client.get("/health", headers={"Origin": ORIGIN})
    assert r.status_code == 200
    assert r.headers.get("access-control-allow-origin") == ORIGIN


def test_get_health_still_ok_without_origin():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
