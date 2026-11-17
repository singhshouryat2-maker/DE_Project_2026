-- MakeMyTrip DBMS Project: partitioning design for bookings (Phase 5)
-- Run after 01, 02 and 05:  psql -d makemytrip -f sql/08_partitioning.sql
-- Builds a RANGE-partitioned copy of bookings (by booked_at, one partition per quarter),
-- copies the data in, and shows partition pruning with EXPLAIN.
-- The original mmt.bookings table is NOT changed.

SET search_path TO mmt;

DROP TABLE IF EXISTS bookings_partitioned;

-- Why RANGE on booked_at:
--   * almost every report filters on a booked_at range (R09, R12, R17, R20, R25), so whole
--     partitions are skipped (partition pruning);
--   * old quarters stop changing, so they can be archived or detached cheaply;
--   * new data always goes into the newest partition.
--
-- Primary-key rule for partitioned tables: a PRIMARY KEY or UNIQUE constraint must include
-- the partition key. So the key becomes (booking_id, booked_at), and booking_ref can only be
-- unique per partition, (booking_ref, booked_at). Global uniqueness of booking_id and
-- booking_ref must then come from the application (or a small lookup table).
CREATE TABLE bookings_partitioned (
    booking_id      INTEGER       NOT NULL,
    booking_ref     CHAR(8)       NOT NULL,
    customer_id     INTEGER       NOT NULL REFERENCES customers (customer_id) ON DELETE RESTRICT,
    booking_type    VARCHAR(6)    NOT NULL,
    booked_at       TIMESTAMPTZ   NOT NULL,
    total_amount    NUMERIC(10,2) NOT NULL,
    coupon_code     VARCHAR(12)   REFERENCES coupons (coupon_code) ON DELETE RESTRICT,
    discount        NUMERIC(10,2) NOT NULL DEFAULT 0,
    payment_method  VARCHAR(10)   NOT NULL,
    status          VARCHAR(15)   NOT NULL,
    cancelled_at    TIMESTAMPTZ,
    refund_amount   NUMERIC(10,2),
    PRIMARY KEY (booking_id, booked_at),
    UNIQUE (booking_ref, booked_at),
    CONSTRAINT chk_bp_type     CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    CONSTRAINT chk_bp_status   CHECK (status IN ('PENDING_PAYMENT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT chk_bp_amount   CHECK (total_amount > 0),
    CONSTRAINT chk_bp_discount CHECK (discount >= 0 AND (coupon_code IS NOT NULL) = (discount > 0)),
    CONSTRAINT chk_bp_cancel   CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL))
) PARTITION BY RANGE (booked_at);

-- One partition per quarter (IST boundaries)
CREATE TABLE bookings_2025_q1 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
CREATE TABLE bookings_2025_q2 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');
CREATE TABLE bookings_2025_q3 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');
CREATE TABLE bookings_2025_q4 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');
CREATE TABLE bookings_2026_q1 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');
CREATE TABLE bookings_2026_q2 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');
CREATE TABLE bookings_2026_q3 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');
-- Catches anything outside the ranges above, so an insert never fails
CREATE TABLE bookings_default PARTITION OF bookings_partitioned DEFAULT;

-- Indexes created on the parent are created on every partition automatically
CREATE INDEX idx_bp_customer_status ON bookings_partitioned (customer_id, status);
CREATE INDEX idx_bp_booked_at       ON bookings_partitioned (booked_at);

-- Copy the data in
INSERT INTO bookings_partitioned SELECT * FROM bookings;
ANALYZE bookings_partitioned;

-- Rows per partition
SELECT tableoid::regclass AS partition, count(*) AS row_count
FROM bookings_partitioned
GROUP BY 1
ORDER BY 1;

-- Partition pruning: a June 2026 report only touches bookings_2026_q2
EXPLAIN (COSTS OFF)
SELECT booked_at::date AS day, count(*)
FROM bookings_partitioned
WHERE booked_at >= '2026-06-01 00:00:00+05:30' AND booked_at < '2026-07-01 00:00:00+05:30'
GROUP BY 1;
