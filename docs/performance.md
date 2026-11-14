# Performance: legacy vs refactored report query

Question: every order in March 2025, with customer and total.
Data: about 40,000 orders and 80,000 order lines. Measured in logical reads
(pages read), which is more stable than time.

| Query      | Indexes | SalesOrder reads | SalesOrderLine reads | Total reads | Elapsed |
| ---------- | ------- | ---------------- | -------------------- | ----------- | ------- |
| Legacy     | No      | 447              | 13,192               | 13,641      | 27 ms   |
| Refactored | No      | 447              | 13,627               | 14,074      | 21 ms   |
| Legacy     | Yes     | 447              | 3,483                | 3,932       | 21 ms   |
| Refactored | Yes     | 14               | 3,483                | 3,497       | 7 ms    |

Result: about 74% fewer pages read, and roughly 4x faster.

What changed:

- Replaced YEAR()/MONTH() with a date range, so the date index can be used
- Replaced SELECT \* and correlated subqueries with the shared rpt.OrderSummary view
- Added a covering index on SalesOrder(OrderDate) and on SalesOrderLine(SalesOrderId)

Lesson: neither change worked alone. The rewrite without an index still scanned
every order (447 pages). The index without the rewrite couldn't be used for the
date filter, because YEAR() hides the column from it. Together: 447 -> 14 pages.
