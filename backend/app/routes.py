from decimal import Decimal, InvalidOperation

from flask import Blueprint, jsonify, request
from flask_jwt_extended import create_access_token, get_jwt_identity, jwt_required
from werkzeug.security import check_password_hash, generate_password_hash

from .extensions import db
from .models import Transaction, User


api_bp = Blueprint("api", __name__, url_prefix="/api")
ALLOWED_TRANSACTION_TYPES = {"payment", "transfer", "bill"}


def get_current_user():
    user_id = get_jwt_identity()
    return User.query.get(int(user_id))


@api_bp.get("/health")
def health_check():
    return jsonify({"status": "ok"}), 200


@api_bp.post("/auth/signup")
def signup():
    data = request.get_json() or {}
    full_name = data.get("full_name", "").strip()
    email = data.get("email", "").strip().lower()
    password = data.get("password", "")

    if not full_name or not email or not password:
        return jsonify({"message": "Full name, email, and password are required."}), 400

    if User.query.filter_by(email=email).first():
        return jsonify({"message": "An account with this email already exists."}), 409

    user = User(
        full_name=full_name,
        email=email,
        password_hash=generate_password_hash(password),
    )
    db.session.add(user)
    db.session.commit()

    token = create_access_token(identity=user.id)

    return jsonify({"token": token, "user": user.to_dict()}), 201


@api_bp.post("/auth/login")
def login():
    data = request.get_json() or {}
    email = data.get("email", "").strip().lower()
    password = data.get("password", "")

    user = User.query.filter_by(email=email).first()
    if user is None or not check_password_hash(user.password_hash, password):
        return jsonify({"message": "Invalid email or password."}), 401

    token = create_access_token(identity=user.id)

    return jsonify({"token": token, "user": user.to_dict()}), 200


@api_bp.get("/auth/me")
@jwt_required()
def get_me():
    user = get_current_user()
    if user is None:
        return jsonify({"message": "User not found."}), 404

    return jsonify({"user": user.to_dict()}), 200


@api_bp.get("/transactions")
@jwt_required()
def list_transactions():
    user = get_current_user()
    if user is None:
        return jsonify({"message": "User not found."}), 404

    transactions = (
        Transaction.query.filter_by(user_id=user.id)
        .order_by(Transaction.created_at.desc())
        .all()
    )

    return jsonify({"transactions": [transaction.to_dict() for transaction in transactions]}), 200


@api_bp.post("/transactions")
@jwt_required()
def create_transaction():
    user = get_current_user()
    if user is None:
        return jsonify({"message": "User not found."}), 404

    data = request.get_json() or {}
    recipient_name = data.get("recipient_name", "").strip()
    amount_raw = str(data.get("amount", "")).strip()
    transaction_type = data.get("transaction_type", "").strip().lower()
    reference = data.get("reference", "").strip() or None

    if not recipient_name or not amount_raw or not transaction_type:
        return jsonify({"message": "Recipient, amount, and type are required."}), 400

    if transaction_type not in ALLOWED_TRANSACTION_TYPES:
        return jsonify({"message": "Transaction type is not supported."}), 400

    try:
        amount = Decimal(amount_raw)
    except InvalidOperation:
        return jsonify({"message": "Amount must be a valid number."}), 400

    if amount <= 0:
        return jsonify({"message": "Amount must be greater than zero."}), 400

    transaction = Transaction(
        user_id=user.id,
        recipient_name=recipient_name,
        amount=amount,
        transaction_type=transaction_type,
        reference=reference,
    )
    db.session.add(transaction)
    db.session.commit()

    return jsonify({"transaction": transaction.to_dict()}), 201
