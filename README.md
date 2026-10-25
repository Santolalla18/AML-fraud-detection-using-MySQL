# AML Fraud Detection Using MySQL

Rule-based transaction monitoring in MySQL, evaluated against labeled data. Each rule is a SQL query. Each one is measured on precision and recall against the dataset's `is_fraud` label, so I can see which rules actually catch fraud and which don't.

**Tools:** MySQL Workbench (CTEs, window functions, conditional aggregation), Power BI
**Files:** `trxn_monitoring_sql_proj.sql` (queries) | `AML findings visualizations.pbix` (dashboard) | `synthetic_fraud_dataset.csv` (data)

## Data

| | |
|---|---|
| Transactions | 10,000 |
| Users | 1,000 (2 to 21 transactions each, 10 on average) |
| Fraud | 500 transactions (5.0%) |
| Columns | `transaction_id, user_id, amount, transaction_type, merchant_category, country, hour, device_risk_score, ip_risk_score, is_fraud` |

Things to know about the dataset:
- It is **synthetic**. The fraud label comes from how the data was generated, not from real investigations.
- `hour` is an **integer hour of day (0 to 23)** for a single day, not a timestamp. Date functions like `DATE()` and `HOUR()` don't apply to it.
- 231 transactions are exactly $1.00 and none are fraud. This looks like a floor from data generation, so rules that look for repeated amounts exclude it.

## Detection rules and results

Each rule flags transactions. **Precision** is the share of flagged transactions that are fraud, and **recall** is the share of all 500 fraud transactions caught.

| Rule | Logic | Flagged | Fraud | Precision | Recall |
|---|---|---|---|---|---|
| R1. Odd hours | `hour < 6` | 193 | 193 | 100% | 38.6% |
| R2. High-risk country | `country = 'NG'` | 100 | 100 | 100% | 20.0% |
| R3. High amount | `amount > 500` | 337 | 337 | 100% | 67.4% |
| R4. Outlier vs. user's own median | `amount > 5 x user median` (users with 5+ transactions) | 331 | 329 | 99.4% | 65.8% |
| R5. Repeated fixed amounts | same amount (above $1) appears 10+ times | 133 | 133 | 100% | 26.6% |
| **Any rule (R1 to R5)** | at least one rule hit | **493** | **491** | **99.6%** | **98.2%** |

### Why a median baseline (R4)
My first version compared each user's maximum to their average. One large transaction inflates the average and hides itself. Using the median fixes that. At the same 5x threshold, the average baseline catches 228 fraud transactions (45.6% recall, no false positives). The median baseline catches 329 (65.8% recall) at the cost of 2 false positives.

```sql
with ranked as (
  select user_id, amount,
         row_number() over (partition by user_id order by amount) as rn,
         count(*)     over (partition by user_id)                  as cnt
  from synthetic_fraud_dataset
),
medians as (
  select user_id, max(cnt) as cnt,
         avg(case when rn in (floor((cnt+1)/2), ceil((cnt+1)/2)) then amount end) as median_amount
  from ranked
  group by user_id
)
select t.*
from synthetic_fraud_dataset t
join medians m using (user_id)
where m.cnt >= 5 and t.amount > 5 * m.median_amount;
```

MySQL has no `MEDIAN()`. The middle row (or the two middle rows when the count is even) is averaged with conditional aggregation.

### Rules that did not work
These were tested and showed no lift over the 5.0% base rate:

| Rule | Result |
|---|---|
| 15+ transactions in the day | 92 users, 1,489 transactions, 4.2% fraud |
| 20+ transactions in the day | 7 users, 144 transactions, 3.5% fraud |
| 60%+ of a user's transactions at odd hours (20+ transactions) | 0 users flagged |
| Velocity spike: 4+ transactions by one user in one hour | 52 user-hours, 210 transactions, 3.3% fraud |

Fraud in this data shows up at the **transaction level** (hour, country, amount relative to the baseline, repeated amounts), not as high volume per user. With about 10 transactions per user in one day, volume and velocity rules have little to find.

### Combining the rules
Counting how many rules each transaction hits gives a simple risk score:

| Rules hit | Transactions | Fraud | Fraud rate |
|---|---|---|---|
| 0 | 9,507 | 9 | 0.1% |
| 1 | 75 | 73 | 97.3% |
| 2 | 260 | 260 | 100% |
| 3 | 133 | 133 | 100% |
| 4 | 25 | 25 | 100% |

```sql
-- repeated-amount list and per-user medians come from CTEs as above
select rule_hits, count(*) as transactions, sum(is_fraud) as fraud, round(avg(is_fraud), 3) as fraud_rate
from (
  select t.is_fraud,
         (t.hour < 6) + (t.country = 'NG') + (t.amount > 500)
         + (m.cnt >= 5 and t.amount > 5 * m.median_amount)
         + (t.amount in (select amount from repeated)) as rule_hits
  from synthetic_fraud_dataset t
  join medians m using (user_id)
) s
group by rule_hits
order by rule_hits;
```

The 9 fraud transactions that no rule catches have modest amounts and high device and IP risk scores (0.70 or higher).

## Risk scores
`device_risk_score` or `ip_risk_score` of 0.5 or higher flags exactly the 500 fraud transactions, with 100% precision and recall. In this synthetic data the scores separate fraud so cleanly that they say nothing about how rules would perform on real data. I treat them as an upper bound, not a rule to report.

## Limitations
- **Synthetic labels.** Real fraud labels are late, noisy and incomplete. These numbers show how the method works, not how it would perform in production.
- **No holdout set.** I picked thresholds and measured them on the same data, so the results are optimistic.
- **R2 and R5 are dataset-specific.** NG is hard-coded because it showed up in this data. A real system would use a maintained country-risk list. R5 found repeated amounts of $10.00 and $22.17, which in real data would need review before use.
- **One day of data,** so there is no multi-day behavior, no true velocity analysis, and no per-user history to build a baseline from.
- **Thresholds are judgment calls** (5x, 500, hour < 6) and should be tuned with a precision and alert-volume trade-off in mind.

## Acknowledgments
- Fraud detection query patterns and risk indicator thresholds (e.g., odd-hour concentration and velocity spike logic) were inspired by [Aliasgar Vandeliwala's Fraud-Detection-SQL-Project](https://github.com/Aliasgar24/Fraud-Detection-SQL-Project/blob/main/RedFlag_Transactions_Aliasgar_Vandeliwala.sql).
- All implementation, Power BI data modeling, and query adaptations for single-day transaction logic were independently developed.
