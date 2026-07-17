"""Authentication adapters for the protected RawatBunda ML backend."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from typing import Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import UUID


@dataclass(frozen=True)
class AuthenticatedActor:
    user_id: str
    role: str


class AuthenticationError(ValueError):
    """The bearer token is absent, invalid, expired, or unauthorized."""


class AuthenticationServiceError(RuntimeError):
    """The configured identity provider could not be reached safely."""


class AuthVerifier(Protocol):
    def verify(self, authorization: str | None) -> AuthenticatedActor: ...


class SupabaseAuthVerifier:
    """Resolve a Supabase access token using the authoritative Auth endpoint."""

    def __init__(self, *, supabase_url: str, anon_key: str, timeout_seconds: float = 5.0):
        self._url = supabase_url.rstrip("/")
        self._anon_key = anon_key
        self._timeout = timeout_seconds

    @classmethod
    def from_environment(cls) -> "SupabaseAuthVerifier":
        url = os.environ.get("SUPABASE_URL", "").strip()
        anon_key = os.environ.get("SUPABASE_ANON_KEY", "").strip()
        if not url or not anon_key:
            raise ValueError("SUPABASE_URL and SUPABASE_ANON_KEY are required")
        return cls(supabase_url=url, anon_key=anon_key)

    def verify(self, authorization: str | None) -> AuthenticatedActor:
        if not authorization or not authorization.startswith("Bearer "):
            raise AuthenticationError("Bearer token is required")
        token = authorization.removeprefix("Bearer ").strip()
        if not token:
            raise AuthenticationError("Bearer token is required")

        request = Request(
            f"{self._url}/auth/v1/user",
            method="GET",
            headers={
                "apikey": self._anon_key,
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
        )
        try:
            with urlopen(request, timeout=self._timeout) as response:
                raw = response.read(65_537)
        except HTTPError as error:
            if error.code in {401, 403}:
                raise AuthenticationError("Supabase token is invalid or expired") from error
            raise AuthenticationServiceError("Supabase Auth rejected verification") from error
        except (URLError, TimeoutError, OSError) as error:
            raise AuthenticationServiceError("Supabase Auth is unavailable") from error
        if len(raw) > 65_536:
            raise AuthenticationServiceError("Supabase Auth response is unexpectedly large")
        try:
            payload = json.loads(raw)
            user_id = str(UUID(payload["id"]))
            role = payload.get("app_metadata", {}).get("app_role")
        except (json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
            raise AuthenticationServiceError("Supabase Auth returned an invalid user") from error
        if role not in {"bidan", "pasien", "admin"}:
            raise AuthenticationError("Account has no approved app role")
        return AuthenticatedActor(user_id=user_id, role=role)


class StaticTokenVerifier:
    """Explicit local/test verifier; never enabled implicitly in production."""

    def __init__(self, token: str, *, user_id: str, role: str = "bidan"):
        if not token:
            raise ValueError("Development token must not be empty")
        self._token = token
        self._actor = AuthenticatedActor(user_id=str(UUID(user_id)), role=role)

    def verify(self, authorization: str | None) -> AuthenticatedActor:
        if authorization != f"Bearer {self._token}":
            raise AuthenticationError("Bearer token is invalid")
        return self._actor


__all__ = [
    "AuthenticatedActor",
    "AuthenticationError",
    "AuthenticationServiceError",
    "AuthVerifier",
    "StaticTokenVerifier",
    "SupabaseAuthVerifier",
]
