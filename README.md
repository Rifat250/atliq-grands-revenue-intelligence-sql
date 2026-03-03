# 🏨 __AtliQ Grands Revenue Intelligence & Optimization – SQL Analytics Project__

## __Overview__

The hospitality industry operates on thin margins, where small changes in occupancy, pricing, cancellations, and customer satisfaction can have a significant impact on overall profitability. This project analyzes the business performance of AtliQ Grands, a hotel chain facing declining revenue and market share. Using MySQL, I conducted an in-depth analysis of operational and financial data to uncover actionable insights aimed at improving revenue, optimizing occupancy, and enhancing customer experience.

Through structured SQL analysis, the project examines:
* Revenue trends and city-level performance
* Occupancy and capacity utilization
*	Booking platform effectiveness
*	Cancellation revenue impact
*	Customer ratings and service quality
*	Executive KPIs including ADR, RevPAR, and Occupancy Rate

Beyond writing queries, the focus of this project was to think like a business analyst, not just extracting data but translating it into meaningful insights that support strategic decision-making.

This case study demonstrates advanced SQL capabilities such as aggregations, joins, CTEs, window functions, ranking, and KPI calculations, applied to a real-world hospitality analytics scenario.

## __Dataset Summary: The Foundation of Our Analysis__

The dataset is structured using a star-schema architecture optimized for analytical querying. It contains 134,590 booking-level records stored in the central fact table fact_bookings, capturing individual reservation attributes such as booking dates, room types, prices, stay duration, booking status, and customer ratings.An additional fact table, fact_aggregated_bookings, stores pre-aggregated daily metrics related to room capacity, successful bookings, and occupancy counts, enabling efficient KPI computation. The schema is supported by dimension tables for Hotels, Rooms, and Date, providing descriptive context and temporal hierarchies for analysis. This data model is designed to support high-performance SQL analytics, enabling complex joins, time-based calculations, and scalable metric evaluation across multiple business dimensions.

## __Star Schema Data Model__

![Data Model](data%20model.png)

## 📊 __SQL Analysis & Key Business Insights__

__1.What is the total revenue generated during the analysis period?__

```
SELECT
	SUM(revenue_realised) AS total_revenue_realized
FROM fact_bookings;
```
__Result__

# total_revenue_realized
'1708771229'

Total Revenue Realized by AtliQ Grands: $1.71 Billion (during the analysis period)
