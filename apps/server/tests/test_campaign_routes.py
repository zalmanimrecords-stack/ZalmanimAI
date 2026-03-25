from datetime import datetime, timezone


def test_admin_can_create_and_list_campaigns(client, admin_headers):
    create_response = client.post(
        "/api/admin/campaigns",
        headers=admin_headers,
        json={
            "name": "Spring Push",
            "title": "New Release",
            "body_text": "Listen now",
            "targets": [
                {
                    "channel_type": "wordpress",
                    "external_id": "connector-1",
                    "channel_payload": {"post_type": "post"},
                }
            ],
        },
    )

    assert create_response.status_code == 200
    payload = create_response.json()
    assert payload["name"] == "Spring Push"
    assert payload["status"] == "draft"
    assert len(payload["targets"]) == 1
    assert payload["targets"][0]["channel_type"] == "wordpress"

    list_response = client.get("/api/admin/campaigns", headers=admin_headers)

    assert list_response.status_code == 200
    campaigns = list_response.json()
    assert len(campaigns) == 1
    assert campaigns[0]["id"] == payload["id"]


def test_admin_can_schedule_and_cancel_campaign(client, admin_headers):
    create_response = client.post(
        "/api/admin/campaigns",
        headers=admin_headers,
        json={"name": "Schedule Me", "title": "Queued", "body_text": "Later"},
    )
    assert create_response.status_code == 200
    campaign_id = create_response.json()["id"]

    scheduled_at = datetime(2026, 3, 25, 12, 0, tzinfo=timezone.utc).isoformat()
    schedule_response = client.post(
        f"/api/admin/campaigns/{campaign_id}/schedule",
        headers=admin_headers,
        json={"scheduled_at": scheduled_at},
    )

    assert schedule_response.status_code == 200
    scheduled_payload = schedule_response.json()
    assert scheduled_payload["status"] == "scheduled"
    assert scheduled_payload["scheduled_at"] is not None

    cancel_response = client.post(
        f"/api/admin/campaigns/{campaign_id}/cancel",
        headers=admin_headers,
    )

    assert cancel_response.status_code == 200
    canceled_payload = cancel_response.json()
    assert canceled_payload["status"] == "draft"
    assert canceled_payload["scheduled_at"] is None
