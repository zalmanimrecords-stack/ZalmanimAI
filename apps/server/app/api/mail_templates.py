import html
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.models import DemoSubmission, MailingList, MailingSubscriber
from app.services.mail_settings import get_effective_mail_config_for_api

_DEMO_MAILING_LIST_NAME = "Artists Demo Intake"


def _artist_portal_url() -> str:
    return (settings.artist_portal_base_url or "").strip() or "https://artists.zalmanim.com"


def _safe_json_dict(raw: str | None) -> dict:
    import json

    try:
        data = json.loads(raw or "{}") or {}
    except (json.JSONDecodeError, TypeError):
        data = {}
    return data if isinstance(data, dict) else {}


def _safe_json_list(raw: str | None) -> list:
    import json

    try:
        data = json.loads(raw or "[]") or []
    except (json.JSONDecodeError, TypeError):
        data = []
    return data if isinstance(data, list) else []


def _default_demo_approval_subject(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return f"Your demo was approved, {safe_name}"


def _default_demo_approval_body(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return (
        f"Hi {safe_name},\n\n"
        "Thanks for sending your demo.\n\n"
        "We reviewed it and would like to move forward with you. "
        "Please reply to this email so we can continue the next steps.\n\n"
        "Best regards"
    )


def _default_demo_receipt_subject(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return f"Demo received from {safe_name}"


def _build_demo_submission_summary(item: DemoSubmission) -> list[tuple[str, str]]:
    fields = _safe_json_dict(item.fields_json)
    links = _safe_json_list(item.links_json)
    submission_links = ", ".join(str(link).strip() for link in links if str(link).strip())
    return [
        ("Artist name", item.artist_name),
        ("Contact name", item.contact_name or "-"),
        ("Email", item.email),
        ("Phone", item.phone or "-"),
        ("Genre", item.genre or "-"),
        ("City", item.city or "-"),
        ("Links", submission_links or "-"),
        ("Message", item.message or "-"),
        ("Email consent", "Yes" if item.consent_to_emails else "No"),
        ("Source", item.source or "-"),
    ]


def _default_demo_receipt_body(item: DemoSubmission) -> str:
    recipient_name = (item.contact_name or item.artist_name or "there").strip()
    lines = [
        f"Hi {recipient_name},",
        "",
        "We received your demo and it will enter treatment soon.",
        "",
        "Submission summary:",
    ]
    for label, value in _build_demo_submission_summary(item):
        lines.append(f"- {label}: {value}")
    lines.extend([
        "",
        "Thanks for sending your music to Zalmanim.",
        "",
        "Best regards,",
        "Zalmanim",
    ])
    return "\n".join(lines)


def _default_demo_rejection_subject(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return f"Thank you for your demo submission, {safe_name}"


def _default_demo_rejection_body(artist_name: str) -> str:
    portal_url = _artist_portal_url()
    website_url = (settings.zalmanim_website_url or "").strip() or "https://zalmanim.com"
    safe_name = (artist_name or "there").strip()
    return (
        f"Hi {safe_name},\n\n"
        "Thank you for sending us your music. We received it with respect and appreciate you thinking of us.\n\n"
        "After careful consideration, we feel it does not quite fit the musical direction of our labels at this time. "
        "We would be happy to receive more demos from you in the future in the hope they may align with our line.\n\n"
        f"Our website: {website_url}\n"
        f"Artist portal (submit demos): {portal_url}\n\n"
        "Best regards,\nZalmanim"
    )


def _apply_demo_rejection_placeholders(text: str, item: DemoSubmission) -> str:
    portal_url = _artist_portal_url()
    website_url = (settings.zalmanim_website_url or "").strip() or "https://zalmanim.com"
    safe_name = (item.artist_name or "there").strip()
    return (
        text.replace("{artist_name}", safe_name)
        .replace("{artist_portal_url}", portal_url)
        .replace("{zalmanim_website}", website_url)
    )


def _get_demo_approval_subject_and_body(artist_name: str) -> tuple[str, str]:
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("demo_approval_subject") or "").strip()
    body = (mail.get("demo_approval_body") or "").strip()
    if not subject:
        subject = _default_demo_approval_subject(artist_name)
    else:
        subject = subject.replace("{artist_name}", (artist_name or "there").strip())
    if not body:
        body = _default_demo_approval_body(artist_name)
    else:
        body = body.replace("{artist_name}", (artist_name or "there").strip())
    return subject, body


def _get_demo_receipt_subject_and_body(item: DemoSubmission) -> tuple[str, str]:
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("demo_receipt_subject") or "").strip()
    body = (mail.get("demo_receipt_body") or "").strip()
    replacements = {
        "{recipient_name}": (item.contact_name or item.artist_name or "there").strip(),
        "{artist_name}": (item.artist_name or "there").strip(),
        "{contact_name}": (item.contact_name or "").strip(),
        "{email}": (item.email or "").strip(),
        "{phone}": (item.phone or "").strip(),
        "{genre}": (item.genre or "").strip(),
        "{city}": (item.city or "").strip(),
        "{links}": ", ".join(str(link).strip() for link in _safe_json_list(item.links_json) if str(link).strip()),
        "{message}": (item.message or "").strip(),
        "{source}": (item.source or "").strip(),
        "{submission_summary}": "\n".join(
            f"- {label}: {value}" for label, value in _build_demo_submission_summary(item)
        ),
    }
    if not subject:
        subject = _default_demo_receipt_subject(item.artist_name)
    if not body:
        body = _default_demo_receipt_body(item)
    for token, value in replacements.items():
        subject = subject.replace(token, value)
        body = body.replace(token, value)
    return subject, body


def _get_demo_rejection_subject_and_body(item: DemoSubmission) -> tuple[str, str]:
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("demo_rejection_subject") or "").strip()
    body = (mail.get("demo_rejection_body") or "").strip()
    if not subject:
        subject = _default_demo_rejection_subject(item.artist_name)
    else:
        subject = _apply_demo_rejection_placeholders(subject, item)
    if not body:
        body = _default_demo_rejection_body(item.artist_name)
    else:
        body = _apply_demo_rejection_placeholders(body, item)
    return subject, body


def _build_demo_receipt_subject(artist_name: str) -> str:
    safe_name = (artist_name or "there").strip()
    return f"Demo received from {safe_name}"


def _build_demo_receipt_body(item: DemoSubmission) -> str:
    recipient_name = (item.contact_name or item.artist_name or "there").strip()
    lines = [
        f"Hi {recipient_name},",
        "",
        "We received your demo and it will enter treatment soon.",
        "",
        "Submission summary:",
    ]
    for label, value in _build_demo_submission_summary(item):
        lines.append(f"- {label}: {value}")
    lines.extend([
        "",
        "Thanks for sending your music to Zalmanim.",
        "",
        "Best regards,",
        "Zalmanim",
    ])
    return "\n".join(lines)


def _build_demo_receipt_html(item: DemoSubmission) -> str:
    recipient_name = html.escape((item.contact_name or item.artist_name or "there").strip())
    rows = "\n".join(
        f"<tr><td style='padding:8px 12px;font-weight:600;border:1px solid #e5ddd2;'>{html.escape(label)}</td>"
        f"<td style='padding:8px 12px;border:1px solid #e5ddd2;'>{html.escape(value)}</td></tr>"
        for label, value in _build_demo_submission_summary(item)
    )
    return (
        f"<p>Hi {recipient_name},</p>"
        "<p>We received your demo and it will enter treatment soon.</p>"
        "<p><strong>Submission summary</strong></p>"
        "<table style='border-collapse:collapse;border:1px solid #e5ddd2;'>"
        f"{rows}"
        "</table>"
        "<p>Thanks for sending your music to Zalmanim.</p>"
        "<p>Best regards,<br/>Zalmanim</p>"
    )


def _ensure_demo_mailing_list(db: Session) -> MailingList:
    mailing_list = db.query(MailingList).filter(MailingList.name == _DEMO_MAILING_LIST_NAME).first()
    if mailing_list:
        return mailing_list
    mailing_list = MailingList(
        name=_DEMO_MAILING_LIST_NAME,
        description="Artists who submitted demos and consented to marketing and operational emails.",
        default_language="en",
    )
    db.add(mailing_list)
    db.flush()
    return mailing_list


def _upsert_demo_mailing_subscriber(db: Session, item: DemoSubmission) -> None:
    if not item.consent_to_emails:
        return
    mailing_list = _ensure_demo_mailing_list(db)
    subscriber = (
        db.query(MailingSubscriber)
        .filter(MailingSubscriber.list_id == mailing_list.id, MailingSubscriber.email == item.email)
        .first()
    )
    consent_source = (item.source_site_url or item.source or "demo_submission").strip() or "demo_submission"
    consent_at = item.consent_at or datetime.now(timezone.utc)
    display_name = (item.contact_name or item.artist_name or "").strip() or None
    notes = f"Auto-added from demo submission #{item.id}."
    if subscriber:
        subscriber.full_name = display_name
        subscriber.status = "subscribed"
        subscriber.consent_source = consent_source
        subscriber.consent_at = consent_at
        subscriber.unsubscribed_at = None
        subscriber.notes = notes
        return
    db.add(
        MailingSubscriber(
            list_id=mailing_list.id,
            email=item.email,
            full_name=display_name,
            status="subscribed",
            consent_source=consent_source,
            consent_at=consent_at,
            unsubscribe_token="",
            notes=notes,
        )
    )


def _default_groover_invite_subject() -> str:
    return "Thanks for reaching out on Groover"


def _default_groover_invite_body(display_name: str, registration_url: str, portal_url: str) -> str:
    return (
        f"Hi {display_name},\n\n"
        "I hope you are doing well. I am Simon from Zalmanim Music,\n"
        "and I would like to introduce you to our work.\n\n"
        "We are a music label and an internet magazine that works with electronic music, focusing on underground dance music such as Techno, Psytech, and sometimes some variants of house. "
        "We are also releasing some Ambient and chill out to ease the mind.\n\n"
        "We also work on a new label focused only on Psytech and Prog Trance named SiYu Music.\n\n"
        "We also have an internet magazine at www.zalmanim.com and we promote music on our YouTube channel https://www.youtube.com/channel/UCa24JK3VKaYJwVlQCiSqzqg\n\n"
        "I invite you to listen to our music and be impressed by it. You can\n"
        "find out our label music at the following link:\n"
        "https://soundcloud.com/zalmanim\n\n"
        "We've been in contact over Groover.\n\n"
        "To continue, please complete your artist registration form here:\n"
        f"{registration_url}\n\n"
        "Once you complete the form, you will be able to sign in to our artist portal:\n"
        f"{portal_url}\n\n"
        "So, if you are interested in releasing music with the label, please\n"
        "send me some unreleased music.\n\n"
        "If you are interested in sharing your music on our YouTube channel,\n"
        "please send me some artwork and the music file.\n\n"
        "If you're interested in an interview or short article, please send us a short bio and pictures or any written material, and we will see if it suits both of us.\n\n"
        "Peace,\n"
        "Best regards,\n"
        "Simon Rosenfeld\n"
        "Founder & A&R | Zalmanim & SiYu Rec\n"
        "ðŸŒ www.zalmanim.com\n\n"
        "ðŸŽ§ Join our SoundCloud promo group:\n"
        "https://influenceplanner.com/invite/Anyone\n\n"
        "ðŸ’¬ Join our WhatsApp artist community:\n"
        "https://chat.whatsapp.com/Bc4EpRLdpIwEV7lAzYzdSy\n"
    )


def _get_groover_invite_subject_and_body(
    display_name: str,
    registration_url: str,
    portal_url: str,
) -> tuple[str, str]:
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("groover_invite_subject") or "").strip()
    body = (mail.get("groover_invite_body") or "").strip()
    replacements = {
        "{display_name}": display_name,
        "{registration_url}": registration_url,
        "{portal_url}": portal_url,
    }
    if not subject:
        subject = _default_groover_invite_subject()
    if not body:
        body = _default_groover_invite_body(display_name, registration_url, portal_url)
    for token, value in replacements.items():
        subject = subject.replace(token, value)
        body = body.replace(token, value)
    return subject, body


def _build_groover_invite_html(
    *,
    body_text: str,
    registration_url: str,
    portal_url: str,
) -> str:
    escaped = html.escape(body_text)
    registration_prompt = html.escape("To continue, please complete your artist registration form here:")
    portal_prompt = html.escape("Once you complete the form, you will be able to sign in to our artist portal:")
    registration_placeholder = "__GROOVER_REGISTRATION_LINK__"
    portal_placeholder = "__GROOVER_PORTAL_LINK__"

    escaped = escaped.replace(
        registration_prompt,
        '<span style="color:#c62828;font-weight:700;">'
        "To continue, please complete your artist registration form here:"
        "</span>",
    )
    escaped = escaped.replace(
        portal_prompt,
        '<span style="color:#c62828;font-weight:700;">'
        "Once you complete the form, you will be able to sign in to our artist portal:"
        "</span>",
    )
    escaped = escaped.replace(html.escape(registration_url), registration_placeholder)
    escaped = escaped.replace(html.escape(portal_url), portal_placeholder)

    body_html = "<p>" + escaped.replace("\n\n", "</p><p>").replace("\n", "<br>") + "</p>"
    body_html = body_html.replace(
        registration_placeholder,
        f'<a href="{html.escape(registration_url)}" '
        'style="color:#c62828;font-weight:700;text-decoration:underline;">'
        "Complete your artist registration form"
        "</a>",
    )
    body_html = body_html.replace(
        portal_placeholder,
        f'<a href="{html.escape(portal_url)}" style="font-weight:600;text-decoration:underline;">'
        "Sign in to the artist portal"
        "</a>",
    )
    return body_html


def _default_update_profile_invite_subject() -> str:
    return "Update your artist page and see your releases"


def _default_update_profile_invite_body(
    display_name: str,
    portal_url: str,
    username: str,
    temporary_password: str | None,
) -> str:
    password_line = (
        f"Temporary password: {temporary_password}"
        if (temporary_password or "").strip()
        else "Use your existing password."
    )
    return (
        f"Hi {display_name},\n\n"
        "We'd love you to update your artist page and see your releases on the label.\n\n"
        f"Portal: {portal_url}\n"
        f"Username: {username}\n"
        f"{password_line}\n\n"
        "Please sign in, change your password if needed, and update your profile and releases.\n\n"
        "If you have any questions, reply to this email.\n"
    )


def _get_update_profile_invite_subject_and_body(
    display_name: str,
    portal_url: str,
    username: str,
    temporary_password: str | None,
) -> tuple[str, str]:
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("update_profile_invite_subject") or "").strip()
    body = (mail.get("update_profile_invite_body") or "").strip()
    password_line = (
        f"Temporary password: {temporary_password}"
        if (temporary_password or "").strip()
        else "Use your existing password."
    )
    replacements = {
        "{display_name}": display_name,
        "{portal_url}": portal_url,
        "{username}": username,
        "{temporary_password}": (temporary_password or "").strip(),
        "{password_line}": password_line,
    }
    if not subject:
        subject = _default_update_profile_invite_subject()
    if not body:
        body = _default_update_profile_invite_body(display_name, portal_url, username, temporary_password)
    for token, value in replacements.items():
        subject = subject.replace(token, value)
        body = body.replace(token, value)
    return subject, body


def _default_password_reset_subject() -> str:
    return "Password reset"


def _default_password_reset_body(reset_link: str, expiry_minutes: int) -> str:
    return (
        f"Use this link to reset your password (valid for {expiry_minutes} minutes):\n\n"
        f"{reset_link}\n\n"
        "If you did not request this, ignore this email."
    )


def _get_password_reset_subject_and_body(reset_link: str, expiry_minutes: int) -> tuple[str, str]:
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("password_reset_subject") or "").strip()
    body = (mail.get("password_reset_body") or "").strip()
    replacements = {
        "{reset_link}": reset_link,
        "{expiry_minutes}": str(expiry_minutes),
    }
    if not subject:
        subject = _default_password_reset_subject()
    if not body:
        body = _default_password_reset_body(reset_link, expiry_minutes)
    for token, value in replacements.items():
        subject = subject.replace(token, value)
        body = body.replace(token, value)
    return subject, body


def _default_portal_invite_subject() -> str:
    return "Your Zalmanim Artists Portal access"


def _default_portal_invite_body(display_name: str, portal_url: str, username: str, temporary_password: str) -> str:
    return (
        f"Hi {display_name},\n\n"
        "Your access to the Zalmanim Artists Portal is ready.\n\n"
        "Inside the portal you can update your profile, upload media, upload releases, submit demos, "
        "and change your password.\n\n"
        f"Portal link: {portal_url}\n"
        f"Username: {username}\n"
        f"Temporary password: {temporary_password}\n\n"
        "Please sign in and change your password after your first login.\n\n"
        "If you have any questions, reply to this email.\n"
    )


def _get_portal_invite_subject_and_body(
    display_name: str, portal_url: str, username: str, temporary_password: str
) -> tuple[str, str]:
    mail = get_effective_mail_config_for_api()
    subject = (mail.get("portal_invite_subject") or "").strip()
    body = (mail.get("portal_invite_body") or "").strip()
    if not subject:
        subject = _default_portal_invite_subject()
    else:
        subject = (
            subject.replace("{display_name}", display_name)
            .replace("{portal_url}", portal_url)
            .replace("{username}", username)
            .replace("{temporary_password}", temporary_password)
        )
    if not body:
        body = _default_portal_invite_body(display_name, portal_url, username, temporary_password)
    else:
        body = (
            body.replace("{display_name}", display_name)
            .replace("{portal_url}", portal_url)
            .replace("{username}", username)
            .replace("{temporary_password}", temporary_password)
        )
    return subject, body
