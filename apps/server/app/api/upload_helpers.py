import io
import os
import re

from fastapi import HTTPException, UploadFile, status
from PIL import Image, ImageOps

_INVALID_FILENAME_CHARS_RE = re.compile(r'[<>:"/\\|?*\x00-\x1f]+')
_FILENAME_WHITESPACE_RE = re.compile(r"\s+")


def _sanitize_filename_component(value: str | None, *, fallback: str) -> str:
    text = (value or "").strip()
    text = _INVALID_FILENAME_CHARS_RE.sub(" ", text)
    text = _FILENAME_WHITESPACE_RE.sub(" ", text).strip(" .-_")
    return text or fallback


def _pending_release_label_image_base_name(pending_release) -> str:
    """Human-readable stem for label images: Artist Name - Release Title (sanitized)."""
    artist = _sanitize_filename_component(
        getattr(pending_release, "artist_name", None),
        fallback="Artist",
    )
    title = _sanitize_filename_component(
        getattr(pending_release, "release_title", None),
        fallback="Release",
    )
    return f"{artist} - {title}"


def _unique_filename(directory: str, base_name: str, extension: str) -> str:
    candidate = f"{base_name}{extension}"
    index = 2
    while os.path.exists(os.path.join(directory, candidate)):
        candidate = f"{base_name} ({index}){extension}"
        index += 1
    return candidate


def _read_upload_bytes(file: UploadFile, *, max_bytes: int, description: str) -> bytes:
    content = file.file.read(max_bytes + 1)
    if len(content) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{description} is too large. Maximum allowed size is {max_bytes // (1024 * 1024)}MB.",
        )
    return content


def _bytes_to_jpg_3000_square(data: bytes) -> bytes:
    raw = Image.open(io.BytesIO(data))
    raw = ImageOps.exif_transpose(raw)
    raw = raw.convert("RGB")
    out_img = ImageOps.fit(raw, (3000, 3000), method=Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    out_img.save(buf, format="JPEG", quality=92, optimize=True)
    return buf.getvalue()
