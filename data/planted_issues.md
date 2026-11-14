# Planted issues (answer key)

## Validation should quarantine
1. SO-5041: customer C-9999 does not exist (its line is rejected too)
2. SO-5042: impossible order date 2026-13-45 (its line is rejected too)
3. SO-5010: duplicate order row (keep the first, reject the copy)
4. SO-5002 line 9: unknown product RCV-999
5. SO-5003 line 9: negative quantity -5
6. C-1013: customer with no name
7. Budget 2026-07-01 Fish Tracking: amount 'TBD' is not a number

## Reconciliation should flag
8. OPP-1041: Closed Won deal with no ERP order
9. OPP-1005: deal amount is $1,500 higher than the order total

## Normal (must NOT be flagged)
- OPP-1042, OPP-1043, OPP-1044: Closed Lost deals without orders
