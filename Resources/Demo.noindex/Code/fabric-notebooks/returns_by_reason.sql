-- Returns in the last 90 days by reason, and how many of them the assistant opened.
-- For the pilot meeting on Tuesdays. Run it on the SQL analytics endpoint of contoso_sales: clean_returns.ipynb
-- rebuilds returns_clean every morning, so a return opened today shows up tomorrow.

SELECT
    reason,
    COUNT(*) AS returns,
    SUM(CASE WHEN opened_by = 'assistant' THEN 1 ELSE 0 END) AS by_assistant,
    CAST(100.0 * SUM(CASE WHEN opened_by = 'assistant' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4, 1)) AS assistant_pct,
    SUM(CASE WHEN resolution = 'replacement' THEN 1 ELSE 0 END) AS replacements,
    SUM(CASE WHEN resolution = 'refund' THEN 1 ELSE 0 END) AS refunds,
    CAST(AVG(CAST(days_after_delivery AS decimal(5, 1))) AS decimal(4, 1)) AS avg_days_after_delivery
FROM dbo.returns_clean
WHERE opened_on >= DATEADD(day, -90, CAST(GETDATE() AS date))
GROUP BY reason
ORDER BY returns DESC;
