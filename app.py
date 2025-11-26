from flask import Flask, render_template
import mysql.connector
from mysql.connector import Error
import os

app = Flask(__name__)

# MySQL connection config from environment variables
db_config = {
    "host": os.getenv("DB_HOST"),         # e.g., terraform-xxxx.us-east-1.rds.amazonaws.com
    "user": os.getenv("DB_USER"),         # e.g., rds_user
    "password": os.getenv("DB_PASS"),     # your password
    "database": os.getenv("DB_NAME")      # e.g., your_database_name
}

def get_first_user_name():
    """Fetch the first user's name from the users table."""
    try:
        connection = mysql.connector.connect(**db_config)
        if connection.is_connected():
            cursor = connection.cursor()
            cursor.execute("SELECT username FROM users WHERE id = 1;")
            result = cursor.fetchone()
            if result:
                return result[0]  # first user's name
            return None
    except Error as e:
        print(f"Error while connecting to MySQL: {e}")
        return None
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'connection' in locals() and connection.is_connected():
            connection.close()

@app.route("/")
def home():
    first_user_name = get_first_user_name()
    return render_template("index.html", user_name=first_user_name)

@app.errorhandler(404)
def page_not_found(e):
    return render_template("error.html"), 404

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
