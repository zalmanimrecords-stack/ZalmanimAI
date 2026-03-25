import os
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_lm_user, require_admin
from app.core.config import settings
from app.db.session import get_db
from app.schemas.schemas import CampaignCreate, CampaignOut, CampaignUpdate, ScheduleCampaignRequest, UserContext
from app.services.campaign_service import (
    cancel_schedule,
    create_campaign as create_campaign_svc,
    delete_campaign,
    get_campaign,
    list_campaigns as list_campaigns_svc,
    set_campaign_scheduled,
    update_campaign as update_campaign_svc,
)

router = APIRouter()

_CAMPAIGN_MEDIA_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


@router.get("/admin/campaigns", response_model=list[CampaignOut])
def list_campaigns(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
    status: str | None = Query(None),
    limit: int = Query(100, le=200),
    offset: int = Query(0, ge=0),
) -> list[CampaignOut]:
    require_admin(user)
    campaigns = list_campaigns_svc(db, status=status, limit=limit, offset=offset)
    return [CampaignOut.from_campaign(c) for c in campaigns]


@router.get("/admin/campaigns/{campaign_id}", response_model=CampaignOut)
def get_campaign_route(
    campaign_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> CampaignOut:
    require_admin(user)
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Campaign not found")
    return CampaignOut.from_campaign(campaign)


@router.post("/admin/campaigns", response_model=CampaignOut)
def create_campaign_route(
    payload: CampaignCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> CampaignOut:
    require_admin(user)
    targets = [
        {"channel_type": t.channel_type, "external_id": t.external_id, "channel_payload": t.channel_payload}
        for t in payload.targets
    ]
    campaign = create_campaign_svc(
        db,
        name=payload.name,
        title=payload.title,
        body_text=payload.body_text,
        body_html=payload.body_html,
        media_url=payload.media_url,
        artist_id=payload.artist_id,
        targets=targets,
    )
    return CampaignOut.from_campaign(campaign)


@router.post("/admin/campaigns/upload-media")
def upload_campaign_media(
    request: Request,
    file: UploadFile = File(...),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_admin(user)
    ext = (os.path.splitext(file.filename or "")[1] or "").lower()
    if ext not in _CAMPAIGN_MEDIA_EXT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file type. Allowed: {', '.join(_CAMPAIGN_MEDIA_EXT)}",
        )
    media_dir = os.path.join(settings.upload_dir, "campaign_media")
    os.makedirs(media_dir, exist_ok=True)
    filename = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(media_dir, filename)
    with open(path, "wb") as out:
        out.write(file.file.read())
    base = str(request.base_url).rstrip("/")
    if not base.endswith("/api") and not base.endswith("/api/"):
        base = base + "/api"
    url = f"{base}/media/campaigns/{filename}"
    return {"url": url}


@router.get("/media/campaigns/{filename}")
def serve_campaign_media(filename: str):
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid filename")
    ext = (os.path.splitext(filename)[1] or "").lower()
    if ext not in _CAMPAIGN_MEDIA_EXT:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    path = os.path.join(settings.upload_dir, "campaign_media", filename)
    if not os.path.isfile(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    media_types = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".gif": "image/gif", ".webp": "image/webp"}
    return FileResponse(path, media_type=media_types.get(ext, "application/octet-stream"))


@router.patch("/admin/campaigns/{campaign_id}", response_model=CampaignOut)
def update_campaign_route(
    campaign_id: int,
    payload: CampaignUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> CampaignOut:
    require_admin(user)
    kwargs = payload.model_dump(exclude_unset=True)
    campaign = update_campaign_svc(db, campaign_id, **kwargs)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Campaign not found or not editable")
    return CampaignOut.from_campaign(campaign)


@router.delete("/admin/campaigns/{campaign_id}")
def delete_campaign_route(
    campaign_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_admin(user)
    if not delete_campaign(db, campaign_id):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Campaign not found or cannot be deleted")
    return {"ok": True}


@router.post("/admin/campaigns/{campaign_id}/schedule", response_model=CampaignOut)
def schedule_campaign_route(
    campaign_id: int,
    payload: ScheduleCampaignRequest,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> CampaignOut:
    require_admin(user)
    campaign = get_campaign(db, campaign_id)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Campaign not found")
    if campaign.status != "draft":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only draft campaigns can be scheduled")
    campaign = set_campaign_scheduled(db, campaign_id, payload.scheduled_at)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Could not schedule campaign")
    return CampaignOut.from_campaign(campaign)


@router.post("/admin/campaigns/{campaign_id}/cancel", response_model=CampaignOut)
def cancel_campaign_schedule_route(
    campaign_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> CampaignOut:
    require_admin(user)
    campaign = cancel_schedule(db, campaign_id)
    if not campaign:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Campaign not found or not scheduled")
    return CampaignOut.from_campaign(campaign)
