"""Runtime configuration loaded from Lambda environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass

# Claude Haiku 4.5 via the US cross-region inference profile.
# Must be granted in the IAM policy (see infra/).
DEFAULT_MODEL_ID = "us.anthropic.claude-haiku-4-5-20251001-v1:0"


@dataclass(frozen=True)
class Settings:
    bucket_name: str
    model_id: str = DEFAULT_MODEL_ID
    aws_region: str | None = None
    max_tokens: int = 1024
    max_context_chars: int = 20_000

    @classmethod
    def from_env(cls) -> Settings:
        bucket = os.environ.get("BUCKET_NAME")
        if not bucket:
            raise RuntimeError("BUCKET_NAME environment variable is required")
        return cls(
            bucket_name=bucket,
            model_id=os.environ.get("BEDROCK_MODEL_ID", DEFAULT_MODEL_ID),
            aws_region=os.environ.get("AWS_REGION"),
            max_tokens=int(os.environ.get("BEDROCK_MAX_TOKENS", "1024")),
            max_context_chars=int(os.environ.get("RAG_MAX_CONTEXT_CHARS", "20000")),
        )
