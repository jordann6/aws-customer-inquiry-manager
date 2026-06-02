import json
import os
import uuid
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timezone
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
ses = boto3.client("ses")

TABLE_NAME = os.environ["TABLE_NAME"]
SUPPORT_EMAIL = os.environ["SUPPORT_EMAIL"]
SENDER_EMAIL = os.environ["SENDER_EMAIL"]

VALID_STATUSES = {"open", "in-progress", "resolved", "closed"}


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, cls=DecimalEncoder),
    }


def handler(event, context):
    route_key = event.get("routeKey", "")
    path_params = event.get("pathParameters") or {}
    inquiry_id = path_params.get("id")

    routes = {
        "POST /inquiries":              lambda: create_inquiry(json.loads(event.get("body") or "{}")),
        "GET /inquiries":               lambda: list_inquiries(event.get("queryStringParameters") or {}),
        "GET /inquiries/{id}":          lambda: get_inquiry(inquiry_id),
        "PATCH /inquiries/{id}/status": lambda: update_status(inquiry_id, json.loads(event.get("body") or "{}")),
    }

    fn = routes.get(route_key)
    if not fn:
        return respond(404, {"error": "Not found"})
    return fn()


def create_inquiry(body):
    table = dynamodb.Table(TABLE_NAME)
    now = datetime.now(timezone.utc).isoformat()
    inquiry = {
        "inquiry_id": str(uuid.uuid4()),
        "name":       body["name"],
        "email":      body["email"],
        "subject":    body["subject"],
        "message":    body["message"],
        "status":     "open",
        "created_at": now,
        "updated_at": now,
    }
    table.put_item(Item=inquiry)
    _send_notifications(inquiry)
    return respond(201, inquiry)


def list_inquiries(query_params):
    table = dynamodb.Table(TABLE_NAME)
    status_filter = query_params.get("status")

    if status_filter:
        result = table.query(
            IndexName="status-index",
            KeyConditionExpression=Key("status").eq(status_filter),
        )
    else:
        result = table.scan()

    return respond(200, result["Items"])


def get_inquiry(inquiry_id):
    table = dynamodb.Table(TABLE_NAME)
    result = table.get_item(Key={"inquiry_id": inquiry_id})
    inquiry = result.get("Item")
    if not inquiry:
        return respond(404, {"error": "Inquiry not found"})
    return respond(200, inquiry)


def update_status(inquiry_id, body):
    new_status = body.get("status")
    if new_status not in VALID_STATUSES:
        return respond(400, {"error": f"status must be one of: {', '.join(sorted(VALID_STATUSES))}"})

    table = dynamodb.Table(TABLE_NAME)
    result = table.update_item(
        Key={"inquiry_id": inquiry_id},
        UpdateExpression="SET #s = :s, updated_at = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": new_status,
            ":t": datetime.now(timezone.utc).isoformat(),
        },
        ReturnValues="ALL_NEW",
    )
    return respond(200, result.get("Attributes", {}))


def _send_notifications(inquiry):
    ses.send_email(
        Source=SENDER_EMAIL,
        Destination={"ToAddresses": [SUPPORT_EMAIL]},
        Message={
            "Subject": {"Data": f"[New Inquiry] {inquiry['subject']}"},
            "Body": {"Text": {"Data": (
                f"New customer inquiry received.\n\n"
                f"ID: {inquiry['inquiry_id']}\n"
                f"From: {inquiry['name']} <{inquiry['email']}>\n"
                f"Subject: {inquiry['subject']}\n\n"
                f"Message:\n{inquiry['message']}"
            )}},
        },
    )
    ses.send_email(
        Source=SENDER_EMAIL,
        Destination={"ToAddresses": [inquiry["email"]]},
        Message={
            "Subject": {"Data": f"We received your inquiry — {inquiry['subject']}"},
            "Body": {"Text": {"Data": (
                f"Hi {inquiry['name']},\n\n"
                f"We've received your inquiry and will respond shortly.\n\n"
                f"Reference ID: {inquiry['inquiry_id']}\n"
                f"Subject: {inquiry['subject']}\n\n"
                f"Thank you for reaching out."
            )}},
        },
    )
