import httpx
import jsonschema
import numpy as np
import pytest
from fastapi.testclient import TestClient

from anode_model.server import MAX_IMAGE_BYTES, Settings, create_app

from .conftest import FakePredictor, png_bytes, square_mask

KEY = "test-key"
HOST = "storage.example.supabase.co"
URL = f"https://{HOST}/object/sign/inspection-photos/a.png?token=t"


def client(handler, mask=None) -> TestClient:
    settings = Settings(api_key=KEY, allowed_hosts=frozenset({HOST}))
    predictor = FakePredictor(mask if mask is not None else square_mask())
    return TestClient(create_app(predictor, settings, httpx.MockTransport(handler)))


def ok_image(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, content=png_bytes(200, 100))


def body(**over):
    return {"imageUrl": URL, "widthPx": 200, "heightPx": 100, "mmPerPx": 0.1, **over}


def test_health_names_the_model():
    assert client(ok_image).get("/health").json() == {"ok": True, "modelName": "fake-model", "modelVersion": "test-1"}


def test_measures_a_photo_to_contract(response_schema, request_schema):
    jsonschema.validate(body(), request_schema)
    res = client(ok_image).post("/measure", json=body(), headers={"X-Anode-Key": KEY})
    assert res.status_code == 200
    jsonschema.validate(res.json(), response_schema)
    assert res.json()["percentAreaRusted"] == pytest.approx(12.0)


@pytest.mark.parametrize("key", ["", "wrong"])
def test_requires_the_shared_key(key):
    headers = {"X-Anode-Key": key} if key else {}
    assert client(ok_image).post("/measure", json=body(), headers=headers).status_code == 401


@pytest.mark.parametrize(
    "url",
    [f"http://{HOST}/a.png", "https://evil.example.com/a.png", "https://169.254.169.254/latest/meta-data"],
)
def test_fetches_only_https_from_allowed_hosts(url):
    res = client(ok_image).post("/measure", json=body(imageUrl=url), headers={"X-Anode-Key": KEY})
    assert res.status_code == 422


def test_does_not_follow_redirects():
    def redirect(request):
        return httpx.Response(302, headers={"Location": "https://evil.example.com/x.png"})

    assert client(redirect).post("/measure", json=body(), headers={"X-Anode-Key": KEY}).status_code == 502


def test_refuses_images_over_the_size_cap():
    def huge(request):
        return httpx.Response(200, content=b"\0" * (MAX_IMAGE_BYTES + 1))

    assert client(huge).post("/measure", json=body(), headers={"X-Anode-Key": KEY}).status_code == 413


def test_reports_download_failures():
    def missing(request):
        return httpx.Response(404)

    def broken(request):
        raise httpx.ConnectError("down")

    for handler in (missing, broken):
        assert client(handler).post("/measure", json=body(), headers={"X-Anode-Key": KEY}).status_code == 502


def test_refuses_non_images_and_wrong_sizes():
    def text(request):
        return httpx.Response(200, content=b"not an image")

    assert client(text).post("/measure", json=body(), headers={"X-Anode-Key": KEY}).status_code == 422
    assert client(ok_image).post("/measure", json=body(widthPx=201), headers={"X-Anode-Key": KEY}).status_code == 422


@pytest.mark.parametrize("bad", [{"mmPerPx": 0}, {"widthPx": -1}, {"extra": 1}, {"widthPx": "200"}])
def test_validates_the_request_like_the_contract(bad, request_schema):
    payload = body(**bad)
    schema_ok = True
    try:
        jsonschema.validate(payload, request_schema)
    except jsonschema.ValidationError:
        schema_ok = False
    res = client(ok_image).post("/measure", json=payload, headers={"X-Anode-Key": KEY})
    assert not schema_ok
    assert res.status_code == 422


def test_rejects_a_predictor_that_returns_the_wrong_shape():
    class Bad(FakePredictor):
        def predict(self, rgb):
            return np.zeros((5, 5), np.float32)

    settings = Settings(api_key=KEY, allowed_hosts=frozenset({HOST}))
    app = create_app(Bad(square_mask()), settings, httpx.MockTransport(ok_image))
    assert TestClient(app).post("/measure", json=body(), headers={"X-Anode-Key": KEY}).status_code == 500


def test_settings_require_key_and_hosts(monkeypatch):
    monkeypatch.delenv("ANODE_API_KEY", raising=False)
    monkeypatch.delenv("ANODE_ALLOWED_IMAGE_HOSTS", raising=False)
    with pytest.raises(RuntimeError):
        Settings.from_env()
    monkeypatch.setenv("ANODE_API_KEY", "k")
    monkeypatch.setenv("ANODE_ALLOWED_IMAGE_HOSTS", " A.example.com , b.example.com ")
    assert Settings.from_env().allowed_hosts == frozenset({"a.example.com", "b.example.com"})
