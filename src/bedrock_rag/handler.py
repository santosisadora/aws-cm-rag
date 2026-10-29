"""Lambda entry point: fetch a document from S3 and answer a question about it with Bedrock.

This is a minimal "retrieve then generate" skeleton. Retrieval is currently a direct
S3 lookup by key; swap `fetch_document` for a vector search (e.g. Bedrock Knowledge
Bases or OpenSearch) as the project grows.

Handler: bedrock_rag.handler.lambda_handler (deployed as handler.lambda_handler via the
root-level shim that infra/cli/deploy-lambda.ps1 adds to the zip)
"""

from __future__ import annotations

import json
import logging
from functools import lru_cache
from typing import Any

import boto3
from botocore.exceptions import ClientError

from .config import Settings

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SYSTEM_PROMPT = (
    "You are a helpful assistant. Answer the user's question using only the provided "
    "context. If the answer is not in the context, say you don't know."
)


@lru_cache(maxsize=1)
def _get_clients(region: str | None) -> tuple[Any, Any]:
    """Create clients once per Lambda execution environment (reused across invocations)."""
    return (
        boto3.client("s3", region_name=region),
        boto3.client("bedrock-runtime", region_name=region),
    )


def fetch_document(s3_client: Any, bucket: str, key: str, max_chars: int) -> str:
    """Read a UTF-8 text object from S3 (requires s3:GetObject)."""
    response = s3_client.get_object(Bucket=bucket, Key=key)
    text = response["Body"].read().decode("utf-8", errors="replace")
    if len(text) > max_chars:
        logger.warning("Truncating document %s from %d to %d chars", key, len(text), max_chars)
        text = text[:max_chars]
    return text


def generate_answer(bedrock_client: Any, settings: Settings, question: str, context: str) -> str:
    """Call the model via the Converse API (requires bedrock:InvokeModel)."""
    prompt = f"<context>\n{context}\n</context>\n\nQuestion: {question}"
    response = bedrock_client.converse(
        modelId=settings.model_id,
        system=[{"text": SYSTEM_PROMPT}],
        messages=[{"role": "user", "content": [{"text": prompt}]}],
        inferenceConfig={"maxTokens": settings.max_tokens, "temperature": 0.0},
    )
    return response["output"]["message"]["content"][0]["text"]


def answer_question(
    question: str,
    document_key: str,
    *,
    settings: Settings,
    s3_client: Any,
    bedrock_client: Any,
) -> str:
    context = fetch_document(
        s3_client, settings.bucket_name, document_key, settings.max_context_chars
    )
    return generate_answer(bedrock_client, settings, question, context)


def _parse_event(event: dict[str, Any]) -> dict[str, Any]:
    """Accept direct invocation payloads or API Gateway / Function URL events."""
    body = event.get("body")
    if body is None:
        return event
    if isinstance(body, str):
        return json.loads(body)
    return body


def _response(status: int, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
    }


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    try:
        payload = _parse_event(event)
    except json.JSONDecodeError:
        return _response(400, {"error": "Request body must be valid JSON"})

    question = payload.get("question")
    document_key = payload.get("document_key")
    if not question or not document_key:
        return _response(400, {"error": "'question' and 'document_key' are required"})

    settings = Settings.from_env()
    s3_client, bedrock_client = _get_clients(settings.aws_region)

    try:
        answer = answer_question(
            question,
            document_key,
            settings=settings,
            s3_client=s3_client,
            bedrock_client=bedrock_client,
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "Unknown")
        logger.exception("AWS call failed: %s", code)
        # Without s3:ListBucket, a missing key surfaces as AccessDenied rather than NoSuchKey.
        if code in ("NoSuchKey", "AccessDenied"):
            return _response(404, {"error": f"Document '{document_key}' not found"})
        return _response(502, {"error": "Upstream AWS service error"})

    return _response(200, {"answer": answer, "document_key": document_key})
