# 03 · Baseline timings

**Machine:** MacBook Pro M4 · **PostgreSQL:** 15.19 (Homebrew) · **Data:** seed data (144,792 bookings)
**Method:** `./benchmarks/run_benchmark.sh makemytrip baseline`. Every query ran 3 times with `EXPLAIN (ANALYZE, BUFFERS)`; the time is the `Execution Time` line. Write queries ran inside `BEGIN; … ROLLBACK;`. Raw plans are in `benchmarks/results/baseline/`.
**Indexes at this point:** only the ones PostgreSQL makes for PRIMARY KEY and UNIQUE constraints (no tuning yet).

## Timing table

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Flight search: Delhi → Mumbai on 5 July 2026 with seats left | READ | 18.154 | 11.887 | 11.763 | 13.935 |
| R02: Fare calendar: cheapest Bengaluru → Delhi fare for each day of July 2026 | READ | 1.875 | 1.668 | 2.069 | 1.871 |
| R03: Hotel search: 4★+ hotels in Goa with a swimming pool, best rated first | READ | 0.608 | 0.610 | 0.886 | 0.701 |
| R04: Room availability: rooms left per room type of hotel 208 for 10–12 July 2026 | READ | 7.873 | 7.462 | 6.377 | 7.237 |
| R05: "My Trips": customer 1021's upcoming confirmed trips | READ | 13.458 | 13.404 | 15.290 | 14.051 |
| R06: Support: open a booking by its reference | READ | 0.034 | 0.048 | 0.056 | 0.046 |
| R07: Airline manifest: passengers on flight 13047 ordered by seat | READ | 6.900 | 6.854 | 5.934 | 6.563 |
| R08: Revenue management: July 2026 flights with fewer than 5 passengers booked | READ | 15.385 | 14.358 | 11.693 | 13.812 |
| R09: Trends: 10 most-booked routes in June 2026 | READ | 21.269 | 19.708 | 17.285 | 19.421 |
| R10: Flight status board: delayed flights | READ | 0.968 | 0.932 | 1.077 | 0.992 |
| R11: Payments: bookings waiting for payment for more than 30 minutes (checked at 23:59 on 30 Jun 2026) | READ | 9.275 | 8.707 | 8.212 | 8.731 |
| R12: Finance: revenue per booking type per month in 2026 (excluding cancellations) | READ | 23.303 | 17.308 | 17.063 | 19.225 |
| R13: Marketing: coupons that have never been used | READ | 13.580 | 13.318 | 14.624 | 13.841 |
| R14: Airline partnerships: cancellation rate of flight bookings per airline | READ | 30.326 | 30.694 | 30.229 | 30.416 |
| R15: Hotel partnerships: room-nights sold per city for stays in June 2026 | READ | 17.161 | 27.477 | 29.820 | 24.819 |
| R16: Insights: average days between booking and travel, per booking type and loyalty tier | READ | 79.050 | 73.232 | 71.632 | 74.638 |
| R17: Loyalty: customers with 3 or more completed trips that started in 2026 | READ | 20.911 | 20.125 | 21.238 | 20.758 |
| R18: Hotel page: Goa reviews that mention breakfast | READ | 3.345 | 3.408 | 4.419 | 3.724 |
| R19: Operations: passengers booked on every flight departing in June 2026 | READ | 1514.992 | 1443.985 | 1430.903 | 1463.293 |
| R20: Finance: bookings per day and running total for June 2026 | READ | 8.024 | 7.988 | 7.860 | 7.957 |
| R21: Concessions: senior-citizen passengers (60+) per route in 2026 | READ | 21.575 | 18.826 | 18.024 | 19.475 |
| R22: Support console: all bookings, newest first, page 4,001 (25 per page) | READ | 39.565 | 38.352 | 36.936 | 38.284 |
| R23: Sign-in: find the customer by email, ignoring case | READ | 6.563 | 6.742 | 6.705 | 6.670 |
| R24: Hotel ranking: Goa hotels with at least 5 reviews, by average review rating | READ | 2.021 | 2.061 | 2.315 | 2.132 |
| R25: Insights: last-minute flight bookings (made less than 24 hours before departure) in 2026 | READ | 23.890 | 20.822 | 20.264 | 21.659 |
| W01: Checkout: create a pending flight booking for customer 1021 | WRITE | 0.420 | 0.409 | 0.406 | 0.412 |
| W02: Payment gateway callback: confirm the oldest booking that is waiting for payment | WRITE | 12.402 | 11.657 | 11.875 | 11.978 |
| W03: Customer cancels booking MMA7772F with a 70% refund | WRITE | 0.212 | 0.168 | 0.183 | 0.188 |
| W04: Flight ops: every flight that was scheduled to depart before 1 July 2026 has now departed | WRITE | 1.907 | 1.887 | 1.089 | 1.628 |
| W05: Front desk: assign room numbers to every guest checking in on 1 July 2026 | WRITE | 6.369 | 5.000 | 2.966 | 4.778 |
| **Total (sum of all 30)** | | **1921.415** | **1829.097** | **1809.193** | **1853.235** |

**R19 alone is 79% of the total time.** The 5 slowest queries are R19, R16, R22, R14 and R15.

## Scan type and why each query is slow or fast

| Query | Scan type (from the plan) | Why |
|---|---|---|
| R01 | Seq Scan on flights, flight_bookings; Index Scan on bookings_pkey | No index on (origin, destination, date), and `DATE(departure_at)` hides the column from any index, so all 13,848 flights and 84,899 flight bookings are read. |
| R02 | Seq Scan on flights | Reads all flights to find one route; `departure_at::date` in WHERE also blocks an index. Fast only because the table is small. |
| R03 | Seq Scan on hotels | Only 3,000 hotels, so a full scan is cheap. No index on city or the JSONB `pool` flag. |
| R04 | Seq Scan on hotel_bookings; Index Scan on room_types, bookings | Room types are found by index (hotel_id is in a UNIQUE key), but all 59,893 hotel bookings are scanned because `room_type_id` has no index. |
| R05 | Seq Scan on bookings; Index Scans on the rest | No index on `bookings.customer_id`, so all 144,792 bookings are read to find one customer's trips. |
| R06 | Index Scan on bookings_booking_ref_key | `booking_ref` is UNIQUE, so it has an index: one lookup. Fastest query. |
| R07 | Seq Scan on flight_bookings; Index Scans on bookings, passengers | No index on `flight_bookings.flight_id`, so all flight bookings are read to find one flight. |
| R08 | Seq Scan on flights, flight_bookings | Joins every flight booking to filter July SCHEDULED flights; no index on `departure_at`/`status` or `flight_id`. |
| R09 | Seq Scan on bookings, flight_bookings, flights | No index on `booked_at`, so all bookings are read for one month, then hash-joined. |
| R10 | Seq Scan on flights | No index on `status`; only a few rows are DELAYED, but every flight is checked. Small table, so still fast. |
| R11 | Seq Scan on bookings | Only 97 PENDING_PAYMENT rows, but there is no index on `status`, so all 144,792 rows are read. |
| R12 | Seq Scan on bookings | `EXTRACT(YEAR FROM booked_at)` hides the column from any index, so the whole table is read and grouped. |
| R13 | Seq Scan on coupons, bookings | `NOT IN (SELECT …)` over all bookings. It also returns **0 rows, which is wrong**: the subquery contains NULL coupon codes. |
| R14 | Seq Scan on all 4 tables | Reads every flight booking with its booking, flight and airline; it is a full report, so a large scan is expected. |
| R15 | Seq Scan on bookings, hotel_bookings, hotels | No index on `check_in`/`check_out`, so all hotel bookings are read for one month. Times vary (17–30 ms) because the run is short and small effects matter. |
| R16 | Seq Scan on 5 tables | Joins all bookings with customers, flights and hotel bookings with no filter at all: the biggest full scan in the workload. |
| R17 | Seq Scan on bookings | No index on `status` or `booked_at`; the whole table is read, then grouped by customer. |
| R18 | Seq Scan on hotel_reviews, hotels | `ILIKE '%breakfast%'` starts with `%`, so a normal B-tree index cannot be used. |
| R19 | Seq Scan on flights, flight_bookings; Index Only Scan on passengers | **The slow query.** The correlated subquery runs once for each of the 720 June flights, and each run scans all 84,899 flight bookings because `flight_bookings.flight_id` has no index. |
| R20 | Seq Scan on bookings | `booked_at::date BETWEEN …` hides the column from any index; the window function itself is cheap. |
| R21 | Seq Scan on passengers, flight_bookings, flights | No index on `age` or `departure_at`; all 163,380 passengers are read. |
| R22 | Seq Scan on bookings | `OFFSET 100000` forces PostgreSQL to sort the whole table and throw away 100,000 rows to return 25. No index on `booked_at`. |
| R23 | Seq Scan on customers | The UNIQUE index is on `email`, but the query uses `lower(email)`, so the index cannot be used. |
| R24 | Seq Scan on hotel_reviews, hotels | Small tables; groups all reviews of Goa hotels. No index on `hotel_reviews.hotel_id`. |
| R25 | Seq Scan on bookings, flight_bookings, flights | `departure_at - booked_at < 24 hours` compares two columns from different tables, so no index can filter it; everything is joined first. |
| W01 | No scan | A single-row INSERT; only the PK/UNIQUE indexes and foreign keys are checked. |
| W02 | Index Scan on bookings_pkey | `min(booking_id) … WHERE status = 'PENDING_PAYMENT'` walks the primary key in order and checks the status of each row until it finds one; no index on `status`. |
| W03 | Index Scan on bookings_booking_ref_key | Finds the booking by its UNIQUE reference: one lookup. |
| W04 | Seq Scan on flights | No index on `status`/`departure_at`; reads all flights to update 10. |
| W05 | Seq Scan on hotel_bookings; Index Scan on bookings_pkey | No index on `check_in`, so all hotel bookings are read to find guests checking in on one day. |

## What this tells us for Phase 4
- Almost every query is a **Seq Scan**, because only PK/UNIQUE indexes exist. The biggest wins will come from indexes on foreign keys (`flight_bookings.flight_id`, `bookings.customer_id`, `hotel_bookings.room_type_id`) and on the columns used in WHERE (`booked_at`, `status`, `departure_at`, `check_in`).
- Some queries cannot use an index as written: functions on columns (`DATE(departure_at)`, `EXTRACT(YEAR …)`, `lower(email)`), a leading `%` in `ILIKE`, and `OFFSET` paging. These need expression indexes or a rewrite.
- **R19** (correlated subquery) should be rewritten as one JOIN + GROUP BY, or helped by an index on `flight_bookings.flight_id`.
- **R13** must be fixed to use `NOT EXISTS`, because it currently returns the wrong result.
