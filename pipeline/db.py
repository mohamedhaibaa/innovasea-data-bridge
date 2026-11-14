"""Shared database connection for the Data Bridge pipeline.

Reads credentials from .env so no secrets live in the code.
"""
import os

import pyodbc
from dotenv import load_dotenv

load_dotenv()


def get_connection() -> pyodbc.Connection:
    """Open an encrypted connection to the Azure SQL Database."""
    conn_str = (
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server=tcp:{os.environ['DB_SERVER']},1433;"
        f"Database={os.environ['DB_NAME']};"
        f"Uid={os.environ['DB_USER']};"
        f"Pwd={os.environ['DB_PASSWORD']};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=60;"  # serverless DB may need time to wake up
    )
    return pyodbc.connect(conn_str)


if __name__ == "__main__":
    with get_connection() as conn:
        row = conn.cursor().execute(
            "SELECT DB_NAME(), SYSDATETIME()"
        ).fetchone()
        print(f"Connected to {row[0]} at {row[1]}")