"""The agent's tools. File Search runs inside Foundry; the two functions run here, in the web app, because they
reach systems Foundry can't: the orders lakehouse in Microsoft Fabric and the returns API.

They run as the app's managed identity, which can do only what they need (checklist §5): read orders, as a Viewer
of the Fabric workspace, and open returns, with the returns API's Returns.Write role. Neither can refund, cancel an
order or change an address, so the agent can't either.
"""

from __future__ import annotations

import contextlib
import datetime as dt
import json
import logging
import os
import struct
from collections.abc import Callable
from typing import Any

import httpx
import pyodbc
from azure.ai.projects.models import FileSearchTool, FunctionTool, Tool
from azure.identity import DefaultAzureCredential

log = logging.getLogger(__name__)
credential = DefaultAzureCredential()

RETURN_WINDOW_DAYS = 30
SQL_COPT_SS_ACCESS_TOKEN = 1256  # the ODBC driver's connection attribute for an Entra ID access token

LOOKUP_ORDER = FunctionTool(
    name="lookup_order",
    description="Finds an order by its number: the customer's first name, status, delivery date, items, and whether "
                "it can still be returned. Call it before saying anything about an order.",
    parameters={
        "type": "object",
        "properties": {
            "order_id": {"type": "string", "description": "The order number, e.g. 48213."},
        },
        "required": ["order_id"],
        "additionalProperties": False,
    },
    strict=True,
)

CREATE_RETURN = FunctionTool(
    name="create_return",
    description="Opens the return for an order inside its return window, or records the customer's choice on it. "
                "Opening a return emails the customer a prepaid label and commits them to nothing.",
    parameters={
        "type": "object",
        "properties": {
            "order_id": {"type": "string", "description": "The order number, e.g. 48213."},
            "reason": {"type": "string", "enum": ["damaged", "wrong_item", "not_as_described", "no_longer_needed"]},
            "resolution": {
                "type": "string",
                "enum": ["undecided", "replacement", "refund"],
                "description": "undecided until the customer has chosen a replacement or a refund.",
            },
        },
        "required": ["order_id", "reason", "resolution"],
        "additionalProperties": False,
    },
    strict=True,
)


def policy_search() -> FileSearchTool:
    """The policy PDFs, one file per page (python -m src.agent policies)."""
    return FileSearchTool(vector_store_ids=[os.environ["POLICY_VECTOR_STORE_ID"]], max_num_results=5)


def agent_tools() -> list[Tool]:
    """Everything a new version of the agent may use."""
    return [policy_search(), LOOKUP_ORDER, CREATE_RETURN]


# TODO(sara): one 10-second budget for both tools (checklist §5). httpx gives up after 5 seconds per step, but
#  pyodbc has no query timeout, so a slow lakehouse leaves the customer looking at "• • •" for as long as it takes.
def call_tool(name: str, arguments: str) -> str:
    """Runs a function the agent asked for and gives it the result, as JSON.

    Failures go back to the agent too, so it can tell the customer instead of guessing. The log gets the tool, the
    order number and the kind of error, never what the customer wrote or what a system answered (checklist §4)."""
    order = "?"
    try:
        values = json.loads(arguments)
        order = str(values.get("order_id", "?"))
        result = FUNCTIONS[name](**values)
    except ValueError as error:  # our own words, from order_number()
        result = {"error": str(error)}
    except Exception as error:  # noqa: BLE001
        log.warning("%s failed for order %s: %s", name, order, type(error).__name__)
        result = {"error": f"{name} didn't work this time. Don't guess: say so, and offer Talk to a person."}
    return json.dumps(result, default=str)


def order_number(text: str) -> str:
    """'#48213 ' becomes '48213'. Anything else is refused before it gets near SQL or a URL."""
    number = text.strip().removeprefix("#")
    if not (number.isascii() and number.isdigit() and len(number) <= 10):
        raise ValueError("Order numbers are digits only, like 48213. Ask the customer to check theirs.")
    return number


def return_window_open(delivered_on: dt.date | None, today: dt.date | None = None) -> bool:
    """Returns are accepted for 30 days after delivery. An order that hasn't arrived can't be returned yet."""
    if delivered_on is None:
        return False
    days = ((today or dt.datetime.now(dt.UTC).date()) - delivered_on).days
    return 0 <= days <= RETURN_WINDOW_DAYS


ORDER_QUERY = """
SELECT o.order_id, c.first_name, o.status, CAST(o.delivered_at AS date) AS delivered_on,
       l.product_name, l.quantity
FROM dbo.orders AS o
JOIN dbo.customers AS c ON c.customer_id = o.customer_id
JOIN dbo.order_lines AS l ON l.order_id = o.order_id
WHERE o.order_id = ?
ORDER BY l.line_number
"""


def connect() -> pyodbc.Connection:
    """The SQL analytics endpoint of the contoso_sales lakehouse, signed in as the app's identity."""
    token = credential.get_token("https://database.windows.net/.default").token.encode("utf-16-le")
    return pyodbc.connect(
        f"Driver={{ODBC Driver 18 for SQL Server}};Server={os.environ['FABRIC_SQL_ENDPOINT']},1433;"
        "Database=contoso_sales;Encrypt=yes",
        attrs_before={SQL_COPT_SS_ACCESS_TOKEN: struct.pack(f"<I{len(token)}s", len(token), token)},
    )


def lookup_order(order_id: str) -> dict[str, Any]:
    """Read-only. Known issue: whoever knows an order number can look it up. That's acceptable behind the pilot's
    sign-in, but before going public it must check that the order belongs to the signed-in customer."""
    with contextlib.closing(connect()) as connection:
        rows = connection.cursor().execute(ORDER_QUERY, order_number(order_id)).fetchall()
    if not rows:
        return {"found": False,
                "note": "Order history covers the last 12 months. If the customer confirms the number, hand over."}
    first = rows[0]
    return {
        "found": True,
        "order_id": first.order_id,
        "customer_first_name": first.first_name,
        "status": first.status,
        "delivered_on": first.delivered_on,
        "return_window_open": return_window_open(first.delivered_on),
        "items": [{"product": row.product_name, "quantity": row.quantity} for row in rows],
    }


def create_return(order_id: str, reason: str, resolution: str) -> dict[str, Any]:
    """Opens the order's return, or records the customer's choice on it: the returns API keeps one return per
    order, so calling again only changes its resolution. Opening it emails the customer a prepaid label."""
    number = order_number(order_id)
    if os.environ.get("RETURNS_DRY_RUN") == "1":  # evaluations and local runs
        return {"rma": "RMA-DRYRUN", "resolution": resolution, "label_emailed": True}
    token = credential.get_token("api://contoso-returns/.default").token
    response = httpx.put(
        f"{os.environ['RETURNS_API']}/orders/{number}/return",
        json={"reason": reason, "resolution": resolution, "channel": "support-agent"},
        headers={"Authorization": f"Bearer {token}"},
    )
    response.raise_for_status()
    body = response.json()
    return {key: body[key] for key in ("rma", "resolution", "label_emailed", "replacement") if key in body}


FUNCTIONS: dict[str, Callable[..., dict[str, Any]]] = {"lookup_order": lookup_order, "create_return": create_return}
