# 05 · Scalability report (large dataset)

**Data:** `large_data.zip` from faculty: 10.4 million rows, about 20× the seed data (2,897,285 bookings, 3,272,394 passengers, 1,698,936 flight bookings, 1,198,349 hotel bookings, 800,000 customers). All 7 data checks in the load script returned 0.
**Steps:** new database `makemytrip_large` → our `sql/01_schema.sql` → `sql/02_load_data.sql` with `seed_data` changed to `large_data` → our `sql/05_indexes.sql` (it ends with `ANALYZE`) → `./benchmarks/run_benchmark.sh makemytrip_large large 3 sql/06_optimized_queries.sql`.
**Only the optimized queries were run on the large data** (not the original 30).
**Machine:** PostgreSQL 16. The seed numbers below were measured again on the same machine, right after the large run, with the same indexes (`benchmarks/results/seed_rerun/`), so the growth column compares like with like.
Results: `benchmarks/results/large/` (summary.csv + all plans).

## 1. Results against the targets

**All 30 queries meet their target on the large data.** Only R03 needed a fix (section 3).

| Query | Target | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what we changed |
|---|---|---:|---:|---:|:-:|---|
| R01 | Real-time < 5 ms | 0.267 | 1.280 | 4.8× | Yes | — |
| R02 | Real-time < 5 ms | 0.303 | 0.258 | 0.9× | Yes | — |
| R03 | Real-time < 5 ms | 0.396 | 0.328 | 0.8× | Yes | Added `idx_hotels_city_rating` + `CREATE STATISTICS` (see "What broke at scale") |
| R04 | Real-time < 5 ms | 0.888 | 0.555 | 0.6× | Yes | — |
| R05 | Real-time < 5 ms | 0.164 | 0.110 | 0.7× | Yes | — |
| R06 | Real-time < 5 ms | 0.097 | 0.097 | 1.0× | Yes | — |
| R07 | Real-time < 5 ms | 0.260 | 3.432 | 13.2× | Yes | — |
| R08 | Partner < 250 ms | 2.535 | 23.232 | 9.2× | Yes | — |
| R09 | Report < 5,000 ms | 23.966 | 218.305 | 9.1× | Yes | — |
| R10 | Real-time < 5 ms | 0.067 | 0.053 | 0.8× | Yes | — |
| R11 | Real-time < 5 ms | 0.058 | 0.375 | 6.5× | Yes | — |
| R12 | Report < 5,000 ms | 36.329 | 813.873 | 22.4× | Yes | — |
| R13 | Partner < 250 ms | 0.192 | 0.226 | 1.2× | Yes | — |
| R14 | Report < 5,000 ms | 100.012 | 1073.849 | 10.7× | Yes | — |
| R15 | Report < 5,000 ms | 46.077 | 361.334 | 7.8× | Yes | — |
| R16 | Report < 5,000 ms | 198.618 | 2630.810 | 13.2× | Yes | — |
| R17 | Report < 5,000 ms | 46.113 | 1092.053 | 23.7× | Yes | — |
| R18 | Partner < 250 ms | 6.984 | 67.054 | 9.6× | Yes | — |
| R19 | Report < 5,000 ms | 22.530 | 425.061 | 18.9× | Yes | — |
| R20 | Report < 5,000 ms | 3.395 | 59.125 | 17.4× | Yes | — |
| R21 | Report < 5,000 ms | 40.109 | 397.648 | 9.9× | Yes | — |
| R22 | Partner < 250 ms | 25.520 | 28.459 | 1.1× | Yes | — |
| R23 | Real-time < 5 ms | 0.070 | 0.096 | 1.4× | Yes | — |
| R24 | Partner < 250 ms | 4.458 | 115.595 | 25.9× | Yes | — |
| R25 | Report < 5,000 ms | 58.664 | 477.990 | 8.1× | Yes | — |
| W01 | Real-time < 5 ms | 1.378 | 1.310 | 1.0× | Yes | — |
| W02 | Real-time < 5 ms | 0.611 | 0.588 | 1.0× | Yes | — |
| W03 | Real-time < 5 ms | 0.613 | 0.687 | 1.1× | Yes | — |
| W04 | Batch < 1,000 ms | 2.514 | 2.389 | 1.0× | Yes | — |
| W05 | Partner < 250 ms | 3.020 | 61.800 | 20.5× | Yes | — |

Slowest query on the large data: **R16 at 2.6 s** (target 5 s). Slowest real-time query: **R07 at 3.4 ms** (target 5 ms).

## 2. Growth analysis

The data grew about 20×, but the queries did not all grow by the same amount. They fall into 3 groups:

**a) Barely grew (about 1×): R02, R03, R04, R05, R06, R10, R13, R22, R23, W01, W02, W03, W04**
These use an index to jump straight to a small, fixed number of rows (one customer, one booking reference, one route on one day, the 30 coupons, the delayed flights). An index lookup costs about log(n), so 20× more rows adds only one more level to the B-tree.
- The `flights` table did not grow (13,848 rows in both datasets), so R02, R10 and W04 read the same rows as before.
- R22 (page 4,001) always reads exactly 100,025 rows through `idx_bookings_booked_at`, whatever the table size, so it stays at about 28 ms. With much bigger offsets, keyset paging would be needed: the app remembers the `booked_at` of the last row it showed and asks for `WHERE booked_at < :last_seen ORDER BY booked_at DESC LIMIT 25`.

**b) Grew less than 20× (about 5–15×): R01, R07, R08, R09, R11, R14, R15, R16, R18, R21, R25**
- R01, R07, R08: one flight now has about 20× more bookings (the number of flights stayed the same), but the work is still index lookups, so the growth is smaller.
- R09, R15, R21, R25 read a big share of a table. On the large tables PostgreSQL switches to **parallel workers** (`Gather`, 2 workers), which it did not use on the 145,000-row seed tables. That cuts the growth to about 8–10×.
- R14 and R16 read every booking and already ran in parallel on the seed data. They grew 11–13×, less than 20×, because part of their work is on tables that did not grow 20× (`flights`, `airlines`) and on fixed per-query costs.

**c) Grew about 20× (15–26×): R12, R17, R19, R20, R24, W05**
These read a fixed *share* of the data (a whole year, a whole month, or every passenger on June flights). 20× more data means 20× more rows to read, so they grow in step with it. W05 updates every guest checking in on 1 July, and there are 20× more of them.

**Grew more than 20×: none.** No query got worse than the data growth, because none of them sorts or joins in a way that grows faster than the table (the R19 correlated subquery, which would have, was already rewritten in CP3).

## 3. What broke at scale and how we fixed it: R03

On a first run of the large data (our Mac, `05_indexes.sql` from CP3), **R03 (hotel search) took 8.1 ms, over its 5 ms target**. It was 0.8 ms on the seed data.

**Why (from the plan):**
```
Limit  (rows=14) (actual rows=20)
  ->  Sort  Sort Key: user_rating DESC NULLS LAST   Sort Method: top-N heapsort
        ->  Bitmap Heap Scan on hotels  (rows=14) (actual rows=1920)
              Recheck Cond: city_name = 'Goa' AND star_rating >= 4
              Filter: (amenities ->> 'pool') = 'true'     Rows Removed by Filter: 820
              ->  Bitmap Index Scan on idx_hotels_city_stars  (actual rows=2740)
```
The planner **guessed 14 rows, but 1,920 hotels matched**. PostgreSQL keeps no statistics for a value inside a JSON column, so it uses a fixed guess for `amenities ->> 'pool' = 'true'`. Believing only 14 rows would come back, it fetched all 2,740 Goa 4★+ hotels, threw away 820 without a pool, sorted the other 1,920 and kept 20. With 3,000 hotels in the seed data this was cheap, but with 60,000 hotels the waste became visible.

**Fix (added to `sql/05_indexes.sql`):**
```sql
CREATE INDEX idx_hotels_city_rating ON hotels (city_name, user_rating DESC NULLS LAST);
CREATE STATISTICS st_hotels_pool ON ((amenities ->> 'pool')) FROM hotels;
```
The index returns Goa hotels already ordered by rating. The statistics give the planner the real share of hotels with a pool, so it now expects many matches and picks the index.

**After:**
```
Limit  (actual rows=20)
  ->  Index Scan using idx_hotels_city_rating on hotels  (actual rows=20)
        Index Cond: city_name = 'Goa'
        Filter: star_rating >= 4 AND (amenities ->> 'pool') = 'true'   Rows Removed by Filter: 63
```
It reads 83 rows and stops, with no sort. **R03: 8.1 ms → 0.33 ms.**

**Lesson:** an index alone is not enough at scale. The planner also needs correct statistics, especially for JSON and expression filters.

## 4. Storage

| | Seed data | Large data | Growth |
|---|---:|---:|---:|
| Tables (`mmt` schema) | 41 MB | 776 MB | 19× |
| Indexes | 37 MB | 748 MB | 20× |
| Whole database | 122 MB* | 1,532 MB | — |

\* The seed database also holds the CP4 `bookings_partitioned` copy.

The indexes are now almost as big as the tables (748 MB vs 776 MB), so every INSERT into `bookings` has to update 7 indexes. Largest tables on the large data:

| Table | Table size | Index size |
|---|---:|---:|
| bookings | 298 MB | 292 MB |
| passengers | 184 MB | 85 MB |
| customers | 82 MB | 154 MB |
| hotel_bookings | 68 MB | 104 MB |
| flight_bookings | 92 MB | 73 MB |

`customers` has more index than table because it has 4 indexes, 3 of them on text columns (`email` UNIQUE, `phone` UNIQUE, `lower(email)`, plus the primary key).

## 5. Partitioning, sharding, replicas and maintenance

### Partitioning (`sql/08_partitioning.sql`, tested on the large data)
`bookings_partitioned` is split by `booked_at` into quarters. The large data fills 6 of them with about 480,000 rows each (2025 Q1 – 2026 Q2).

| Test on 2.9 M bookings | Plain `bookings` | Partitioned | Partitions read |
|---|---:|---:|---|
| June 2026 total | 22.0 ms | 21.4 ms | only `bookings_2026_q2` |
| 2026 revenue by month (like R12) | 467 ms | 514 ms | 2026 Q1–Q3 + default (2 with data) |

**Pruning works** (the June query reads one partition of eight), but at 2.9 million rows it gives **no speed gain**, because `idx_bookings_booked_at` already lets PostgreSQL jump to the right dates. What partitioning does help with:
- **Archiving:** removing a whole quarter is `DROP TABLE bookings_2025_q1` (instant) instead of a `DELETE` of 480,000 rows.
- **Maintenance:** VACUUM, ANALYZE and REINDEX run per partition, and each partition's index is about 8× smaller.
- **Cost:** the primary key must include `booked_at`, so `booking_id` alone is no longer enforced unique, and the tables that reference `bookings(booking_id)` would need to change.

**Decision:** keep `bookings` unpartitioned for now. Switch to partitions when old data must be archived, or when the table reaches roughly 50–100 million rows.

### Read replicas
The 10 report queries (R09, R12, R14–R17, R19–R21, R25) take 60 ms – 2.6 s, while customer queries take under 5 ms. Running both on one server means a report can slow down checkout. Send the reports and partner tools to a **streaming read replica**, and keep the primary for real-time reads and all writes (W01–W05). The reports can be a few seconds behind without any problem.

### Sharding
It's not needed at 1.5 GB, since one server handles it easily. If it were needed, shard by **`customer_id`**: a customer's bookings, flight bookings, passengers and hotel bookings would all live on the same shard, so R05 ("My Trips"), R23 (sign-in) and W01–W03 stay on one shard. Small shared tables (flights, hotels, airports, airlines, coupons) would be copied to every shard. Reports that cover all customers would run on a separate analytics copy, not across shards.

### Queries to watch as data keeps growing
- **R14 and R16** read every booking (1.1 s and 2.6 s now, growing about linearly). At about 40× the seed data, R16 would pass 5 s. Fix then: a **materialized view** refreshed every night (`REFRESH MATERIALIZED VIEW CONCURRENTLY`), so the report reads a few hundred pre-summed rows.
- **R07** is 3.4 ms (max 4.6 ms) against 5 ms. If flights get much fuller, add `INCLUDE` columns to the passenger lookup for an index-only scan.

### Maintenance
- Run `ANALYZE` after every bulk load. The R03 problem showed that wrong estimates break plans.
- Keep `CREATE STATISTICS` on JSON and expression filters (`st_hotels_pool`).
- Leave autovacuum on, and watch for table bloat on `bookings` (W02 and W03 update it all the time).
- Use `pg_stat_statements` to catch new slow queries, and check index usage (`pg_stat_user_indexes.idx_scan = 0` means an unused index that only slows writes).

## 6. Conclusion

With the CP3 indexes and rewrites, the database handled 20× more data with **all 30 queries within target**. Only one fix was needed (R03, a wrong planner estimate on a JSON filter). Index lookups stayed flat, and queries that read a share of the data grew about 20× or less, thanks to parallel workers. Nothing grew faster than the data. The next limits will be the full-table reports R14 and R16 (fix: materialized views), and separating reports from customer traffic (fix: a read replica). Partitioning is ready in `sql/08_partitioning.sql` for when archiving is needed.
