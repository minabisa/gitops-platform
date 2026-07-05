import pytest
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../src"))
from app import app

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client

def test_home(client):
    res = client.get("/")
    assert res.status_code == 200
    assert res.json["status"] == "healthy"

def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json["status"] == "ok"
