# 02 · Schema design

The schema was worked out from the 12 CSV exports in `seed_data/`. All tables live in schema `mmt`.
Files: `sql/01_schema.sql` (tables and constraints) and `sql/02_load_data.sql` (load, row counts, integrity checks).
Tested on PostgreSQL 15/16: both scripts run top to bottom with no errors, and all 30 workload queries run on this schema.

## 1. How we chose data types

| Kind of data | Type used | Why |
|--------------|-----------|-----|
| Money (`base_fare`, `total_amount`, `discount`, …) | `NUMERIC(10,2)` | Exact to the paisa. `FLOAT` would give rounding errors. |
| Times with an offset (`+05:30`) | `TIMESTAMPTZ` | Keeps the real moment in time; comparisons across time zones stay correct. |
| Dates (`check_in`, `valid_from`) | `DATE` | No time part in the data. |
| Hotel check-in/out time | `TIME` | Only a clock time (14:00, 11:00). |
| Small whole numbers (seats, rooms, age, rating) | `SMALLINT` | Values are small; saves space. |
| IDs | `INTEGER` | Up to ~2.1 billion, enough even at 20× growth. |
| Fixed-length codes (IATA, airline, phone, booking ref) | `CHAR(n)` | Always the same length. |
| Status / category values | `VARCHAR` + `CHECK … IN (…)` | Only the listed values are allowed. |
| `amenities` | `JSONB` | It is a JSON object of yes/no flags (`{"pool": true, …}`); JSONB lets queries read `amenities ->> 'pool'`. |

## 2. Data dictionary

### airports (16 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| iata_code | CHAR(3) | PK, CHECK `^[A-Z]{3}$` | A 3-letter IATA code is unique worldwide, so it is a good natural key. |
| airport_name | VARCHAR(100) | NOT NULL | Every airport has a name. |
| city_name | VARCHAR(50) | NOT NULL | Used for display and search. |
| country_code | CHAR(2) | NOT NULL, CHECK `^[A-Z]{2}$` | ISO country code (IN, AE, SG). |

### airlines (5 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| airline_code | CHAR(2) | PK, CHECK `^[A-Z0-9]{2}$` | IATA airline code; can contain a digit (6E). |
| airline_name | VARCHAR(50) | NOT NULL, UNIQUE | Two airlines cannot share a name. |

### flights (13,848 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| flight_id | INTEGER | PK | One row = one dated flight. |
| airline_code | CHAR(2) | NOT NULL, FK → airlines ON DELETE RESTRICT | Cannot delete an airline that still has flights. |
| flight_no | VARCHAR(8) | NOT NULL, CHECK format `XX-123`, CHECK prefix = airline_code | `6E-137` must belong to airline 6E. |
| origin, destination | CHAR(3) | NOT NULL, FK → airports RESTRICT, CHECK origin ≠ destination | A flight cannot go to the airport it left from. |
| departure_at, arrival_at | TIMESTAMPTZ | NOT NULL, CHECK arrival > departure | Time order. |
| aircraft | VARCHAR(10) | NOT NULL | A320neo, A321neo, B737-8. |
| total_seats | SMALLINT | NOT NULL, CHECK > 0 | Capacity. |
| base_fare | NUMERIC(10,2) | NOT NULL, CHECK > 0 | Price. |
| status | VARCHAR(10) | NOT NULL, CHECK IN (SCHEDULED, DELAYED, DEPARTED, LANDED, CANCELLED) | Only valid states. |
| (flight_no, departure_at) | | UNIQUE | The same flight number cannot depart twice at the same time (candidate key). |

### hotels (3,000 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| hotel_id | INTEGER | PK | |
| hotel_name | VARCHAR(100) | NOT NULL, UNIQUE | Names include the city and a number, so they are unique. |
| city_name | VARCHAR(50) | NOT NULL | |
| star_rating | SMALLINT | NOT NULL, CHECK 1–5 | Official stars. |
| user_rating | NUMERIC(2,1) | NULL allowed, CHECK 0–5 | Empty for 134 hotels that have not been rated yet. |
| amenities | JSONB | NOT NULL, CHECK it is a JSON object | 7 yes/no flags. |
| check_in_time, check_out_time | TIME | NOT NULL | |

### room_types (9,000 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| room_type_id | INTEGER | PK | |
| hotel_id | INTEGER | NOT NULL, FK → hotels ON DELETE CASCADE | A room type cannot exist without its hotel. |
| room_name | VARCHAR(30) | NOT NULL, CHECK IN (Standard Room, Deluxe Room, Suite), UNIQUE (hotel_id, room_name) | One of each type per hotel. |
| max_guests | SMALLINT | NOT NULL, CHECK 1–10 | |
| price_per_night | NUMERIC(10,2) | NOT NULL, CHECK > 0 | |
| total_rooms | SMALLINT | NOT NULL, CHECK > 0 | |
| (room_type_id, hotel_id) | | UNIQUE | Lets `hotel_bookings` use a composite FK (see below). |

### customers (40,000 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| customer_id | INTEGER | PK | |
| full_name | VARCHAR(100) | NOT NULL | Names repeat (only 500 distinct), so not unique. |
| email | VARCHAR(100) | NOT NULL, UNIQUE, CHECK basic email format | Used for sign-in. |
| phone | CHAR(10) | NOT NULL, UNIQUE, CHECK `^[6-9][0-9]{9}$` | Indian mobile number. |
| loyalty_tier | VARCHAR(8) | NOT NULL, CHECK IN (BLUE, SILVER, GOLD, PLATINUM) | |
| created_at | TIMESTAMPTZ | NOT NULL | |

### coupons (30 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| coupon_code | VARCHAR(12) | PK, CHECK `^[A-Z0-9]+$` | The code itself is the key. |
| applies_to | VARCHAR(6) | NOT NULL, CHECK IN (FLIGHT, HOTEL, ALL) | |
| discount_pct | SMALLINT | NOT NULL, CHECK 1–100 | |
| max_discount | NUMERIC(10,2) | NOT NULL, CHECK > 0 | |
| valid_from, valid_to | DATE | NOT NULL, CHECK valid_to ≥ valid_from | |

### bookings (144,792 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| booking_id | INTEGER | PK | |
| booking_ref | CHAR(8) | NOT NULL, UNIQUE, CHECK `^MM[0-9A-Z]{6}$` | What the customer types to find a booking. Letters A–Z are allowed because the workload inserts `MMZZ0001`. |
| customer_id | INTEGER | NOT NULL, FK → customers ON DELETE RESTRICT | Bookings are financial records; a customer with bookings must not be deleted. |
| booking_type | VARCHAR(6) | NOT NULL, CHECK IN (FLIGHT, HOTEL) | Says which subtype table has the details. |
| booked_at | TIMESTAMPTZ | NOT NULL | |
| total_amount | NUMERIC(10,2) | NOT NULL, CHECK > 0 | Amount paid after discount. |
| coupon_code | VARCHAR(12) | NULL allowed, FK → coupons ON DELETE RESTRICT | Empty when no coupon was used (127,144 rows). RESTRICT, not SET NULL: setting it to NULL would leave a discount with no coupon. |
| discount | NUMERIC(10,2) | NOT NULL, CHECK ≥ 0 and (coupon given ⇔ discount > 0) | No discount without a coupon. |
| payment_method | VARCHAR(10) | NOT NULL, CHECK IN (CARD, UPI, NETBANKING, WALLET, EMI) | |
| status | VARCHAR(15) | NOT NULL, CHECK IN (PENDING_PAYMENT, CONFIRMED, COMPLETED, CANCELLED) | |
| cancelled_at | TIMESTAMPTZ | NULL allowed, CHECK (status = CANCELLED ⇔ cancelled_at given), CHECK cancelled_at ≥ booked_at | Filled only for the 11,494 cancelled bookings. |
| refund_amount | NUMERIC(10,2) | NULL allowed, CHECK (refund given ⇔ cancelled), CHECK 0 ≤ refund ≤ total_amount | Never refund more than was paid. |

### flight_bookings (84,899 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| booking_id | INTEGER | PK, FK → bookings ON DELETE CASCADE | 1:1 subtype of a booking, so it shares the booking's key. Deleting the booking deletes its details. |
| flight_id | INTEGER | NOT NULL, FK → flights ON DELETE RESTRICT | Cannot delete a flight that has bookings. |
| cabin | VARCHAR(8) | NOT NULL, CHECK IN (ECONOMY, PREMIUM, BUSINESS) | |
| passengers | SMALLINT | NOT NULL, CHECK 1–9 | |
| fare_paid | NUMERIC(10,2) | NOT NULL, CHECK > 0 | Fare before discount. |

### passengers (163,380 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| booking_id | INTEGER | PK part, FK → flight_bookings ON DELETE CASCADE | A passenger belongs to one flight booking. |
| seq_no | SMALLINT | PK part, CHECK 1–9 | Passenger 1, 2, 3 … inside the booking. There is no passenger_id, so the key is **(booking_id, seq_no)**. |
| full_name | VARCHAR(100) | NOT NULL | |
| age | SMALLINT | NOT NULL, CHECK 0–120 | |
| gender | CHAR(1) | NOT NULL, CHECK IN (M, F, X) | |
| seat_no | VARCHAR(3) | NULL allowed, CHECK `^[1-9][0-9]?[A-F]$` | Empty (21,612 rows) until the passenger does web check-in. Rows 1–30, seats A–F. |

### hotel_bookings (59,893 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| booking_id | INTEGER | PK, FK → bookings ON DELETE CASCADE | 1:1 subtype of a booking. |
| hotel_id, room_type_id | INTEGER | NOT NULL, composite FK (room_type_id, hotel_id) → room_types ON DELETE RESTRICT | The composite FK makes sure the room type really belongs to the booked hotel. |
| check_in, check_out | DATE | NOT NULL, CHECK check_out > check_in | At least one night. |
| rooms | SMALLINT | NOT NULL, CHECK > 0 | |
| guests | SMALLINT | NOT NULL, CHECK > 0 | |
| room_number | VARCHAR(4) | NULL allowed, CHECK 3–4 digits | Empty (6,815 rows) until the guest checks in; every COMPLETED stay has one. Text because query W05 assigns it as text. |
| (booking_id, hotel_id) | | UNIQUE | Target of the composite FK from hotel_reviews. |

### hotel_reviews (15,913 rows)
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| review_id | INTEGER | PK | |
| booking_id | INTEGER | NOT NULL, UNIQUE | At most one review per stay (1:0..1). |
| hotel_id | INTEGER | NOT NULL, composite FK (booking_id, hotel_id) → hotel_bookings ON DELETE CASCADE | The review must be for the hotel that was booked. |
| rating | SMALLINT | NOT NULL, CHECK 1–5 | |
| title | VARCHAR(100) | NOT NULL | Always filled. |
| review_text | TEXT | NULL allowed | Optional comment; empty in 4,812 reviews. |
| created_at | TIMESTAMPTZ | NOT NULL | |

**CHECK constraints in total:** 46 (more than the 12 required).

### Indexes that exist after Phase 2
Only the ones PostgreSQL creates for PRIMARY KEY and UNIQUE constraints (22 in total): every `*_pkey`, plus `airlines_airline_name_key`, `bookings_booking_ref_key`, `customers_email_key`, `customers_phone_key`, `hotels_hotel_name_key`, `hotel_reviews_booking_id_key`, `uq_flight_instance`, `uq_room_type_name`, `uq_room_type_hotel`, `uq_hb_hotel`. No other index was created.

## 3. ER diagram

![ER diagram](../diagrams/er_diagram.png)

Mermaid source: `diagrams/er_diagram.mmd`.

**Relationships and cardinality**
| Relationship | Cardinality |
|--------------|-------------|
| airline → flights | 1 : N |
| airport → flights (as origin, and as destination) | 1 : N, twice |
| hotel → room_types | 1 : N (each hotel has 3) |
| customer → bookings | 1 : N |
| coupon → bookings | 0..1 : N |
| booking → flight_booking / hotel_booking | 1 : 0..1 (exactly one of the two) |
| flight → flight_bookings | 1 : N |
| flight_booking → passengers | 1 : N (1–4 in the data) |
| room_type → hotel_bookings | 1 : N |
| hotel_booking → hotel_review | 1 : 0..1 |
| customers ↔ flights | M : N, resolved through bookings + flight_bookings |
| customers ↔ hotels | M : N, resolved through bookings + hotel_bookings |

## 4. Functional dependencies and normal form

| Table | Key | Functional dependencies | Normal form |
|-------|-----|------------------------|-------------|
| airports | iata_code | iata_code → airport_name, city_name, country_code | BCNF |
| airlines | airline_code | airline_code → airline_name; airline_name → airline_code | BCNF (both determinants are keys) |
| flights | flight_id | flight_id → all; (flight_no, departure_at) → all; flight_no → airline_code | 3NF, see note 1 |
| hotels | hotel_id | hotel_id → all; hotel_name → all | BCNF |
| room_types | room_type_id | room_type_id → all; (hotel_id, room_name) → all | BCNF |
| customers | customer_id | customer_id → all; email → all; phone → all | BCNF |
| coupons | coupon_code | coupon_code → all | BCNF |
| bookings | booking_id | booking_id → all; booking_ref → all | BCNF |
| flight_bookings | booking_id | booking_id → flight_id, cabin, passengers, fare_paid | BCNF |
| passengers | (booking_id, seq_no) | (booking_id, seq_no) → full_name, age, gender, seat_no | BCNF |
| hotel_bookings | booking_id | booking_id → all; room_type_id → hotel_id | 3NF, see note 2 |
| hotel_reviews | review_id | review_id → all; booking_id → all; booking_id → hotel_id | BCNF (booking_id is a key) |

**Note 1, `flights.airline_code`:** `flight_no → airline_code` (the first two letters of `6E-137` are `6E`). `flight_no` is not a key, so strictly this breaks BCNF. We keep `airline_code` because it is the foreign key to `airlines`, and the CHECK `left(flight_no,2) = airline_code` stops the two from ever disagreeing, so there is no update anomaly.

**Note 2, `hotel_bookings.hotel_id`:** `room_type_id → hotel_id`, so `hotel_id` is redundant. We keep it because the hotel queries (R04, R15) filter by hotel directly, and the composite FK `(room_type_id, hotel_id) → room_types` guarantees it is always the right hotel.

### Derived or redundant columns
| Column | Can be computed from | Keep it? |
|--------|---------------------|----------|
| `flight_bookings.fare_paid` | `bookings.total_amount + bookings.discount` (true for all 84,899 rows) | Yes: it records the fare at booking time; checked by integrity check 4. |
| `flight_bookings.passengers` | number of rows in `passengers` for that booking (true for all rows) | Yes: the queries count seats sold without joining 163k passenger rows; checked by integrity check 1. |
| `hotel_reviews.hotel_id` | the hotel of the booking | Yes: lets hotel pages find reviews without a join; the composite FK keeps it correct. |
| `hotels.user_rating` | not exactly the average of `hotel_reviews.rating` | Kept as given; it comes from outside this database. |

## 5. When are columns empty, and why

| Column | Empty rows | When it is empty |
|--------|-----------:|------------------|
| bookings.coupon_code | 127,144 | No coupon used (discount is then 0). |
| bookings.cancelled_at | 133,298 | Booking is not CANCELLED. |
| bookings.refund_amount | 133,298 | Booking is not CANCELLED. |
| passengers.seat_no | 21,612 | Passenger did not do web check-in (all CONFIRMED future flights, and some others who got a seat at the airport). |
| hotel_bookings.room_number | 6,815 | Guest has not checked in: every booking that is not COMPLETED. |
| hotels.user_rating | 134 | Hotel not rated yet. |
| hotel_reviews.review_text | 4,812 | Reviewer gave only a star rating and title. |

## 6. Load results

`sql/02_load_data.sql` loaded all 12 files with no errors.

| Table | Rows loaded | Expected |
|-------|------------:|---------:|
| airports | 16 | 16 |
| airlines | 5 | 5 |
| flights | 13,848 | 13,848 |
| hotels | 3,000 | 3,000 |
| room_types | 9,000 | 9,000 |
| customers | 40,000 | 40,000 |
| coupons | 30 | 30 |
| bookings | 144,792 | 144,792 |
| flight_bookings | 84,899 | 84,899 |
| passengers | 163,380 | 163,380 |
| hotel_bookings | 59,893 | 59,893 |
| hotel_reviews | 15,913 | 15,913 |

## 7. Integrity checks

Each check is in `sql/02_load_data.sql` and returns the number of bad rows.

| # | Check | Bad rows |
|---|-------|---------:|
| 1 | Every flight booking has exactly as many passenger rows as its `passengers` count | 0 |
| 2 | No flight was booked after it departed | 0 |
| 3 | Each booking is exactly one of flight / hotel, matching `booking_type` | 0 |
| 4 | `fare_paid = total_amount + discount` | 0 |
| 5 | Coupons used only on the right booking type, inside validity dates, not over `max_discount` | 0 |
| 6 | Reviews only for COMPLETED stays, written after check-out | 0 |
| 7 | Room numbers only on COMPLETED stays | 0 |

## 8. Data problems found

These are real problems in the data. None of them stopped the load, but we did **not** add constraints that the data breaks; we list them here instead.

1. **Same seat given twice.** 18,443 (flight, seat) pairs are used by more than one passenger on bookings that are not cancelled, so `UNIQUE (flight, seat_no)` cannot be added. Seat assignment needs fixing.
2. **More guests than the room allows.** 9,994 hotel bookings have `guests > max_guests × rooms`. Either extra beds are allowed or the booking screen does not check this.
3. **Stale flight status.** 10 flights that departed before 1 Jul 2026 still say SCHEDULED (4) or DELAYED (6). Query W04 is meant to fix exactly this.
4. **Stale pending payments.** 6 hotel bookings are still PENDING_PAYMENT although their check-in date has already passed.
5. **Unrated hotels with reviews.** 134 hotels have no `user_rating`, but together they have 697 reviews, so `user_rating` is not kept in sync with reviews.
6. **Email case.** All 40,000 emails have an upper-case domain (`@Rediffmail.com`). Sign-in (R23) must use `lower(email)`. Emails are already unique when lower-cased.
7. **"Coupons never used" is wrong (P6).** 10 coupons have never been used, but R13 returns 0 rows because `NOT IN (SELECT coupon_code FROM bookings)` meets NULLs. `NOT EXISTS` returns the correct 10.
8. **Cross-table rules we cannot write as CHECK.** "Booking type matches the subtype table", "room number only after check-in" and "passenger count = passenger rows" span two tables, so a CHECK cannot enforce them. We verify them with integrity checks 1, 3 and 7 instead.
