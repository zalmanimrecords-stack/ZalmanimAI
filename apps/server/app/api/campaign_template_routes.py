from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_lm_user, require_admin
from app.db.session import get_db
from app.models.models import EmailCampaignTemplate
from app.schemas.schemas import (
    EmailCampaignTemplateCreate,
    EmailCampaignTemplateOut,
    EmailCampaignTemplateUpdate,
    UserContext,
)

router = APIRouter()


@router.get("/admin/campaign-email-templates", response_model=list[EmailCampaignTemplateOut])
def list_campaign_email_templates(
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> list[EmailCampaignTemplateOut]:
    require_admin(user)
    rows = (
        db.query(EmailCampaignTemplate)
        .order_by(EmailCampaignTemplate.updated_at.desc(), EmailCampaignTemplate.id.desc())
        .all()
    )
    return [EmailCampaignTemplateOut.model_validate(r) for r in rows]


@router.get("/admin/campaign-email-templates/{template_id}", response_model=EmailCampaignTemplateOut)
def get_campaign_email_template(
    template_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> EmailCampaignTemplateOut:
    require_admin(user)
    row = db.get(EmailCampaignTemplate, template_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")
    return EmailCampaignTemplateOut.model_validate(row)


@router.post("/admin/campaign-email-templates", response_model=EmailCampaignTemplateOut)
def create_campaign_email_template(
    payload: EmailCampaignTemplateCreate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> EmailCampaignTemplateOut:
    require_admin(user)
    row = EmailCampaignTemplate(
        name=payload.name.strip(),
        description=(payload.description or "").strip(),
        subject=payload.subject.strip(),
        body_text=payload.body_text or "",
        body_html=payload.body_html,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return EmailCampaignTemplateOut.model_validate(row)


@router.patch("/admin/campaign-email-templates/{template_id}", response_model=EmailCampaignTemplateOut)
def update_campaign_email_template(
    template_id: int,
    payload: EmailCampaignTemplateUpdate,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> EmailCampaignTemplateOut:
    require_admin(user)
    row = db.get(EmailCampaignTemplate, template_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")
    data = payload.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        row.name = data["name"].strip()
    if "description" in data:
        row.description = (data["description"] or "").strip()
    if "subject" in data and data["subject"] is not None:
        row.subject = data["subject"].strip()
    if "body_text" in data:
        row.body_text = data["body_text"] or ""
    if "body_html" in data:
        row.body_html = data["body_html"]
    db.commit()
    db.refresh(row)
    return EmailCampaignTemplateOut.model_validate(row)


@router.delete("/admin/campaign-email-templates/{template_id}")
def delete_campaign_email_template(
    template_id: int,
    db: Session = Depends(get_db),
    user: UserContext = Depends(get_current_lm_user),
) -> dict:
    require_admin(user)
    row = db.get(EmailCampaignTemplate, template_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")
    db.delete(row)
    db.commit()
    return {"ok": True}
