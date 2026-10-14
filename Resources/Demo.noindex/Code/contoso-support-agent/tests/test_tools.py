"""uv run pytest. Nothing here needs Azure: the tests touch only what src/tools.py decides by itself."""

import datetime as dt
import json

import pytest

from src import tools


@pytest.mark.parametrize(
    ("delivered", "today", "expected"),
    [
        (dt.date(2026, 10, 3), dt.date(2026, 10, 3), True),  # the day it arrives
        (dt.date(2026, 10, 3), dt.date(2026, 11, 2), True),  # day 30
        (dt.date(2026, 10, 3), dt.date(2026, 11, 3), False),  # day 31
        (None, dt.date(2026, 10, 9), False),  # not delivered yet
    ],
)
def test_return_window(delivered, today, expected):
    assert tools.return_window_open(delivered, today) is expected


def test_failures_reach_the_agent_as_data_and_the_log_without_details(monkeypatch, caplog):
    def broken(order_id):
        raise ConnectionError("Alex Smith, 12 Pine Road")

    monkeypatch.setitem(tools.FUNCTIONS, "lookup_order", broken)
    result = json.loads(tools.call_tool("lookup_order", '{"order_id": "48213"}'))

    assert "Talk to a person" in result["error"]
    assert "lookup_order failed for order 48213: ConnectionError" in caplog.text
    assert "Pine Road" not in caplog.text


def test_tools_the_agent_doesnt_have_are_errors_too():
    assert "error" in json.loads(tools.call_tool("refund", '{"order_id": "48213", "amount": 900}'))


def test_only_order_numbers_get_through():
    assert tools.order_number(" #48213 ") == "48213"
    for text in ["48213; DROP TABLE orders", "../admin", "４８２１３", ""]:
        with pytest.raises(ValueError):
            tools.order_number(text)


def test_dry_runs_open_no_real_returns(monkeypatch):
    monkeypatch.setenv("RETURNS_DRY_RUN", "1")
    monkeypatch.setattr(tools.httpx, "put", lambda *args, **kwargs: pytest.fail("called the returns API"))

    assert tools.create_return("48213", "damaged", "undecided") == {
        "rma": "RMA-DRYRUN", "resolution": "undecided", "label_emailed": True,
    }
