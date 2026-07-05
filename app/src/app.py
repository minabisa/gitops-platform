from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route("/")
def home():
    return jsonify({
        "status": "healthy",
        "environment": os.getenv("APP_ENV", "unknown"),
        "version": os.getenv("APP_VERSION", "0.0.1")
    })

@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
