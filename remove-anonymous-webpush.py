#!/usr/bin/env python3
import sqlite3
import sys


def main() -> None:
    database = sys.argv[1]
    with sqlite3.connect(database) as connection:
        anonymous = connection.execute(
            "SELECT COUNT(*) FROM subscription WHERE user_id = ''"
        ).fetchone()[0]
        connection.execute(
            """
            DELETE FROM subscription_topic
            WHERE subscription_id IN (
                SELECT id FROM subscription WHERE user_id = ''
            )
            """
        )
        connection.execute("DELETE FROM subscription WHERE user_id = ''")
    print(f"Removed {anonymous} anonymous Web Push subscription(s)")


if __name__ == "__main__":
    main()
