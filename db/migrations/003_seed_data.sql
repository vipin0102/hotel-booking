-- 200 bookings: 5 cities, 3 organizations, 4 statuses,
-- created_at spread over the last 60 days.
INSERT INTO hotel_bookings
    (id, org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at)
SELECT
    gen_random_uuid(),
    (ARRAY['11111111-1111-1111-1111-111111111111',
           '22222222-2222-2222-2222-222222222222',
           '33333333-3333-3333-3333-333333333333']::uuid[])[1 + g % 3],
    'HOTEL-' || (1 + g % 20),
    (ARRAY['delhi', 'mumbai', 'bangalore', 'goa', 'jaipur'])[1 + g % 5],
    CURRENT_DATE + (g % 30),
    CURRENT_DATE + (g % 30) + 1 + (g % 4),
    1000 + (g * 37 % 9000),
    (ARRAY['pending', 'confirmed', 'cancelled', 'completed'])[1 + g % 4],
    NOW() - (g % 60) * INTERVAL '1 day'
FROM generate_series(1, 200) AS g;

-- Events only for bookings that are not pending
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT id, 'booking_' || status,
       jsonb_build_object('amount', amount, 'city', city),
       created_at + INTERVAL '1 hour'
FROM hotel_bookings
WHERE status <> 'pending';

-- Update planner statistics (helps the index-only scan)
VACUUM ANALYZE;
