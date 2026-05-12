-- 1.What is the total revenue generated during the analysis period?

SELECT
	SUM(revenue_realised) AS total_revenue_realized
FROM fact_bookings;

-- 2.How does monthly revenue trend evolve? (MoM growth & decline %)

WITH monthly_revenue AS (
    SELECT
        MONTH(booking_date) AS month_no,
        MONTHNAME(booking_date) AS month,
        SUM(revenue_realised) AS revenue
    FROM fact_bookings
    GROUP BY month_no, month
)
SELECT
    month_no,
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month_no) AS previous_month_revenue,
    ROUND(
        ((revenue - LAG(revenue) OVER (ORDER BY month_no)) 
        / LAG(revenue) OVER (ORDER BY month_no)) * 100,
        2
    ) AS mom_growth_pct
FROM monthly_revenue
ORDER BY month_no;

-- 3.What is the revenue contribution (%) by each city?

SELECT
    dh.city,
    SUM(fb.revenue_realised) AS revenue,
    ROUND(
        (SUM(fb.revenue_realised) /
        (SELECT SUM(revenue_realised)
         FROM fact_bookings)
        ) * 100,2
    ) AS revenue_contribution_pct
FROM dim_hotels AS dh
JOIN fact_bookings AS fb
ON dh.property_id = fb.property_id
GROUP BY dh.city
ORDER BY revenue DESC;

-- 4.Which hotels contribute the most and least revenue within each city?

WITH hotel_revenue AS (
    SELECT
        dh.property_name,
        dh.city,
        SUM(fb.revenue_realised) AS revenue
    FROM dim_hotels AS dh
    JOIN fact_bookings AS fb
	ON dh.property_id = fb.property_id
    GROUP BY dh.property_name, dh.city
),
ranked_hotels AS 
(
    SELECT
        *,
        RANK() OVER (PARTITION BY city ORDER BY revenue DESC) AS rank_desc,
        RANK() OVER (PARTITION BY city ORDER BY revenue ASC) AS rank_asc
    FROM hotel_revenue
)

SELECT 
	city,
    property_name,
    revenue
FROM ranked_hotels
WHERE rank_desc = 1 OR rank_asc = 1
ORDER BY city, revenue DESC;

/* 5.Compare Luxury and Business hotel categories across key performance metrics,
including total revenue, booking volume, occupancy percentage, and Average Daily Rate (ADR).
Additionally, calculate each category’s contribution percentage to total revenue and total bookings.
Identify the least-performing category for each metric and compare ADR between the two categories.
Finally, explain which category performs stronger overall and 
justify the conclusion using the observed metrics.
*/

WITH metrics1 AS
(
	SELECT
		dh.category,
        SUM(fb.revenue_realised) AS revenue,
        COUNT(fb.booking_id) AS booking_volume,
        ROUND(
			SUM(fb.revenue_realised)/COUNT(fb.booking_id),2
            ) AS adr
	FROM dim_hotels AS dh
    JOIN fact_bookings AS fb
    ON dh.property_id = fb.property_id
    GROUP BY dh.category
),
metrics2 AS
(
	SELECT
		dh.category,
        ROUND(
			(SUM(fab.successful_bookings)/SUM(fab.capacity))*100,2
            )AS occupancy_pct
	FROM dim_hotels AS dh
    JOIN fact_aggregated_bookings AS fab
    ON dh.property_id = fab.property_id
    GROUP BY dh.category
)
SELECT
	m1.category,
    m1.revenue,
    ROUND(
		m1.revenue * 100/ SUM(m1.revenue) OVER(),2
        ) AS rev_contribution_pct,
    m1.booking_volume,
    ROUND(
		m1.booking_volume * 100/ SUM(m1.booking_volume) OVER(),2
        ) AS booking_contribution_pct,
    m1.adr,
    m2.occupancy_pct,
    CASE WHEN m1.revenue = MIN(m1.revenue) OVER()
		THEN 'least_performer' ELSE 'better' END AS rev_status,
	CASE WHEN m1.booking_volume = MIN(m1.booking_volume) OVER()
		THEN 'least_performer' ELSE 'better' END AS booking_status,
	CASE WHEN m1.adr = MIN(m1.adr) OVER()
		THEN 'least_performer' ELSE 'better' END AS adr_status,
	CASE WHEN m2.occupancy_pct = MIN(m2.occupancy_pct) OVER()
		THEN 'least_performer' ELSE 'better' END AS occupancy_status,
	CASE WHEN m1.revenue = MAX(m1.revenue) OVER ()
         THEN 'stronger_overall'
         ELSE 'weaker_overall' END AS overall_strength
FROM metrics1 AS m1
JOIN metrics2 AS m2
ON m1.category = m2.category
ORDER BY m1.category;

-- 6.What is the overall occupancy rate, and how does it vary by city?

SELECT
	COALESCE(dh.city,'Overall') AS city,
    ROUND(
		(SUM(fab.successful_bookings)/SUM(fab.capacity))*100,2)
        AS occupancy_rate 
FROM dim_hotels AS dh
JOIN fact_aggregated_bookings AS fab
ON dh.property_id = fab.property_id
GROUP BY dh.city WITH ROLLUP
ORDER BY CASE WHEN dh.city IS NULL THEN 0 ELSE 1 END, occupancy_rate DESC; 

-- 7.Which hotels are under-utilized (low occupancy vs high capacity)?

WITH hotel_metrics AS
(
	SELECT
		dh.property_id,
		dh.property_name AS hotels,
		ROUND(
			(SUM(fab.successful_bookings)/SUM(fab.capacity))*100,2)
        AS occupancy_rate ,
		SUM(fab.capacity) AS capacity
	FROM dim_hotels AS dh
	JOIN fact_aggregated_bookings AS fab
	ON dh.property_id = fab.property_id
	GROUP BY dh.property_id, dh.property_name
),
average_capacity AS
(
	SELECT
		AVG(capacity) AS avg_capacity
	FROM hotel_metrics
)
SELECT
	hm.hotels,
    hm.occupancy_rate,
    hm.capacity,
    CASE WHEN hm.occupancy_rate < 50 AND hm.capacity >= ac.avg_capacity 
			THEN 'underutilized' ELSE 'ok' END AS utilization_status
FROM hotel_metrics AS hm
CROSS JOIN average_capacity AS ac
ORDER BY hm.occupancy_rate, hm.capacity DESC;

-- 8.How does occupancy differ by: o Room class o Weekday vs Weekend

SELECT
	dr.room_class,
	dd.day_type,
	ROUND(
			(SUM(fab.successful_bookings)/SUM(fab.capacity))*100,2)
	AS occupancy_pct
FROM dim_date_clean AS dd
JOIN fact_aggregated_bookings AS fab
ON dd.date = STR_TO_DATE(fab.check_in_date,'%d-%b-%Y')
JOIN dim_rooms AS dr
ON fab.room_category = dr.room_id
GROUP BY dr.room_class, dd.day_type;

-- 9.Which hotels perform below their city’s average occupancy?

WITH hotel_metrics AS
(
	SELECT
		dh.property_id,
        dh.property_name,
        dh.city,
		ROUND(
				(SUM(fab.successful_bookings)/SUM(fab.capacity))*100,2)
		AS hotel_occupancy
	FROM dim_hotels AS dh
	JOIN fact_aggregated_bookings AS fab
	ON dh.property_id = fab.property_id
    GROUP BY dh.property_id, dh.property_name, dh.city
),
city_metrics AS
(
	SELECT
		city,
		ROUND(AVG(hotel_occupancy),2) AS city_avg_occupancy
	FROM hotel_metrics 
    GROUP BY city
)
SELECT
	h.property_name,
    h.hotel_occupancy,
    c.city,
    c.city_avg_occupancy
FROM hotel_metrics AS h
JOIN city_metrics AS c
ON h.city = c.city
WHERE h.hotel_occupancy < c.city_avg_occupancy
ORDER BY h.city, h.hotel_occupancy;

-- 10.What is the revenue contribution and booking share by each platform?

SELECT
	booking_platform,
    ROUND(
		(COUNT(booking_id)/SUM(COUNT(booking_id)) OVER() * 100),2
        )AS booking_share_pct,
    ROUND(
		(SUM(revenue_realised)/SUM(SUM(revenue_realised)) OVER() * 100),2
        )AS revenue_pct
FROM fact_bookings
GROUP BY booking_platform
ORDER BY booking_share_pct DESC;

-- 11.Which platforms show high cancellation rates, and how do they impact revenue?

SELECT
	booking_platform,
    ROUND(
    (SUM(CASE WHEN booking_status='Cancelled' THEN 1 ELSE 0 END) /
    COUNT(booking_id))*100,2
    ) AS cancellation_rate,
    ROUND(
    SUM(CASE WHEN booking_status='Cancelled' THEN
    (revenue_generated - revenue_realised) ELSE 0 END),2 
    )AS revenue_lost_for_cancellation
FROM fact_bookings
GROUP BY booking_platform
ORDER BY cancellation_rate DESC;

-- 12. Which platform generates the highest revenue per booking?

SELECT
	booking_platform,
    ROUND(
    SUM(revenue_realised)/ COUNT(booking_id),2
    ) AS revenue_per_booking
FROM fact_bookings
GROUP BY booking_platform
ORDER BY revenue_per_booking DESC;

-- 13. What is the distribution of booking status? (Checked-out, Cancelled, No-show)

SELECT
	booking_status,
    COUNT(booking_id) AS booking_count,
    ROUND(
		(COUNT(booking_id) / SUM(COUNT(booking_id)) OVER()) * 100,2
    ) AS booking_pct
FROM fact_bookings
GROUP BY booking_status
ORDER BY booking_pct DESC;

-- 14.	How much revenue is lost due to cancellations.

SELECT
	booking_status,
	SUM(revenue_generated) - SUM(revenue_realised) AS revenue_lost,
    ROUND(
		((SUM(revenue_generated) - SUM(revenue_realised)) / SUM(revenue_generated) )* 100,2
    ) AS revenue_lost_pct
FROM fact_bookings
WHERE booking_status = 'Cancelled'
GROUP BY booking_status ;	

-- 15. Which city and room type have the highest cancellation impact?

SELECT
	dh.city,
    dr.room_class,
    ROUND(SUM(fb.revenue_generated) - SUM(fb.revenue_realised), 2) AS revenue_lost_amt,
    ROUND(
		((SUM(fb.revenue_generated) - SUM(fb.revenue_realised)) / SUM(fb.revenue_generated) )* 100,2
    ) AS revenue_lost_pct
FROM dim_hotels AS dh
JOIN fact_bookings AS fb
ON dh.property_id = fb.property_id
JOIN dim_rooms AS dr
ON fb.room_category = dr.room_id
WHERE fb.booking_status = 'Cancelled'
GROUP BY dh.city, dr.room_class
ORDER BY revenue_lost_amt DESC
LIMIT 1;

-- 16. What is the average rating by hotel and by city?

SELECT
	dh.city,
    dh.property_name,
    ROUND(AVG(fb.ratings_given),2) AS average_rating
FROM dim_hotels AS dh
JOIN fact_bookings AS fb
ON dh.property_id = fb.property_id
GROUP BY dh.city, dh.property_name
ORDER BY dh.city, average_rating DESC ;

-- 17. Is there a correlation between ratings and revenue performance?

SELECT
	ratings_given,
    ROUND(AVG(revenue_realised),2) AS avg_revenue,
    COUNT(booking_id) AS booking_count
FROM fact_bookings
WHERE ratings_given IS NOT NULL
GROUP BY ratings_given
ORDER BY avg_revenue DESC;

-- 18. Which hotels generate high revenue but have low ratings? 

WITH hotel_metrics AS
(
	SELECT
		dh.property_id,
		dh.property_name,
		SUM(fb.revenue_realised) AS revenue,
        ROUND(AVG(ratings_given),2) AS avg_ratings
	FROM dim_hotels AS dh
	JOIN fact_bookings AS fb
	ON dh.property_id = fb.property_id
    WHERE ratings_given IS NOT NULL
	GROUP BY dh.property_id, dh.property_name
),
benchmarks AS
(
	SELECT
		ROUND(AVG(revenue),2) AS average_revenue,
        ROUND(AVG(avg_ratings),2) AS average_ratings
	FROM hotel_metrics
)
SELECT
	hm.property_name,
    hm.revenue,
    hm.avg_ratings
FROM hotel_metrics AS hm
CROSS JOIN benchmarks AS b
WHERE  hm.revenue > b.average_revenue
AND hm.avg_ratings < b.average_ratings
ORDER BY hm.revenue DESC;

-- 19. Rank hotels by revenue within each city .

SELECT
	dh.city,
    dh.property_name,
    SUM(fb.revenue_realised) AS revenue,
    RANK() OVER(PARTITION BY dh.city ORDER BY SUM(fb.revenue_realised) DESC) AS rnk
FROM dim_hotels AS dh
JOIN fact_bookings AS fb
ON dh.property_id = fb.property_id
GROUP BY dh.city, dh.property_id, dh.property_name;

-- 20. Identify top 3 revenue-generating hotels per city.

WITH city_metrics AS
(
SELECT
	dh.city,
    dh.property_name,
    SUM(fb.revenue_realised) AS revenue,
    RANK() OVER(PARTITION BY dh.city ORDER BY SUM(fb.revenue_realised) DESC) AS rnk
FROM dim_hotels AS dh
JOIN fact_bookings AS fb
ON dh.property_id = fb.property_id
GROUP BY dh.city, dh.property_id, dh.property_name
)
SELECT
	city,
    property_name,
    rnk
FROM city_metrics
WHERE rnk IN (1,2,3);

-- 21.	Calculate Month-over-Month revenue growth %.

WITH revenue_trends AS
(
	SELECT
		MONTH(dd.date) AS month_no,
		MONTHNAME(dd.date) AS month_name,
		SUM(fb.revenue_realised) AS revenue,
		LAG(SUM(fb.revenue_realised)) OVER(ORDER BY MONTH(dd.date)) AS prev_month_revenue
    FROM dim_date_clean AS dd
    JOIN fact_bookings AS fb
    ON dd.date = fb.booking_date
    GROUP BY month_no, month_name
)
SELECT
	month_name,
    revenue,
    prev_month_revenue,
    ROUND(
		((revenue - prev_month_revenue) / prev_month_revenue) * 100,2
        ) AS revenue_growth_pct
FROM revenue_trends 
ORDER BY month_no;

-- 22. Which hotels have high capacity but low RevPAR?

WITH revenue_metrics AS
(
	SELECT
		dh.property_id,
		dh.property_name,
		SUM(fb.revenue_realised) AS revenue
	FROM dim_hotels AS dh  
	JOIN fact_bookings AS fb
	ON dh.property_id = fb.property_id 
	GROUP BY dh.property_id, dh.property_name
),
capacity_metrics AS
(
	SELECT
		property_id,
        SUM(capacity) AS capacity
	FROM fact_aggregated_bookings
    GROUP BY property_id
),
hotel_metrics AS
(
	SELECT
		rm.property_id,
        rm.property_name,
        rm.revenue,
        cm.capacity,
        ROUND(rm.revenue / cm.capacity,2) AS revpar
	FROM revenue_metrics AS rm
    JOIN capacity_metrics AS cm
    ON rm.property_id = cm.property_id			
),
benchmarks AS
(
	SELECT
		AVG(capacity) AS average_capacity,
        AVG(revpar) AS average_revpar
	FROM hotel_metrics
)
SELECT
	hm.property_id,
	hm.property_name,
    hm.capacity,
	hm.revenue,
    hm.revpar
FROM hotel_metrics AS hm
CROSS JOIN benchmarks AS b
WHERE hm.capacity > b.average_capacity
AND hm.revpar < b.average_revpar
ORDER BY hm.capacity DESC, hm.revpar;

-- 23. Calculate key KPIs:•	ADR • RevPAR • Occupancy %

WITH revenue_metrics AS
(
	SELECT
		SUM(revenue_realised) AS revenue
    FROM fact_bookings
),
hotel_metrics AS
(
	SELECT
		SUM(successful_bookings) AS rooms_sold,
        SUM(capacity) AS capacity
    FROM fact_aggregated_bookings
)
SELECT
	ROUND(r.revenue / h.rooms_sold,2) AS ADR,
    ROUND(r.revenue / h.capacity,2) AS RevPAR,
    ROUND((h.rooms_sold /  h.capacity)*100,2) AS Occupancy_pct
FROM revenue_metrics AS r
CROSS JOIN hotel_metrics AS h;

-- 24. Which city delivers the highest RevPAR?

WITH revenue_metrics AS
(
	SELECT
		dh.city,
		SUM(revenue_realised) AS revenue
    FROM dim_hotels AS dh
    JOIN fact_bookings AS fb
    ON dh.property_id = fb.property_id
    GROUP BY dh.city
),
capacity_metrics AS
(
	SELECT
		dh.city,
        SUM(fab.capacity) AS capacity
	FROM dim_hotels AS dh
    JOIN fact_aggregated_bookings AS fab
    ON dh.property_id = fab.property_id
    GROUP BY dh.city
)
SELECT
	r.city,
    ROUND(r.revenue / c.capacity,2) AS RevPAR
FROM revenue_metrics AS r 
JOIN capacity_metrics AS c
ON r.city = c.city
ORDER BY RevPAR DESC;

/* 25. Based on revenue, occupancy rate, RevPAR, and customer ratings,
 which cities should AtliQ prioritize for further investment? */
 
 WITH metrics1 AS 
 (
	SELECT
		dh.city,
        SUM(fb.revenue_realised) AS revenue,
        ROUND(AVG(fb.ratings_given),2) AS customer_ratings
	FROM dim_hotels AS dh
    JOIN fact_bookings AS fb
    ON dh.property_id = fb.property_id
    GROUP BY dh.city
 ),
 metrics2 AS
 (
	SELECT
		dh.city,
        ROUND(
        (SUM(fab.successful_bookings) / SUM(fab.capacity))*100,2
        ) AS occupancy_rate,
        ROUND(
        MAX(m1.revenue) / SUM(fab.capacity),2
        ) AS RevPAR
	FROM dim_hotels AS dh
    JOIN fact_aggregated_bookings AS fab
    ON dh.property_id = fab.property_id
    JOIN metrics1 AS m1
    ON dh.city = m1.city
    GROUP BY dh.city
 ),
 benchmarks AS
 (
	SELECT
		AVG(m1.revenue) AS avg_revenue,
        AVG(m2.occupancy_rate) AS avg_occupancy_rate,
        AVG(m2.RevPAR) AS avg_RevPAR,
        AVG(m1.customer_ratings) AS avg_customer_ratings
	FROM metrics1 AS m1
    JOIN metrics2 AS m2
    ON m1.city = m2.city
 )
 SELECT
	m1.city,
    m1.revenue,
    CASE WHEN m1.revenue > b.avg_revenue THEN 'OK' ELSE 'NOT OK' 
    END AS revenue_status,
    m2.occupancy_rate,
    CASE WHEN m2.occupancy_rate > b.avg_occupancy_rate THEN 'OK' ELSE 'NOT OK' 
    END AS occupancy_rate_status,
    m2.RevPAR,
    CASE WHEN m2.RevPAR > b.avg_RevPAR THEN 'OK' ELSE 'NOT OK' 
    END AS RevPAR_status,
    m1.customer_ratings,
    CASE WHEN m1.customer_ratings > b.avg_customer_ratings THEN 'OK' ELSE 'NOT OK' 
    END AS customer_ratings_status,
    (
		CASE WHEN m1.revenue > b.avg_revenue THEN 1 ELSE 0 END +
        CASE WHEN m2.occupancy_rate > b.avg_occupancy_rate THEN 1 ELSE 0 END +
        CASE WHEN m2.RevPAR > b.avg_RevPAR THEN 1 ELSE 0 END +
        CASE WHEN m1.customer_ratings > b.avg_customer_ratings THEN 1 ELSE 0 END 
	) AS kpi_score,
    CASE
		WHEN
			(
				CASE WHEN m1.revenue > b.avg_revenue THEN 1 ELSE 0 END +
				CASE WHEN m2.occupancy_rate > b.avg_occupancy_rate THEN 1 ELSE 0 END +
				CASE WHEN m2.RevPAR > b.avg_RevPAR THEN 1 ELSE 0 END +
				CASE WHEN m1.customer_ratings > b.avg_customer_ratings THEN 1 ELSE 0 END
			) >=3 THEN 'invest'
		WHEN
			(
				CASE WHEN m1.revenue > b.avg_revenue THEN 1 ELSE 0 END +
				CASE WHEN m2.occupancy_rate > b.avg_occupancy_rate THEN 1 ELSE 0 END +
				CASE WHEN m2.RevPAR > b.avg_RevPAR THEN 1 ELSE 0 END +
				CASE WHEN m1.customer_ratings > b.avg_customer_ratings THEN 1 ELSE 0 END
			) =2 THEN 'improve'
		ELSE 'do not invest' 
        END AS investment_decision
FROM metrics1 AS m1
JOIN metrics2 AS m2
ON m1.city = m2.city
CROSS JOIN benchmarks AS b
ORDER BY kpi_score DESC ;
