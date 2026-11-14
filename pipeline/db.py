"""Shared database connection for the Data Bridge pipeline.

Reads credentials from .env so no secrets live in the code.
"""
import time  # add this at the top, with the other imports

import os

import pyodbc
from dotenv import load_dotenv

load_dotenv()





def get_connection(retries: int = 3, wait_seconds: int = 15) -> pyodbc.Connection:
    """Open an encrypted connection to Azure SQL.

    The free serverless database pauses when idle, so the first attempt
    can time out while it wakes up. Retry a few times before giving up.
    """
    conn_str = (
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server=tcp:{os.environ['DB_SERVER']},1433;"
        f"Database={os.environ['DB_NAME']};"
        f"Uid={os.environ['DB_USER']};"
        f"Pwd={os.environ['DB_PASSWORD']};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=60;"
    )
    for attempt in range(1, retries + 1):
        try:
            return pyodbc.connect(conn_str)
        except pyodbc.OperationalError:
            if attempt == retries:
                raise
            print(f"Connection attempt {attempt} failed; database may be "
                  f"waking up. Retrying in {wait_seconds}s...")
            time.sleep(wait_seconds)


if __name__ == "__main__":
    with get_connection() as conn:
        row = conn.cursor().execute(
            "SELECT DB_NAME(), SYSDATETIME()"
        ).fetchone()
        print(f"Connected to {row[0]} at {row[1]}")