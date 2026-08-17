-- Query 1 (behavior deep dive)
-- we are not only investigating large amount of transactions (over 20) made in one day per user,  
-- but also the amounts averages, min and max
select user_id, date(hour) as trxn_time, count(*) as trxn_count, round(sum(amount), 2) as total_amount_spent,
round(avg(amount), 2) as avg_amount_spent, round(max(amount), 2) as max_amount_spent, round(min(amount), 2) as min_amount_spent
from synthetic_fraud_dataset
group by user_id, trxn_time
having trxn_count >= 20
order by trxn_count asc;

-- Query 2
select user_id, date(hour) as trxn_time, count(*) as trxn_count from synthetic_fraud_dataset
where amount > 10 AND amount < 500
group by user_id, trxn_time
having trxn_count >= 20
order by trxn_count asc;

-- Query 3
select user_id, count(*) as trxn_count, sum(
	case 
		when hour(synthetic_fraud_dataset.hour) between 0 AND 6 then 1 else 0
	end 
) as odd_time_trxn from synthetic_fraud_dataset
group by user_id
having trxn_count >= 20 and
odd_time_trxn/trxn_count >= 0.60
order by odd_time_trxn desc, trxn_count desc;


-- Query (more advanced) velocity spike
with daily_count as ( 
select user_id, synthetic_fraud_dataset.hour as potential_trxn_spike, count(*) as trxn_count 
from synthetic_fraud_dataset
group by user_id, potential_trxn_spike),

user_vs as (
select user_id, sum(trxn_count) over(partition by user_id)/24 as avg_hr_trxn,
max(trxn_count) over(partition by user_id) as peak_daily_trxn,
count(*) over(partition by user_id) as active_hours from daily_count )

select distinct user_id, avg_hr_trxn, peak_daily_trxn, peak_daily_trxn/avg_hr_trxn as spike_ratio
from user_vs
where peak_daily_trxn/avg_hr_trxn >= 2
and peak_daily_trxn >= 5
and active_hours >= 1;

-- something that will make the case stronger

select user_id, amount, synthetic_fraud_dataset.hour, count(*) as trxn_count
from synthetic_fraud_dataset 
where user_id in ('282','470')
group by user_id, amount, synthetic_fraud_dataset.hour
order by user_id, synthetic_fraud_dataset.hour;



