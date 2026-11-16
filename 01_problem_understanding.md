# 01 · Problem understanding

MakeMyTrip sells flights and hotel stays. The old database has no documented schema and the product teams report eight problems. For each one: what the business needs, who is hurt, and whether it is **real-time** (a customer or staff member is waiting on a screen) or **reporting** (a report that can take longer).

| # | What the business needs | Stakeholders affected | Type |
|---|-------------------------|-----------------------|------|
| P1 | Travellers must see flights for a route and date, the cheapest fare for each day of the month, correct seats-left numbers and the delayed-flights board, instantly. | Traveller, revenue management | Real-time |
| P2 | Hotel search filtered by city, stars and amenities (pool, wifi …), and a check of how many rooms are still free for the chosen dates. | Traveller, hotel partner | Real-time |
| P3 | "My Trips" page, finding a booking by its reference, and sign-in by email must open without delay. | Traveller, customer support | Real-time |
| P4 | Airlines need the passenger list (manifest) of a flight, flights with few passengers, and cancellation rates per airline. | Airline partner | Manifest real-time; the rest reporting |
| P5 | Checkout must create bookings, the payment queue must find pending payments quickly, and confirmations and cancellations must not slow down when many people pay at once. | Traveller, payments team | Real-time |
| P6 | Marketing's "coupons never used" report returns **nothing**, which is wrong. Some coupons were never used; the result is empty because `NOT IN` meets the NULL `coupon_code` of bookings without a coupon. This is a correctness bug, not just a speed problem. | Marketing | Reporting |
| P7 | Hotels want room-nights sold per city. The front desk must assign room numbers at check-in quickly. | Hotel partner, front desk | Room-nights reporting; check-in real-time |
| P8 | Finance and loyalty reports (revenue per month, booking lead time, repeat customers, last-minute bookings, popular routes, senior-citizen passengers per route) time out today and must keep working when bookings grow 20×. | Finance, loyalty team, revenue management | Reporting |

## Performance targets we will aim for
- **Real-time** queries (P1, P2, P3, P5, manifest in P4, check-in in P7): a few milliseconds, because a person is waiting.
- **Reporting** queries (P4 reports, P6, P7 room-nights, P8): may take longer, but must finish and must still work at 20× data.

## Assumptions
1. All times are Indian Standard Time (`+05:30`), which is how they appear in the data.
2. `total_amount` is the amount the customer actually paid; `discount` was already taken off it (for flights `fare_paid = total_amount + discount` holds for every row).
3. A booking is either a flight booking or a hotel booking, never both (checked: true for all 144,792 rows).
4. A seat number appears only after web check-in, and a room number only after the guest checks in at the hotel, so both can be empty.
5. The 30 queries are the most important workload; their results must stay exactly the same after optimisation (except R13, whose current result is wrong).
