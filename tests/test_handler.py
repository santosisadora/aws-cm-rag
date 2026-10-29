import io
import json
from unittest.mock import MagicMock, patch

import pytest
from botocore.exceptions import ClientError

from bedrock_rag import handler
from bedrock_rag.config import Settings


@pytest.fixture
def clients():
    s3 = MagicMock()
    s3.get_object.return_value = {"Body": io.BytesIO(b"The sky is blue.")}
    bedrock = MagicMock()
    bedrock.converse.return_value = {
        "output": {"message": {"content": [{"text": "Blue."}]}}
    }
    return s3, bedrock


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("BUCKET_NAME", "test-bucket")
    monkeypatch.setenv("AWS_REGION", "us-east-1")


def _invoke(event, clients):
    with patch.object(handler, "_get_clients", return_value=clients):
        return handler.lambda_handler(event, None)


def test_direct_invocation_returns_answer(clients):
    s3, bedrock = clients
    result = _invoke({"question": "What color is the sky?", "document_key": "doc.txt"}, clients)

    assert result["statusCode"] == 200
    assert json.loads(result["body"])["answer"] == "Blue."
    s3.get_object.assert_called_once_with(Bucket="test-bucket", Key="doc.txt")
    prompt = bedrock.converse.call_args.kwargs["messages"][0]["content"][0]["text"]
    assert "The sky is blue." in prompt


def test_api_gateway_body_is_parsed(clients):
    body = json.dumps({"question": "q", "document_key": "doc.txt"})
    result = _invoke({"body": body}, clients)
    assert result["statusCode"] == 200


def test_missing_fields_returns_400(clients):
    result = _invoke({"question": "q"}, clients)
    assert result["statusCode"] == 400


def test_missing_document_returns_404(clients):
    s3, _ = clients
    s3.get_object.side_effect = ClientError({"Error": {"Code": "AccessDenied"}}, "GetObject")
    result = _invoke({"question": "q", "document_key": "missing.txt"}, clients)
    assert result["statusCode"] == 404


def test_document_is_truncated():
    s3 = MagicMock()
    s3.get_object.return_value = {"Body": io.BytesIO(b"x" * 50)}
    assert handler.fetch_document(s3, "b", "k", max_chars=10) == "x" * 10


def test_settings_require_bucket(monkeypatch):
    monkeypatch.delenv("BUCKET_NAME")
    with pytest.raises(RuntimeError):
        Settings.from_env()
