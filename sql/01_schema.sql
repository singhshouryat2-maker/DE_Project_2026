-- MakeMyTrip Travel Booking Database: schema
-- Team T0131. Run on an empty database:  psql -d makemytrip -f sql/01_schema.sql
-- Only constraints here (PK, FK, UNIQUE, NOT NULL, CHECK). No extra indexes.

DROP SCHEMA IF EXISTS mmt CASCADE;
CREATE SCHEMA mmt;
SET search_path TO mmt;

-- ---------------------------------------------------------------
-- Reference tables
-- ---------------------------------------------------------------

CREATE TABLE airports (
    iata_code     CHAR(3)      PRIMARY KEY,
    airport_name  VARCHAR(100) NOT NULL,
    city_name     VARCHAR(50)  NOT NULL,
    country_code  CHAR(2)      NOT NULL,
    CONSTRAINT chk_airport_iata    CHECK (iata_code ~ '^[A-Z]{3}$'),
    CONSTRAINT chk_airport_country CHECK (country_code ~ '^[A-Z]{2}$')
);

CREATE TABLE airlines (
    airline_code  CHAR(2)      PRIMARY KEY,
    airline_name  VARCHAR(50)  NOT NULL UNIQUE,
    CONSTRAINT chk_airline_code CHECK (airline_code ~ '^[A-Z0-9]{2}$')
);

CREATE TABLE flights (
    flight_id     INTEGER       PRIMARY KEY,
    airline_code  CHAR(2)       NOT NULL REFERENCES airlines (airline_code) ON DELETE RESTRICT,
    flight_no     VARCHAR(8)    NOT NULL,
    origin        CHAR(3)       NOT NULL REFERENCES airports (iata_code) ON DELETE RESTRICT,
    destination   CHAR(3)       NOT NULL REFERENCES airports (iata_code) ON DELETE RESTRICT,
    departure_at  TIMESTAMPTZ   NOT NULL,
    arrival_at    TIMESTAMPTZ   NOT NULL,
    aircraft      VARCHAR(10)   NOT NULL,
    total_seats   SMALLINT      NOT NULL,
    base_fare     NUMERIC(10,2) NOT NULL,
    status        VARCHAR(10)   NOT NULL,
    CONSTRAINT uq_flight_instance      UNIQUE (flight_no, departure_at),
    CONSTRAINT chk_flight_no_format    CHECK (flight_no ~ '^[A-Z0-9]{2}-[0-9]{1,4}$'),
    CONSTRAINT chk_flight_no_airline   CHECK (left(flight_no, 2) = airline_code),
    CONSTRAINT chk_flight_route        CHECK (origin <> destination),
    CONSTRAINT chk_flight_times        CHECK (arrival_at > departure_at),
    CONSTRAINT chk_flight_seats        CHECK (total_seats > 0),
    CONSTRAINT chk_flight_fare         CHECK (base_fare > 0),
    CONSTRAINT chk_flight_status       CHECK (status IN ('SCHEDULED', 'DELAYED', 'DEPARTED', 'LANDED', 'CANCELLED'))
);

CREATE TABLE hotels (
    hotel_id        INTEGER      PRIMARY KEY,
    hotel_name      VARCHAR(100) NOT NULL UNIQUE,
    city_name       VARCHAR(50)  NOT NULL,
    star_rating     SMALLINT     NOT NULL,
    user_rating     NUMERIC(2,1),                  -- NULL = not rated yet
    amenities       JSONB        NOT NULL,
    check_in_time   TIME         NOT NULL,
    check_out_time  TIME         NOT NULL,
    CONSTRAINT chk_hotel_stars       CHECK (star_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_hotel_user_rating CHECK (user_rating BETWEEN 0 AND 5),
    CONSTRAINT chk_hotel_amenities   CHECK (jsonb_typeof(amenities) = 'object')
);

CREATE TABLE room_types (
    room_type_id     INTEGER       PRIMARY KEY,
    hotel_id         INTEGER       NOT NULL REFERENCES hotels (hotel_id) ON DELETE CASCADE,
    room_name        VARCHAR(30)   NOT NULL,
    max_guests       SMALLINT      NOT NULL,
    price_per_night  NUMERIC(10,2) NOT NULL,
    total_rooms      SMALLINT      NOT NULL,
    CONSTRAINT uq_room_type_name     UNIQUE (hotel_id, room_name),
    CONSTRAINT uq_room_type_hotel    UNIQUE (room_type_id, hotel_id),  -- target of the composite FK below
    CONSTRAINT chk_room_name         CHECK (room_name IN ('Standard Room', 'Deluxe Room', 'Suite')),
    CONSTRAINT chk_room_max_guests   CHECK (max_guests BETWEEN 1 AND 10),
    CONSTRAINT chk_room_price        CHECK (price_per_night > 0),
    CONSTRAINT chk_room_total        CHECK (total_rooms > 0)
);

CREATE TABLE customers (
    customer_id   INTEGER      PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,
    phone         CHAR(10)     NOT NULL UNIQUE,
    loyalty_tier  VARCHAR(8)   NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL,
    CONSTRAINT chk_customer_email CHECK (email ~ '^[^@\s]+@[^@\s]+\.[A-Za-z]+$'),
    CONSTRAINT chk_customer_phone CHECK (phone ~ '^[6-9][0-9]{9}$'),
    CONSTRAINT chk_customer_tier  CHECK (loyalty_tier IN ('BLUE', 'SILVER', 'GOLD', 'PLATINUM'))
);

CREATE TABLE coupons (
    coupon_code   VARCHAR(12)   PRIMARY KEY,
    applies_to    VARCHAR(6)    NOT NULL,
    discount_pct  SMALLINT      NOT NULL,
    max_discount  NUMERIC(10,2) NOT NULL,
    valid_from    DATE          NOT NULL,
    valid_to      DATE          NOT NULL,
    CONSTRAINT chk_coupon_code    CHECK (coupon_code ~ '^[A-Z0-9]+$'),
    CONSTRAINT chk_coupon_applies CHECK (applies_to IN ('FLIGHT', 'HOTEL', 'ALL')),
    CONSTRAINT chk_coupon_pct     CHECK (discount_pct BETWEEN 1 AND 100),
    CONSTRAINT chk_coupon_max     CHECK (max_discount > 0),
    CONSTRAINT chk_coupon_dates   CHECK (valid_to >= valid_from)
);

-- ---------------------------------------------------------------
-- Bookings (supertype) and its two subtypes
-- ---------------------------------------------------------------

CREATE TABLE bookings (
    booking_id      INTEGER       PRIMARY KEY,
    booking_ref     CHAR(8)       NOT NULL UNIQUE,
    customer_id     INTEGER       NOT NULL REFERENCES customers (customer_id) ON DELETE RESTRICT,
    booking_type    VARCHAR(6)    NOT NULL,
    booked_at       TIMESTAMPTZ   NOT NULL,
    total_amount    NUMERIC(10,2) NOT NULL,           -- amount paid, after discount
    coupon_code     VARCHAR(12)   REFERENCES coupons (coupon_code) ON DELETE RESTRICT,
    discount        NUMERIC(10,2) NOT NULL DEFAULT 0,
    payment_method  VARCHAR(10)   NOT NULL,
    status          VARCHAR(15)   NOT NULL,
    cancelled_at    TIMESTAMPTZ,                      -- only when CANCELLED
    refund_amount   NUMERIC(10,2),                    -- only when CANCELLED
    CONSTRAINT chk_booking_ref       CHECK (booking_ref ~ '^MM[0-9A-Z]{6}$'),
    CONSTRAINT chk_booking_type      CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    CONSTRAINT chk_booking_amount    CHECK (total_amount > 0),
    CONSTRAINT chk_booking_payment   CHECK (payment_method IN ('CARD', 'UPI', 'NETBANKING', 'WALLET', 'EMI')),
    CONSTRAINT chk_booking_status    CHECK (status IN ('PENDING_PAYMENT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT chk_booking_discount  CHECK (discount >= 0 AND (coupon_code IS NOT NULL) = (discount > 0)),
    CONSTRAINT chk_booking_cancel    CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL)),
    CONSTRAINT chk_booking_refund    CHECK ((refund_amount IS NULL) = (cancelled_at IS NULL)
                                            AND (refund_amount IS NULL OR refund_amount BETWEEN 0 AND total_amount)),
    CONSTRAINT chk_booking_cancel_after CHECK (cancelled_at IS NULL OR cancelled_at >= booked_at)
);

CREATE TABLE flight_bookings (
    booking_id  INTEGER       PRIMARY KEY REFERENCES bookings (booking_id) ON DELETE CASCADE,
    flight_id   INTEGER       NOT NULL REFERENCES flights (flight_id) ON DELETE RESTRICT,
    cabin       VARCHAR(8)    NOT NULL,
    passengers  SMALLINT      NOT NULL,
    fare_paid   NUMERIC(10,2) NOT NULL,               -- fare before discount
    CONSTRAINT chk_fb_cabin      CHECK (cabin IN ('ECONOMY', 'PREMIUM', 'BUSINESS')),
    CONSTRAINT chk_fb_passengers CHECK (passengers BETWEEN 1 AND 9),
    CONSTRAINT chk_fb_fare       CHECK (fare_paid > 0)
);

CREATE TABLE passengers (
    booking_id  INTEGER      NOT NULL REFERENCES flight_bookings (booking_id) ON DELETE CASCADE,
    seq_no      SMALLINT     NOT NULL,
    full_name   VARCHAR(100) NOT NULL,
    age         SMALLINT     NOT NULL,
    gender      CHAR(1)      NOT NULL,
    seat_no     VARCHAR(3),                            -- NULL until web check-in
    PRIMARY KEY (booking_id, seq_no),
    CONSTRAINT chk_pax_seq    CHECK (seq_no BETWEEN 1 AND 9),
    CONSTRAINT chk_pax_age    CHECK (age BETWEEN 0 AND 120),
    CONSTRAINT chk_pax_gender CHECK (gender IN ('M', 'F', 'X')),
    CONSTRAINT chk_pax_seat   CHECK (seat_no ~ '^[1-9][0-9]?[A-F]$')
);

CREATE TABLE hotel_bookings (
    booking_id    INTEGER    PRIMARY KEY REFERENCES bookings (booking_id) ON DELETE CASCADE,
    hotel_id      INTEGER    NOT NULL,
    room_type_id  INTEGER    NOT NULL,
    check_in      DATE       NOT NULL,
    check_out     DATE       NOT NULL,
    rooms         SMALLINT   NOT NULL,
    guests        SMALLINT   NOT NULL,
    room_number   VARCHAR(4),                          -- NULL until the guest checks in
    -- the room type must belong to the same hotel
    CONSTRAINT fk_hb_room_type   FOREIGN KEY (room_type_id, hotel_id)
                                 REFERENCES room_types (room_type_id, hotel_id) ON DELETE RESTRICT,
    CONSTRAINT uq_hb_hotel       UNIQUE (booking_id, hotel_id),   -- target of the review FK below
    CONSTRAINT chk_hb_dates      CHECK (check_out > check_in),
    CONSTRAINT chk_hb_rooms      CHECK (rooms > 0),
    CONSTRAINT chk_hb_guests     CHECK (guests > 0),
    CONSTRAINT chk_hb_room_no    CHECK (room_number ~ '^[0-9]{3,4}$')
);

CREATE TABLE hotel_reviews (
    review_id    INTEGER      PRIMARY KEY,
    booking_id   INTEGER      NOT NULL UNIQUE,
    hotel_id     INTEGER      NOT NULL,
    rating       SMALLINT     NOT NULL,
    title        VARCHAR(100) NOT NULL,
    review_text  TEXT,                                 -- optional comment
    created_at   TIMESTAMPTZ  NOT NULL,
    -- the review must be for the hotel that was actually booked
    CONSTRAINT fk_review_booking FOREIGN KEY (booking_id, hotel_id)
                                 REFERENCES hotel_bookings (booking_id, hotel_id) ON DELETE CASCADE,
    CONSTRAINT chk_review_rating CHECK (rating BETWEEN 1 AND 5)
);
