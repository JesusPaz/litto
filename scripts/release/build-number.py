#!/usr/bin/env python3
"""Monotonic Apple build number from the current minute: 360.14.43 style, as in AFK."""
import datetime


def build_number(now):
    minutes = int((now - datetime.datetime(2020, 1, 1, tzinfo=datetime.timezone.utc)).total_seconds() // 60)
    return f'{minutes // 10000}.{minutes // 100 % 100}.{minutes % 100}'


if __name__ == '__main__':
    print(build_number(datetime.datetime.now(datetime.timezone.utc)))
