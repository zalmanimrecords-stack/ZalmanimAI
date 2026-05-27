import io

import pytest
from fastapi import HTTPException

from app.services.mailchimp_audience_import import (
    import_mailchimp_rows,
    parse_mailchimp_audience_file,
    rows_from_csv,
)


def test_rows_from_csv_mailchimp_headers():
    data = (
        "Email Address,First Name,Last Name,Status\n"
        "fan@example.com,Maya,Cohen,subscribed\n"
    ).encode("utf-8")
    rows = rows_from_csv(data)
    assert len(rows) == 1
    assert rows[0]["Email Address"] == "fan@example.com"


def test_parse_mailchimp_audience_file_rejects_unknown_extension():
    with pytest.raises(HTTPException) as exc:
        parse_mailchimp_audience_file("audience.txt", b"data")
    assert exc.value.status_code == 400


def test_parse_mailchimp_xlsx_round_trip():
    pytest.importorskip("openpyxl")
    from openpyxl import Workbook

    wb = Workbook()
    ws = wb.active
    ws.append(["Email Address", "First Name", "Last Name", "Status"])
    ws.append(["excel@example.com", "Lea", "Levi", "subscribed"])
    buf = io.BytesIO()
    wb.save(buf)

    rows = parse_mailchimp_audience_file("export.xlsx", buf.getvalue())
    assert len(rows) == 1
    assert rows[0]["Email Address"] == "excel@example.com"


def test_import_mailchimp_rows(db_session):
    from app.models.models import MailingList

    mailing_list = MailingList(name="Import test", physical_address="123 St")
    db_session.add(mailing_list)
    db_session.commit()
    db_session.refresh(mailing_list)

    rows = [{"Email Address": "new@example.com", "First Name": "New", "Status": "subscribed"}]
    created, updated, skipped = import_mailchimp_rows(
        db_session,
        mailing_list,
        rows,
        source_label="test",
    )
    assert created == 1
    assert updated == 0
    assert skipped == 0
