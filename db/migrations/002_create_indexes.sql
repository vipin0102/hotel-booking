-- Index for the report query:
--   WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
--   GROUP BY org_id, status  (with SUM(amount))
-- city first (equality), created_at second (range).
-- INCLUDE adds org_id, status, amount so the query is answered from the
-- index alone (Index Only Scan), without reading the table.
CREATE INDEX idx_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);

-- Speeds up "get all events of a booking"
CREATE INDEX idx_events_booking_id ON booking_events (booking_id);
