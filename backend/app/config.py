import json
import os

from dotenv import load_dotenv


load_dotenv()


def _load_secrets_manager_payload():
    """
    Load optional application config from AWS Secrets Manager.
    Falls back to local env vars when the secret is unavailable.
    """
    secret_name = os.getenv("APP_SECRETS_NAME", "").strip()
    if not secret_name:
        return {}

    try:
        import boto3
        from botocore.exceptions import BotoCoreError, ClientError
    except ImportError:
        return {}

    region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-west-2"
    try:
        client = boto3.client("secretsmanager", region_name=region)
        response = client.get_secret_value(SecretId=secret_name)
        raw_secret = response.get("SecretString", "")
        if not raw_secret:
            return {}
        parsed_secret = json.loads(raw_secret)
        return parsed_secret if isinstance(parsed_secret, dict) else {}
    except (BotoCoreError, ClientError, json.JSONDecodeError):
        return {}


_aws_secrets = _load_secrets_manager_payload()


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY") or _aws_secrets.get("SECRET_KEY", "dev-secret-key")
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY") or _aws_secrets.get("JWT_SECRET_KEY", "dev-jwt-secret")
    SQLALCHEMY_DATABASE_URI = os.getenv("DATABASE_URL") or _aws_secrets.get(
        "DATABASE_URL",
        "postgresql://fintech_user:fintech_password@localhost:5432/fintech_db",
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    CORS_ORIGINS = [
        origin.strip()
        for origin in (os.getenv("CORS_ORIGINS") or _aws_secrets.get("CORS_ORIGINS", "http://localhost:5173")).split(",")
    ]
