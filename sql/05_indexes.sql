-- MakeMyTrip DBMS Project: indexes (Phase 4)
-- Run after 01_schema.sql and 02_load_data.sql:  psql -d makemytrip -f sql/05_indexes.sql
-- Each index says which queries it serves and why this type and column order.

SET search_path TO mmt;

-- ---------------------------------------------------------------
-- flights
-- ---------------------------------------------------------------

-- R01, R02: search one route on one day / one month.
-- Composite B-tree: the two equality columns (origin, destination) first, then the range column (departure_at).
-- Needs the sargable date range from 06_optimized_queries.sql; DATE(departure_at) could not use it.
CREATE INDEX idx_flights_route_departure ON flights (origin, destination, departure_at);

-- R08, R19, R21, W04: filters on a departure_at range (a month, or "before 1 July").
-- Single-column B-tree because the range is the only filter.
CREATE INDEX idx_flights_departure ON flights (departure_at);

-- R10: the status board only wants DELAYED flights, ordered by departure.
-- Partial index: holds only the few DELAYED rows, so it is tiny and already in the right order.
CREATE INDEX idx_flights_delayed ON flights (departure_at) WHERE status = 'DELAYED';

-- ---------------------------------------------------------------
-- flight_bookings
-- ---------------------------------------------------------------

-- R01, R07, R08, R19: find the bookings of one flight (foreign key, had no index).
-- INCLUDE (passengers) makes it covering: seat counts are summed without visiting the table.
CREATE INDEX idx_fb_flight ON flight_bookings (flight_id) INCLUDE (passengers);

-- ---------------------------------------------------------------
-- bookings
-- ---------------------------------------------------------------

-- R05: "My Trips" for one customer with one status.
-- Composite: customer_id (equality, very selective) first, then status (equality).
CREATE INDEX idx_bookings_customer_status ON bookings (customer_id, status);

-- R09, R12, R17, R20, R22, R25: every report filters or sorts on booked_at.
-- Single-column B-tree; R22 reads it backwards for ORDER BY booked_at DESC instead of sorting the table.
CREATE INDEX idx_bookings_booked_at ON bookings (booked_at);

-- R11: pending payments ordered by booked_at. Only 97 of 144,792 rows are PENDING_PAYMENT.
-- Partial index: tiny, and it costs nothing for the other 99.9% of rows.
CREATE INDEX idx_bookings_pending_booked ON bookings (booked_at) WHERE status = 'PENDING_PAYMENT';

-- W02: min(booking_id) of the pending bookings.
-- Partial index on booking_id: the minimum is the first entry, no walk through the primary key.
CREATE INDEX idx_bookings_pending_id ON bookings (booking_id) WHERE status = 'PENDING_PAYMENT';

-- R13: NOT EXISTS checks "is this coupon used anywhere".
-- Partial index on coupon_code: only the ~17,600 rows that have a coupon, so it stays small.
CREATE INDEX idx_bookings_coupon ON bookings (coupon_code) WHERE coupon_code IS NOT NULL;

-- ---------------------------------------------------------------
-- hotel_bookings
-- ---------------------------------------------------------------

-- R04: bookings of one room type that overlap a date range.
-- Composite: room_type_id (equality) first, then check_in (range); INCLUDE the other columns the query reads.
CREATE INDEX idx_hb_room_type_checkin ON hotel_bookings (room_type_id, check_in) INCLUDE (check_out, rooms);

-- W05: guests checking in on one day.
CREATE INDEX idx_hb_checkin ON hotel_bookings (check_in);

-- R15: stays that overlap June 2026. "check_out > 1 June" is the selective side
-- (only recent stays), so the index is on check_out.
CREATE INDEX idx_hb_checkout ON hotel_bookings (check_out);

-- ---------------------------------------------------------------
-- customers
-- ---------------------------------------------------------------

-- R23: sign-in uses lower(email). The UNIQUE index on email cannot serve lower(email),
-- so this is an expression index on exactly that expression.
CREATE INDEX idx_customers_lower_email ON customers (lower(email));

-- ---------------------------------------------------------------
-- hotels and hotel_reviews
-- ---------------------------------------------------------------

-- R03, R18, R24: everything is "hotels in Goa". city_name (equality) first, then star_rating (range in R03).
CREATE INDEX idx_hotels_city_stars ON hotels (city_name, star_rating);

-- R18, R24: reviews of a set of hotels (foreign key, had no index).
CREATE INDEX idx_reviews_hotel ON hotel_reviews (hotel_id);

-- ---------------------------------------------------------------
-- passengers
-- ---------------------------------------------------------------

-- R21: senior citizens (age >= 60) only.
-- Partial index on booking_id: only the senior passengers, ready to join to flight_bookings.
CREATE INDEX idx_pax_senior ON passengers (booking_id) WHERE age >= 60;

-- Fresh statistics so the planner knows about the new indexes and data distribution.
ANALYZE;
