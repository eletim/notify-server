#!/usr/bin/env python3
"""Move only matching server URLs in account-synced topic subscriptions.
Stop ntfy and back up auth.db before running. Users, tokens and keys are untouched.
"""
import argparse
import json
import sqlite3

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('database')
parser.add_argument('old_url')
parser.add_argument('new_url')
args = parser.parse_args()
changed = 0
with sqlite3.connect(args.database) as db:
    for user_id, raw in db.execute('SELECT id, prefs FROM user').fetchall():
        prefs = json.loads(raw)
        count = 0
        for subscription in prefs.get('subscriptions', []):
            if subscription.get('base_url') == args.old_url:
                subscription['base_url'] = args.new_url
                count += 1
        if count:
            db.execute('UPDATE user SET prefs = ? WHERE id = ?', (json.dumps(prefs), user_id))
            changed += count
print(f'Updated {changed} saved subscription URLs')
