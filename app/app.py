import os

import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)


def get_connection():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "db"),
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        connect_timeout=3,
    )


@app.route("/")
def index():
    return jsonify(message="Task Tracker API")


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/counter")
def counter():
    conn = get_connection()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                "CREATE TABLE IF NOT EXISTS counter "
                "(id INT PRIMARY KEY, value INT NOT NULL)"
            )
            cur.execute(
                "INSERT INTO counter (id, value) VALUES (1, 1) "
                "ON CONFLICT (id) DO UPDATE SET value = counter.value + 1 "
                "RETURNING value"
            )
            value = cur.fetchone()[0]
    finally:
        conn.close()
    return jsonify(counter=value)