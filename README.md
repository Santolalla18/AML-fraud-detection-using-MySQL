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
- `hour` is an **integer hour of day (0 to 23)** for a single day, not a timestamp data type. Date functions like `DATE()` and `HOUR()` don't apply to it.
- 231 transactions are exactly $1.00 and none are fraud. This looks like a floor from data generation, so rules that look for repeated amounts exclude it.

## Detection rules and results

Each rule flags transactions. **Precision** is the share of flagged transactions that are fraud, and **recall** is the share of all 500 fraud transactions caught.

| Rule | Logic | Flagged | Fraud | Precision | Recall |
|---|---|---|---|---|---|
| 1. Odd hours | `hour < 6` | 193 | 193 | 100% | 38.6% |
| 2. High-risk country | `country = 'NG'` | 100 | 100 | 100% | 20.0% |
| 3. High amount | `amount > 500` | 337 | 337 | 100% | 67.4% |
| 4. Outlier vs. user's own median | `amount > 5 x user median` (users with 10+ transactions) | 331 | 329 | 99.4% | 65.8% |
| 5. Repeated fixed amounts | same amount (above $1) appears 10+ times | 133 | 133 | 100% | 26.6% |
| **Any rule (1 to 5)** | at least one rule hit | **493** | **491** | **99.6%** | **98.2%** |

### Why a median baseline (Rule 4)
My first version compared each user's maximum to their average. One large transaction inflates the average and hides itself. Using the median fixes that. At the same 5x threshold, the average baseline catches 228 fraud transactions (45.6% recall, no false positives). The median baseline catches 329 (65.8% recall) at the cost of 2 false positives.

```sql script
with ranked AS (
	SELECT user_id, amount,
	row_number() OVER (PARTITION BY user_id ORDER BY amount) AS a,
	count(*) OVER (PARTITION BY user_id) AS b
	FROM synthetic_fraud_dataset
	)
,
-- there is no built in MEDIAN() function in mySQL, so our job is to come up with a way that simulates the same thing	
user_stats AS (
	SELECT user_id, count(*) as trxn_count, round(sum(amount), 2) as total_amount_spent, 
	round(avg(amount), 2) as avg_amount_spent, round(max(amount), 2) as max_amount_spent, round(min(amount), 2) as min_amount_spent,
	round(avg(CASE WHEN a in (floor((b+1)/2), ceil((b+1)/2)) then amount END), 2) as median_amount_spent
    FROM ranked
	GROUP BY user_id
    ) 

SELECT *, round(max_amount_spent/median_amount_spent, 2) AS max_to_median -- looking at the ratio max amount to median amount spent for each user
FROM user_stats
WHERE trxn_count >= 10 
	AND max_amount_spent >= 5 * median_amount_spent -- abitrary, open to change based investigator's needs
ORDER BY max_to_median DESC;
```

MySQL has no `MEDIAN()` built in function. The middle row (or the two middle rows when the count is even) is averaged with conditional aggregation.

### Combining the rules (this will be part of next stage)
Counting how many rules each transaction hits gives a simple risk score.

## Risk scores
`device_risk_score` or `ip_risk_score` of 0.5 or higher flags exactly the 500 fraud transactions, with 100% precision and recall. In this synthetic data the scores separate fraud so cleanly that they say nothing about how rules would perform on real data. I treat them as an upper bound, not a rule to report.

## Limitations
- **Synthetic labels.** Real fraud labels are late, noisy and incomplete. These numbers show how the method works, not how it would perform in production.
- **No holdout set.** I picked thresholds and measured them on the same data, so the results are optimistic.
- **Rule 2 and Rule 5 are dataset-specific.** NG is hard-coded because it showed up in this data. A real system would use a maintained country-risk list. Rule 5 found repeated amounts of $10.00 and $22.17, which in real data would need review before use.
- **One day of data,** so there is no multi-day behavior, no true velocity analysis, and no per-user history to build a baseline from.
- **Thresholds are judgment calls** (5x, 500, hour < 6) and should be tuned with a precision and alert-volume trade-off in mind.

## Acknowledgments
- Fraud detection query patterns and risk indicator thresholds (e.g., odd-hour concentration and velocity spike logic) were inspired by [Aliasgar Vandeliwala's Fraud-Detection-SQL-Project](https://github.com/Aliasgar24/Fraud-Detection-SQL-Project/blob/main/RedFlag_Transactions_Aliasgar_Vandeliwala.sql).
- All implementation, Power BI data modeling, and query adaptations for single-day transaction logic were independently developed.
