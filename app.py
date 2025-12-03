from flask import Flask, render_template
import mysql.connector
from mysql.connector import Error
import os
import logging

# -------------------------
# CONFIGURE LOGGING
# -------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

app = Flask(__name__)

# MySQL connection config from environment variables!
db_config = {
    "host": os.getenv("DB_HOST"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASS"),
    "database": os.getenv("DB_NAME")
}

# Log the DB configuration EXCEPT PASSWORD
logging.info(f"DB CONFIG → host={db_config['host']}, user={db_config['user']}, database={db_config['database']}")


def get_first_user_name():
    """Fetch the first user's name from the users table."""
    try:
        logging.info("Trying to connect to MySQL...")
        connection = mysql.connector.connect(**db_config)

        if connection.is_connected():
            logging.info("Successfully connected to MySQL")
            cursor = connection.cursor()
            cursor.execute("SELECT name FROM users WHERE id = 1;")
            result = cursor.fetchone()
            logging.info(f"Query result: {result}")

            if result:
                return result[0]
            else:
                logging.warning("No result found for id=1")
                return None

    except Error as e:
        logging.error(f"❌ ERROR while connecting to MySQL: {e}")
        return None

    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'connection' in locals() and connection.is_connected():
            connection.close()
            logging.info("MySQL connection closed.")


@app.route("/")
def home():
    print("hii pleasse work")
    logging.info("Handling request: /")
    first_user_name = get_first_user_name()
    return render_template("index.html", user_name=first_user_name)


@app.errorhandler(404)
def page_not_found(e):
    logging.warning("404 error encountered")
    return render_template("error.html"), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
