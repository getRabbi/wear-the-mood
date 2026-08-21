"""Cron one-shot: event reminders (RETENTION spec §15, §23).

Wraps ``app.cron.event_reminders``. Runs HOURLY, like the daily stylist push,
because each reminder window is a day wide and an hourly pass is what keeps a
7-day nudge from landing at 3am. Finite, no loop.

Gated on ``feature_event_planner``: with the flag off — which is how it ships —
the job connects, reads one flag, sends nothing and exits.
"""

from app.cron.event_reminders import main

if __name__ == "__main__":
    main()
