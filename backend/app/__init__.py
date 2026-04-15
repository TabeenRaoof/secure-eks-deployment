import time

from flask import Flask
from sqlalchemy.exc import SQLAlchemyError

from .config import Config
from .extensions import db, init_extensions
from .routes import api_bp


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)

    init_extensions(app)
    app.register_blueprint(api_bp)

    with app.app_context():
        last_error = None
        for _ in range(10):
            try:
                db.create_all()
                last_error = None
                break
            except SQLAlchemyError as error:
                last_error = error
                time.sleep(2)

        if last_error is not None:
            raise last_error

    return app
