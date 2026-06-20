---Phase 1: Data Quality & Validation Audits

---Q1 Duplicate Transaction Detection Identify and flag duplicate transaction records.

SELECT transaction_id,
	   count(*) 
from   Customer_data
GROUP by  transaction_id
Having count(*) > 1

---Q2: Invalid Revenue Validation –Audit the database for non-positive (<= 0) transaction amounts.

SELECT * 
from customer_data
where customer_data.purchase_amount <= 0

---Q3 Future Transaction Audit – Catch data anomalies where purchase dates are accidentally logged ahead of the current timestamp.

SELECT * 
from customer_data
where purchase_date > CURRENT_TIMESTAMP

---Phase 2: Core Revenue & Product Analytics

---Q4  Customer Lifetime Value Classification 

with customer_spending as 
(
select customer_data.customer_id,
	   sum(Customer_data.purchase_amount) as total_amount
from customer_data
group by customer_data.customer_id
order by  sum(Customer_data.purchase_amount) desc
)
select *,
	case
		when total_amount >= 600 
			then 'high'
		when total_amount < 600 and total_amount >= 400 
			then 'medium'
		when total_amount < 400 
			then 'low'
	end as Spending_category

from customer_spending
order by customer_id	

--- Q5 Value-Based Customer Segmentation – Classify buyers into High, Medium, and Low-Value tiers using strategic spending boundaries.

CREATE OR REPLACE VIEW view_customer_segments AS

WITH customer_total_spend AS (
    SELECT *,
           SUM(purchase_amount) OVER(PARTITION BY customer_id) AS total_customer_spend
    FROM customer_data
)
SELECT *,
       CASE
           WHEN total_customer_spend >= 600 THEN 'High'
           WHEN total_customer_spend >= 400 THEN 'Medium'
           ELSE 'Low'
       END AS spending_category
FROM customer_total_spend


---Q6 Finding the best products by revenue.

select item_purchased as items,
	   sum(purchase_amount) as total_revenue
FROM customer_data
group by item_purchased
order by sum(purchase_amount) DESC 

--- Q7 Product category percentage contribution.

with category_revenue as 
(
SELECT category,
	   sum(purchase_amount) as total_revenue
from customer_data
group by category
)

select *,
	  (total_revenue / SUM(total_revenue) OVER () * 100) as revenue_percent
from category_revenue

---Q8 map and rank the best and worst performing months of the year for inbound sales volume

with Monthly_revenue as
(
select to_char(purchase_date , 'FMMonth') as months,
	   extract(year FROM purchase_date) as years,
	   sum(purchase_amount) as total_revenue
from customer_data
group by to_char(purchase_date , 'FMMonth'),extract(year FROM purchase_date)
),
rankings as (
SELECT *,
	   dense_rank() over(Partition by years order by total_revenue desc ) as best_rnk,
       dense_rank() over(Partition by years order by total_revenue asc ) as worst_rnk
from Monthly_revenue
)
select * from rankings 
where best_rnk = 1
or worst_rnk = 1
order by years , months


---Phase 3: Advanced Retention & Customer Behavior

---Q9 90-Day Churn Risk Assessment – Isolate inactive users who have gone 90+ days without a logged purchase.

with buy_date as 
(
SELECT customer_id,
	   max(purchase_date) as max_date

from customer_data
GROUP by  customer_id
)

SELECT * ,
	   (select max(purchase_date)  from customer_data)- max_date	as days_since_last_purchase
from buy_date
where   extract (day from ((select max(purchase_date) from customer_data) - max_date)) > 90 


--- Q10 Repeat Purchase Conversion Rate – Calculate the ratio of multi-purchase clients against the total unique customer base.

with purchase_history as 
(
select customer_id ,
	   count(*) as purchase_numbers
from customer_data 
group by customer_id
)

select ((count (case when "purchase_numbers">1 then "customer_id" end)::numeric/(select count(distinct customer_id) from customer_data)::numeric) * 100) as ratio
from purchase_history
where purchase_numbers>1


--- Q11 Mean Time Between Purchases – Track customer velocity by evaluating the average historical days elapsed between user transactions.

-- Global Micro KPI: Company-Wide Average Days Between Purchases

CREATE OR REPLACE VIEW view_customer_purchase_velocity AS

with purchase_velocity as 
(
select customer_id,
	   purchase_date,
	   lag (purchase_date) over(partition by customer_id order by purchase_date ),
	   purchase_date -  lag (purchase_date) over(partition by customer_id order by purchase_date ) as differences
from customer_data
--order by customer_id,purchase_date asc
)
select customer_id,
	   avg(differences)
from purchase_velocity	
group by customer_id

-- Global Macro KPI: Company-Wide Average Days Between Purchases

with purchase_velocity as 
(
select customer_id,
	   purchase_date,
	   lag (purchase_date) over(partition by customer_id order by purchase_date ),
	   purchase_date -  lag (purchase_date) over(partition by customer_id order by purchase_date ) as differences
from customer_data
order by customer_id,purchase_date asc
)
select  avg(differences)
from purchase_velocity	

--- Q12 Ranks of Loyalty Engagement – Formally rank the client base using dense indexing based on absolute transaction frequencies.

with tranxs_records as 
(
select  customer_id,
  		count(transaction_id) as total_tranxs
from customer_data
group by customer_id
)
select  *,
	  	dense_rank() over(order by total_tranxs desc)
from tranxs_records		  


--- Q13 Cohort Analysis (Acquisition Matrix) – Create structured cohort tables tracking user monetization lifespans relative to their first purchase month.

CREATE OR REPLACE VIEW view_cohort_retention AS

with cohort_months as
(
SELECT customer_id ,
	  date_trunc('month',min(purchase_date)) as cohort_month
from customer_data
group by customer_id
),

activity_month as
(
select distinct customer_id,
	   date_trunc('month',purchase_date) as activity_month
	   from customer_data
)
select c1.customer_id,
	   c1.cohort_month,
	   a1.activity_month,
	  ((EXTRACT(YEAR FROM a1.activity_month) - EXTRACT(YEAR FROM c1.cohort_month)) * 12) +
      (EXTRACT(MONTH FROM a1.activity_month) - EXTRACT(MONTH FROM c1.cohort_month)) AS cohort_index
from cohort_months c1
join activity_month a1
on c1.customer_id = a1.customer_id

--- Q14 Month-over-Month Revenue Growth Momentum – Evaluate operational trajectory utilizing time-lagged analytical adjustments--Month-over-Month Revenue Growth Momentum – Evaluate operational trajectory utilizing time-lagged analytical adjustments

with rev_table as 
(
select extract(year from purchase_date) as years,
	   extract(month from purchase_date) as months,
	   sum(purchase_amount) as total_revenue
from customer_data
group by extract(year from purchase_date), extract(month from purchase_date)
order by extract(year from purchase_date), extract(month from purchase_date)
),
prev_revs as
(
select *,
	  lag(total_revenue) over() as prev_rev	
from rev_table
)
select *,
		(((total_revenue - prev_rev)/prev_rev) * 100) as MoM
from prev_revs		

--- Q15 Month-over-Month User Retention – Quantify sticky engagement by measuring returning buyer cohorts month over month.

CREATE OR REPLACE VIEW view_mom_retention AS

WITH unique_monthly_users AS 
(
SELECT DISTINCT 
        customer_id,
        DATE_TRUNC('month', purchase_date)::date AS active_month
FROM customer_data
),
monthly_crossovers AS 
(
SELECT t1.active_month AS current_month,
       COUNT(DISTINCT t1.customer_id) AS total_active_users,
       COUNT(DISTINCT t2.customer_id) AS returning_users
FROM unique_monthly_users t1
LEFT JOIN unique_monthly_users t2 
ON t1.customer_id = t2.customer_id 
AND t2.active_month = (t1.active_month + INTERVAL '1 month')::date
GROUP BY t1.active_month
)

SELECT current_month,
       total_active_users,
       returning_users,
       ROUND(((returning_users::numeric / total_active_users::numeric) * 100), 2) AS mom_retention_rate
FROM monthly_crossovers
ORDER BY current_month ASC;

--- Q16 Dynamic Customer Lifetime Value (CLV) Modeling – Formulate algorithmic projections calculating AOV × Frequency × Expected User Lifespan

select avg(purchase_amount) * (count(*)/count(distinct customer_id)) * 3 as corporate_clv_projection
from customer_data


--- Q17 Running Financial Ledger – Render a continuous running sum total of organizational revenue over time.

with rev_table as 
(
select extract(year from purchase_date) as years,
	   extract(month from purchase_date) as months,
	   sum(purchase_amount) as total_revenue
from customer_data
group by extract(year from purchase_date)   , extract(month from purchase_date)   
order by extract(year from purchase_date)   , extract(month from purchase_date)   
)
select *,
       sum(total_revenue) over(Rows BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
from rev_table