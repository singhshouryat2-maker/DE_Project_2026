-- Load the seed data. Run from the repository root (where seed_data/ is):
--   psql -d makemytrip -f sql/02_load_data.sql
-- Parents are loaded before children so every foreign key is satisfied.

SET search_path TO mmt;

\copy airports        FROM 'seed_data/airports.csv'        WITH (FORMAT csv, HEADER true)
\copy airlines        FROM 'seed_data/airlines.csv'        WITH (FORMAT csv, HEADER true)
\copy flights         FROM 'seed_data/flights.csv'         WITH (FORMAT csv, HEADER true)
\copy hotels          FROM 'seed_data/hotels.csv'          WITH (FORMAT csv, HEADER true)
\copy room_types      FROM 'seed_data/room_types.csv'      WITH (FORMAT csv, HEADER true)
\copy customers       FROM 'seed_data/customers.csv'       WITH (FORMAT csv, HEADER true)
\copy coupons         FROM 'seed_data/coupons.csv'         WITH (FORMAT csv, HEADER true)
\copy bookings        FROM 'seed_data/bookings.csv'        WITH (FORMAT csv, HEADER true)
\copy flight_bookings FROM 'seed_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy passengers      FROM 'seed_data/passengers.csv'      WITH (FORMAT csv, HEADER true)
\copy hotel_bookings  FROM 'seed_data/hotel_bookings.csv'  WITH (FORMAT csv, HEADER true)
\copy hotel_reviews   FROM 'seed_data/hotel_reviews.csv'   WITH (FORMAT csv, HEADER true)

ANALYZE;

-- Row counts (must match the README)
SELECT 'airports' AS table_name, count(*) AS row_count FROM airports
UNION ALL SELECT 'airlines', count(*) FROM airlines
UNION ALL SELECT 'flights', count(*) FROM flights
UNION ALL SELECT 'hotels', count(*) FROM hotels
UNION ALL SELECT 'room_types', count(*) FROM room_types
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'coupons', count(*) FROM coupons
UNION ALL SELECT 'bookings', count(*) FROM bookings
UNION ALL SELECT 'flight_bookings', count(*) FROM flight_bookings
UNION ALL SELECT 'passengers', count(*) FROM passengers
UNION ALL SELECT 'hotel_bookings', count(*) FROM hotel_bookings
UNION ALL SELECT 'hotel_reviews', count(*) FROM hotel_reviews;

-- Integrity checks (each one should return 0)

-- 1. Every flight booking has exactly as many passenger rows as its passengers count
SELECT count(*) AS check1_passenger_count_mismatch
FROM flight_bookings fb
LEFT JOIN (SELECT booking_id, count(*) AS n FROM passengers GROUP BY booking_id) p USING (booking_id)
WHERE fb.passengers <> coalesce(p.n, 0);

-- 2. No flight was booked after it departed
SELECT count(*) AS check2_booked_after_departure
FROM flight_bookings fb
JOIN bookings b USING (booking_id)
JOIN flights f ON f.flight_id = fb.flight_id
WHERE b.booked_at > f.departure_at;

-- 3. A booking is either a flight booking or a hotel booking, never both, and matches booking_type
SELECT count(*) AS check3_wrong_subtype
FROM bookings b
LEFT JOIN flight_bookings fb USING (booking_id)
LEFT JOIN hotel_bookings hb USING (booking_id)
WHERE (b.booking_type = 'FLIGHT' AND (fb.booking_id IS NULL OR hb.booking_id IS NOT NULL))
   OR (b.booking_type = 'HOTEL'  AND (hb.booking_id IS NULL OR fb.booking_id IS NOT NULL));

-- 4. fare_paid = total_amount + discount for every flight booking
SELECT count(*) AS check4_fare_mismatch
FROM flight_bookings fb
JOIN bookings b USING (booking_id)
WHERE fb.fare_paid <> b.total_amount + b.discount;

-- 5. A coupon is only used on the booking type it applies to, inside its validity dates
SELECT count(*) AS check5_bad_coupon_use
FROM bookings b
JOIN coupons c USING (coupon_code)
WHERE (c.applies_to <> 'ALL' AND c.applies_to <> b.booking_type)
   OR b.booked_at::date NOT BETWEEN c.valid_from AND c.valid_to
   OR b.discount > c.max_discount;

-- 6. Reviews only exist for COMPLETED stays and are written after check-out
SELECT count(*) AS check6_bad_review
FROM hotel_reviews r
JOIN hotel_bookings hb USING (booking_id)
JOIN bookings b USING (booking_id)
WHERE b.status <> 'COMPLETED' OR r.created_at::date < hb.check_out;

-- 7. A room number is given only to COMPLETED stays
SELECT count(*) AS check7_room_number_not_completed
FROM hotel_bookings hb
JOIN bookings b USING (booking_id)
WHERE hb.room_number IS NOT NULL AND b.status <> 'COMPLETED';
