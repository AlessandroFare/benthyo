-- Migration 023: Enable Supabase Realtime for buddy DMs.

ALTER PUBLICATION supabase_realtime ADD TABLE buddy_messages;

ALTER TABLE buddy_messages REPLICA IDENTITY FULL;
