# Contoso Sales notebooks

Notebooks, queries and scripts for **Contoso Sales**, the team's workspace in Microsoft Fabric. Its lakehouse,
`contoso_sales`, holds the last 12 months of orders and every return. Two things read it: the returns assistant
(`lookup_order`, read-only, through the SQL analytics endpoint) and the *Returns by reason* report in Power BI, in
Direct Lake mode.

| File | What it does | When |
|---|---|---|
| `clean_returns.ipynb` | `returns_raw` into `returns_clean`: one row per return, with a reason we can count | daily, 06:30 |
| `returns_by_reason.sql` | the last 90 days of returns by reason, and how many of them the assistant opened | Tuesdays, for the pilot meeting |
| `add_order_history_shortcut.py` | adds the order history to the lakehouse as a OneLake shortcut | once |

## Tables

| Table | What's in it | Written by |
|---|---|---|
| `orders`, `order_lines`, `customers` | the shop's orders from the last 12 months | *Copy orders* pipeline, nightly |
| `returns_raw` | the returns API's returns, with a new row each day one changes | *Copy returns* pipeline, 06:00 |
| `returns_clean` | one row per return: reason, resolution, days after delivery | `clean_returns.ipynb` |
| `orders_history` | orders older than 12 months, read in place from the archive | OneLake shortcut |

`returns_raw` keeps what customers wrote about why they're returning something, so only the data team can read it.
`returns_clean` keeps the reason's code and nothing a customer wrote.

## Changing a notebook

Edit it in the workspace, export it as `.ipynb` and commit it here, so the next person starts from what runs. To start
from this repo instead, import the notebook into the workspace and attach `contoso_sales` as its default lakehouse.

Ask Javier for Contributor on the workspace.
