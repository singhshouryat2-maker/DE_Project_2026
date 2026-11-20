# 04 · Optimization report

**Data:** seed data (144,792 bookings) · **PostgreSQL:** 16
**Method:** `./benchmarks/run_benchmark.sh`, 5 runs per query, `EXPLAIN (ANALYZE, BUFFERS)`, average of the `Execution Time` lines. Write queries ran inside `BEGIN; … ROLLBACK;`.

To compare fairly, **before** and **after** were run on the same machine, one right after the other:
- **Before:** no extra indexes, original `queries/workload_30.sql` → `benchmarks/results/baseline_cloud/`
- **After:** `sql/05_indexes.sql` (16 indexes) + `sql/06_optimized_queries.sql` → `benchmarks/results/optimized/`

(The CP2 Mac run in `benchmarks/results/baseline/` shows the same slow queries; this machine is a bit slower, e.g. R19 is 2150 ms here vs 1463 ms on the Mac.)

## Result

**Total time for all 30 queries: 2875.5 ms → 506.7 ms (5.7x faster).**
The biggest single win is R19: 2150 ms → 20 ms (105x).

## All 30 queries

| Query | Before (ms) | Problem | Optimization | After (ms) | Improvement | Same result |
|---|---:|---|---|---:|---|---|
| R01 | 14.676 | Seq scan on flights; date filter `departure_time::date = ...` cannot use an index | Rewrote filter as an IST time range + `idx_flights_departure`, `idx_fb_flight` | 0.197 | 74.5x faster | Yes |
| R02 | 1.202 | Seq scan on flights; `::date` filter | Sargable IST range + `idx_flights_departure` | 0.222 | 5.4x faster | Yes |
| R03 | 0.348 | Seq scan on hotels | `idx_hotels_city_stars (city, stars)` | 0.213 | 1.6x faster | Yes |
| R04 | 4.392 | Seq scan on hotel_bookings | `idx_hb_checkout`, `idx_hb_room_type_checkin` | 0.501 | 8.8x faster | Yes |
| R05 | 11.336 | Seq scan on bookings to find one customer | `idx_bookings_customer_status (customer_id, status)` | 0.160 | 70.8x faster | Yes |
| R06 | 0.074 | Already uses the UNIQUE index on booking_ref | None needed (first run was a cold-cache outlier) | 0.067 | about the same | Yes |
| R07 | 5.857 | Seq scan on flight_bookings to find one flight | `idx_fb_flight (flight_id)` - FK had no index | 0.197 | 29.7x faster | Yes |
| R08 | 15.676 | Seq scans on flights and flight_bookings | `idx_flights_departure` + `idx_fb_flight` (index-only) | 2.107 | 7.4x faster | Yes |
| R09 | 28.324 | Seq scans on 3 tables | `idx_bookings_booked_at`; still reads most flight_bookings | 26.500 | about the same | Yes |
| R10 | 1.189 | Seq scan for the few DELAYED flights | Partial index `idx_flights_delayed WHERE status = DELAYED` | 0.034 | 35.0x faster | Yes |
| R11 | 10.401 | Seq scan on bookings for few pending rows | Partial index `idx_bookings_pending_booked` | 0.045 | 231.1x faster | Yes |
| R12 | 33.307 | Seq scan; `EXTRACT(year ...)` filter | Sargable IST range + `idx_bookings_booked_at`; reads a whole year, so little gain | 30.020 | about the same | Yes |
| R13 | 35.805 | **Wrong result**: `NOT IN` + a NULL coupon_code returns 0 rows | Rewrote as `NOT EXISTS` (10 rows, correct) + `idx_bookings_coupon` | 0.158 | 226.6x faster | Yes (now correct) |
| R14 | 75.740 | Aggregates every flight booking | No change possible: needs all rows | 80.617 | about the same | Yes |
| R15 | 32.947 | Seq scan on hotel_bookings | `idx_hb_checkout`; still aggregates large share | 33.058 | about the same | Yes |
| R16 | 157.738 | Aggregates whole tables | No change possible: needs all rows | 149.443 | about the same | Yes |
| R17 | 39.691 | Seq scan on bookings | `idx_bookings_booked_at`; reads a whole year | 38.377 | about the same | Yes |
| R18 | 8.790 | `ILIKE %breakfast%` cannot use B-tree | `idx_hotels_city_stars` narrows to Goa; text search stays a scan | 8.633 | about the same | Yes |
| R19 | 2150.421 | Correlated subquery runs once per flight over flight_bookings | Rewrote as one JOIN + GROUP BY + `idx_flights_departure` | 20.374 | 105.5x faster | Yes |
| R20 | 13.183 | Seq scan; `::date` filter | Sargable IST range + index-only scan on `idx_bookings_booked_at` | 2.926 | 4.5x faster | Yes |
| R21 | 42.264 | Seq scan on passengers | Partial index `idx_pax_senior WHERE age >= 60` | 34.115 | 1.2x faster | Yes |
| R22 | 82.192 | Sorts all bookings for OFFSET 100000 | `idx_bookings_booked_at` gives order without a sort | 20.325 | 4.0x faster | Yes |
| R23 | 14.363 | `lower(email)` cannot use the plain UNIQUE index | Expression index `idx_customers_lower_email` | 0.073 | 196.8x faster | Yes |
| R24 | 4.343 | Seq scans on reviews and hotels | `idx_hotels_city_stars`, `idx_reviews_hotel` | 3.820 | 1.1x faster | Yes |
| R25 | 60.432 | Seq scans on 3 tables | `idx_bookings_booked_at`; compares 2 columns, so most rows still read | 48.068 | 1.3x faster | Yes |
| W01 | 1.179 | Simple INSERT | None needed | 1.088 | about the same | Yes |
| W02 | 22.130 | Seq scan for oldest pending booking | Partial index `idx_bookings_pending_id` | 0.444 | 49.8x faster | Yes |
| W03 | 0.386 | Uses UNIQUE booking_ref index | None needed | 0.502 | slower | Yes |
| W04 | 2.370 | Seq scan on flights | `idx_flights_departure` available; planner still prefers seq scan (many rows) | 1.846 | 1.3x faster | Yes |
| W05 | 4.786 | Seq scan on hotel_bookings | `idx_hb_checkin` | 2.601 | 1.8x faster | Yes |
| **Total** | **2875.542** | | | **506.731** | **5.7x faster** | |

R06 "before" uses the median, because its first run was a cold-cache outlier (81 ms, the other 4 runs were ~0.07 ms).

## What we changed

**1. Indexes (`sql/05_indexes.sql`).** The schema only had PRIMARY KEY and UNIQUE indexes. We added:
- **Foreign key index:** `flight_bookings(flight_id)`. Postgres does not index foreign keys automatically, so every "bookings for this flight" query scanned the whole table.
- **Normal and multi-column indexes:** `bookings(customer_id, status)`, `bookings(booked_at)`, `flights(origin, destination, departure_at)`, `hotels(city, stars)`, check-in/check-out dates.
- **Partial indexes** (only the few rows we search for): pending-payment bookings, DELAYED flights, passengers aged 60+, bookings with a coupon. They are tiny (16 kB) but make R10, R11 and W02 take under 0.5 ms.
- **Expression index:** `lower(email)` for case-insensitive sign-in (R23: 14.4 ms → 0.07 ms).

**2. Query rewrites (`sql/06_optimized_queries.sql`).**
- **Sargable dates (R01, R02, R12, R20):** `departure_at::date = '2026-07-05'` puts a function on the column, so an index cannot be used. We wrote it as a range: `departure_at >= '2026-07-05 00:00+05:30' AND departure_at < '2026-07-06 00:00+05:30'` (IST, so the result is the same).
- **R19:** the original ran a subquery once for each of 720 flights (463,790 buffer reads). We changed it to one `LEFT JOIN … GROUP BY` (14,997 buffer reads).
- **R13 (wrong result fixed):** `NOT IN (SELECT coupon_code FROM bookings)` returns **0 rows**, because most bookings have `coupon_code = NULL` and `x NOT IN (…, NULL)` is never true. `NOT EXISTS` returns the correct **10 unused coupons**.

## Before / after plans (top 5)

**R19** (2150 → 20 ms)
- Before: `Seq Scan on flights` → **SubPlan runs 720 times** (loops=720), 463,790 buffers.
- After: `Hash Right Join` + `HashAggregate`, one pass, 14,997 buffers.

**R13** (35.8 → 0.16 ms, and now correct)
- Before: `Seq Scan on coupons`, Filter `NOT (hashed SubPlan)` over all 144,792 bookings → rows=0.
- After: `Nested Loop Anti Join` + `Index Only Scan using idx_bookings_coupon` → rows=10.

**R01** (14.7 → 0.20 ms)
- Before: `Seq Scan on flights` + `Seq Scan on flight_bookings` (802 buffers).
- After: `Index Scan using idx_flights_departure` + `Index Scan using idx_fb_flight` (30 buffers).

**R22** (82.2 → 20.3 ms)
- Before: `Seq Scan on bookings` → `Sort`, **external merge on disk (8 MB)** to reach OFFSET 100,000.
- After: `Index Scan Backward using idx_bookings_booked_at`, no sort. Still reads 100,025 rows because of the big OFFSET; keyset paging (`WHERE booked_at < last_seen`) would fix that fully.

**W02** (22.1 → 0.44 ms)
- Before: walks `bookings_pkey` and throws away 144,695 rows to find the first pending one.
- After: `Index Only Scan using idx_bookings_pending_id` (partial index, 3 buffers).

## Write overhead

More indexes mean every INSERT/UPDATE must update them too. In our writes this cost is small:
- **W01** (INSERT): 1.18 → 1.09 ms, no visible slowdown.
- **W03** (UPDATE by reference): 0.39 → 0.50 ms, a little slower (more indexes on bookings to update).
- **W02, W04, W05** got faster, because finding the rows became cheaper than the extra index work.

## Index sizes (`pg_relation_size`)

| Index | Size |
|---|---:|
| idx_bookings_booked_at | 3200 kB |
| idx_bookings_customer_status | 2624 kB |
| idx_customers_lower_email | 2080 kB |
| idx_fb_flight | 1888 kB |
| idx_hb_room_type_checkin | 1856 kB |
| idx_pax_senior | 776 kB |
| idx_flights_route_departure | 448 kB |
| idx_hb_checkin | 448 kB |
| idx_hb_checkout | 448 kB |
| idx_flights_departure | 320 kB |
| idx_reviews_hotel | 200 kB |
| idx_bookings_coupon | 144 kB |
| idx_hotels_city_stars | 40 kB |
| idx_flights_delayed | 16 kB |
| idx_bookings_pending_booked | 16 kB |
| idx_bookings_pending_id | 16 kB |
| **Total** | **≈ 14.2 MB** |

## Queries we could not speed up much

- **R14, R16:** they aggregate every booking in the database. An index cannot help when all rows are needed; only a summary table (materialized view) would.
- **R12, R15, R17, R25, R09:** they read a whole year or month, which is a large share of the table, so the planner correctly keeps a sequential scan or gains little.
- **R18:** `ILIKE '%breakfast%'` starts with `%`, so a B-tree index cannot be used (a `pg_trgm` GIN index could).
- **W04:** updates many flights, so a sequential scan is still the best plan.
