import hashlib

from app.core.config import settings

_redis_client = None
_LOGIN_WINDOW_SECONDS = 300
_MAX_LOGIN_ATTEMPTS = 5
_KEY_PREFIX = "auth:login:"


def _get_redis():
    global _redis_client
    if _redis_client is None:
        try:
            import redis

            _redis_client = redis.from_url(settings.redis_url, decode_responses=True)
        except Exception:
            _redis_client = None
    return _redis_client


def _hash_value(value: str) -> str:
    return hashlib.sha256((value or "").encode("utf-8")).hexdigest()


def _email_key(email: str) -> str:
    return f"{_KEY_PREFIX}email:{_hash_value((email or '').strip().lower())}"


def _ip_key(client_ip: str) -> str:
    return f"{_KEY_PREFIX}ip:{_hash_value((client_ip or 'unknown').strip().lower())}"


def _read_attempt_count(key: str) -> int:
    r = _get_redis()
    if not r:
        return 0
    try:
        raw = r.get(key)
        return int(raw) if raw else 0
    except Exception:
        return 0


def _read_retry_after(key: str) -> int:
    r = _get_redis()
    if not r:
        return 0
    try:
        ttl = int(r.ttl(key))
        return ttl if ttl > 0 else _LOGIN_WINDOW_SECONDS
    except Exception:
        return _LOGIN_WINDOW_SECONDS


def check_login_allowed(*, email: str, client_ip: str) -> tuple[bool, int | None]:
    email_key = _email_key(email)
    ip_key = _ip_key(client_ip)
    email_attempts = _read_attempt_count(email_key)
    ip_attempts = _read_attempt_count(ip_key)
    if email_attempts < _MAX_LOGIN_ATTEMPTS and ip_attempts < _MAX_LOGIN_ATTEMPTS:
        return True, None
    retry_after = max(_read_retry_after(email_key), _read_retry_after(ip_key), 1)
    return False, retry_after


def register_failed_login(*, email: str, client_ip: str) -> None:
    r = _get_redis()
    if not r:
        return
    for key in (_email_key(email), _ip_key(client_ip)):
        try:
            pipe = r.pipeline()
            pipe.incr(key)
            pipe.expire(key, _LOGIN_WINDOW_SECONDS)
            pipe.execute()
        except Exception:
            return


def clear_login_failures(*, email: str, client_ip: str) -> None:
    r = _get_redis()
    if not r:
        return
    try:
        r.delete(_email_key(email), _ip_key(client_ip))
    except Exception:
        return
