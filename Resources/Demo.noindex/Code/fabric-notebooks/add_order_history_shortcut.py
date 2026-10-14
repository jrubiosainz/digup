"""Adds the order history to the contoso_sales lakehouse as a OneLake shortcut: it's read where it is, not copied.

The lakehouse holds the last 12 months of orders, so lookup_order can't find older ones and their returns have no
delivery date (pilot meeting, October 6). The history is already Delta tables in the archive storage account. The
shortcut makes it Tables/orders_history, which Spark, the SQL analytics endpoint and Power BI read like any other
table, with nothing to copy or keep in sync.

    export FABRIC_WORKSPACE_ID=...    # Contoso Sales: it's in the workspace's URL
    export FABRIC_LAKEHOUSE_ID=...    # contoso_sales: in the lakehouse's URL
    export ARCHIVE_CONNECTION_ID=...  # Settings › Manage connections and gateways › stcontosoarchive
    python add_order_history_shortcut.py

It needs Contributor on the workspace. Running it again changes nothing.
"""

import os

import httpx
from azure.identity import DefaultAzureCredential

FABRIC = "https://api.fabric.microsoft.com/v1"


def main() -> None:
    workspace, lakehouse = os.environ["FABRIC_WORKSPACE_ID"], os.environ["FABRIC_LAKEHOUSE_ID"]
    shortcut = {
        "path": "Tables",
        "name": "orders_history",
        "target": {
            "adlsGen2": {
                "location": "https://stcontosoarchive.dfs.core.windows.net",
                "subpath": "/orders/history",
                "connectionId": os.environ["ARCHIVE_CONNECTION_ID"],
            },
        },
    }
    token = DefaultAzureCredential().get_token("https://api.fabric.microsoft.com/.default").token
    response = httpx.post(
        f"{FABRIC}/workspaces/{workspace}/items/{lakehouse}/shortcuts",
        params={"shortcutConflictPolicy": "CreateOrOverwrite"},
        headers={"Authorization": f"Bearer {token}"},
        json=shortcut,
        timeout=30,
    )
    response.raise_for_status()
    made = response.json()
    target = made["target"]["adlsGen2"]
    print(f"{made['path']}/{made['name']} reads {target['location']}{target['subpath']}")


if __name__ == "__main__":
    main()
